#!/bin/bash
#
# stop-service.sh - Stop and remove Docker Compose service on target host
# Called by webhook container via SSH when service folder is removed
#
# Usage: stop-service.sh <target> <service>
# Example: stop-service.sh x202 caddy
#

set -euo pipefail

TARGET="${1:-}"
SERVICE="${2:-}"
REPO_PATH="${REPO_PATH:-$HOME/homelab}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$SERVICE" ]; then
    log_error "Usage: stop-service.sh <target> <service>"
    log_error "Example: stop-service.sh x202 caddy"
    exit 1
fi

log_info "Stopping service=$SERVICE on target=$TARGET"

# Change to repo directory
cd "$REPO_PATH" || { log_error "Failed to cd to $REPO_PATH"; exit 1; }

# Pull latest changes (to ensure we have the removal)
log_info "Pulling latest changes..."
if ! git pull origin main; then
    log_error "Git pull failed"
    exit 1
fi

# Run Ansible playbook
INVENTORY="pve/x000/ansible/inventory/hosts.yml"
PLAYBOOK="pve/x000/ansible/playbooks/stop-service.yml"

if [ ! -f "$INVENTORY" ]; then
    log_error "Inventory not found: $INVENTORY"
    exit 1
fi

if [ ! -f "$PLAYBOOK" ]; then
    log_error "Playbook not found: $PLAYBOOK"
    exit 1
fi

log_info "Running Ansible playbook to stop service..."

ANSIBLE_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK"
ANSIBLE_CMD+=" -e target_host=$TARGET"
ANSIBLE_CMD+=" -e service=$SERVICE"

if $ANSIBLE_CMD; then
    log_info "Service $SERVICE stopped successfully"
    exit 0
else
    log_error "Failed to stop service $SERVICE"
    exit 1
fi
