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
# Pull: Server → Local
make pull user@HOST  # e.g., make pull code@x202

# Push: Local → Server
make push user@HOST  # e.g., make push code@x202
```

HOST must match a directory in `pve/` (x000, x201, x202, x250).

**Direct script usage:**
```bash
./scripts/sync-files.sh user@host ./pve/PATH  # Server → Local
./scripts/sync-files.sh ./pve/PATH user@host  # Local → Server
```

Config: Define files in `pve/*/.envrc` `SYNC_FILES` array.

## Environments

- **x000**: Legacy services (deprecated)
- **x199**: Control node (Ansible, Semaphore, webhook handler)
- **x201**: DNS/network services
- **x202**: Web/application services (primary)
- **x250**: AI/ML workloads
- **x203**: K3s cluster (planned)

## Automation

### GitOps Workflow

Push to `main` branch triggers automated deployments:

```
GitHub Push → webhook.wywiol.eu → x199 webhook handler → {
  pve/x202/* → Ansible deployment (x202 services)
  pve/x201/* → Ansible deployment (x201 services)
  pve/x199/infra/tofu/* → OpenTofu plan (infrastructure updates)
  pve/x199/ansible/* → Syntax check
}
```

**Components:**
- **Webhook Handler** (x199): adnanh/webhook with GitHub signature verification
- **Semaphore UI** (x199): Ansible playbook orchestration
- **OpenTofu** (x199): Proxmox VM management
- **Caddy** (x199): Reverse proxy with GitHub IP whitelist

**Full Documentation:** [docs/automation/ansible-opentofu-automation.md](./docs/automation/ansible-opentofu-automation.md)

## Documentation

- **[CLAUDE.md](./CLAUDE.md)** - Service management commands
- **[docs/automation/](./docs/automation/)** - GitOps automation (Ansible + OpenTofu + webhooks)
- **[pve/x199/ansible/README.md](./pve/x199/ansible/README.md)** - Ansible playbooks + vault
- **[pve/x199/infra/README.md](./pve/x199/infra/README.md)** - OpenTofu VM management
- **[pve/x199/docker/config/webhook/README.md](./pve/x199/docker/config/webhook/README.md)** - Webhook handler setup
- **[docs/](./docs/)** - Docker, Linux, Proxmox, WSL guides
- **[scripts/](./scripts/)** - Init + setup scripts

## Structure

```
├── pve/                     # Proxmox environments
│   ├── x199/                # Control node (all automation)
│   │   ├── Makefile         # Service + bootstrap commands
│   │   ├── bootstrap.sh     # Control node setup
│   │   ├── ansible/         # Ansible playbooks + vault
│   │   ├── infra/tofu/      # OpenTofu VM management
│   │   └── docker/config/   # Caddy, Semaphore, webhook
│   ├── x201/                # DNS services
│   ├── x202/                # Web services (primary)
│   │   ├── Makefile         # Service orchestration
│   │   └── docker/config/SERVICE/
│   └── x250/                # AI/ML workloads
├── scripts/                 # Utility scripts
│   ├── sync-files.sh        # Local ↔ server sync
│   ├── init-vm.sh           # VM initialization
│   └── init-lxc.sh          # LXC initialization
└── docs/                    # Documentation
    ├── automation/          # GitOps automation guide
    └── plans/archive/       # Historical planning docs
```

See [CLAUDE.md](./CLAUDE.md) for service commands.
