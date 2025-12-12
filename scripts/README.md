# Scripts

Initialization and utility scripts for homelab setup.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `init-host.sh` | Universal host initialization (VM, LXC, RPi, bare metal) |
| `init-development-host.sh` | Developer workstation setup (PHP/Node dev environment) |
| `sync-files.sh` | Bidirectional file sync (rsync wrapper) |

## init-host.sh

Universal initialization script supporting Ubuntu, Debian, and Raspberry Pi OS across VMs, LXC containers, and bare metal.

### Features

- Auto-detects environment (LXC, VM, RPi, bare metal)
- Auto-detects OS via `/etc/os-release`
- Installs base packages: ca-certificates, curl, sudo, zsh, rsync, build-essential
- Configures passwordless sudo for Ansible compatibility
- Docker installation via get.docker.com
- User creation with SSH key setup
- QEMU guest agent (VMs only)
- Kitty terminal compatibility fix

### Usage

```bash
# Basic usage (as root)
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/init-host.sh | bash

# Or download and run with options
./init-host.sh [OPTIONS]

# Options:
#   --disable-dns-stub   Disable systemd-resolved DNSStubListener (for local DNS)
#   --skip-docker        Skip Docker installation
#   --skip-user          Skip user creation
```

### Configuration

Create `.env` file in same directory (optional):

```bash
# Username to create (default: code)
USERNAME="code"

# SSH public key(s) for authorized_keys
AUTHORIZED_KEYS="ssh-ed25519 AAAA... user@host"
```

See `.env.example` for template.

### What it configures

1. **Base packages** - Essential tools for management
2. **Sudo** - Passwordless sudo for created user (required by Ansible)
3. **Docker** - Docker Engine + Compose plugin
4. **User** - Non-root user with docker group membership
5. **SSH** - Authorized keys from config or generates new keypair

## init-development-host.sh

Developer workstation initialization for PHP/Node.js development on Ubuntu/Debian.

### Features

- Auto-detects environment (LXC, VM, RPi, bare metal)
- Homebrew for Linux (package management)
- CLI dev tools: neovim, lazygit, fzf, ripgrep, fd, tree-sitter, tmux, bat, eza, gh, delta
- ZSH stack: oh-my-zsh, powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- PHP 7.4 + 8.3 via ondrej/php PPA (optional, `--install-php`)
- Node.js via fnm (fast node manager)
- Composer 2
- VPN: openfortivpn
- Kitty terminal compatibility
- Idempotent: safe to run multiple times

### Usage

```bash
# As root
./init-development-host.sh [OPTIONS]

# Options:
#   --install-php   Install PHP stack (disabled by default)
#   --skip-node     Skip Node.js installation
#   --skip-user     Skip user creation
```

### Configuration

Create `.env` file in same directory (optional):

```bash
USERNAME="code"
AUTHORIZED_KEYS="ssh-ed25519 AAAA... user@host"
SKIP_PHP=true      # PHP opt-in (default: true)
SKIP_NODE=false    # Node enabled by default
```

### Version Switching

After install, use the Makefile in home directory:

```bash
# Show current versions
make status

# Switch PHP version
make php74
make php83

# Switch Node version
make node20
make node22
```

### What it installs

| Source | Packages |
|--------|----------|
| apt | git, curl, zsh, build-essential, unzip, openfortivpn |
| apt (ondrej/php) | php7.4, php8.3, composer (if --install-php) |
| brew | neovim, lazygit, fzf, ripgrep, fd, tree-sitter, tmux, jq, bat, eza, gh, delta, fnm |
| brew cask | font-anonymous-pro |

## sync-files.sh

Synchronize files between local and remote systems using rsync.

### Usage

```bash
# Pull: Server -> Local
./scripts/sync-files.sh pull NAME

# Push: Local -> Server
./scripts/sync-files.sh push NAME
```

NAME must match a directory in `pve/` (x000, x201, x202, x250).

### Configuration

Each `pve/NAME/` directory must have a `.envrc` file:

```bash
REMOTE_HOST="user@hostname"
REMOTE_FILES=(
  "file1"
  "dir/file2"
)
```

Copy `.envrc.example` to `.envrc` and set `REMOTE_HOST`.

## Tests

Test suite located in `scripts/tests/`:

```bash
# Test sync-files.sh and Makefile
./scripts/tests/test-sync-makefile.sh

# Test init-development-host.sh
./scripts/tests/test-init-dev-host.sh
```
