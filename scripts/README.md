# Scripts

Initialization and utility scripts for homelab setup.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `init-host.sh` | Universal host initialization (VM, LXC, RPi, bare metal) |
| `sync-files.sh` | Bidirectional file sync (rsync wrapper) |
| `health-monitor.sh` | Generate system/Docker health reports for AI analysis |

## init-host.sh

Universal initialization script supporting Ubuntu, Debian, and Raspberry Pi OS across VMs, LXC containers, and bare metal.

### Features

- Auto-detects environment (LXC, VM, RPi, bare metal)
- Auto-detects OS via `/etc/os-release`
- Installs base packages: ca-certificates, curl, sudo, zsh, rsync, build-essential, git, unzip
- Homebrew for Linux (package management)
- CLI dev tools: neovim, lazygit, fzf, ripgrep, fd, tree-sitter, tmux, jq, bat, eza, gh, delta, fnm
- ZSH stack: oh-my-zsh, powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- Powerlevel10k pre-configured from a versioned `~/.p10k.zsh` - no wizard on first login
- herdr terminal workspace manager, with this homelab's keybindings
- Claude Code (native build, self-updating)
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

**Root is required.** Without it the script aborts immediately with
`This script must be run as root`. Only `--help` works as a regular user.

```bash
# One-liner, no options
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/init-host.sh | sudo bash

# One-liner with options - note the `-s --`, without it bash eats the flags
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/init-host.sh | sudo bash -s -- --install-node

# From a root shell (sudo -i) or as root over SSH
./init-host.sh [OPTIONS]

# From a user shell, local copy
sudo ./init-host.sh [OPTIONS]

# Options:
#   --install-php       Install PHP stack (7.4, 8.3, composer)
#   --install-node      Install Node.js stack (fnm + Node 20 LTS)
#   --install-fortivpn  Install openfortivpn (FortiGate VPN client)
#   --disable-dns-stub  Disable systemd-resolved DNSStubListener
#   --skip-docker       Skip Docker installation
#   --skip-user         Skip user creation (for cloud-init pre-created users)
#   --skip-herdr        Skip herdr terminal workspace manager
#   --skip-claude       Skip Claude Code installation
```

### Configuration

Optional `.env`, read from the script's own directory:

```bash
# Username to create (default: code)
USERNAME="code"

# SSH public key(s) for authorized_keys
AUTHORIZED_KEYS="ssh-ed25519 AAAA... user@host"
```

See `.env.example` for template.

**Piped via curl there is no script directory** - `.env` is then read from the
current working directory instead. Either `cd` to the directory holding `.env`
first, or download the script and run it from a local copy. Environment
variables exported in the shell are ignored: the script assigns its own
defaults before loading `.env`.

### What it installs

| Source | Packages |
|--------|----------|
| apt | git, curl, zsh, build-essential, unzip, rsync, locales |
| apt (ondrej/php) | php7.4, php8.3, composer (if --install-php) |
| brew | neovim, lazygit, fzf, ripgrep, fd, tree-sitter, tmux, jq, bat, eza, gh, delta, fnm |
| brew cask | font-anonymous-pro |
| herdr.dev/install.sh | herdr → `/usr/local/bin/herdr` |
| claude.ai/install.sh | Claude Code → `~/.local/bin/claude` (per user) |

### Shipped configuration

`init-host/` holds the dotfiles the script installs, so a new host comes up
configured rather than needing a wizard:

| Asset | Installed as | Source of truth |
|-------|--------------|-----------------|
| `init-host/p10k.zsh` | `~/.p10k.zsh` | output of `p10k configure` |
| `init-host/herdr/config.toml` | `~/.config/herdr/config.toml` | the workstation's herdr config |
| `init-host/Makefile` | `~/Makefile` | PHP/Node version switcher |

Piped through curl the script has no directory of its own, so these are fetched
from the repo over HTTPS instead. Both paths were exercised in the test suite.

### herdr

Installed with the upstream installer, which resolves the release for the host's
os/arch and checks the SHA-256 from the same manifest `herdr update` uses. It
defaults to `~/.local/bin`, which under root means `/root/.local/bin`, so
`HERDR_INSTALL_DIR=/usr/local/bin` is set to make it system-wide.

Keybindings, carried over from the workstation:

| Action | herdr default | Here |
|--------|---------------|------|
| prefix | `ctrl+b` | `ctrl+s` |
| `goto` (move between workspaces and panes) | `prefix+g` | `prefix+s` |

`ctrl+s` is the terminal's XOFF character, but the herdr client puts its
terminal in raw mode with flow control off (`-ixon`), so it arrives as a
keystroke. The cost is that a program inside a pane never sees `ctrl+s`.

A config only lists overrides; every key it omits keeps herdr's default, and an
explicit binding that collides with a default silently disables one of the two.
The script runs `herdr config check` after installing the config and prints any
issue it reports.

### Claude Code

Installed as the target user, not root: the installer puts everything under
`$HOME`, so run as root the launcher would land in `/root/.local/bin` and never
be found from the user's shell. `~/.local/bin` is added to `PATH` in `.zshrc`
because the installer does not do it for zsh.

Authenticate on first use with `claude`.

### Re-running the script

Safe by design - a second run must not discard what the tools themselves wrote:

- `~/.p10k.zsh`, `~/.config/herdr/config.toml` and `~/Makefile` are installed
  **only when absent**. `p10k configure` and herdr's settings overlay write
  those same files, and an edit made there wins over the versioned copy.
- `.zshrc` edits are all conditional: the theme and plugin lines are rewritten
  from whatever they currently hold (so the result is the same from any
  starting point), and the instant prompt, PATH and p10k source lines are
  appended only when not already present.
- herdr and Claude Code are skipped when already installed.

To take a new version of a shipped config, delete the file and re-run.

### What it configures

1. **Base packages** - Essential tools for management
2. **Homebrew** - Linux package manager
3. **ZSH stack** - Oh My Zsh + Powerlevel10k + plugins
4. **Neovim** - LazyVim configuration
5. **Docker** - Docker Engine + Compose plugin (official repo)
6. **User** - Non-root user with docker group membership
7. **SSH** - Authorized keys from config or generates new keypair
8. **herdr** - Terminal workspace manager + keybindings
9. **Claude Code** - Native build under the user's home

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

NAME must match a directory in `pve/` (x000, x201, x202, x203).

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

## health-monitor.sh

Generate system and Docker health reports for AI analysis. Supports Debian, Ubuntu, and Raspberry Pi OS.

### Features

**System Checks:**
- CPU usage (via /proc/stat)
- Memory usage (via free)
- Disk usage per mount point
- Network connectivity (ping 8.8.8.8, 1.1.1.1)
- System logs analysis (journalctl errors/warnings)

**Docker Checks:**
- Daemon status (installed, running)
- Container states (running, stopped, exited)
- Unexpected exits (non-zero exit codes)
- Resource usage (CPU, memory per container)
- Restart counts (detect unstable containers)
- Containers created but not running
- Stopped containers not removed
- Long-running containers (>30 days default)
- Container disk usage
- Log errors (ERROR, FATAL, CRITICAL, Exception, panic, failed)
- Security issues (privileged, capabilities, host network, docker socket mount)
- Missing resource limits (memory, CPU)
- Network configuration
- Volume mounts

### Usage

```bash
./scripts/health-monitor.sh [OPTIONS]

# Options:
#   --format FORMAT     Output format: json, yaml, markdown (default: json)
#   --output FILE       Write report to file (default: stdout)
#   --config FILE       Load configuration from file
#   --quiet             Suppress progress output
#   --help              Show help

# Examples:
./scripts/health-monitor.sh                           # JSON to stdout
./scripts/health-monitor.sh --format markdown         # Markdown to stdout
./scripts/health-monitor.sh --format yaml --output /tmp/report.yaml
./scripts/health-monitor.sh --quiet --output /tmp/report.json
```

### Run from URL

Execute latest version directly without downloading:

```bash
# JSON output (default)
bash <(curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/health-monitor.sh)

# Markdown output, quiet mode
bash <(curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/health-monitor.sh) --quiet --format markdown

# Save report to file
bash <(curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/health-monitor.sh) --quiet --format markdown > health-report.md
```

### Configuration

Create `.env.health-monitor` file (optional):

```bash
# System thresholds (percentage)
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85

# Container thresholds
CONTAINER_CPU_THRESHOLD=80
CONTAINER_MEMORY_THRESHOLD=80
CONTAINER_RESTART_THRESHOLD=3

# Log analysis
LOG_HOURS=24
LOG_PATTERNS="ERROR|FATAL|CRITICAL|Exception|panic|failed"

# Long-running container threshold (days)
LONG_RUNNING_DAYS=30
```

See `.env.health-monitor.example` for template.

### Output Formats

**JSON** (default): Structured data for programmatic analysis
```json
{
  "report_metadata": { "generated_at": "...", "server_name": "..." },
  "overall_status": "OK|WARNING|CRITICAL",
  "summary": { "total_checks": 20, "passed": 18, "warnings": 2 },
  "checks": { "system": {...}, "docker": {...} },
  "recommendations": ["Container 'redis' exceeds memory threshold"]
}
```

**YAML**: Human-readable structured data

**Markdown**: Report format for documentation/sharing

### Report Status Levels

| Status | Meaning |
|--------|---------|
| OK | All checks within thresholds |
| WARNING | Non-critical issues detected |
| CRITICAL | Critical issues (docker not running, high error count) |

## Tests

Test suite located in `scripts/tests/`:

```bash
# Test sync-files.sh and Makefile
./scripts/tests/test-sync-makefile.sh

# Test init-host.sh
./scripts/tests/test-init-host.sh

# Test health-monitor.sh
./scripts/tests/test-health-monitor.sh
```
