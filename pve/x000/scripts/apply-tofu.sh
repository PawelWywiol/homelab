#!/bin/bash
#
# apply-tofu.sh - Run OpenTofu plan/apply for infrastructure changes
# Called by webhook container via SSH
#
# Usage: apply-tofu.sh [auto-apply]
# Example: apply-tofu.sh        # Plan only
#          apply-tofu.sh true   # Auto-apply if TOFU_AUTO_APPLY=true
#

set -euo pipefail

AUTO_APPLY="${1:-false}"
REPO_PATH="${REPO_PATH:-$HOME/homelab}"
TOFU_DIR="${TOFU_DIR:-$REPO_PATH/pve/x000/infra/tofu}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "OpenTofu update triggered"

# Change to repo directory
cd "$REPO_PATH" || { log_error "Failed to cd to $REPO_PATH"; exit 1; }

# Pull latest changes
log_info "Pulling latest changes..."
if ! git pull origin main; then
    log_error "Git pull failed"
    exit 1
fi

# Change to tofu directory
cd "$TOFU_DIR" || { log_error "Failed to cd to $TOFU_DIR"; exit 1; }

# Initialize if needed
if [ ! -d ".terraform" ]; then
    log_info "Initializing OpenTofu..."
    tofu init
fi

# Run plan
PLAN_FILE="/tmp/tofu-plan-$(date +%Y%m%d%H%M%S).tfplan"
log_info "Running tofu plan..."

if ! PLAN_OUTPUT=$(tofu plan -out="$PLAN_FILE" 2>&1); then
    log_error "OpenTofu plan failed:"
    echo "$PLAN_OUTPUT"
    rm -f "$PLAN_FILE"
    exit 1
fi

# Check for changes
if echo "$PLAN_OUTPUT" | grep -q "No changes"; then
    log_info "No infrastructure changes detected"
    rm -f "$PLAN_FILE"
    exit 0
fi

# Show plan summary
log_info "Plan summary:"
echo "$PLAN_OUTPUT" | grep -E "Plan:|to add|to change|to destroy" || true

# Apply if auto-apply enabled
if [ "$AUTO_APPLY" = "true" ]; then
    log_warn "Auto-apply enabled, applying changes..."
    if tofu apply "$PLAN_FILE"; then
        log_info "OpenTofu apply completed successfully"
        rm -f "$PLAN_FILE"
        exit 0
    else
        log_error "OpenTofu apply failed"
        rm -f "$PLAN_FILE"
        exit 1
    fi
else
    log_info "Plan file saved: $PLAN_FILE"
    log_info "To apply manually: cd $TOFU_DIR && tofu apply $PLAN_FILE"
    exit 0
fi
