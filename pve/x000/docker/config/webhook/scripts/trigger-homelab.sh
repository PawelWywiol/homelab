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
#   pve/x203/docker/config/* → Ansible deploy to x203
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

# Extract files by change type (added, modified, removed)
ADDED_FILES=$(echo "$PAYLOAD" | jq -r '[.commits[].added[]] | unique | .[]' 2>/dev/null || echo "")
MODIFIED_FILES=$(echo "$PAYLOAD" | jq -r '[.commits[].modified[]] | unique | .[]' 2>/dev/null || echo "")
REMOVED_FILES=$(echo "$PAYLOAD" | jq -r '[.commits[].removed[]] | unique | .[]' 2>/dev/null || echo "")

# Combine for total count check
CHANGED_FILES=$(echo -e "${ADDED_FILES}\n${MODIFIED_FILES}\n${REMOVED_FILES}" | grep -v '^$' | sort -u)

if [ -z "$CHANGED_FILES" ]; then
    log_info "No file changes detected, skipping"
    send_notification "ℹ️ Webhook: No Changes" "**Commit:** \`$COMMIT_SHA\` $COMMIT_MSG${NL}**Author:** $COMMIT_AUTHOR${NL}**Branch:** $BRANCH_NAME${NL}${NL}No file changes in payload"
    exit 0
fi

log_debug "Added files:\n$ADDED_FILES"
log_debug "Modified files:\n$MODIFIED_FILES"
log_debug "Removed files:\n$REMOVED_FILES"

# Track state
TOFU_PLAN=false
TOFU_FILES=()
IGNORED_FILES=()

# Services by operation type - x202
SERVICES_TO_START_X202=()
SERVICES_TO_RESTART_X202=()
SERVICES_TO_STOP_X202=()

# Services by operation type - x000
SERVICES_TO_START_X000=()
SERVICES_TO_RESTART_X000=()
SERVICES_TO_STOP_X000=()

# Services by operation type - x203
SERVICES_TO_START_X203=()
SERVICES_TO_RESTART_X203=()
SERVICES_TO_STOP_X203=()

# Helper: extract service name from x202 path
extract_service_x202() {
    echo "$1" | sed -n 's|pve/x202/docker/config/\([^/]*\)/.*|\1|p'
}

# Helper: extract service name from x000 path
extract_service_x000() {
    echo "$1" | sed -n 's|pve/x000/docker/config/\([^/]*\)/.*|\1|p'
}

# Helper: extract service name from x203 path
extract_service_x203() {
    echo "$1" | sed -n 's|pve/x203/docker/config/\([^/]*\)/.*|\1|p'
}

# Helper: add to array if not already present
add_unique() {
    local -n arr=$1
    local val=$2
    if [ -n "$val" ] && [[ ! " ${arr[*]} " =~ " ${val} " ]]; then
        arr+=("$val")
    fi
}

# Analyze ADDED files → services to start
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        pve/x202/docker/config/*)
            SERVICE=$(extract_service_x202 "$file")
            add_unique SERVICES_TO_START_X202 "$SERVICE"
            log_debug "x202 start needed: $file"
            ;;
        pve/x000/docker/config/*)
            SERVICE=$(extract_service_x000 "$file")
            add_unique SERVICES_TO_START_X000 "$SERVICE"
            log_debug "x000 start needed: $file"
            ;;
        pve/x203/docker/config/*)
            SERVICE=$(extract_service_x203 "$file")
            add_unique SERVICES_TO_START_X203 "$SERVICE"
            log_debug "x203 start needed: $file"
            ;;
        pve/x000/infra/tofu/*)
            TOFU_PLAN=true
            TOFU_FILES+=("$(basename "$file")")
            ;;
        *)
            add_unique IGNORED_FILES "$file"
            ;;
    esac
done <<< "$ADDED_FILES"

# Analyze MODIFIED files → services to restart
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        pve/x202/docker/config/*)
            SERVICE=$(extract_service_x202 "$file")
            # Only restart if not already in start list
            if [[ ! " ${SERVICES_TO_START_X202[*]} " =~ " ${SERVICE} " ]]; then
                add_unique SERVICES_TO_RESTART_X202 "$SERVICE"
            fi
            log_debug "x202 restart needed: $file"
            ;;
        pve/x000/docker/config/*)
            SERVICE=$(extract_service_x000 "$file")
            # Only restart if not already in start list
            if [[ ! " ${SERVICES_TO_START_X000[*]} " =~ " ${SERVICE} " ]]; then
                add_unique SERVICES_TO_RESTART_X000 "$SERVICE"
            fi
            log_debug "x000 restart needed: $file"
            ;;
        pve/x203/docker/config/*)
            SERVICE=$(extract_service_x203 "$file")
            # Only restart if not already in start list
            if [[ ! " ${SERVICES_TO_START_X203[*]} " =~ " ${SERVICE} " ]]; then
                add_unique SERVICES_TO_RESTART_X203 "$SERVICE"
            fi
            log_debug "x203 restart needed: $file"
            ;;
        pve/x000/infra/tofu/*)
            TOFU_PLAN=true
            add_unique TOFU_FILES "$(basename "$file")"
            ;;
        *)
            add_unique IGNORED_FILES "$file"
            ;;
    esac
done <<< "$MODIFIED_FILES"

# Analyze REMOVED files → services to stop
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        pve/x202/docker/config/*)
            SERVICE=$(extract_service_x202 "$file")
            # Only stop if not being started or restarted
            if [[ ! " ${SERVICES_TO_START_X202[*]} " =~ " ${SERVICE} " ]] && \
               [[ ! " ${SERVICES_TO_RESTART_X202[*]} " =~ " ${SERVICE} " ]]; then
                add_unique SERVICES_TO_STOP_X202 "$SERVICE"
            fi
            log_debug "x202 stop needed: $file"
            ;;
        pve/x000/docker/config/*)
            SERVICE=$(extract_service_x000 "$file")
            # Only stop if not being started or restarted
            if [[ ! " ${SERVICES_TO_START_X000[*]} " =~ " ${SERVICE} " ]] && \
               [[ ! " ${SERVICES_TO_RESTART_X000[*]} " =~ " ${SERVICE} " ]]; then
                add_unique SERVICES_TO_STOP_X000 "$SERVICE"
            fi
            log_debug "x000 stop needed: $file"
            ;;
        pve/x203/docker/config/*)
            SERVICE=$(extract_service_x203 "$file")
            # Only stop if not being started or restarted
            if [[ ! " ${SERVICES_TO_START_X203[*]} " =~ " ${SERVICE} " ]] && \
               [[ ! " ${SERVICES_TO_RESTART_X203[*]} " =~ " ${SERVICE} " ]]; then
                add_unique SERVICES_TO_STOP_X203 "$SERVICE"
            fi
            log_debug "x203 stop needed: $file"
            ;;
        pve/x000/infra/tofu/*)
            TOFU_PLAN=true
            add_unique TOFU_FILES "$(basename "$file")"
            ;;
        *)
            add_unique IGNORED_FILES "$file"
            ;;
    esac
done <<< "$REMOVED_FILES"

# Determine if any x000 actions needed
DEPLOY_X000=false
STOP_X000=false
[ ${#SERVICES_TO_START_X000[@]} -gt 0 ] || [ ${#SERVICES_TO_RESTART_X000[@]} -gt 0 ] && DEPLOY_X000=true
[ ${#SERVICES_TO_STOP_X000[@]} -gt 0 ] && STOP_X000=true

# Determine if any x202 actions needed
DEPLOY_X202=false
STOP_X202=false
[ ${#SERVICES_TO_START_X202[@]} -gt 0 ] || [ ${#SERVICES_TO_RESTART_X202[@]} -gt 0 ] && DEPLOY_X202=true
[ ${#SERVICES_TO_STOP_X202[@]} -gt 0 ] && STOP_X202=true

# Determine if any x203 actions needed
DEPLOY_X203=false
STOP_X203=false
[ ${#SERVICES_TO_START_X203[@]} -gt 0 ] || [ ${#SERVICES_TO_RESTART_X203[@]} -gt 0 ] && DEPLOY_X203=true
[ ${#SERVICES_TO_STOP_X203[@]} -gt 0 ] && STOP_X203=true

# Build commit info block for notifications
COMMIT_INFO="**Commit:** [\`$COMMIT_SHA\`]($COMMIT_URL) $COMMIT_MSG${NL}**Author:** $COMMIT_AUTHOR${NL}**Branch:** $BRANCH_NAME"

# If only ignored files, notify and exit
if [ "$DEPLOY_X000" = false ] && [ "$STOP_X000" = false ] && \
   [ "$DEPLOY_X202" = false ] && [ "$STOP_X202" = false ] && \
   [ "$DEPLOY_X203" = false ] && [ "$STOP_X203" = false ] && [ "$TOFU_PLAN" = false ]; then
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

# Stop removed services on x000 first
if [ "$STOP_X000" = true ]; then
    STOP_STR=$(IFS=', '; echo "${SERVICES_TO_STOP_X000[*]}")
    log_info "Stopping removed services on x000: $STOP_STR"

    START_DETAILS="**Services:** $STOP_STR${NL}**Action:** Stop & Remove"
    send_start_notification "stop_x000" "$COMMIT_INFO" "$START_DETAILS"

    START_TIME=$(date +%s)

    STOP_OUTPUT=""
    STOP_FAILED=false
    for svc in "${SERVICES_TO_STOP_X000[@]}"; do
        log_info "Stopping service: $svc"
        if OUTPUT=$(run_stop "x000" "$svc" 2>&1); then
            STOP_OUTPUT+="$svc: stopped${NL}"
        else
            STOP_OUTPUT+="$svc: failed - $OUTPUT${NL}"
            STOP_FAILED=true
        fi
    done

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ "$STOP_FAILED" = true ]; then
        log_error "Some x000 services failed to stop after ${DURATION}s"
        send_end_notification "stop_x000" "$COMMIT_INFO" "failure" "$DURATION" "$STOP_OUTPUT"
        exit 1
    else
        ACTIONS_TAKEN+=("x000 stop")
        log_info "x000 services stopped in ${DURATION}s"
        send_end_notification "stop_x000" "$COMMIT_INFO" "success" "$DURATION" ""
    fi
fi

# Stop removed services on x202
if [ "$STOP_X202" = true ]; then
    STOP_STR=$(IFS=', '; echo "${SERVICES_TO_STOP_X202[*]}")
    log_info "Stopping removed services on x202: $STOP_STR"

    # Send start notification
    START_DETAILS="**Services:** $STOP_STR${NL}**Action:** Stop & Remove"
    send_start_notification "stop_x202" "$COMMIT_INFO" "$START_DETAILS"

    # Track timing
    START_TIME=$(date +%s)

    # Execute stop for each service
    STOP_OUTPUT=""
    STOP_FAILED=false
    for svc in "${SERVICES_TO_STOP_X202[@]}"; do
        log_info "Stopping service: $svc"
        if OUTPUT=$(run_stop "x202" "$svc" 2>&1); then
            STOP_OUTPUT+="$svc: stopped${NL}"
        else
            STOP_OUTPUT+="$svc: failed - $OUTPUT${NL}"
            STOP_FAILED=true
        fi
    done

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ "$STOP_FAILED" = true ]; then
        log_error "Some x202 services failed to stop after ${DURATION}s"
        send_end_notification "stop_x202" "$COMMIT_INFO" "failure" "$DURATION" "$STOP_OUTPUT"
        exit 1
    else
        ACTIONS_TAKEN+=("x202 stop")
        log_info "x202 services stopped in ${DURATION}s"
        send_end_notification "stop_x202" "$COMMIT_INFO" "success" "$DURATION" ""
    fi
fi

# Stop removed services on x203
if [ "$STOP_X203" = true ]; then
    STOP_STR=$(IFS=', '; echo "${SERVICES_TO_STOP_X203[*]}")
    log_info "Stopping removed services on x203: $STOP_STR"

    START_DETAILS="**Services:** $STOP_STR${NL}**Action:** Stop & Remove"
    send_start_notification "stop_x203" "$COMMIT_INFO" "$START_DETAILS"

    START_TIME=$(date +%s)

    STOP_OUTPUT=""
    STOP_FAILED=false
    for svc in "${SERVICES_TO_STOP_X203[@]}"; do
        log_info "Stopping service: $svc"
        if OUTPUT=$(run_stop "x203" "$svc" 2>&1); then
            STOP_OUTPUT+="$svc: stopped${NL}"
        else
            STOP_OUTPUT+="$svc: failed - $OUTPUT${NL}"
            STOP_FAILED=true
        fi
    done

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ "$STOP_FAILED" = true ]; then
        log_error "Some x203 services failed to stop after ${DURATION}s"
        send_end_notification "stop_x203" "$COMMIT_INFO" "failure" "$DURATION" "$STOP_OUTPUT"
        exit 1
    else
        ACTIONS_TAKEN+=("x203 stop")
        log_info "x203 services stopped in ${DURATION}s"
        send_end_notification "stop_x203" "$COMMIT_INFO" "success" "$DURATION" ""
    fi
fi

# Deploy/restart services on x000
if [ "$DEPLOY_X000" = true ]; then
    ALL_DEPLOY_SERVICES_X000=("${SERVICES_TO_START_X000[@]}" "${SERVICES_TO_RESTART_X000[@]}")
    SERVICES_STR=$(IFS=', '; echo "${ALL_DEPLOY_SERVICES_X000[*]}")
    log_info "Deploying to x000: $SERVICES_STR"

    START_DETAILS="**Target:** x000"
    [ ${#SERVICES_TO_START_X000[@]} -gt 0 ] && START_DETAILS+="${NL}**Start:** $(IFS=', '; echo "${SERVICES_TO_START_X000[*]}")"
    [ ${#SERVICES_TO_RESTART_X000[@]} -gt 0 ] && START_DETAILS+="${NL}**Restart:** $(IFS=', '; echo "${SERVICES_TO_RESTART_X000[*]}")"

    send_start_notification "deploy_x000" "$COMMIT_INFO" "$START_DETAILS"

    START_TIME=$(date +%s)

    if EXEC_OUTPUT=$(run_deploy "x000" "all" 2>&1); then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        ACTIONS_TAKEN+=("x000 deploy")
        log_info "x000 deployment completed in ${DURATION}s"

        send_end_notification "deploy_x000" "$COMMIT_INFO" "success" "$DURATION" ""
    else
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        log_error "x000 deployment failed after ${DURATION}s"

        send_end_notification "deploy_x000" "$COMMIT_INFO" "failure" "$DURATION" "$EXEC_OUTPUT"
        exit 1
    fi
fi

# Deploy/restart services on x202
if [ "$DEPLOY_X202" = true ]; then
    ALL_DEPLOY_SERVICES_X202=("${SERVICES_TO_START_X202[@]}" "${SERVICES_TO_RESTART_X202[@]}")
    SERVICES_STR=$(IFS=', '; echo "${ALL_DEPLOY_SERVICES_X202[*]}")
    log_info "Deploying to x202: $SERVICES_STR"

    START_DETAILS="**Target:** x202"
    [ ${#SERVICES_TO_START_X202[@]} -gt 0 ] && START_DETAILS+="${NL}**Start:** $(IFS=', '; echo "${SERVICES_TO_START_X202[*]}")"
    [ ${#SERVICES_TO_RESTART_X202[@]} -gt 0 ] && START_DETAILS+="${NL}**Restart:** $(IFS=', '; echo "${SERVICES_TO_RESTART_X202[*]}")"

    send_start_notification "deploy_x202" "$COMMIT_INFO" "$START_DETAILS"

    START_TIME=$(date +%s)

    if EXEC_OUTPUT=$(run_deploy "x202" "all" 2>&1); then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        ACTIONS_TAKEN+=("x202 deploy")
        log_info "x202 deployment completed in ${DURATION}s"

        send_end_notification "deploy_x202" "$COMMIT_INFO" "success" "$DURATION" ""
    else
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        log_error "x202 deployment failed after ${DURATION}s"

        send_end_notification "deploy_x202" "$COMMIT_INFO" "failure" "$DURATION" "$EXEC_OUTPUT"
        exit 1
    fi
fi

# Deploy/restart services on x203
if [ "$DEPLOY_X203" = true ]; then
    ALL_DEPLOY_SERVICES_X203=("${SERVICES_TO_START_X203[@]}" "${SERVICES_TO_RESTART_X203[@]}")
    SERVICES_STR=$(IFS=', '; echo "${ALL_DEPLOY_SERVICES_X203[*]}")
    log_info "Deploying to x203: $SERVICES_STR"

    START_DETAILS="**Target:** x203"
    [ ${#SERVICES_TO_START_X203[@]} -gt 0 ] && START_DETAILS+="${NL}**Start:** $(IFS=', '; echo "${SERVICES_TO_START_X203[*]}")"
    [ ${#SERVICES_TO_RESTART_X203[@]} -gt 0 ] && START_DETAILS+="${NL}**Restart:** $(IFS=', '; echo "${SERVICES_TO_RESTART_X203[*]}")"

    send_start_notification "deploy_x203" "$COMMIT_INFO" "$START_DETAILS"

    START_TIME=$(date +%s)

    if EXEC_OUTPUT=$(run_deploy "x203" "all" 2>&1); then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        ACTIONS_TAKEN+=("x203 deploy")
        log_info "x203 deployment completed in ${DURATION}s"

        send_end_notification "deploy_x203" "$COMMIT_INFO" "success" "$DURATION" ""
    else
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        log_error "x203 deployment failed after ${DURATION}s"

        send_end_notification "deploy_x203" "$COMMIT_INFO" "failure" "$DURATION" "$EXEC_OUTPUT"
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
