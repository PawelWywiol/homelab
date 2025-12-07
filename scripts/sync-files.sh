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

echo "Syncing $NAME ($ACTION) with $REMOTE_HOST..."

for item in "${REMOTE_FILES[@]}"; do
    if [ "$ACTION" = "pull" ]; then
        # Pull: remote -> local
        rsync -avPL --no-perms --no-owner --no-group --update --checksum --relative "$REMOTE_HOST:./$item" "$LOCAL_PATH/"
    else
        # Push: local -> remote
        rsync -avPL --no-perms --no-owner --no-group --update --checksum --relative "$LOCAL_PATH/./$item" "$REMOTE_HOST:~/"
    fi
    echo "Synchronized: $item"
done

echo "Done!"
