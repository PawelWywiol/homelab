#!/bin/bash
# Sync files between local and remote host
# Usage: ./sync-files.sh push|pull NAME
#   push NAME - Push files from ./pve/NAME to remote host
#   pull NAME - Pull files from remote host to ./pve/NAME
#
# Configuration is read from ./pve/NAME/.envrc:
#   REMOTE_HOST="user@hostname"
#   REMOTE_FILES=("file1" "dir/file2")

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ACTION=$1
NAME=$2

if [ -z "$ACTION" ] || [ -z "$NAME" ]; then
    echo "Usage: $0 push|pull NAME"
    echo ""
    echo "  push NAME - Push files from ./pve/NAME to remote host"
    echo "  pull NAME - Pull files from remote host to ./pve/NAME"
    echo ""
    echo "Configuration is read from ./pve/NAME/.envrc"
    exit 1
fi

if [ "$ACTION" != "push" ] && [ "$ACTION" != "pull" ]; then
    echo "Error: Invalid action '$ACTION'. Use 'push' or 'pull'."
    exit 1
fi

LOCAL_PATH="$REPO_ROOT/pve/$NAME"
ENVRC_PATH="$LOCAL_PATH/.envrc"

if [ ! -d "$LOCAL_PATH" ]; then
    echo "Error: Directory '$NAME' not found in ./pve/"
    echo "Available directories:"
    ls -1 "$REPO_ROOT/pve/" 2>/dev/null | grep -v '^\.' || echo "  (none)"
    exit 1
fi

if [ ! -f "$ENVRC_PATH" ]; then
    echo "Error: .envrc not found in ./pve/$NAME/"
    echo "Create .envrc with REMOTE_HOST and REMOTE_FILES variables."
    exit 1
fi

# Source the .envrc file
source "$ENVRC_PATH"

if [ -z "$REMOTE_HOST" ]; then
    echo "Error: REMOTE_HOST is empty or not set in ./pve/$NAME/.envrc"
    exit 1
fi

if [ -z "${REMOTE_FILES[*]}" ]; then
    echo "Error: REMOTE_FILES is empty or not set in ./pve/$NAME/.envrc"
    exit 1
fi

# Parse REMOTE_HOST to extract user@host and optional path
# Formats: user@host, user@host:, user@host:/path, user@host:~/path
if [[ "$REMOTE_HOST" =~ ^([^@]+@[^:]+):?(.*)$ ]]; then
    USER_HOST="${BASH_REMATCH[1]}"
    REMOTE_PATH="${BASH_REMATCH[2]}"
else
    echo "Error: Invalid REMOTE_HOST format '$REMOTE_HOST'"
    echo "Expected: user@host, user@host:, user@host:/path, or user@host:~/path"
    exit 1
fi

# Build remote destination (empty path = home directory)
if [ -n "$REMOTE_PATH" ]; then
    # Ensure path ends with / for proper rsync behavior
    REMOTE_PATH="${REMOTE_PATH%/}/"
    REMOTE_DEST="$USER_HOST:$REMOTE_PATH"
else
    REMOTE_DEST="$USER_HOST:"
fi

echo "Syncing $NAME ($ACTION) with $USER_HOST (path: ${REMOTE_PATH:-~/})..."

for item in "${REMOTE_FILES[@]}"; do
    if [ "$ACTION" = "pull" ]; then
        # Pull: remote -> local
        rsync -avPL --no-perms --no-owner --no-group --update --checksum --mkpath --relative "$USER_HOST:${REMOTE_PATH:+$REMOTE_PATH}./$item" "$LOCAL_PATH/"
    else
        # Push: local -> remote
        rsync -avPL --no-perms --no-owner --no-group --update --checksum --mkpath --relative "$LOCAL_PATH/./$item" "$REMOTE_DEST"
    fi
    echo "Synchronized: $item"
done

echo "Done!"
