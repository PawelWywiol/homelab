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
| x000 | Control node | caddy, webhook, portainer, cloudflared, pihole | `pve/x000/Makefile` |
| x202 | Web/App (primary) | 16 services | `pve/x202/Makefile` |

**Path pattern:** `pve/ENV/docker/config/SERVICE/`

## Service Management

### x202 Services

```bash
cd pve/x202
make SERVICE [up|down|restart|pull|logs]
```

| Service | Description |
|---------|-------------|
| portainer | Container management UI |
| postgres | PostgreSQL + pgAdmin |
| redis | Redis cache |
| mongo | MongoDB + Mongo Express |
| rabbitmq | Message broker |
| influxdb | Time-series DB |
| grafana | Dashboards |
| n8n | Workflow automation |
| wakapi | Coding activity tracker |
| beszel | System monitoring |
| glitchtip | Error tracking |
| k6 | Load testing |

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
| pihole | 53, 5080 | DNS + ad-blocking |

## Control Node Setup

Setup control node:

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

Push to `main` triggers automated deployments:

```
GitHub Push → webhook.wywiol.eu (Caddy: IP whitelist)
           → webhook:8097 (custom image with bash/jq, HMAC verification)
           → SSH to localhost → scripts/deploy.sh
           → git pull + Ansible / OpenTofu
           → Deploy services / Update VMs
           → Discord notification
```

**Triggers:**

| Path Change | Action |
|-------------|--------|
| `pve/x202/docker/config/*` | Deploy x202 services (Ansible) |
| `pve/x000/infra/tofu/*` | OpenTofu plan (manual apply) |

**Ansible playbooks:**
- `deploy-service.yml` - Deploy Docker Compose services
- `rollback-service.yml` - Rollback to previous version

**Managed hosts:** x202 (VM)

## File Sync

```bash
# Root Makefile shortcuts
make pull NAME   # Server -> Local (NAME = x000|x202|x250)
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
│   ├── x000/                 # Control node
│   │   ├── Makefile          # Service + setup commands
│   │   ├── setup.sh          # Control node setup
│   │   ├── setup.env.example
│   │   ├── backup-control-node.sh
│   │   ├── verify-backups.sh
│   │   ├── scripts/          # Host scripts for webhook
│   │   │   ├── deploy.sh     # Deployment script
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
│   ├── legacy/               # Legacy services (deprecated)
│   ├── x202/                 # Web services (primary VM)
│   │   ├── Makefile          # Service orchestration
│   │   └── docker/config/SERVICE/
│   └── x250/                 # AI/ML
├── scripts/
│   ├── sync-files.sh         # Bidirectional rsync
│   ├── tests/                # Test suite
│   ├── init-host.sh          # Universal host init (VM/LXC/RPi)
│   ├── .env.example          # init-host.sh config template
│   ├── init-vm.sh            # VM initialization (legacy)
│   └── init-lxc.sh           # LXC initialization (legacy)
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
- [pve/x000/docker/config/webhook/README.md](pve/x000/docker/config/webhook/README.md) - Webhook setup & troubleshooting
- [pve/x000/ansible/README.md](pve/x000/ansible/README.md) - Ansible setup
- [pve/x000/infra/README.md](pve/x000/infra/README.md) - OpenTofu/Proxmox
- [pve/x000/README.md](pve/x000/README.md) - Control node
- [docs/automation/](docs/automation/) - GitOps workflow
