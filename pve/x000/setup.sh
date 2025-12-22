#!/usr/bin/env bash
#
# Setup script for x000 control node
# Transforms a fresh machine into a fully configured control node
#
# Usage (on x000):
#   git clone https://github.com/PawelWywiol/homelab.git
#   cd ~/homelab/pve/x000
#   cp setup.env.example .env
#   nano .env  # Configure required values
#   make setup
#
# Idempotent: Safe to re-run - skips already installed components
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Logging
# =============================================================================

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC} $1 (already done)"; }

# =============================================================================
# Validation
# =============================================================================

load_env() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Create from template: cp setup.env.example .env"
        exit 1
    fi

    set -a
    source "$ENV_FILE"
    set +a

    # Set defaults
    REPO_PATH="${REPO_PATH:-${HOME}}"
    TIMEZONE="${TIMEZONE:-Europe/Warsaw}"

    # Validate required
    local required=(BASE_DOMAIN CONTROL_NODE_IP LOCAL_NETWORK_RANGE CLOUDFLARE_API_TOKEN)
    for var in "${required[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required variable $var not set in .env"
            exit 1
        fi
    done
}

check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run as root. Script uses sudo when needed."
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        log_info "Detected OS: $OS_ID $OS_VERSION"
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    if [ "$OS_ID" != "ubuntu" ] && [ "$OS_ID" != "debian" ] && [ "$OS_ID" != "raspbian" ]; then
        log_error "Unsupported OS: $OS_ID. Supports Ubuntu/Debian/Raspbian only."
        exit 1
    fi
}

# =============================================================================
# Installation Functions (Idempotent)
# =============================================================================

install_docker() {
    log_step "Checking Docker..."

    if command -v docker &>/dev/null; then
        log_skip "Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
        return 0
    fi

    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    log_warn "Added $USER to docker group. May need to re-login."

    # Install docker compose plugin
    sudo apt-get install -y docker-compose-plugin

    log_info "Docker installed successfully"
}

install_base_packages() {
    log_step "Checking base packages..."

    local packages=(curl wget git jq rsync sshpass python3 python3-pip gnupg)
    local to_install=()

    for pkg in "${packages[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -eq 0 ]; then
        log_skip "Base packages"
        return 0
    fi

    log_info "Installing: ${to_install[*]}"
    sudo apt-get update
    sudo apt-get install -y "${to_install[@]}"

    if [ "$OS_ID" = "ubuntu" ]; then
        if ! dpkg -l software-properties-common &>/dev/null; then
            sudo apt-get install -y software-properties-common
        fi
    fi
}

install_ansible() {
    log_step "Checking Ansible..."

    if command -v ansible &>/dev/null; then
        log_skip "Ansible $(ansible --version | head -n1 | awk '{print $3}')"

        # Ensure collections installed
        ansible-galaxy collection install community.docker community.general ansible.posix --force-with-deps &>/dev/null || true
        return 0
    fi

    log_info "Installing Ansible..."
    if [ "$OS_ID" = "ubuntu" ]; then
        sudo add-apt-repository --yes --update ppa:ansible/ansible
    fi
    sudo apt-get install -y ansible

    # Install collections
    log_info "Installing Ansible collections..."
    ansible-galaxy collection install community.docker
    ansible-galaxy collection install community.general
    ansible-galaxy collection install ansible.posix

    log_info "Ansible installed: $(ansible --version | head -n1)"
}

install_opentofu() {
    log_step "Checking OpenTofu..."

    if command -v tofu &>/dev/null; then
        log_skip "OpenTofu $(tofu --version | head -n1 | awk '{print $2}')"
        return 0
    fi

    log_info "Installing OpenTofu..."
    curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
    chmod +x /tmp/install-opentofu.sh
    sudo /tmp/install-opentofu.sh --install-method deb
    rm /tmp/install-opentofu.sh

    log_info "OpenTofu installed: $(tofu --version | head -n1)"
}

# =============================================================================
# Setup Functions (Idempotent)
# =============================================================================

setup_ansible_vault() {
    log_step "Checking Ansible vault..."

    mkdir -p ~/.ansible
    chmod 700 ~/.ansible

    if [ -f ~/.ansible/vault_password ]; then
        log_skip "Ansible vault password"
        return 0
    fi

    log_info "Generating Ansible vault password..."
    openssl rand -base64 32 > ~/.ansible/vault_password
    chmod 600 ~/.ansible/vault_password
    log_warn "Vault password: ~/.ansible/vault_password"
}

setup_ssh_key() {
    log_step "Checking SSH key..."

    if [ -z "${SSH_KEY_NAME:-}" ]; then
        log_skip "SSH key (SSH_KEY_NAME not set)"
        return 0
    fi

    local key_path="$HOME/.ssh/$SSH_KEY_NAME"

    if [ -f "$key_path" ]; then
        log_skip "SSH key $key_path"
        return 0
    fi

    log_info "Generating SSH key..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "ansible@$(hostname)" -f "$key_path" -N ""
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    log_warn "SSH public key for managed nodes:"
    cat "${key_path}.pub"
}

setup_docker_network() {
    log_step "Checking Docker network..."

    if docker network inspect homelab &>/dev/null; then
        log_skip "Docker network 'homelab'"
        return 0
    fi

    log_info "Creating Docker network 'homelab'..."
    docker network create homelab
}

generate_secrets() {
    log_step "Generating secrets..."

    # Webhook secret
    if [ -z "${GITHUB_WEBHOOK_SECRET:-}" ]; then
        GITHUB_WEBHOOK_SECRET=$(openssl rand -hex 32)
        log_info "Generated GITHUB_WEBHOOK_SECRET"
    fi
}

setup_caddy() {
    log_step "Setting up Caddy..."

    local caddy_dir="${SCRIPT_DIR}/docker/config/caddy"

    # Validate Caddyfile exists (now tracked in git, not generated)
    local caddyfile="${caddy_dir}/Caddyfile"
    if [ ! -f "$caddyfile" ]; then
        log_warn "Caddyfile not found at ${caddyfile}"
        log_warn "Caddyfile should be committed to git. Check repository or create manually."
    fi

    # Create .env file
    local env_file="${caddy_dir}/.env"
    if [ -f "$env_file" ]; then
        log_skip "Caddy .env"
    else
        log_info "Creating Caddy .env..."
        cat > "$env_file" <<EOF
# Caddy Configuration - Generated by setup.sh
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
CLOUDFLARE_EMAIL=${CLOUDFLARE_EMAIL:-}
BASE_DOMAIN=${BASE_DOMAIN}
LOCAL_NETWORK_RANGE=${LOCAL_NETWORK_RANGE}
EOF
        chmod 600 "$env_file"
    fi
}

setup_webhook() {
    log_step "Setting up Webhook..."

    local webhook_dir="${SCRIPT_DIR}/docker/config/webhook"

    # Ensure scripts are executable
    chmod +x "${webhook_dir}"/scripts/*.sh 2>/dev/null || true

    # Create .env file
    local env_file="${webhook_dir}/.env"
    if [ -f "$env_file" ]; then
        log_skip "Webhook .env"
    else
        log_info "Creating Webhook .env..."
        cat > "$env_file" <<EOF
# Webhook Configuration - Generated by setup.sh
GITHUB_WEBHOOK_SECRET=${GITHUB_WEBHOOK_SECRET}
REPO_PATH=${REPO_PATH}
TOFU_AUTO_APPLY=false
TOFU_WORKING_DIR=${REPO_PATH}/infra/tofu
# Discord notifications - set DISCORD_WEBHOOK_URL manually after setup
DISCORD_ENABLED=true
DISCORD_WEBHOOK_URL=
UID=$(id -u)
GID=$(id -g)
TIMEZONE=${TIMEZONE}
LOG_LEVEL=info
EOF
        chmod 600 "$env_file"
    fi
}

# =============================================================================
# Service Management
# =============================================================================

start_services() {
    log_step "Starting services..."

    cd "$SCRIPT_DIR"

    log_info "Starting Caddy..."
    make caddy up

    log_info "Starting Webhook..."
    make webhook up
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    local wh_sub="${WEBHOOK_SUBDOMAIN:-webhook}"

    echo ""
    echo "============================================================================="
    log_info "Setup complete!"
    echo "============================================================================="
    echo ""
    log_info "Services running:"
    echo "  - Caddy (reverse proxy)"
    echo "  - Webhook (GitHub handler)"
    echo ""
    log_info "Installed tools:"
    echo "  - Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "  - Ansible: $(ansible --version | head -n1 | awk '{print $3}')"
    echo "  - OpenTofu: $(tofu --version | head -n1 | awk '{print $2}')"
    echo ""
    log_warn "Next steps:"
    echo ""
    echo "  1. Configure DNS:"
    echo "     ${wh_sub}.${BASE_DOMAIN} → ${CONTROL_NODE_IP}"
    echo "     ${BASE_DOMAIN} → ${CONTROL_NODE_IP}"
    echo ""
    echo "  2. Configure GitHub webhook:"
    echo "     URL: https://${wh_sub}.${BASE_DOMAIN}/hooks/deploy-x202-services"
    echo "     Secret: ${GITHUB_WEBHOOK_SECRET}"
    echo "     Events: Push"
    echo ""

    if [ -n "${SSH_KEY_NAME:-}" ]; then
        echo "  3. Distribute SSH key to managed nodes:"
        if [ -n "${MANAGED_NODES:-}" ]; then
            for node in ${MANAGED_NODES}; do
                echo "     ssh-copy-id -i ~/.ssh/${SSH_KEY_NAME}.pub \$USER@${node}"
            done
        else
            echo "     ssh-copy-id -i ~/.ssh/${SSH_KEY_NAME}.pub \$USER@<node-ip>"
        fi
        echo ""
    fi

    log_warn "Save these credentials:"
    echo "  - Vault password: ~/.ansible/vault_password"
    echo "  - Webhook secret: ${GITHUB_WEBHOOK_SECRET}"
    echo ""
    log_info "Manage services:"
    echo "  make caddy|webhook|portainer|cloudflared|pihole [up|down|restart|logs]"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "============================================================================="
    log_info "x000 Control Node Setup"
    echo "============================================================================="
    echo ""

    # Validation
    check_not_root
    load_env
    detect_os

    # Install tools
    install_docker
    install_base_packages
    install_ansible
    install_opentofu

    # Setup
    setup_ansible_vault
    setup_ssh_key
    setup_docker_network
    generate_secrets
    setup_caddy
    setup_webhook

    # Start
    start_services

    # Done
    print_summary
}

main "$@"
