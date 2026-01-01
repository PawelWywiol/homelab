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

# Discord embed colors
DISCORD_COLOR_START=16776960     # Yellow/orange
DISCORD_COLOR_SUCCESS=65280      # Green
DISCORD_COLOR_FAILURE=16711680   # Red
DISCORD_COLOR_INFO=3447003       # Blue

# Output truncation limit (Discord embeds max 4096 chars)
OUTPUT_MAX_LENGTH=2000

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

# Send notification via Discord webhook
# Usage: send_notification "title" "message" ["priority"]
# priority: high=red, default=green
send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"

    if [ "${DISCORD_ENABLED:-true}" != "true" ]; then
        log_debug "Notifications disabled, skipping"
        return 0
    fi

    local webhook_url="${DISCORD_WEBHOOK_URL:-}"
    if [ -z "$webhook_url" ]; then
        log_warn "DISCORD_WEBHOOK_URL not set, skipping notification"
        return 1
    fi

    # Color: green=65280 (success), red=16711680 (error/high priority)
    local color=65280
    if [ "$priority" = "high" ]; then
        color=16711680
    fi

    log_debug "Sending Discord notification: $title - $message"

    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$message" \
        --argjson color "$color" \
        '{embeds: [{title: $title, description: $desc, color: $color, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]}')

    if ! curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook_url" | grep -q "^2"; then
        log_warn "Failed to send Discord notification"
        return 1
    fi

    return 0
}

# Truncate text to max length with ellipsis
# Usage: truncate_output "long text" [max_length]
truncate_output() {
    local text="$1"
    local max_len="${2:-$OUTPUT_MAX_LENGTH}"

    if [ ${#text} -le "$max_len" ]; then
        echo "$text"
    else
        echo "${text:0:$((max_len - 3))}..."
    fi
}

# Format duration from seconds to human readable
# Usage: format_duration 125 → "2m 5s"
format_duration() {
    local seconds="$1"

    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        if [ "$secs" -eq 0 ]; then
            echo "${mins}m"
        else
            echo "${mins}m ${secs}s"
        fi
    else
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        echo "${hours}h ${mins}m"
    fi
}

# Build Discord embed JSON with fields
# Usage: build_embed "title" color "description" ["footer"]
build_embed() {
    local title="$1"
    local color="$2"
    local description="$3"
    local footer="${4:-}"

    if [ -n "$footer" ]; then
        jq -n \
            --arg title "$title" \
            --arg desc "$description" \
            --argjson color "$color" \
            --arg footer "$footer" \
            '{embeds: [{title: $title, description: $desc, color: $color, footer: {text: $footer}, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]}'
    else
        jq -n \
            --arg title "$title" \
            --arg desc "$description" \
            --argjson color "$color" \
            '{embeds: [{title: $title, description: $desc, color: $color, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]}'
    fi
}

# Send start notification for workflow
# Usage: send_start_notification "type" "commit_info" "details"
# type: deploy|tofu
send_start_notification() {
    local type="$1"
    local commit_info="$2"
    local details="$3"

    if [ "${DISCORD_ENABLED:-true}" != "true" ]; then
        log_debug "Notifications disabled, skipping start notification"
        return 0
    fi

    local webhook_url="${DISCORD_WEBHOOK_URL:-}"
    if [ -z "$webhook_url" ]; then
        log_warn "DISCORD_WEBHOOK_URL not set, skipping notification"
        return 1
    fi

    local title emoji
    case "$type" in
        deploy_x000)
            emoji="📦"
            title="$emoji x000 Deploy Started"
            ;;
        deploy_x202|deploy)
            emoji="📦"
            title="$emoji x202 Deploy Started"
            ;;
        stop_x000)
            emoji="🛑"
            title="$emoji x000 Stop Started"
            ;;
        stop_x202|stop)
            emoji="🛑"
            title="$emoji x202 Stop Started"
            ;;
        tofu)
            emoji="🔧"
            title="$emoji OpenTofu Plan Started"
            ;;
        *)
            emoji="🚀"
            title="$emoji Workflow Started"
            ;;
    esac

    local message
    message=$(printf "%s\n━━━━━━━━━━━━━━━━━━━━━━\n%s" "$commit_info" "$details")

    log_debug "Sending start notification: $title"

    local payload
    payload=$(build_embed "$title" "$DISCORD_COLOR_START" "$message")

    if ! curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook_url" | grep -q "^2"; then
        log_warn "Failed to send Discord start notification"
        return 1
    fi

    return 0
}

# Send end notification for workflow
# Usage: send_end_notification "type" "commit_info" "status" "duration_secs" "output"
# type: deploy|tofu
# status: success|failure
send_end_notification() {
    local type="$1"
    local commit_info="$2"
    local status="$3"
    local duration_secs="$4"
    local output="$5"

    if [ "${DISCORD_ENABLED:-true}" != "true" ]; then
        log_debug "Notifications disabled, skipping end notification"
        return 0
    fi

    local webhook_url="${DISCORD_WEBHOOK_URL:-}"
    if [ -z "$webhook_url" ]; then
        log_warn "DISCORD_WEBHOOK_URL not set, skipping notification"
        return 1
    fi

    local title color emoji duration_str
    duration_str=$(format_duration "$duration_secs")

    case "$type" in
        deploy_x000)
            if [ "$status" = "success" ]; then
                emoji="✅"
                title="$emoji x000 Deploy Success"
                color="$DISCORD_COLOR_SUCCESS"
            else
                emoji="❌"
                title="$emoji x000 Deploy Failed"
                color="$DISCORD_COLOR_FAILURE"
            fi
            ;;
        deploy_x202|deploy)
            if [ "$status" = "success" ]; then
                emoji="✅"
                title="$emoji x202 Deploy Success"
                color="$DISCORD_COLOR_SUCCESS"
            else
                emoji="❌"
                title="$emoji x202 Deploy Failed"
                color="$DISCORD_COLOR_FAILURE"
            fi
            ;;
        stop_x000)
            if [ "$status" = "success" ]; then
                emoji="✅"
                title="$emoji x000 Stop Success"
                color="$DISCORD_COLOR_SUCCESS"
            else
                emoji="❌"
                title="$emoji x000 Stop Failed"
                color="$DISCORD_COLOR_FAILURE"
            fi
            ;;
        stop_x202|stop)
            if [ "$status" = "success" ]; then
                emoji="✅"
                title="$emoji x202 Stop Success"
                color="$DISCORD_COLOR_SUCCESS"
            else
                emoji="❌"
                title="$emoji x202 Stop Failed"
                color="$DISCORD_COLOR_FAILURE"
            fi
            ;;
        tofu)
            if [ "$status" = "success" ]; then
                emoji="✅"
                title="$emoji OpenTofu Plan Ready"
                color="$DISCORD_COLOR_SUCCESS"
            else
                emoji="❌"
                title="$emoji OpenTofu Plan Failed"
                color="$DISCORD_COLOR_FAILURE"
            fi
            ;;
        *)
            if [ "$status" = "success" ]; then
                emoji="✅"
                title="$emoji Workflow Success"
                color="$DISCORD_COLOR_SUCCESS"
            else
                emoji="❌"
                title="$emoji Workflow Failed"
                color="$DISCORD_COLOR_FAILURE"
            fi
            ;;
    esac

    # Build message - only show output on failure
    local message
    if [ "$status" = "failure" ] && [ -n "$output" ]; then
        local truncated_output
        truncated_output=$(truncate_output "$output")
        message=$(printf "%s\n**Duration:** %s\n━━━━━━━━━━━━━━━━━━━━━━\n**Error**\n\`\`\`\n%s\n\`\`\`" \
            "$commit_info" "$duration_str" "$truncated_output")
    else
        message=$(printf "%s\n**Duration:** %s" "$commit_info" "$duration_str")
    fi

    log_debug "Sending end notification: $title"

    local payload
    payload=$(build_embed "$title" "$color" "$message")

    if ! curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$webhook_url" | grep -q "^2"; then
        log_warn "Failed to send Discord end notification"
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

# Run stop script on host
# Usage: run_stop "target" "service"
run_stop() {
    local target="$1"
    local service="$2"
    local repo_path="${REPO_PATH:-~/homelab/pve/x000}"

    log_info "Stopping $service on $target"
    ssh_to_host "${repo_path}/scripts/stop-service.sh $target $service"
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
