# Homelab Infrastructure

Proxmox-based homelab with Docker Compose orchestration, Ansible automation, and OpenTofu infrastructure management.

## Quick Start

**Primary environment** (x202):
```bash
cd pve/x202
make SERVICE [up|down|restart]  # See CLAUDE.md for service list
```

## File Sync

Sync configuration between local and server using Makefile shortcuts:

```bash
# Pull: Server -> Local
make pull NAME  # e.g., make pull x202

# Push: Local -> Server
make push NAME  # e.g., make push x202
```

NAME must match a directory in `pve/` (x000, x201, x202, x203).

**Direct script usage:**
```bash
./scripts/sync-files.sh pull NAME  # Server -> Local
./scripts/sync-files.sh push NAME  # Local -> Server
```

**Config:** Copy `pve/NAME/.envrc.example` to `.envrc` and set `REMOTE_HOST`.

## Environments

- **x000**: Control node (Ansible, webhook handler, automation)
- **x201**: Self-hosted web apps (Proxmox VM)
- **x202**: Web/application services (primary, Proxmox VM)
- **x203**: File sharing (Samba, qBittorrent, Proxmox VM)
- **archive**: Retired services and environments, not deployed

## Automation

### GitOps Workflow

Push to `main` branch triggers automated deployments:

```
GitHub Push → webhook.wywiol.eu/hooks/homelab → x000 webhook handler → {
  pve/x000/docker/config/* → Ansible deployment (x000 services)
  pve/x201/docker/config/* → Ansible deployment (x201 services)
  pve/x202/docker/config/* → Ansible deployment (x202 services)
  pve/x203/docker/config/* → Ansible deployment (x203 services)
  pve/x000/infra/tofu/*    → OpenTofu plan (infrastructure updates)
}
```

Removing a service directory stops and removes its containers on the target
host. Paths outside those prefixes are reported as ignored.

**Components:**
- **Webhook Handler** (x000): adnanh/webhook with GitHub signature verification
- **OpenTofu** (x000): Proxmox VM management
- **Caddy** (x000): Reverse proxy with GitHub IP whitelist

**Full Documentation:** [docs/automation/README.md](./docs/automation/README.md)

## Documentation

- **[CLAUDE.md](./CLAUDE.md)** - Service management commands
- **[docs/automation/](./docs/automation/)** - GitOps automation (Ansible + OpenTofu + webhooks)
- **[pve/x201/README.md](./pve/x201/README.md)** - Web apps
- **[pve/x202/README.md](./pve/x202/README.md)** - Web services
- **[pve/x203/README.md](./pve/x203/README.md)** - File sharing
- **[pve/x000/ansible/README.md](./pve/x000/ansible/README.md)** - Ansible playbooks + vault
- **[pve/x000/infra/README.md](./pve/x000/infra/README.md)** - OpenTofu VM management
- **[pve/x000/docker/config/webhook/README.md](./pve/x000/docker/config/webhook/README.md)** - Webhook handler setup
- **[docs/](./docs/)** - Docker, Linux, Proxmox, WSL guides
- **[scripts/](./scripts/)** - Init + setup scripts

## Structure

```
├── pve/                     # Proxmox environments
│   ├── archive/             # Retired services + environments (not deployed)
│   ├── x000/                # Control node (automation hub)
│   │   ├── Makefile         # Service + setup commands
│   │   ├── setup.sh         # Control node setup
│   │   ├── scripts/         # Host scripts (deploy.sh, stop-service.sh, apply-tofu.sh)
│   │   ├── ansible/         # Ansible playbooks + vault
│   │   ├── infra/tofu/      # OpenTofu VM management
│   │   └── docker/config/   # Caddy, webhook, portainer, cloudflared, pihole, …
│   ├── x201/                # Web apps (VM)
│   │   ├── Makefile         # Service orchestration
│   │   └── docker/config/SERVICE/
│   ├── x202/                # Web services (primary VM)
│   │   ├── Makefile         # Service orchestration
│   │   └── docker/config/SERVICE/
│   └── x203/                # File sharing (VM)
│       ├── Makefile         # Service orchestration
│       └── docker/config/SERVICE/
├── scripts/                 # Utility scripts
│   ├── sync-files.sh        # Local ↔ server sync
│   ├── init-host.sh         # Universal host initialization (root)
│   ├── init-host/           # Dotfiles it installs (p10k, herdr, Makefile)
│   ├── health-monitor.sh    # System/Docker health report
│   └── tests/               # Test suites
└── docs/                    # Documentation
    └── automation/          # GitOps automation guide
```

See [CLAUDE.md](./CLAUDE.md) for service commands.
