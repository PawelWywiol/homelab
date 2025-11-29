#!/bin/bash
#
# Verify backup integrity for control node
# Checks: existence, age, checksums, restore capability
#
# Usage: ./verify-backups.sh [backup-destination]
#

set -euo pipefail

# Configuration
BACKUP_DEST="${1:-/opt/backups/control-node}"
MAX_AGE_HOURS=24
TEMP_RESTORE="/tmp/backup-verify-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

# Find latest backup
log_info "Finding latest backup in ${BACKUP_DEST}..."
LATEST_BACKUP=$(find "${BACKUP_DEST}" -maxdepth 1 -type d -name "20*" | sort -r | head -n1)

if [ -z "${LATEST_BACKUP}" ]; then
    log_error "No backups found in ${BACKUP_DEST}"
    exit 1
fi

log_info "Latest backup: ${LATEST_BACKUP}"
echo ""

# Check 1: Backup age
log_info "Check 1: Verifying backup age..."
BACKUP_TIME=$(stat -f "%Sm" -t "%s" "${LATEST_BACKUP}" 2>/dev/null || stat -c "%Y" "${LATEST_BACKUP}" 2>/dev/null)
CURRENT_TIME=$(date +%s)
AGE_HOURS=$(( (CURRENT_TIME - BACKUP_TIME) / 3600 ))

if [ ${AGE_HOURS} -le ${MAX_AGE_HOURS} ]; then
    check_pass "Backup is ${AGE_HOURS} hours old (< ${MAX_AGE_HOURS}h)"
else
    check_fail "Backup is ${AGE_HOURS} hours old (> ${MAX_AGE_HOURS}h)"
fi

# Check 2: Required files exist
log_info "Check 2: Verifying required files..."
REQUIRED_FILES=(
    "vault_password"
    "ssh-keys.tar.gz.gpg"
    "semaphore-config.tar.gz"
    "caddy-data.tar.gz"
    "checksums.txt"
    "manifest.txt"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "${LATEST_BACKUP}/${file}" ]; then
        check_pass "Found: ${file}"
    else
        check_fail "Missing: ${file}"
    fi
done

# Check 3: Verify checksums
log_info "Check 3: Verifying checksums..."
if [ -f "${LATEST_BACKUP}/checksums.txt" ]; then
    cd "${LATEST_BACKUP}"
    if sha256sum -c checksums.txt > /dev/null 2>&1; then
        check_pass "All checksums valid"
    else
        check_fail "Checksum verification failed"
    fi
    cd - > /dev/null
else
    check_fail "Checksum file not found"
fi

# Check 4: Test restore capability
log_info "Check 4: Testing restore capability..."
mkdir -p "${TEMP_RESTORE}"

# Test tarball extraction
if [ -f "${LATEST_BACKUP}/semaphore-config.tar.gz" ]; then
    if tar tzf "${LATEST_BACKUP}/semaphore-config.tar.gz" > /dev/null 2>&1; then
        check_pass "Semaphore backup is extractable"
    else
        check_fail "Semaphore backup is corrupted"
    fi
fi

if [ -f "${LATEST_BACKUP}/caddy-data.tar.gz" ]; then
    if tar tzf "${LATEST_BACKUP}/caddy-data.tar.gz" > /dev/null 2>&1; then
        check_pass "Caddy backup is extractable"
    else
        check_fail "Caddy backup is corrupted"
    fi
fi

# Test GPG decryption (if gpg available)
if command -v gpg &> /dev/null; then
    if [ -f "${LATEST_BACKUP}/ssh-keys.tar.gz.gpg" ]; then
        if gpg --list-packets "${LATEST_BACKUP}/ssh-keys.tar.gz.gpg" > /dev/null 2>&1; then
            check_pass "SSH keys backup is encrypted properly"
        else
            check_fail "SSH keys backup encryption is invalid"
        fi
    fi
else
    log_warn "GPG not available, skipping encryption check"
fi

# Cleanup
rm -rf "${TEMP_RESTORE}"

# Check 5: Disk space
log_info "Check 5: Verifying available disk space..."
BACKUP_SIZE=$(du -sb "${BACKUP_DEST}" | cut -f1)
AVAILABLE_SPACE=$(df -B1 "${BACKUP_DEST}" | tail -1 | awk '{print $4}')
SPACE_RATIO=$(( BACKUP_SIZE * 100 / AVAILABLE_SPACE ))

if [ ${SPACE_RATIO} -lt 80 ]; then
    check_pass "Disk space OK (${SPACE_RATIO}% used)"
else
    check_warn "Disk space low (${SPACE_RATIO}% used)"
fi

# Summary
echo ""
log_info "=== Verification Summary ==="
echo "Total checks: $((CHECKS_PASSED + CHECKS_FAILED))"
echo "Passed: ${CHECKS_PASSED}"
echo "Failed: ${CHECKS_FAILED}"
echo ""

if [ ${CHECKS_FAILED} -eq 0 ]; then
    log_info "All checks passed! Backups are healthy."
    exit 0
else
    log_error "Some checks failed! Review backup system."
    exit 1
fi
