#!/bin/bash
set -e

# =============================================================================
# init-development-host.sh - Developer workstation initialization
# Supports: Ubuntu, Debian (VMs, LXC containers, bare metal)
# Installs: Homebrew, Neovim, ZSH stack, PHP/Node dev tools
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
USERNAME="code"
AUTHORIZED_KEYS=""
SKIP_PHP=true       # PHP opt-in (use --install-php)
SKIP_NODE=false
SKIP_USER=false
SKIP_DOCKER=false

# Load .env if exists
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo "Loading config from $SCRIPT_DIR/.env"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
fi

# Parse CLI args
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-php) SKIP_PHP=false; shift ;;
        --skip-node) SKIP_NODE=true; shift ;;
        --skip-user) SKIP_USER=true; shift ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Developer workstation initialization script."
            echo "Installs: Homebrew, Neovim, ZSH stack, Docker, PHP/Node dev tools"
            echo ""
            echo "Options:"
            echo "  --install-php   Install PHP stack (7.4, 8.3, composer) - disabled by default"
            echo "  --skip-node     Skip Node.js installation (fnm + Node 20)"
            echo "  --skip-docker   Skip Docker installation"
            echo "  --skip-user     Skip user creation"
            echo ""
            echo "Config via $SCRIPT_DIR/.env:"
            echo "  USERNAME=code              User to create"
            echo "  AUTHORIZED_KEYS=\"ssh-...\"  SSH keys to add"
            echo "  SKIP_PHP=true              Skip PHP (default: true)"
            echo "  SKIP_NODE=false            Skip Node (default: false)"
            echo "  SKIP_DOCKER=false          Skip Docker (default: false)"
            echo ""
            echo "Current settings:"
            echo "  USERNAME=$USERNAME"
            echo "  SKIP_PHP=$SKIP_PHP"
            echo "  SKIP_NODE=$SKIP_NODE"
            echo "  SKIP_DOCKER=$SKIP_DOCKER"
            echo "  SKIP_USER=$SKIP_USER"
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

run_as_user() {
    su - "$USERNAME" -c "$1"
}

run_as_user_with_brew() {
    su - "$USERNAME" -c "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\" && $1"
}

# =============================================================================
# Installation functions
# =============================================================================

install_base_packages() {
    echo "==> Installing base packages..."
    apt-get update
    apt-get upgrade -y
    apt-get install -y \
        ca-certificates \
        curl \
        sudo \
        zsh \
        build-essential \
        rsync \
        git \
        unzip \
        openfortivpn \
        locales
    apt-get autoremove -y

    # Generate locale
    locale-gen en_US.UTF-8 || true
}

install_homebrew() {
    echo "==> Installing Homebrew..."

    if run_as_user "command -v brew" &>/dev/null; then
        echo "    Homebrew already installed, skipping"
        return 0
    fi

    # Install Homebrew dependencies
    apt-get install -y procps file

    # Install Homebrew as user
    run_as_user 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

    # Add brew to PATH in .zprofile for zsh login shells
    local user_home
    user_home=$(eval echo "~$USERNAME")

    # Add to .zprofile if not already there (zsh login shell)
    if ! grep -q 'linuxbrew' "$user_home/.zprofile" 2>/dev/null; then
        cat >> "$user_home/.zprofile" <<'EOF'

# Homebrew
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
EOF
        chown "$USERNAME:$USERNAME" "$user_home/.zprofile"
    fi

    echo "    Homebrew installed"
}

install_brew_packages() {
    echo "==> Installing Homebrew packages..."

    local packages=(
        neovim
        lazygit
        fzf
        ripgrep
        fd
        tree-sitter
        tmux
        jq
        bat
        eza
        gh
        git-delta
        fnm
    )

    for pkg in "${packages[@]}"; do
        if run_as_user_with_brew "brew list $pkg" &>/dev/null; then
            echo "    $pkg already installed"
        else
            echo "    Installing $pkg..."
            run_as_user_with_brew "brew install $pkg"
        fi
    done
}

install_lazyvim() {
    echo "==> Installing LazyVim..."

    local user_home
    user_home=$(eval echo "~$USERNAME")
    local nvim_config="$user_home/.config/nvim"

    # Check if LazyVim already installed
    if [[ -f "$nvim_config/lua/config/lazy.lua" ]]; then
        echo "    LazyVim already installed"
        return 0
    fi

    # Backup existing nvim config if exists
    if [[ -d "$nvim_config" ]]; then
        echo "    Backing up existing nvim config..."
        mv "$nvim_config" "${nvim_config}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # Clone LazyVim starter
    run_as_user "git clone https://github.com/LazyVim/starter $nvim_config"

    # Remove .git directory
    rm -rf "$nvim_config/.git"

    echo "    LazyVim installed"
}

install_fonts() {
    echo "==> Installing fonts..."

    # Install font cask
    if run_as_user_with_brew "brew list --cask font-anonymous-pro" &>/dev/null; then
        echo "    font-anonymous-pro already installed"
    else
        run_as_user_with_brew "brew install --cask font-anonymous-pro"
        echo "    font-anonymous-pro installed"
    fi
}

install_kitty_terminfo() {
    echo "==> Installing kitty terminal compatibility..."

    if infocmp xterm-kitty &>/dev/null; then
        echo "    kitty terminfo already installed"
        return 0
    fi

    curl -fsSL https://raw.githubusercontent.com/kovidgoyal/kitty/master/terminfo/kitty.terminfo | tic -x -
    echo "    kitty terminfo installed"
}

install_zsh_stack() {
    echo "==> Installing ZSH stack..."

    local user_home
    user_home=$(eval echo "~$USERNAME")
    local ohmyzsh_dir="$user_home/.oh-my-zsh"
    local custom_dir="$ohmyzsh_dir/custom"

    # Install Oh My Zsh
    if [[ -d "$ohmyzsh_dir" ]]; then
        echo "    Oh My Zsh already installed"
    else
        echo "    Installing Oh My Zsh..."
        run_as_user 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    fi

    # Install Powerlevel10k
    local p10k_dir="$custom_dir/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        echo "    Powerlevel10k already installed"
    else
        echo "    Installing Powerlevel10k..."
        run_as_user "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $p10k_dir"
    fi

    # Install zsh-autosuggestions
    local autosugg_dir="$custom_dir/plugins/zsh-autosuggestions"
    if [[ -d "$autosugg_dir" ]]; then
        echo "    zsh-autosuggestions already installed"
    else
        echo "    Installing zsh-autosuggestions..."
        run_as_user "git clone https://github.com/zsh-users/zsh-autosuggestions $autosugg_dir"
    fi

    # Install zsh-syntax-highlighting
    local synhl_dir="$custom_dir/plugins/zsh-syntax-highlighting"
    if [[ -d "$synhl_dir" ]]; then
        echo "    zsh-syntax-highlighting already installed"
    else
        echo "    Installing zsh-syntax-highlighting..."
        run_as_user "git clone https://github.com/zsh-users/zsh-syntax-highlighting $synhl_dir"
    fi
}

install_php_stack() {
    if [[ "$SKIP_PHP" == true ]]; then
        echo "==> Skipping PHP installation (use --install-php to enable)"
        return 0
    fi

    echo "==> Installing PHP stack..."

    # Add ondrej/php PPA
    if [[ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list ]] && \
       [[ ! -f /etc/apt/sources.list.d/ondrej-php.list ]]; then
        echo "    Adding ondrej/php repository..."
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:ondrej/php
        apt-get update
    else
        echo "    ondrej/php repository already added"
    fi

    # Install PHP 7.4
    if command -v php7.4 &>/dev/null; then
        echo "    PHP 7.4 already installed"
    else
        echo "    Installing PHP 7.4..."
        apt-get install -y \
            php7.4-cli \
            php7.4-common \
            php7.4-curl \
            php7.4-mbstring \
            php7.4-xml \
            php7.4-zip \
            php7.4-mysql \
            php7.4-pgsql \
            php7.4-sqlite3 \
            php7.4-intl \
            php7.4-gd
    fi

    # Install PHP 8.3
    if command -v php8.3 &>/dev/null; then
        echo "    PHP 8.3 already installed"
    else
        echo "    Installing PHP 8.3..."
        apt-get install -y \
            php8.3-cli \
            php8.3-common \
            php8.3-curl \
            php8.3-mbstring \
            php8.3-xml \
            php8.3-zip \
            php8.3-mysql \
            php8.3-pgsql \
            php8.3-sqlite3 \
            php8.3-intl \
            php8.3-gd
    fi

    # Set PHP 8.3 as default
    echo "    Setting PHP 8.3 as default..."
    update-alternatives --set php /usr/bin/php8.3 || true

    # Install Composer
    if command -v composer &>/dev/null; then
        echo "    Composer already installed"
    else
        echo "    Installing Composer..."
        curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
}

install_node_stack() {
    if [[ "$SKIP_NODE" == true ]]; then
        echo "==> Skipping Node.js installation (--skip-node)"
        return 0
    fi

    echo "==> Installing Node.js stack..."

    # fnm should be installed via brew already
    if ! run_as_user_with_brew "command -v fnm" &>/dev/null; then
        echo "    ERROR: fnm not found. Install Homebrew packages first."
        return 1
    fi

    # Setup fnm in shell config
    local user_home
    user_home=$(eval echo "~$USERNAME")

    # Add fnm to .zshrc if not already there
    if ! grep -q 'fnm env' "$user_home/.zshrc" 2>/dev/null; then
        cat >> "$user_home/.zshrc" <<'EOF'

# fnm (Fast Node Manager)
eval "$(fnm env --use-on-cd)"
EOF
        chown "$USERNAME:$USERNAME" "$user_home/.zshrc"
    fi

    # Install Node 20 LTS
    if run_as_user_with_brew "fnm list | grep -q 'v20'" 2>/dev/null; then
        echo "    Node 20 already installed"
    else
        echo "    Installing Node 20 LTS..."
        run_as_user_with_brew "fnm install 20"
        run_as_user_with_brew "fnm default 20"
    fi
}

install_docker() {
    if [[ "$SKIP_DOCKER" == true ]]; then
        echo "==> Skipping Docker installation (--skip-docker)"
        return 0
    fi

    echo "==> Installing Docker..."

    # Check if Docker already installed
    if command -v docker &>/dev/null; then
        echo "    Docker already installed"
        # Ensure user is in docker group
        if ! groups "$USERNAME" | grep -q docker; then
            usermod -aG docker "$USERNAME"
            echo "    Added $USERNAME to docker group"
        fi
        return 0
    fi

    # Install prerequisites
    apt-get install -y ca-certificates curl gnupg

    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "    Added Docker GPG key"
    fi

    # Add Docker repository
    local os_id
    os_id=$(detect_os)
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os_id $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
        echo "    Added Docker repository"
    fi

    # Install Docker packages
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    usermod -aG docker "$USERNAME"
    echo "    Added $USERNAME to docker group"

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    echo "    Docker installed"
}

setup_user() {
    if [[ "$SKIP_USER" == true ]]; then
        echo "==> Skipping user setup (--skip-user)"
        return 0
    fi

    echo "==> Setting up user: $USERNAME"

    # Create user if not exists
    if ! user_exists "$USERNAME"; then
        echo "    Creating user $USERNAME..."
        useradd -m -s "$(which zsh)" "$USERNAME"
    else
        echo "    User $USERNAME already exists"
    fi

    # Add to sudo group
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
        return 0
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
        run_as_user "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa"
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

setup_version_switcher() {
    echo "==> Setting up version switcher Makefile..."

    local user_home
    user_home=$(eval echo "~$USERNAME")
    local makefile="$user_home/Makefile"

    # Copy Makefile from template
    local template_dir="$SCRIPT_DIR/init-development-host"
    if [[ -f "$template_dir/Makefile" ]]; then
        cp "$template_dir/Makefile" "$makefile"
        chown "$USERNAME:$USERNAME" "$makefile"
        echo "    Makefile installed to $makefile"
    else
        # Create inline if template doesn't exist
        cat > "$makefile" <<'EOF'
# Version Switcher Makefile
# Usage: make php74, make php83, make node20, make node22

.PHONY: help php74 php83 node20 node22

help:
	@echo "Version Switcher"
	@echo ""
	@echo "PHP versions:"
	@echo "  make php74    - Switch to PHP 7.4"
	@echo "  make php83    - Switch to PHP 8.3"
	@echo ""
	@echo "Node versions:"
	@echo "  make node20   - Switch to Node 20 LTS"
	@echo "  make node22   - Switch to Node 22"
	@echo ""
	@echo "Current versions:"
	@echo "  PHP:  $$(php -v 2>/dev/null | head -1 || echo 'not installed')"
	@echo "  Node: $$(node -v 2>/dev/null || echo 'not installed')"

php74:
	@echo "Switching to PHP 7.4..."
	@sudo update-alternatives --set php /usr/bin/php7.4
	@php -v | head -1

php83:
	@echo "Switching to PHP 8.3..."
	@sudo update-alternatives --set php /usr/bin/php8.3
	@php -v | head -1

node20:
	@echo "Switching to Node 20..."
	@fnm use 20 || fnm install 20
	@node -v

node22:
	@echo "Switching to Node 22..."
	@fnm use 22 || fnm install 22
	@node -v
EOF
        chown "$USERNAME:$USERNAME" "$makefile"
        echo "    Makefile created at $makefile"
    fi
}

setup_zshrc() {
    echo "==> Configuring .zshrc..."

    local user_home
    user_home=$(eval echo "~$USERNAME")
    local zshrc="$user_home/.zshrc"

    # Backup existing .zshrc if exists
    if [[ -f "$zshrc" ]] && [[ ! -f "$zshrc.backup" ]]; then
        cp "$zshrc" "$zshrc.backup"
        echo "    Backed up existing .zshrc"
    fi

    # Update theme to powerlevel10k if not set
    if grep -q 'ZSH_THEME="robbyrussell"' "$zshrc" 2>/dev/null; then
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$zshrc"
        echo "    Set theme to powerlevel10k"
    fi

    # Add plugins if not already configured
    if grep -q 'plugins=(git)' "$zshrc" 2>/dev/null; then
        sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$zshrc"
        echo "    Added zsh plugins"
    fi

    # Add Homebrew to PATH if not present
    if ! grep -q 'linuxbrew' "$zshrc" 2>/dev/null; then
        cat >> "$zshrc" <<'EOF'

# Homebrew
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
EOF
        echo "    Added Homebrew to PATH"
    fi

    chown "$USERNAME:$USERNAME" "$zshrc"
}

print_summary() {
    local env=$1
    local os=$2

    echo ""
    echo "============================================================================="
    echo "Development host initialization complete!"
    echo "============================================================================="
    echo "Environment: $env"
    echo "OS: $os"
    echo "User: $USERNAME"
    echo ""
    echo "Installed:"
    echo "  - Homebrew (Linux)"
    echo "  - Neovim + LazyVim, lazygit, fzf, ripgrep, fd, tree-sitter"
    echo "  - tmux, jq, bat, eza, gh, delta"
    echo "  - ZSH + Oh My Zsh + Powerlevel10k"
    echo "  - openfortivpn"
    if [[ "$SKIP_PHP" != true ]]; then
        echo "  - PHP 7.4, 8.3 + Composer"
    fi
    if [[ "$SKIP_NODE" != true ]]; then
        echo "  - fnm + Node 20 LTS"
    fi
    if [[ "$SKIP_DOCKER" != true ]]; then
        echo "  - Docker + Compose"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Set password:  passwd $USERNAME"
    echo "  2. Switch user:   su - $USERNAME"
    echo "  3. Configure p10k: p10k configure"
    echo "  4. Version switching: make help (in home dir)"
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
    echo "init-development-host.sh - Developer Workstation Setup"
    echo "============================================================================="
    echo "Detected environment: $env"
    echo "Detected OS: $os"
    echo "Username: $USERNAME"
    echo "Install PHP: $([[ "$SKIP_PHP" == true ]] && echo "no" || echo "yes")"
    echo "Install Node: $([[ "$SKIP_NODE" == true ]] && echo "no" || echo "yes")"
    echo "Install Docker: $([[ "$SKIP_DOCKER" == true ]] && echo "no" || echo "yes")"
    echo "Skip user: $SKIP_USER"
    echo "============================================================================="
    echo ""

    install_base_packages
    install_kitty_terminfo
    setup_user
    setup_ssh
    install_homebrew
    install_brew_packages
    install_lazyvim
    install_fonts
    install_zsh_stack
    setup_zshrc
    install_php_stack
    install_node_stack
    install_docker
    setup_version_switcher

    print_summary "$env" "$os"
}

main "$@"
