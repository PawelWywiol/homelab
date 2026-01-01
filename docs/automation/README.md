# Ansible + OpenTofu Automation

**Control Node**: x000
**Managed Host**: x202
**Base Domain**: wywiol.eu
**Status**: Production-ready

## Overview

GitOps automation for homelab infrastructure using Ansible, OpenTofu, and GitHub webhooks. Push to main branch triggers automated service deployments and infrastructure updates.

### Architecture

```
GitHub Push (main) → webhook.wywiol.eu/hooks/homelab (Caddy: GitHub IP whitelist)
                              ↓
                      x000:8097 (webhook: HMAC verification)
                              ↓
                      trigger-homelab.sh (file routing)
                              ↓
                    ┌─────────┴─────────┐
                    ↓                   ↓
            scripts/deploy.sh    scripts/apply-tofu.sh
                    ↓                   ↓
        git pull + Ansible         tofu plan
                    ↓                   ↓
                  x202              Proxmox VM
                 (Web)             (via OpenTofu)
```

### Key Features

- **GitOps Workflow**: Push to main → automated deployment
- **Unified Webhook**: Single `/hooks/homelab` endpoint routes by file changes
- **Service Management**: Ansible playbooks for Docker Compose services
- **Infrastructure as Code**: OpenTofu for Proxmox VM management
- **Security**: Multi-layer (IP whitelist, HMAC, SSH keys, Vault)
- **Notifications**: Discord webhook integration

### Managed Infrastructure

- **x000**: Control node (orchestration hub)
- **x202**: Web services (4 vCPUs, 12GB RAM) - managed by OpenTofu + Ansible

## Quick Start

### Prerequisites

1. **DNS Configuration**:
   ```
   A records:
   webhook.wywiol.eu  → 192.168.0.2 (x000)
   wywiol.eu          → 192.168.0.2
   ```

2. **Proxmox API Token** (for OpenTofu):
   See [pve/x000/infra/README.md](../pve/x000/infra/README.md#proxmox-api-token-setup) for setup instructions.

3. **GitHub Personal Access Token** (for webhooks)

### Installation

**Step 1: Prepare Host**

```bash
# On fresh VM/LXC - run init-host.sh
# From local machine with access to target:
scp scripts/init-host.sh root@x000:/tmp/
ssh root@x000 '/tmp/init-host.sh'
```

**Step 2: Clone Repository**

```bash
ssh code@x000
git clone https://github.com/PawelWywiol/homelab.git
cd ~/homelab/pve/x000
```

**Step 3: Configure and Run Setup**

```bash
# Create configuration
cp setup.env.example .env
nano .env  # Set: CLOUDFLARE_API_TOKEN, BASE_DOMAIN, CONTROL_NODE_IP, LOCAL_NETWORK_RANGE

# Run setup (idempotent - safe to re-run)
make setup
```

**IMPORTANT**: Save credentials from output:
- GitHub webhook secret
- SSH key path

**Step 4: Start Services**

```bash
# Start all control node services
make all up

# Or individually:
make caddy up
make webhook up
make portainer up
```

**Step 5: Distribute SSH Keys**

```bash
# Copy SSH key to x202
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.202

# Test connectivity (run from ansible/ directory)
cd ansible
ansible all -m ping
```

**Step 6: Configure GitHub Webhook**

1. GitHub repo → Settings → Webhooks → Add webhook
2. Payload URL: `https://webhook.wywiol.eu/hooks/homelab`
3. Content type: `application/json`
4. Secret: from `docker/config/webhook/.env` (`GITHUB_WEBHOOK_SECRET`)
5. Events: Just the push event

Test:
```bash
curl https://webhook.wywiol.eu/hooks/health
# Should return: "Webhook service healthy"
```

## Webhook Automation

### How It Works

1. Push changes to `main` branch
2. GitHub sends webhook to `webhook.wywiol.eu/hooks/homelab`
3. Caddy validates GitHub IP range
4. Webhook handler verifies HMAC signature
5. `trigger-homelab.sh` analyzes changed files and routes:
   - `pve/x202/docker/config/*` → Ansible deploy to x202
   - `pve/x000/infra/tofu/*` → OpenTofu plan
6. Discord notification on completion

### Triggers

| Path Pattern | Action |
|--------------|--------|
| `pve/x202/docker/config/*` | Deploy services to x202 |
| `pve/x000/infra/tofu/*` | OpenTofu plan (manual apply) |

### Configuration

**File:** `pve/x000/docker/config/webhook/.env`

```bash
# Required
GITHUB_WEBHOOK_SECRET=<your-secret>

# SSH (for connecting to host)
SSH_HOST=host.docker.internal
SSH_USER=code

# OpenTofu
TOFU_AUTO_APPLY=false  # Manual apply recommended

# Discord notifications
DISCORD_ENABLED=true
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/ID/TOKEN
```

## Ansible Configuration

**Working directory:** Run all Ansible commands from `ansible/` subdirectory.

### Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # x202 host definition
├── group_vars/
│   └── all/
│       ├── vars.yml            # Common variables
│       └── vault.yml.example   # Vault template (unused)
├── playbooks/
│   ├── deploy-service.yml  # Main deployment playbook
│   └── _deploy_single.yml  # Helper task
└── roles/
    └── docker_compose/     # Docker Compose role
```

### Usage

```bash
# Deploy single service
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202" \
  -e "service=caddy"

# Deploy all services to host
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202"

# Dry run
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202" \
  --check
```

### Secrets

Services use `.env` files for secrets (gitignored). Ansible Vault available but currently unused.

## OpenTofu Infrastructure

### Structure

```
pve/x000/infra/tofu/       # Centralized provider config
├── provider.tf            # Proxmox provider
├── variables.tf           # Input variables
├── vms.tf                # x202 VM definition
├── outputs.tf            # Output values
└── terraform.tfvars       # Secrets (not in git)
```

### Usage

```bash
cd ~/homelab/pve/x000/infra/tofu

# Initialize
tofu init

# Plan changes
tofu plan

# Apply changes
tofu apply

# Import existing VM
tofu import proxmox_virtual_environment_vm.x202 pve/202
```

## Service Management

### x000 Control Node

```bash
cd pve/x000

# Start all services
make all up

# Stop all services
make all down

# Individual service
make caddy up|down|restart|logs
make webhook up|down|restart|logs
make portainer up|down|restart|logs
```

### x202 Web Services

```bash
cd pve/x202

# Individual service
make SERVICE up|down|restart|logs

# Available services:
# caddy, portainer, postgres, redis, mongo, rabbitmq,
# influxdb, grafana, n8n, wakapi, beszel, uptime-kuma,
# ntfy, glitchtip
```

## Security

### Multi-Layer Security

1. **Caddy IP whitelist** - Only GitHub IPs for webhook
2. **HMAC-SHA256** - Verifies GitHub authenticity
3. **SSH keys** - Key-based authentication only
4. **API Tokens** - Minimal permissions

### Secret Management

- `.env` files: Service secrets, gitignored
- `~/.ssh/id_ed25519`: SSH key for Ansible
- `terraform.tfvars`: Proxmox credentials (not in git)

## Troubleshooting

### Webhook Issues

```bash
# Check webhook logs
make webhook logs

# Test webhook health
curl https://webhook.wywiol.eu/hooks/health

# Test SSH from container
docker exec webhook ssh code@host.docker.internal "echo OK"
```

### Ansible Issues

```bash
# Run from ansible/ directory
cd ansible

# Test connectivity
ansible all -m ping -vvv

# Check SSH
ssh -i ~/.ssh/id_ed25519 code@192.168.0.202
```

### OpenTofu Issues

```bash
# Check state
tofu show

# Refresh state
tofu refresh

# Force unlock
tofu force-unlock <lock-id>
```

## File Locations

**On x000 (`~/homelab/pve/x000/`):**

| Purpose | Location |
|---------|----------|
| Setup script | `setup.sh` |
| Host scripts | `scripts/deploy.sh`, `scripts/apply-tofu.sh` |
| Docker services | `docker/config/` |
| Ansible config | `ansible/` |
| OpenTofu config | `infra/tofu/` |
| SSH keys | `~/.ssh/id_ed25519` |

---

**Last Updated**: 2025-12-21
**Version**: 3.0
**Status**: Production-ready
