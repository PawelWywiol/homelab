#!/bin/bash
#
# Trigger Semaphore deployment via API
# Called by webhook handler when repository changes are detected
#
# Arguments:
#   $1 - repository.full_name (e.g., "pawelwywiol/home")
#   $2 - ref (e.g., "refs/heads/main")
#   $3 - action (e.g., "x202-services", "x201-services", "ansible-check")
#

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Parse webhook arguments
parse_webhook_args "$@" || error_exit "Failed to parse webhook arguments"

# Validate required environment variables
validate_env "SEMAPHORE_URL" "SEMAPHORE_API_TOKEN" "SEMAPHORE_PROJECT_ID" || \
    error_exit "Missing required environment variables"

log_info "Semaphore deployment triggered for: $REPO_NAME/$BRANCH_NAME (action: $ACTION)"

# Determine template ID based on action
case "$ACTION" in
    "x202-services")
        TEMPLATE_ID="${SEMAPHORE_TEMPLATE_X202}"
        DESCRIPTION="Deploy x202 services"
        ;;
    "x201-services")
        TEMPLATE_ID="${SEMAPHORE_TEMPLATE_X201}"
        DESCRIPTION="Deploy x201 services"
        ;;
    "ansible-check")
        TEMPLATE_ID="${SEMAPHORE_TEMPLATE_ANSIBLE_CHECK}"
        DESCRIPTION="Ansible syntax check"
        ;;
    *)
        error_exit "Unknown action: $ACTION"
        ;;
esac

if [ -z "$TEMPLATE_ID" ]; then
    error_exit "Template ID not configured for action: $ACTION"
fi

log_info "Using template ID: $TEMPLATE_ID ($DESCRIPTION)"

# Call Semaphore API
if response=$(call_semaphore_api "$SEMAPHORE_PROJECT_ID" "$TEMPLATE_ID" "$GIT_REF"); then
    # Extract task ID from response (if present)
    task_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null || echo "unknown")

    log_info "Semaphore task created: ID=$task_id"

    # Send success notification
    send_notification \
        "🚀 Deployment Started" \
        "$DESCRIPTION triggered for $REPO_NAME/$BRANCH_NAME (Task: $task_id)"

    # Output success message
    echo "Semaphore task created successfully"
    echo "Task ID: $task_id"
    echo "Project: $SEMAPHORE_PROJECT_ID"
    echo "Template: $TEMPLATE_ID"
    echo "Repository: $REPO_FULL_NAME"
    echo "Branch: $BRANCH_NAME"

    exit 0
else
    error_exit "Failed to create Semaphore task for $DESCRIPTION"
fi
