#!/bin/bash
#
# trigger-tofu.sh - Trigger OpenTofu infrastructure update via SSH
# Called by webhook handler when vms.tf changes are detected
#
# Arguments:
#   $1 - repository.full_name (e.g., "PawelWywiol/homelab")
#   $2 - ref (e.g., "refs/heads/main")
#   $3 - commit_message (optional)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Parse webhook arguments
parse_webhook_args "$@" || error_exit "Failed to parse webhook arguments"

COMMIT_MSG="${3:-No commit message}"

log_info "OpenTofu update triggered for: $REPO_NAME/$BRANCH_NAME"
log_info "Commit: $COMMIT_MSG"

# Check if auto-apply is enabled
AUTO_APPLY="${TOFU_AUTO_APPLY:-false}"

# Run OpenTofu script on host via SSH
if run_tofu "$AUTO_APPLY"; then
    if [ "$AUTO_APPLY" = "true" ]; then
        success_exit "Infrastructure updated (auto-apply enabled)"
    else
        log_info "OpenTofu plan completed - manual apply required"
        send_notification \
            "Infrastructure Plan Ready" \
            "OpenTofu plan completed for $REPO_NAME/$BRANCH_NAME\n\nCommit: $COMMIT_MSG\n\nManual approval required" \
            "high"
        exit 0
    fi
else
    error_exit "OpenTofu update failed"
fi
