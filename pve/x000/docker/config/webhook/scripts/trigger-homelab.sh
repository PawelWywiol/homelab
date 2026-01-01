#!/bin/bash
#
# trigger-homelab.sh - Unified webhook handler for homelab automation
# Routes GitHub push events to appropriate actions based on changed files
#
# Arguments:
#   $1 - Entire GitHub webhook payload (JSON)
#
# Routing:
#   pve/x202/docker/config/* → Ansible deploy to x202
#   pve/x000/infra/tofu/*    → OpenTofu plan (manual apply)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Newline character for string building
NL=$'\n'

# Parse payload from argument
PAYLOAD="${1:-}"

if [ -z "$PAYLOAD" ]; then
    send_notification "❌ Webhook Error" "No payload received" "high"
    error_exit "No payload received"
fi

# Extract metadata from payload
REPO_FULL_NAME=$(echo "$PAYLOAD" | jq -r '.repository.full_name // empty')
GIT_REF=$(echo "$PAYLOAD" | jq -r '.ref // empty')
COMMIT_MSG=$(echo "$PAYLOAD" | jq -r '.head_commit.message // "No commit message"' | head -1)
COMMIT_SHA=$(echo "$PAYLOAD" | jq -r '.head_commit.id // empty' | cut -c1-7)
COMMIT_AUTHOR=$(echo "$PAYLOAD" | jq -r '.head_commit.author.name // "Unknown"')
COMMIT_URL=$(echo "$PAYLOAD" | jq -r '.head_commit.url // empty')

if [ -z "$REPO_FULL_NAME" ] || [ -z "$GIT_REF" ]; then
    send_notification "❌ Webhook Error" "Invalid payload: missing repository or ref" "high"
    error_exit "Invalid payload: missing repository or ref"
fi

export REPO_NAME=$(echo "$REPO_FULL_NAME" | cut -d'/' -f2)
export BRANCH_NAME=$(echo "$GIT_REF" | sed 's|refs/heads/||')

log_info "Webhook received: $REPO_NAME/$BRANCH_NAME"
log_info "Commit: $COMMIT_MSG"

# Extract all changed files from commits (added + modified + removed)
CHANGED_FILES=$(echo "$PAYLOAD" | jq -r '
    [.commits[].added[], .commits[].modified[], .commits[].removed[]] | unique | .[]
' 2>/dev/null || echo "")

if [ -z "$CHANGED_FILES" ]; then
    log_info "No file changes detected, skipping"
    send_notification "ℹ️ Webhook: No Changes" "**Commit:** \`$COMMIT_SHA\` $COMMIT_MSG${NL}**Author:** $COMMIT_AUTHOR${NL}**Branch:** $BRANCH_NAME${NL}${NL}No file changes in payload"
    exit 0
fi

log_debug "Changed files:\n$CHANGED_FILES"

# Track state
DEPLOY_X202=false
TOFU_PLAN=false
SERVICES_AFFECTED=()
IGNORED_FILES=()
TOFU_FILES=()

# Analyze changed files and determine actions
while IFS= read -r file; do
    case "$file" in
        pve/x202/docker/config/*)
            DEPLOY_X202=true
            # Extract service name from path
            SERVICE=$(echo "$file" | sed -n 's|pve/x202/docker/config/\([^/]*\)/.*|\1|p')
            if [ -n "$SERVICE" ] && [[ ! " ${SERVICES_AFFECTED[*]} " =~ " ${SERVICE} " ]]; then
                SERVICES_AFFECTED+=("$SERVICE")
            fi
            log_debug "x202 deploy needed: $file"
            ;;
        pve/x000/infra/tofu/*)
            TOFU_PLAN=true
            TOFU_FILES+=("$(basename "$file")")
            log_debug "OpenTofu plan needed: $file"
            ;;
        *)
            IGNORED_FILES+=("$file")
            log_debug "Ignored: $file"
            ;;
    esac
done <<< "$CHANGED_FILES"

# Build commit info block for notifications
COMMIT_INFO="**Commit:** [\`$COMMIT_SHA\`]($COMMIT_URL) $COMMIT_MSG${NL}**Author:** $COMMIT_AUTHOR${NL}**Branch:** $BRANCH_NAME"

# If only ignored files, notify and exit
if [ "$DEPLOY_X202" = false ] && [ "$TOFU_PLAN" = false ]; then
    IGNORED_COUNT=${#IGNORED_FILES[@]}
    IGNORED_LIST=$(printf '%s\n' "${IGNORED_FILES[@]}" | head -5 | sed 's/^/• /')
    if [ $IGNORED_COUNT -gt 5 ]; then
        IGNORED_LIST="$IGNORED_LIST${NL}• ... and $((IGNORED_COUNT - 5)) more"
    fi

    log_info "No actionable changes detected ($IGNORED_COUNT files ignored)"
    send_notification "ℹ️ Webhook: Ignored" "$COMMIT_INFO${NL}${NL}**Ignored files ($IGNORED_COUNT):**${NL}$IGNORED_LIST"
    exit 0
fi

# Execute actions with two-phase notifications
ACTIONS_TAKEN=()
EXEC_OUTPUT=""

# Deploy to x202
if [ "$DEPLOY_X202" = true ]; then
    SERVICES_STR=$(IFS=', '; echo "${SERVICES_AFFECTED[*]}")
    log_info "Deploying to x202: $SERVICES_STR"

    # Send start notification
    START_DETAILS="**Services:** $SERVICES_STR${NL}**Target:** x202"
    send_start_notification "deploy" "$COMMIT_INFO" "$START_DETAILS"

    # Track timing
    START_TIME=$(date +%s)

    # Execute and capture output
    if EXEC_OUTPUT=$(run_deploy "x202" "all" 2>&1); then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        ACTIONS_TAKEN+=("x202 deploy")
        log_info "x202 deployment completed in ${DURATION}s"

        # Send success end notification
        send_end_notification "deploy" "$COMMIT_INFO" "success" "$DURATION" "$EXEC_OUTPUT"
    else
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        log_error "x202 deployment failed after ${DURATION}s"

        # Send failure end notification
        send_end_notification "deploy" "$COMMIT_INFO" "failure" "$DURATION" "$EXEC_OUTPUT"
        exit 1
    fi
fi

# Run OpenTofu plan
if [ "$TOFU_PLAN" = true ]; then
    TOFU_FILES_STR=$(IFS=', '; echo "${TOFU_FILES[*]}")
    log_info "Running OpenTofu plan..."
    AUTO_APPLY="${TOFU_AUTO_APPLY:-false}"

    # Send start notification
    START_DETAILS="**Files:** $TOFU_FILES_STR${NL}**Auto-apply:** $AUTO_APPLY"
    send_start_notification "tofu" "$COMMIT_INFO" "$START_DETAILS"

    # Track timing
    START_TIME=$(date +%s)

    # Execute and capture output
    if EXEC_OUTPUT=$(run_tofu "$AUTO_APPLY" 2>&1); then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        if [ "$AUTO_APPLY" = "true" ]; then
            ACTIONS_TAKEN+=("tofu apply")
            log_info "OpenTofu applied in ${DURATION}s"
            send_end_notification "tofu" "$COMMIT_INFO" "success" "$DURATION" "$EXEC_OUTPUT"
        else
            ACTIONS_TAKEN+=("tofu plan")
            log_info "OpenTofu plan ready in ${DURATION}s - manual approval required"

            # Add manual approval note to output
            PLAN_OUTPUT="$EXEC_OUTPUT${NL}${NL}⚠️ Manual approval required on x000"
            send_end_notification "tofu" "$COMMIT_INFO" "success" "$DURATION" "$PLAN_OUTPUT"
        fi
    else
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        log_error "OpenTofu plan failed after ${DURATION}s"

        # Send failure end notification
        send_end_notification "tofu" "$COMMIT_INFO" "failure" "$DURATION" "$EXEC_OUTPUT"
        exit 1
    fi
fi

log_info "Completed: $(IFS=', '; echo "${ACTIONS_TAKEN[*]}")"
exit 0
