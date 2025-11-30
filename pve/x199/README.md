# x199 - Control Node

Automation and orchestration hub for the homelab infrastructure. Contains all Ansible playbooks, OpenTofu configurations, and Docker services for GitOps workflows.

## Quick Start

```bash
# On local machine
git clone https://github.com/PawelWywiol/homelab.git && cd homelab
make push code@x199

# On x199 server
ssh code@x199
cp bootstrap.env.example .env
nano .env  # Set: CLOUDFLARE_API_TOKEN, BASE_DOMAIN, CONTROL_NODE_IP
make bootstrap
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| caddy | 80, 443 | Reverse proxy with auto-HTTPS |
| semaphore | 3001 | Ansible automation UI |
| webhook | 8097 | GitHub webhook handler |

## Usage

```bash
# Manage services
make caddy up|down|restart|pull|logs
make semaphore up|down|restart|pull|logs
make webhook up|down|restart|pull|logs

# Setup
make bootstrap   # Run control node bootstrap
make backup      # Backup control node
make verify      # Verify backups

# Tools
make random      # Generate random secret
make help        # Show help
```

## Structure

**In repository (pve/x199/):**
```
pve/x199/
├── Makefile              # Service + setup commands
├── bootstrap.sh          # Control node setup
├── bootstrap.env.example
├── backup-control-node.sh
├── verify-backups.sh
├── .envrc                # Sync config
├── ansible/              # Ansible configuration
│   ├── ansible.cfg
│   ├── inventory/hosts.yml
│   ├── playbooks/
│   ├── group_vars/all/
│   └── roles/
├── infra/tofu/           # OpenTofu (Proxmox VMs)
│   ├── provider.tf
│   ├── variables.tf
│   ├── vms.tf
│   └── terraform.tfvars.example
└── docker/config/
    ├── caddy/            # Reverse proxy
    ├── semaphore/        # Ansible UI
    └── webhook/          # GitHub webhooks
```

**On x199 server (after sync):**
```
~/
├── Makefile
├── bootstrap.sh
├── ansible/
├── infra/tofu/
├── docker/config/
└── .semaphore/           # Semaphore data (created by bootstrap)
```

## GitOps Triggers

| Path Change | Action |
|-------------|--------|
| `pve/x202/*` | Deploy x202 services |
| `pve/x201/*` | Deploy x201 services |
| `pve/x199/infra/tofu/*` | OpenTofu plan |
| `pve/x199/ansible/*` | Ansible syntax check |

## Documentation

- [Webhook Service](docker/config/webhook/README.md) - GitHub webhook configuration
- [Automation Guide](../../docs/automation/ansible-opentofu-automation.md) - Full automation setup
- [Ansible README](ansible/README.md) - Ansible playbooks and vault
- [OpenTofu README](infra/README.md) - Proxmox VM management
