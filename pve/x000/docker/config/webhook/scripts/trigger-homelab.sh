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

# Parse payload from argument
PAYLOAD="${1:-}"

if [ -z "$PAYLOAD" ]; then
    error_exit "No payload received"
fi

# Extract metadata from payload
REPO_FULL_NAME=$(echo "$PAYLOAD" | jq -r '.repository.full_name // empty')
GIT_REF=$(echo "$PAYLOAD" | jq -r '.ref // empty')
COMMIT_MSG=$(echo "$PAYLOAD" | jq -r '.head_commit.message // "No commit message"' | head -1)

if [ -z "$REPO_FULL_NAME" ] || [ -z "$GIT_REF" ]; then
    error_exit "Invalid payload: missing repository or ref"
fi

export REPO_NAME=$(echo "$REPO_FULL_NAME" | cut -d'/' -f2)
export BRANCH_NAME=$(echo "$GIT_REF" | sed 's|refs/heads/||')

log_info "Webhook received: $REPO_NAME/$BRANCH_NAME"
log_info "Commit: $COMMIT_MSG"

# Extract all changed files from commits (added + modified)
CHANGED_FILES=$(echo "$PAYLOAD" | jq -r '
    [.commits[].added[], .commits[].modified[]] | unique | .[]
' 2>/dev/null || echo "")

if [ -z "$CHANGED_FILES" ]; then
    log_info "No file changes detected, skipping"
    exit 0
fi

log_debug "Changed files:\n$CHANGED_FILES"

# Track actions taken
DEPLOY_X202=false
TOFU_PLAN=false

# Analyze changed files and determine actions
while IFS= read -r file; do
    case "$file" in
        pve/x202/docker/config/*)
            DEPLOY_X202=true
            log_debug "x202 deploy needed: $file"
            ;;
        pve/x000/infra/tofu/*)
            TOFU_PLAN=true
            log_debug "OpenTofu plan needed: $file"
            ;;
        *)
            log_debug "Ignored: $file"
            ;;
    esac
done <<< "$CHANGED_FILES"

# Execute actions
ACTIONS_TAKEN=()

# Deploy to x202
if [ "$DEPLOY_X202" = true ]; then
    log_info "Deploying to x202..."
    if run_deploy "x202" "all"; then
        ACTIONS_TAKEN+=("x202 deploy")
        log_info "x202 deployment completed"
    else
        send_notification "x202 Deploy Failed" "Deployment to x202 failed\n\nCommit: $COMMIT_MSG" "high"
        error_exit "x202 deployment failed"
    fi
fi

# Run OpenTofu plan
if [ "$TOFU_PLAN" = true ]; then
    log_info "Running OpenTofu plan..."
    AUTO_APPLY="${TOFU_AUTO_APPLY:-false}"

    if run_tofu "$AUTO_APPLY"; then
        if [ "$AUTO_APPLY" = "true" ]; then
            ACTIONS_TAKEN+=("tofu apply")
            log_info "OpenTofu applied"
        else
            ACTIONS_TAKEN+=("tofu plan")
            log_info "OpenTofu plan ready - manual approval required"
            send_notification \
                "OpenTofu Plan Ready" \
                "Infrastructure plan completed\n\nCommit: $COMMIT_MSG\n\nManual approval required on x000" \
                "high"
        fi
    else
        send_notification "OpenTofu Failed" "OpenTofu plan failed\n\nCommit: $COMMIT_MSG" "high"
        error_exit "OpenTofu plan failed"
    fi
fi

# Summary
if [ ${#ACTIONS_TAKEN[@]} -eq 0 ]; then
    log_info "No actionable changes detected"
    exit 0
fi

ACTIONS_STR=$(IFS=', '; echo "${ACTIONS_TAKEN[*]}")
success_exit "Completed: $ACTIONS_STR"
