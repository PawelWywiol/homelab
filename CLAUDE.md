# CLAUDE.md

Homelab infrastructure with Docker Compose, Ansible automation, OpenTofu IaC, and GitOps workflows.

## Quick Start

```bash
# x202 (primary) - manage services
cd pve/x202 && make SERVICE up|down|restart|logs

# x000 (control node) - manage automation
cd pve/x000 && make SERVICE up|down|restart|logs
cd pve/x000 && make all up   # Start all control services
cd pve/x000 && make setup    # Run/re-run setup script

# File sync
make pull NAME   # Server -> Local
make push NAME   # Local -> Server
```

## Environments

| ID | Purpose | Services | Makefile |
|----|---------|----------|----------|
| x000 | Control node | 9 | `pve/x000/Makefile` |
| x201 | Web apps | 2 | `pve/x201/Makefile` |
| x202 | Web/App (primary) | 13 | `pve/x202/Makefile` |
| x203 | File sharing | 5 | `pve/x203/Makefile` |
| archive | Not deployed | - | - |

**Path pattern:** `pve/ENV/docker/config/SERVICE/`

Makefiles discover services from `docker/config/`, so adding or removing a
directory is all it takes — no list to update.

## Service Management

### x202 Services

```bash
cd pve/x202
make SERVICE [up|down|restart|pull|logs]
```

| Service | Port | Description |
|---------|------|-------------|
| portainer | 9443 | Container management UI |
| postgres | 5432, 8888 | PostgreSQL + pgAdmin |
| redis | 6379, 8001 | Redis cache |
| mongo | 27017, 8081 | MongoDB + Mongo Express |
| rabbitmq | - | Message broker |
| influxdb | 8086 | Time-series DB |
| grafana | 3002 | Dashboards |
| wakapi | 3003 | Coding activity tracker |
| beszel | 8090 | System monitoring |
| glitchtip | 8000 | Error tracking |
| k6 | - | Load testing |
| glances | - | Host/container metrics |
| docker-socket-proxy | 2375 | Scoped Docker API access |

**Database operations:**
```bash
make postgres add DB_NAME      # Create database + user
make postgres remove DB_NAME   # Drop database + user
make glitchtip createsuperuser # Create admin user
```

**K6 load testing:**
```bash
make k6-build              # Build with extensions
make k6-grafana SCRIPT     # Run → InfluxDB
make k6-dashboard SCRIPT   # Run → HTML export
```

### x000 Services (Control Node)

```bash
cd pve/x000
make SERVICE [up|down|restart|pull|logs]
```

| Service | Port | Description |
|---------|------|-------------|
| caddy | 80, 443 | Reverse proxy (Cloudflare DNS) |
| webhook | 8097 | GitHub webhook handler |
| portainer | 9443 | Container management UI |
| cloudflared | - | Cloudflare Tunnel |
| pihole | 53, 5080, 5443 | DNS + ad-blocking |
| homepage | 3000 | Dashboard |
| n8n | 5678 | Workflow automation |
| glances | - | Host/container metrics |
| docker-socket-proxy | 2375 | Scoped Docker API access |

### x201 Services

```bash
cd pve/x201
make SERVICE [up|down|restart|pull|logs]
```

| Service | Port | Description |
|---------|------|-------------|
| portainer | 9443 | Container management UI |
| glances | - | Host/container metrics |

Landing spot for self-hosted web apps; grows over time.

### x203 Services

```bash
cd pve/x203
make SERVICE [up|down|restart|pull|logs]
```

| Service | Port | Description |
|---------|------|-------------|
| samba | 139, 445 | SMB file sharing |
| share | 8081, 6881, 8080 | qBittorrent + media stack |
| portainer | 9443 | Container management UI |
| glances | - | Host/container metrics |
| docker-socket-proxy | 2375 | Scoped Docker API access |

## Host Initialization

Run on a fresh VM/LXC **as root** (aborts otherwise):

```bash
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/init-host.sh | sudo bash

# With options - `-s --` is required, otherwise bash consumes the flags
curl -fsSL .../init-host.sh | sudo bash -s -- --install-node --disable-dns-stub
```

Installs base packages, Docker, the ZSH/oh-my-zsh + Powerlevel10k stack (with a
versioned `~/.p10k.zsh`, so no wizard), herdr (prefix `ctrl+s`) and Claude Code.
Re-running never overwrites a config the user or its own tool has since edited.

See [scripts/README.md](scripts/README.md#init-hostsh) for options and `.env` config.

## Control Node Setup

Setup control node. Runs **as a normal user** (`setup.sh` refuses root and calls sudo itself):

```bash
# On x000
ssh code@x000
git clone https://github.com/PawelWywiol/homelab.git
cd ~/homelab/pve/x000
cp setup.env.example .env
nano .env  # Set required: CLOUDFLARE_API_TOKEN, BASE_DOMAIN, CONTROL_NODE_IP
make setup
make all up  # Start all services
```

**Installs:** Docker, Ansible (+collections), OpenTofu
**Configures:** Caddy (Cloudflare DNS), Webhook, Docker network
**Auto-generates:** Vault password, webhook secret

## GitOps Automation

Push to `main` triggers automated deployments with two-phase Discord notifications:

```
GitHub Push → webhook.wywiol.eu (Caddy: IP whitelist)
           → webhook:9000 (HMAC verification)
           → trigger-homelab.sh (analyzes added/modified/removed files)
           → scripts/deploy.sh | stop-service.sh | apply-tofu.sh
           → Ansible / OpenTofu
           → 📦/🛑/🔧 Start notification → ✅/❌ End notification
```

**Triggers:**

| Path Change | Action | Notification |
|-------------|--------|--------------|
| `pve/x000/docker/config/*` (add/mod) | Deploy x000 services | 📦 → ✅/❌ |
| `pve/x201/docker/config/*` (add/mod) | Deploy x201 services | 📦 → ✅/❌ |
| `pve/x202/docker/config/*` (add/mod) | Deploy x202 services | 📦 → ✅/❌ |
| `pve/x203/docker/config/*` (add/mod) | Deploy x203 services | 📦 → ✅/❌ |
| any of the above, removed | Stop & remove containers | 🛑 → ✅/❌ |
| `pve/x000/infra/tofu/*` | OpenTofu plan (manual apply) | 🔧 → ✅/❌ |

Only those four prefixes are routed. Anything else — `pve/archive/*` included —
is reported as ignored and deploys nothing.

**Ansible playbooks:**
- `deploy-service.yml` - Deploy Docker Compose services
- `stop-service.yml` - Stop and remove containers
- `rollback-service.yml` - Rollback to previous version

**Managed hosts:** x000 (control node), x201, x202, x203 (VMs)

## File Sync

```bash
# Root Makefile shortcuts
make pull NAME   # Server -> Local (NAME = x000|x201|x202|x203)
make push NAME   # Local -> Server

# Direct script
./scripts/sync-files.sh pull NAME  # Server -> Local
./scripts/sync-files.sh push NAME  # Local -> Server
```

Config: Copy `pve/NAME/.envrc.example` to `.envrc` and set `REMOTE_HOST`.

## Security

**Secrets management:**
- `.env` files contain secrets → **never commit** (gitignored)
- `.env.example` for structure reference (keys only)
- Ansible Vault available but currently unused

**Access control:**
- Caddy: GitHub IP whitelist for webhook endpoint
- Webhook: HMAC-SHA256 signature verification
- Proxmox: API token with minimal permissions

**Backup locations:**
- `/opt/backups/control-node/` - Control node (Ansible vault, SSH keys)
- Proxmox Backup Server - VM/LXC snapshots

## Directory Structure

```
├── Makefile                  # Root sync commands (push/pull)
├── pve/
│   ├── archive/              # Archived services (not deployed)
│   ├── x000/                 # Control node
│   │   ├── Makefile          # Service + setup commands
│   │   ├── setup.sh          # Control node setup
│   │   ├── setup.env.example
│   │   ├── backup-control-node.sh
│   │   ├── verify-backups.sh
│   │   ├── scripts/          # Host scripts for webhook
│   │   │   ├── deploy.sh     # Deployment script
│   │   │   ├── stop-service.sh # Stop containers script
│   │   │   └── apply-tofu.sh # OpenTofu script
│   │   ├── ansible/          # Ansible configuration
│   │   │   ├── inventory/hosts.yml
│   │   │   ├── playbooks/
│   │   │   ├── group_vars/all/
│   │   │   └── roles/
│   │   ├── infra/tofu/       # OpenTofu (Proxmox VMs)
│   │   │   ├── vms.tf
│   │   │   └── provider.tf
│   │   └── docker/config/
│   │       ├── caddy/        # Reverse proxy
│   │       ├── webhook/      # GitHub webhooks
│   │       ├── portainer/    # Container management
│   │       ├── cloudflared/  # Cloudflare tunnel
│   │       └── pihole/       # DNS + ad-blocking
│   ├── x201/                 # Web apps (VM)
│   │   ├── Makefile          # Service orchestration
│   │   └── docker/config/SERVICE/
│   ├── x202/                 # Web services (primary VM)
│   │   ├── Makefile          # Service orchestration
│   │   └── docker/config/SERVICE/
│   └── x203/                 # File sharing (VM)
│       ├── Makefile          # Service orchestration
│       └── docker/config/SERVICE/
├── scripts/
│   ├── sync-files.sh         # Bidirectional rsync
│   ├── tests/                # Test suite
│   ├── init-host.sh          # Universal host init (VM/LXC/RPi)
│   ├── init-host/            # Dotfiles it installs (p10k, herdr, Makefile)
│   ├── .env.example          # init-host.sh config template
│   ├── health-monitor.sh     # System/Docker health report
│   └── claude-statusline.sh  # Terminal statusline helper
└── docs/                     # Guides
```

## Contributing

**Working directory:** Run Make commands from environment root (`pve/x202/`, `pve/x000/`)

**Adding services:**
1. Create `pve/ENV/docker/config/SERVICE/`
2. Add `compose.yml`, `.env.example`
3. Makefile auto-discovers services

**Conventions:**
- Prefer shared PostgreSQL (`pve/x202/docker/config/postgres/`)
- Use `${PWD}/docker/config/SERVICE/` for volume paths
- SSH key auth required for file sync
- All secrets via environment variables

**Documentation:**
- [scripts/README.md](scripts/README.md) - init-host.sh, sync, health monitor
- [pve/x000/docker/config/webhook/README.md](pve/x000/docker/config/webhook/README.md) - Webhook setup & troubleshooting
- [pve/x000/ansible/README.md](pve/x000/ansible/README.md) - Ansible setup
- [pve/x000/infra/README.md](pve/x000/infra/README.md) - OpenTofu/Proxmox
- [pve/x000/README.md](pve/x000/README.md) - Control node
- [pve/x201/README.md](pve/x201/README.md) - Web apps
- [pve/x202/README.md](pve/x202/README.md) - Web services
- [pve/x203/README.md](pve/x203/README.md) - File sharing
- [docs/automation/](docs/automation/) - GitOps workflow
