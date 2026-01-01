# Scripts

Initialization and utility scripts for homelab setup.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `init-host.sh` | Universal host initialization (VM, LXC, RPi, bare metal) |
| `sync-files.sh` | Bidirectional file sync (rsync wrapper) |

## init-host.sh

Universal initialization script supporting Ubuntu, Debian, and Raspberry Pi OS across VMs, LXC containers, and bare metal.

### Features

- Auto-detects environment (LXC, VM, RPi, bare metal)
- Auto-detects OS via `/etc/os-release`
- Installs base packages: ca-certificates, curl, sudo, zsh, rsync, build-essential, git, unzip
- Homebrew for Linux (package management)
- CLI dev tools: neovim, lazygit, fzf, ripgrep, fd, tree-sitter, tmux, jq, bat, eza, gh, delta, fnm
- ZSH stack: oh-my-zsh, powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- LazyVim (Neovim configuration)
- Docker installation via official repository
- User creation with SSH key setup
- QEMU guest agent (VMs only)
- Kitty terminal compatibility fix
- **Optional:** PHP 7.4 + 8.3 via ondrej/php PPA (`--install-php`)
- **Optional:** Node.js 20 LTS via fnm (`--install-node`)
- **Optional:** openfortivpn VPN client (`--install-fortivpn`)
- Idempotent: safe to run multiple times

### Usage

```bash
# Basic usage (as root)
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/init-host.sh | bash

# Or download and run with options
./init-host.sh [OPTIONS]

# Options:
#   --install-php       Install PHP stack (7.4, 8.3, composer)
#   --install-node      Install Node.js stack (fnm + Node 20 LTS)
#   --install-fortivpn  Install openfortivpn (FortiGate VPN client)
#   --disable-dns-stub  Disable systemd-resolved DNSStubListener
#   --skip-docker       Skip Docker installation
#   --skip-user         Skip user creation (for cloud-init pre-created users)
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

### What it installs

| Source | Packages |
|--------|----------|
| apt | git, curl, zsh, build-essential, unzip, rsync, locales |
| apt (ondrej/php) | php7.4, php8.3, composer (if --install-php) |
| brew | neovim, lazygit, fzf, ripgrep, fd, tree-sitter, tmux, jq, bat, eza, gh, delta, fnm |
| brew cask | font-anonymous-pro |

### What it configures

1. **Base packages** - Essential tools for management
2. **Homebrew** - Linux package manager
3. **ZSH stack** - Oh My Zsh + Powerlevel10k + plugins
4. **Neovim** - LazyVim configuration
5. **Docker** - Docker Engine + Compose plugin (official repo)
6. **User** - Non-root user with docker group membership
7. **SSH** - Authorized keys from config or generates new keypair

### Version Switching (PHP/Node)

If PHP or Node is installed, a Makefile is created in user home directory (template: `init-host/Makefile`):

```bash
# Show help
make help

# Show current versions
make status

# Switch PHP version
make php74
make php83

# Switch Node version
make node20
make node22
```

## sync-files.sh

Synchronize files between local and remote systems using rsync.

### Usage

```bash
# Pull: Server -> Local
./scripts/sync-files.sh pull NAME

# Push: Local -> Server
./scripts/sync-files.sh push NAME
```

NAME must match a directory in `pve/` (x000, x202, x250).

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

### REMOTE_HOST Formats

| Format | Destination Path |
|--------|------------------|
| `user@host` | Home directory (`~/`) |
| `user@host:` | Home directory (`~/`) |
| `user@host:~/path` | Home-relative path |
| `user@host:/path` | Absolute path |

**Examples:**

```bash
# Default to home directory
REMOTE_HOST="code@192.168.0.2"

# Explicit home-relative path
REMOTE_HOST="code@192.168.0.2:~/projects/"

# Absolute path
REMOTE_HOST="code@192.168.0.2:/opt/data/"
```

With `REMOTE_HOST="code@server:/opt/data/"` and `REMOTE_FILES=("config/app.yml")`:
- `make push NAME` copies `pve/NAME/config/app.yml` to `code@server:/opt/data/config/app.yml`
- `make pull NAME` copies `code@server:/opt/data/config/app.yml` to `pve/NAME/config/app.yml`

## Tests

Test suite located in `scripts/tests/`:

```bash
# Test sync-files.sh and Makefile
./scripts/tests/test-sync-makefile.sh

# Test init-host.sh
./scripts/tests/test-init-host.sh
```
