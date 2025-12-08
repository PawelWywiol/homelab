#!/bin/bash
#
# Trigger OpenTofu infrastructure update
# Called by webhook handler when infra/tofu changes are detected
#
# Arguments:
#   $1 - repository.full_name (e.g., "PawelWywiol/homelab")
#   $2 - ref (e.g., "refs/heads/main")
#   $3 - commit_message (optional)
#

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Parse webhook arguments
parse_webhook_args "$@" || error_exit "Failed to parse webhook arguments"

COMMIT_MSG="${3:-No commit message}"

# Validate required environment variables
validate_env "TOFU_WORKING_DIR" || error_exit "Missing required environment variables"

log_info "OpenTofu update triggered for: $REPO_NAME/$BRANCH_NAME"
log_info "Commit: $COMMIT_MSG"

# Check if auto-apply is enabled
AUTO_APPLY="${TOFU_AUTO_APPLY:-false}"

# Change to OpenTofu directory
if [ ! -d "$TOFU_WORKING_DIR" ]; then
    error_exit "OpenTofu directory not found: $TOFU_WORKING_DIR"
fi

cd "$TOFU_WORKING_DIR" || error_exit "Failed to change to OpenTofu directory"

log_info "Working directory: $TOFU_WORKING_DIR"

# Initialize OpenTofu (if needed)
if [ ! -d ".terraform" ]; then
    log_info "Initializing OpenTofu..."
    if ! tofu init; then
        error_exit "OpenTofu init failed"
    fi
fi

# Run tofu plan
log_info "Running OpenTofu plan..."

PLAN_FILE="/tmp/tofu-plan-$(date +%s).tfplan"
PLAN_OUTPUT="/tmp/tofu-plan-output-$(date +%s).txt"

if ! tofu plan -out="$PLAN_FILE" > "$PLAN_OUTPUT" 2>&1; then
    PLAN_ERROR=$(cat "$PLAN_OUTPUT")
    log_error "OpenTofu plan failed:"
    log_error "$PLAN_ERROR"

    send_notification \
        "❌ Infrastructure Plan Failed" \
        "OpenTofu plan failed for $REPO_NAME/$BRANCH_NAME\n\nSee logs for details" \
        "high"

    rm -f "$PLAN_FILE" "$PLAN_OUTPUT"
    exit 1
fi

# Parse plan output
PLAN_SUMMARY=$(cat "$PLAN_OUTPUT")
log_info "Plan completed successfully"
log_debug "Plan output:\n$PLAN_SUMMARY"

# Check if there are changes
if echo "$PLAN_SUMMARY" | grep -q "No changes"; then
    log_info "No infrastructure changes detected"

    send_notification \
        "ℹ️ Infrastructure Check" \
        "No changes detected in OpenTofu configuration for $REPO_NAME/$BRANCH_NAME"

    rm -f "$PLAN_FILE" "$PLAN_OUTPUT"
    exit 0
fi

# Extract change summary
CHANGES=$(echo "$PLAN_SUMMARY" | grep -E "Plan:|to add|to change|to destroy" | tail -1)
log_info "Changes detected: $CHANGES"

# Send plan notification
send_notification \
    "📋 Infrastructure Plan Ready" \
    "OpenTofu plan completed for $REPO_NAME/$BRANCH_NAME\n\n$CHANGES\n\nCommit: $COMMIT_MSG"

# Auto-apply if enabled
if [ "$AUTO_APPLY" = "true" ]; then
    log_warn "Auto-apply is ENABLED - applying changes automatically"

    if tofu apply "$PLAN_FILE"; then
        log_info "Infrastructure updated successfully"

        send_notification \
            "✅ Infrastructure Updated" \
            "OpenTofu apply completed for $REPO_NAME/$BRANCH_NAME\n\n$CHANGES" \
            "high"

        rm -f "$PLAN_FILE" "$PLAN_OUTPUT"
        exit 0
    else
        log_error "OpenTofu apply failed"

        send_notification \
            "❌ Infrastructure Apply Failed" \
            "OpenTofu apply failed for $REPO_NAME/$BRANCH_NAME\n\nManual intervention required" \
            "urgent"

        rm -f "$PLAN_FILE" "$PLAN_OUTPUT"
        exit 1
    fi
else
    log_info "Auto-apply is DISABLED - manual apply required"
    log_info "To apply changes, run:"
    log_info "  cd $TOFU_WORKING_DIR && tofu apply $PLAN_FILE"

    send_notification \
        "⚠️ Infrastructure Approval Needed" \
        "OpenTofu plan ready for $REPO_NAME/$BRANCH_NAME\n\n$CHANGES\n\nManual approval required:\ncd $TOFU_WORKING_DIR && tofu apply" \
        "high"

    # Keep plan file for manual apply
    log_info "Plan file saved: $PLAN_FILE"

    exit 0
fi
