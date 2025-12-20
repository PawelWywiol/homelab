# x000 - Control Node

Automation and orchestration hub for the homelab infrastructure. Runs on a standalone machine.

## Quick Start

```bash
# On local machine
git clone https://github.com/PawelWywiol/homelab.git && cd homelab
make push x000

# On x000 (192.168.0.2)
ssh code@x000
cp setup.env.example .env
nano .env  # Set: CLOUDFLARE_API_TOKEN, BASE_DOMAIN, CONTROL_NODE_IP
make setup
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| caddy | 80, 443 | Reverse proxy with auto-HTTPS |
| webhook | 8097 | GitHub webhook handler |
| portainer | 9443 | Container management UI |
| cloudflared | - | Cloudflare Tunnel |
| pihole | 53, 5080 | DNS + ad-blocking |

## Usage

```bash
# Manage services
make caddy up|down|restart|pull|logs
make webhook up|down|restart|pull|logs
make portainer up|down|restart|pull|logs
make cloudflared up|down|restart|pull|logs
make pihole up|down|restart|pull|logs

# Bulk operations
make all up|down  # Start/stop all services

# Setup
make setup       # Run control node setup
make backup      # Backup control node
make verify      # Verify backups

# Tools
make random      # Generate random secret
make help        # Show help
```

## Structure

**In repository (pve/x000/):**
```
pve/x000/
├── Makefile              # Service + setup commands
├── setup.sh              # Control node setup
├── setup.env.example
├── backup-control-node.sh
├── verify-backups.sh
├── .envrc                # Sync config
├── scripts/              # Host scripts
│   ├── deploy.sh         # Ansible deployment
│   └── apply-tofu.sh     # OpenTofu plan/apply
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
    ├── webhook/          # GitHub webhooks
    ├── portainer/        # Container management
    ├── cloudflared/      # Cloudflare tunnel
    └── pihole/           # DNS + ad-blocking
```

**On x000 (after sync):**
```
~/
├── Makefile
├── setup.sh
├── scripts/              # Host scripts (deploy.sh, apply-tofu.sh)
├── ansible/
├── infra/tofu/
└── docker/config/
```

## GitOps Triggers

| Path Change | Action |
|-------------|--------|
| `pve/x202/docker/config/*` | Deploy x202 services |
| `pve/x201/*` | Deploy x201 services |
| `pve/*/vms.tf` | OpenTofu plan |
| `pve/x000/infra/tofu/*` | OpenTofu plan |

## Documentation

- [Webhook Service](docker/config/webhook/README.md) - GitHub webhook configuration
- [Automation Guide](../../docs/automation/ansible-opentofu-automation.md) - Full automation setup
- [Ansible README](ansible/README.md) - Ansible playbooks and vault
- [OpenTofu README](infra/README.md) - Proxmox VM management
