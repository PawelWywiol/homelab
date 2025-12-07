# CLAUDE.md

Homelab infrastructure with Docker Compose, Ansible automation, OpenTofu IaC, and GitOps workflows.

## Quick Start

```bash
# x202 (primary) - manage services
cd pve/x202 && make SERVICE up|down|restart|logs

# x199 (control node) - manage automation
cd pve/x199 && make SERVICE up|down|restart|logs

# File sync
make pull NAME   # Server -> Local
make push NAME   # Local -> Server
```

## Environments

| ID | Purpose | Services | Makefile |
|----|---------|----------|----------|
| x199 | Control node | caddy, semaphore, webhook | `pve/x199/Makefile` |
| x201 | DNS/Network | caddy | `pve/x201/Makefile` |
| x202 | Web/App (primary) | 16 services | `pve/x202/Makefile` |
| x250 | AI/ML | sd-rocm | - |
| x000 | Legacy | various | - |

**Path patterns:**
- x199, x201, x202: `pve/ENV/docker/config/SERVICE/`
- x000 (legacy): `pve/x000/SERVICE/`

## Service Management

### x202 Services

```bash
cd pve/x202
make SERVICE [up|down|restart|pull|logs]
```

| Service | Description |
|---------|-------------|
| caddy | Reverse proxy (Cloudflare DNS) |
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
| uptime-kuma | Uptime monitoring |
| ntfy | Push notifications |
| glitchtip | Error tracking |
| sonarqube | Code quality |
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

### x199 Services (Control Node)

```bash
cd pve/x199
make SERVICE [up|down|restart|pull|logs]
```

| Service | Port | Description |
|---------|------|-------------|
| caddy | 80, 443 | Reverse proxy (Cloudflare DNS) |
| semaphore | 3001 | Ansible automation UI |
| webhook | 8097 | GitHub webhook handler |

## Control Node Setup

Bootstrap fresh Debian/Ubuntu machine as x199 control node:

```bash
# On local machine
git clone https://github.com/PawelWywiol/homelab.git && cd homelab
make push x199

# On x199 server
ssh code@x199
cp bootstrap.env.example .env
nano .env  # Set required: CLOUDFLARE_API_TOKEN, BASE_DOMAIN, CONTROL_NODE_IP
make bootstrap
```

**Installs:** Docker, Ansible (+collections), OpenTofu
**Configures:** Caddy (Cloudflare DNS), Semaphore, Webhook, Docker network
**Auto-generates:** Vault password, Semaphore credentials, webhook secret

## GitOps Automation

Push to `main` triggers automated deployments:

```
GitHub Push → webhook.wywiol.eu (Caddy: IP whitelist)
           → webhook:8097 (HMAC verification)
           → Semaphore API / OpenTofu
           → Deploy services / Update VMs
           → ntfy.sh notification
```

**Triggers:**

| Path Change | Action |
|-------------|--------|
| `pve/x202/*` | Deploy x202 services (Ansible) |
| `pve/x201/*` | Deploy x201 services (Ansible) |
| `pve/x199/infra/tofu/*` | OpenTofu plan (manual apply) |
| `pve/x199/ansible/*` | Syntax check |

**Ansible playbooks:**
- `deploy-service.yml` - Deploy Docker Compose services
- `rollback-service.yml` - Rollback to previous version

**Managed hosts:** x100, x199, x201, x202 (VMs) + 107, 108, 109, 111 (LXC)

## File Sync

```bash
# Root Makefile shortcuts
make pull NAME   # Server -> Local (NAME = x199|x201|x202|x250)
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
- `pve/x199/ansible/group_vars/all/vault.yml` - Ansible Vault encrypted
- `~/.ansible/vault_password` - Vault decryption key (on x199)
- `~/.semaphore/` - Semaphore data (on x199)

**Access control:**
- Caddy: GitHub IP whitelist for webhook endpoint
- Caddy: Local network only for Semaphore UI
- Webhook: HMAC-SHA256 signature verification
- Proxmox: API token with minimal permissions

**Backup locations:**
- `/opt/backups/control-node/` - Control node (Ansible vault, SSH keys)
- Proxmox Backup Server - VM/LXC snapshots

## Directory Structure

```
├── Makefile                  # Root sync commands (push/pull)
├── pve/
│   ├── x199/                 # Control node (all automation)
│   │   ├── Makefile          # Service + bootstrap commands
│   │   ├── bootstrap.sh      # Control node setup
│   │   ├── bootstrap.env.example
│   │   ├── backup-control-node.sh
│   │   ├── verify-backups.sh
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
│   │       ├── semaphore/    # Ansible UI
│   │       └── webhook/      # GitHub webhooks
│   ├── x201/                 # DNS services
│   ├── x202/                 # Web services (primary)
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

**Working directory:** Run Make commands from environment root (`pve/x202/`, `pve/x199/`)

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
- [pve/x199/ansible/README.md](pve/x199/ansible/README.md) - Ansible setup
- [pve/x199/infra/README.md](pve/x199/infra/README.md) - OpenTofu/Proxmox
- [pve/x199/README.md](pve/x199/README.md) - Control node
- [docs/automation/](docs/automation/) - GitOps workflow
