#!/bin/bash
#
# deploy.sh - Deploy services to target host via Ansible
# Called by webhook container via SSH
#
# Usage: deploy.sh <target> [service]
# Example: deploy.sh x202 caddy
#          deploy.sh x202 all
#

set -euo pipefail

TARGET="${1:-}"
SERVICE="${2:-all}"
REPO_PATH="${REPO_PATH:-$HOME/homelab}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate target
if [ -z "$TARGET" ]; then
    log_error "Usage: deploy.sh <target> [service]"
    log_error "Example: deploy.sh x202 caddy"
    exit 1
fi

log_info "Deploying service=$SERVICE to target=$TARGET"

# Change to repo directory
cd "$REPO_PATH" || { log_error "Failed to cd to $REPO_PATH"; exit 1; }

# Pull latest changes
log_info "Pulling latest changes..."
if ! git pull origin main; then
    log_error "Git pull failed"
    exit 1
fi

# Run Ansible playbook
INVENTORY="pve/x000/ansible/inventory/hosts.yml"
PLAYBOOK="pve/x000/ansible/playbooks/deploy-service.yml"

if [ ! -f "$INVENTORY" ]; then
    log_error "Inventory not found: $INVENTORY"
    exit 1
fi

if [ ! -f "$PLAYBOOK" ]; then
    log_error "Playbook not found: $PLAYBOOK"
    exit 1
fi

log_info "Running Ansible playbook..."

ANSIBLE_CMD="ansible-playbook -i $INVENTORY $PLAYBOOK"
ANSIBLE_CMD+=" -e target_host=$TARGET"

if [ "$SERVICE" != "all" ]; then
    ANSIBLE_CMD+=" -e service=$SERVICE"
fi

if $ANSIBLE_CMD; then
    log_info "Deployment completed successfully"
    exit 0
else
    log_error "Deployment failed"
    exit 1
fi
