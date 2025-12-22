#!/bin/sh
#
# Common functions for webhook scripts
# Source this file in trigger scripts: source /scripts/common.sh
#

set -euo pipefail

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
log_debug() {
    if [ "${LOG_LEVEL:-info}" = "debug" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    fi
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# Send notification via ntfy
# Usage: send_notification "title" "message" ["priority"]
send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"

    if [ "${NTFY_ENABLED:-true}" != "true" ]; then
        log_debug "Notifications disabled, skipping"
        return 0
    fi

    local ntfy_url="${NTFY_URL:-https://ntfy.sh}"
    local ntfy_topic="${NTFY_TOPIC:-homelab-wh-b776dffa}"

    log_debug "Sending notification: $title - $message"

    if ! curl -s -o /dev/null \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -d "$message" \
        "${ntfy_url}/${ntfy_topic}"; then
        log_warn "Failed to send notification"
        return 1
    fi

    return 0
}

# Execute command on host via SSH
# Usage: ssh_to_host "command"
ssh_to_host() {
    local command="$1"
    local ssh_host="${SSH_HOST:-host.docker.internal}"
    local ssh_user="${SSH_USER:-code}"
    local ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"

    log_info "Executing on host via SSH: $command"

    if ! ssh -i "$ssh_key" \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
            -o LogLevel=ERROR \
            "${ssh_user}@${ssh_host}" \
            "$command"; then
        log_error "SSH command failed"
        return 1
    fi

    return 0
}

# Run deploy script on host
# Usage: run_deploy "target" "service"
run_deploy() {
    local target="$1"
    local service="${2:-all}"
    local repo_path="${REPO_PATH:-~/homelab/pve/x000}"

    log_info "Deploying $service to $target"
    ssh_to_host "${repo_path}/scripts/deploy.sh $target $service"
}

# Run OpenTofu script on host
# Usage: run_tofu ["auto-apply"]
run_tofu() {
    local auto_apply="${1:-false}"
    local repo_path="${REPO_PATH:-~/homelab/pve/x000}"

    log_info "Running OpenTofu (auto-apply=$auto_apply)"
    ssh_to_host "${repo_path}/scripts/apply-tofu.sh $auto_apply"
}

# Extract repository name from full_name
# Usage: get_repo_name "owner/repo"
get_repo_name() {
    local full_name="$1"
    echo "$full_name" | cut -d'/' -f2
}

# Extract branch name from ref
# Usage: get_branch_name "refs/heads/main"
get_branch_name() {
    local ref="$1"
    echo "$ref" | sed 's|refs/heads/||'
}

# Validate required environment variables
# Usage: validate_env "VAR1" "VAR2" "VAR3"
validate_env() {
    local missing=0

    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable not set: $var"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        return 1
    fi

    return 0
}

# Parse arguments passed from webhook
# Usage: parse_webhook_args "$@"
# Sets: REPO_FULL_NAME, GIT_REF, ACTION
parse_webhook_args() {
    if [ $# -lt 2 ]; then
        log_error "Insufficient arguments. Expected: repository.full_name ref [action]"
        return 1
    fi

    export REPO_FULL_NAME="$1"
    export GIT_REF="$2"
    export ACTION="${3:-deploy}"

    export REPO_NAME=$(get_repo_name "$REPO_FULL_NAME")
    export BRANCH_NAME=$(get_branch_name "$GIT_REF")

    log_debug "Parsed args: repo=$REPO_FULL_NAME ref=$GIT_REF action=$ACTION"
    log_info "Repository: $REPO_NAME, Branch: $BRANCH_NAME, Action: $ACTION"

    return 0
}

# Error handler
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"

    log_error "$message"
    send_notification "❌ Webhook Error" "$message" "high"
    exit "$exit_code"
}

# Success handler
success_exit() {
    local message="$1"

    log_info "$message"
    send_notification "✅ Webhook Success" "$message"
    exit 0
}
