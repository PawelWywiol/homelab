#!/bin/bash
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

# Call Semaphore API
# Usage: call_semaphore_api "project_id" "template_id" "git_ref"
call_semaphore_api() {
    local project_id="$1"
    local template_id="$2"
    local git_ref="${3:-refs/heads/main}"

    local semaphore_url="${SEMAPHORE_URL:-http://localhost:3001}"
    local api_token="${SEMAPHORE_API_TOKEN}"

    if [ -z "$api_token" ]; then
        log_error "SEMAPHORE_API_TOKEN not set"
        return 1
    fi

    log_info "Triggering Semaphore task: project=$project_id template=$template_id ref=$git_ref"

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"template_id\": ${template_id},
            \"environment\": \"{\\\"git_ref\\\": \\\"${git_ref}\\\"}\"
        }" \
        "${semaphore_url}/api/project/${project_id}/tasks")

    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    log_debug "Semaphore API response: HTTP $http_code - $body"

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        log_info "Semaphore task created successfully"
        echo "$body"
        return 0
    else
        log_error "Semaphore API request failed: HTTP $http_code"
        log_error "Response: $body"
        return 1
    fi
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
