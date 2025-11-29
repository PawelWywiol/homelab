#!/bin/bash
#
# Backup script for x199 control node
# Backs up: Ansible vault, SSH keys, Semaphore DB, Caddy certs, OpenTofu state
#
# Usage: ./backup-control-node.sh [backup-destination]
#

set -euo pipefail

# Configuration
BACKUP_DEST="${1:-/opt/backups/control-node}"
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_DEST}/${BACKUP_DATE}"
GPG_RECIPIENT="${GPG_RECIPIENT:-code@x199}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on control node
if [ "$(hostname)" != "x199" ]; then
    log_warn "This script is designed to run on x199 control node"
fi

# Create backup directory
log_info "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# Backup Ansible vault password
log_info "Backing up Ansible vault password..."
if [ -f ~/.ansible/vault_password ]; then
    cp ~/.ansible/vault_password "${BACKUP_DIR}/vault_password"
    chmod 600 "${BACKUP_DIR}/vault_password"
else
    log_warn "Ansible vault password not found"
fi

# Backup SSH keys (GPG encrypted)
log_info "Backing up SSH keys..."
if [ -f ~/.ssh/id_ed25519 ]; then
    tar czf - -C ~/.ssh id_ed25519 id_ed25519.pub | \
        gpg --encrypt --recipient "${GPG_RECIPIENT}" \
        > "${BACKUP_DIR}/ssh-keys.tar.gz.gpg"
else
    log_warn "SSH keys not found at ~/.ssh/id_ed25519"
fi

# Backup Semaphore database
log_info "Backing up Semaphore database..."
SEMAPHORE_CONFIG="${SEMAPHORE_DIR:-/home/code/semaphore}/config"
if [ -d "${SEMAPHORE_CONFIG}" ]; then
    tar czf "${BACKUP_DIR}/semaphore-config.tar.gz" -C "$(dirname ${SEMAPHORE_CONFIG})" config
else
    log_warn "Semaphore config not found at ${SEMAPHORE_CONFIG}"
fi

# Backup Caddy certificates
log_info "Backing up Caddy certificates..."
CADDY_DATA="${HOME}/docker/config/caddy/data"
if [ -d "${CADDY_DATA}" ]; then
    tar czf "${BACKUP_DIR}/caddy-data.tar.gz" -C "$(dirname ${CADDY_DATA})" data
else
    log_warn "Caddy data not found at ${CADDY_DATA}"
fi

# Backup OpenTofu state (if local)
log_info "Backing up OpenTofu state..."
TOFU_DIR="/home/code/home/infra/tofu"
if [ -f "${TOFU_DIR}/terraform.tfstate" ]; then
    cp "${TOFU_DIR}/terraform.tfstate" "${BACKUP_DIR}/terraform.tfstate"
    # Also backup tfvars (contains secrets)
    if [ -f "${TOFU_DIR}/terraform.tfvars" ]; then
        gpg --encrypt --recipient "${GPG_RECIPIENT}" \
            < "${TOFU_DIR}/terraform.tfvars" \
            > "${BACKUP_DIR}/terraform.tfvars.gpg"
    fi
else
    log_info "No local OpenTofu state found (may be using remote backend)"
fi

# Create checksum file
log_info "Creating checksums..."
cd "${BACKUP_DIR}"
sha256sum * > checksums.txt

# Create backup manifest
log_info "Creating backup manifest..."
cat > "${BACKUP_DIR}/manifest.txt" <<EOF
Backup Date: ${BACKUP_DATE}
Hostname: $(hostname)
User: $(whoami)
Backup Path: ${BACKUP_DIR}

Files backed up:
$(ls -lh)

Total size: $(du -sh ${BACKUP_DIR} | cut -f1)
EOF

# Cleanup old backups (keep last 30 days)
log_info "Cleaning up old backups..."
find "${BACKUP_DEST}" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true

# Final summary
log_info "Backup complete!"
echo ""
log_info "Backup location: ${BACKUP_DIR}"
log_info "Files backed up:"
ls -lh "${BACKUP_DIR}"
echo ""
log_warn "IMPORTANT: Store this backup securely and off-site!"
log_warn "Decrypt SSH keys with: gpg --decrypt ssh-keys.tar.gz.gpg | tar xzf -"
log_warn "Decrypt tfvars with: gpg --decrypt terraform.tfvars.gpg > terraform.tfvars"
