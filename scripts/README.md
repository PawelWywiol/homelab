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
./scripts/tests/test-sync-makefile.sh
```
