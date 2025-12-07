#!/bin/bash
set -e

# =============================================================================
# init-host.sh - Universal host initialization script
# Supports: Ubuntu, Debian, Raspberry Pi OS (VMs, LXC containers, bare metal)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
USERNAME="code"
AUTHORIZED_KEYS=""
DISABLE_DNS_STUB=false
SKIP_DOCKER=false
SKIP_USER=false

# Load .env if exists
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo "Loading config from $SCRIPT_DIR/.env"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
fi

# Parse CLI args
while [[ $# -gt 0 ]]; do
    case $1 in
        --disable-dns-stub) DISABLE_DNS_STUB=true; shift ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --skip-user) SKIP_USER=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --disable-dns-stub  Disable systemd-resolved DNSStubListener (for local DNS servers)"
            echo "  --skip-docker       Skip Docker installation"
            echo "  --skip-user         Skip user creation (for cloud-init pre-created users)"
            echo ""
            echo "Config via $SCRIPT_DIR/.env:"
            echo "  USERNAME=code              User to create"
            echo "  AUTHORIZED_KEYS=\"ssh-...\"  SSH keys to add (space-separated)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# =============================================================================
# Detection functions
# =============================================================================

detect_environment() {
    local virt=""
    if command -v systemd-detect-virt &>/dev/null; then
        virt=$(systemd-detect-virt 2>/dev/null || echo "none")
    fi

    if [[ "$virt" == "lxc" ]]; then
        echo "lxc"
    elif [[ "$virt" =~ ^(kvm|qemu|vmware|microsoft|oracle|xen|bochs|parallels)$ ]]; then
        echo "vm"
    elif [[ -f /proc/device-tree/model ]] && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
        echo "rpi"
    elif [[ "$virt" == "none" ]] || [[ -z "$virt" ]]; then
        echo "baremetal"
    else
        echo "unknown"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# =============================================================================
# Helper functions
# =============================================================================

run_as_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        exit 1
    fi
}

user_exists() {
    id "$1" &>/dev/null
}

group_exists() {
    getent group "$1" &>/dev/null
}

# =============================================================================
# Main installation functions
# =============================================================================

install_base_packages() {
    echo "==> Installing base packages..."
    apt-get update
    apt-get upgrade -y
    apt-get install -y ca-certificates curl sudo zsh build-essential rsync
    apt-get autoremove -y
}

install_qemu_guest_agent() {
    local env=$1
    if [[ "$env" == "vm" ]]; then
        echo "==> Installing QEMU guest agent (VM detected)..."
        apt-get install -y qemu-guest-agent
        systemctl enable qemu-guest-agent || true
        systemctl start qemu-guest-agent || true
    else
        echo "==> Skipping QEMU guest agent (not a VM)"
    fi
}

install_docker() {
    if [[ "$SKIP_DOCKER" == true ]]; then
        echo "==> Skipping Docker installation (--skip-docker)"
        return
    fi

    echo "==> Installing Docker..."
    if command -v docker &>/dev/null; then
        echo "    Docker already installed, updating..."
    fi
    curl -fsSL https://get.docker.com | sh

    # Ensure docker group exists
    if ! group_exists docker; then
        groupadd docker
    fi
}

setup_user() {
    if [[ "$SKIP_USER" == true ]]; then
        echo "==> Skipping user setup (--skip-user)"
        return
    fi

    echo "==> Setting up user: $USERNAME"

    # Create user if not exists
    if ! user_exists "$USERNAME"; then
        echo "    Creating user $USERNAME..."
        useradd -m -s "$(which zsh)" "$USERNAME"
    else
        echo "    User $USERNAME already exists"
    fi

    # Add to groups
    if group_exists docker; then
        usermod -aG docker "$USERNAME"
        echo "    Added to docker group"
    fi
    usermod -aG sudo "$USERNAME"
    echo "    Added to sudo group"

    # Set zsh as shell if not already
    local current_shell
    current_shell=$(getent passwd "$USERNAME" | cut -d: -f7)
    if [[ "$current_shell" != *"zsh"* ]]; then
        chsh -s "$(which zsh)" "$USERNAME"
        echo "    Shell set to zsh"
    fi
}

setup_ssh() {
    if [[ "$SKIP_USER" == true ]]; then
        echo "==> Skipping SSH setup (--skip-user)"
        return
    fi

    local user_home
    user_home=$(eval echo "~$USERNAME")
    local ssh_dir="$user_home/.ssh"

    echo "==> Setting up SSH for $USERNAME..."

    # Create .ssh directory
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        echo "    Created $ssh_dir"
    fi

    # Generate SSH key if not exists
    if [[ ! -f "$ssh_dir/id_rsa" ]]; then
        su - "$USERNAME" -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
        echo "    Generated SSH key"
    else
        echo "    SSH key already exists"
    fi

    # Setup authorized_keys
    local auth_file="$ssh_dir/authorized_keys"
    if [[ ! -f "$auth_file" ]]; then
        touch "$auth_file"
    fi

    # Append AUTHORIZED_KEYS if set (dedup)
    if [[ -n "$AUTHORIZED_KEYS" ]]; then
        echo "    Adding authorized keys..."
        # Split by newline and add each key
        while IFS= read -r key; do
            if [[ -n "$key" ]] && ! grep -qF "$key" "$auth_file" 2>/dev/null; then
                echo "$key" >> "$auth_file"
                echo "    Added key: ${key:0:40}..."
            fi
        done <<< "$AUTHORIZED_KEYS"
    fi

    # Fix permissions
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_file"
    chown -R "$USERNAME:$USERNAME" "$ssh_dir"
    echo "    SSH permissions set"
}

disable_dns_stub_listener() {
    if [[ "$DISABLE_DNS_STUB" != true ]]; then
        return
    fi

    echo "==> Handling DNSStubListener..."

    # Check if systemd-resolved is installed and running
    if ! systemctl is-active systemd-resolved &>/dev/null; then
        echo "    systemd-resolved not active, skipping"
        return
    fi

    local conf="/etc/systemd/resolved.conf"
    if [[ ! -f "$conf" ]]; then
        echo "    $conf not found, skipping"
        return
    fi

    # Check if already disabled
    if grep -q "^DNSStubListener=no" "$conf"; then
        echo "    DNSStubListener already disabled"
        return
    fi

    echo "    Disabling DNSStubListener..."
    if grep -q "^#DNSStubListener" "$conf"; then
        sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' "$conf"
    elif grep -q "^DNSStubListener" "$conf"; then
        sed -i 's/^DNSStubListener=.*/DNSStubListener=no/' "$conf"
    else
        echo "DNSStubListener=no" >> "$conf"
    fi

    systemctl restart systemd-resolved
    echo "    DNSStubListener disabled and service restarted"
}

print_summary() {
    local env=$1
    local os=$2

    echo ""
    echo "============================================================================="
    echo "Host initialization complete!"
    echo "============================================================================="
    echo "Environment: $env"
    echo "OS: $os"
    echo "User: $USERNAME"
    echo ""
    echo "Next steps:"
    echo "  1. Set password:  passwd $USERNAME"
    echo "  2. Switch user:   su - $USERNAME"
    echo "  3. Install oh-my-zsh:"
    echo "     sh -c \"\$(curl -fsSL https://install.ohmyz.sh)\""
    echo "  4. Install powerlevel10k:"
    echo "     git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \"\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/themes/powerlevel10k\""
    echo "  5. Install zsh plugins:"
    echo "     git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    echo "     git clone https://github.com/zsh-users/zsh-syntax-highlighting \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    echo ""
    if [[ "$env" == "vm" ]] || [[ "$env" == "rpi" ]]; then
        echo "Reboot recommended: sudo reboot"
    fi
    echo "============================================================================="
}

# =============================================================================
# Main
# =============================================================================

main() {
    run_as_root

    local env os
    env=$(detect_environment)
    os=$(detect_os)

    echo "============================================================================="
    echo "init-host.sh - Universal Host Initialization"
    echo "============================================================================="
    echo "Detected environment: $env"
    echo "Detected OS: $os"
    echo "Username: $USERNAME"
    echo "Disable DNS stub: $DISABLE_DNS_STUB"
    echo "Skip Docker: $SKIP_DOCKER"
    echo "Skip user: $SKIP_USER"
    echo "============================================================================="
    echo ""

    install_base_packages
    install_qemu_guest_agent "$env"
    install_docker
    setup_user
    setup_ssh
    disable_dns_stub_listener

    print_summary "$env" "$os"
}

main "$@"
