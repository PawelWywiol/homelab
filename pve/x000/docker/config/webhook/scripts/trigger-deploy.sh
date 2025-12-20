#!/bin/bash
#
# trigger-deploy.sh - Deploy services via SSH to host
# Called by webhook handler when repository changes are detected
#
# Arguments:
#   $1 - repository.full_name (e.g., "PawelWywiol/homelab")
#   $2 - ref (e.g., "refs/heads/main")
#   $3 - target (e.g., "x202", "x201")
#   $4 - service (optional, specific service or "all")
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Parse webhook arguments
parse_webhook_args "$@" || error_exit "Failed to parse webhook arguments"

TARGET="${3:-}"
SERVICE="${4:-all}"

# Validate target
if [ -z "$TARGET" ]; then
    error_exit "Target not specified. Expected: x202, x201, etc."
fi

log_info "Deployment triggered for target=$TARGET service=$SERVICE"

# Run deploy script on host via SSH
if run_deploy "$TARGET" "$SERVICE"; then
    success_exit "Deployed $SERVICE to $TARGET"
else
    error_exit "Failed to deploy $SERVICE to $TARGET"
fi
