# Ansible + OpenTofu Automation

**Control Node**: x000
**Base Domain**: wywiol.eu
**Status**: Production-ready

## Overview

GitOps automation for homelab infrastructure using Ansible, OpenTofu, Semaphore UI, and GitHub webhooks. Push to main branch triggers automated service deployments and infrastructure updates.

### Key Features

- **GitOps Workflow**: Push to main → automated deployment
- **Service Management**: Ansible playbooks for Docker Compose services
- **Infrastructure as Code**: OpenTofu for Proxmox VM management
- **Web UI**: Semaphore for visual Ansible execution
- **Webhook Automation**: GitHub webhooks trigger deployments
- **Security**: Multi-layer (IP whitelist, HMAC, SSH keys, Vault)
- **Backup**: Comprehensive PBS integration + control node backups
- **Notifications**: ntfy.sh integration

### Architecture

```
GitHub Push (main) → webhook.wywiol.eu (Caddy: GitHub IP whitelist)
                              ↓
                      x000:8097 (adnanh/webhook: HMAC verification)
                              ↓
                    ┌─────────┴─────────┐
                    ↓                   ↓
            Semaphore API          OpenTofu Script
            (Ansible Runner)       (tofu plan/apply)
                    ↓                   ↓
            Ansible Playbooks      tofu plan/apply
            (Docker Compose)       (VM management)
                    ↓                   ↓
        ┌───────────┼───────────┐       │
        ↓           ↓           ↓       ↓
     x201        x202    LXC 107-111  Proxmox VMs
    (DNS)       (Web)    (Services)   (x100,x199,x201,x202)
                              ↓
                        ntfy.sh (notifications)
```

### Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Control Node** | x000 | Orchestration hub |
| **Ansible** | 2.16+ | Configuration management |
| **OpenTofu** | 1.8+ | VM provisioning |
| **Semaphore UI** | Docker | Ansible web interface |
| **Caddy** | Docker | Reverse proxy + HTTPS |
| **Webhook Handler** | adnanh/webhook | GitHub event processor |
| **Notifications** | ntfy.sh | Event notifications |

### Managed Infrastructure

**Control Node**:
- x000: Control node (4GB RAM, external to Proxmox)

**VMs (OpenTofu)**:
- x100: Development (2x2 cores, 12GB RAM, 64GB disk)
- x199: Legacy VM (2 cores, 4GB RAM, 64GB disk)
- x201: DNS services (2 cores, 2GB RAM, 64GB disk)
- x202: Web services (4 cores, 12GB RAM, 128GB disk)

**LXC Containers (Ansible)**:
- 107: sitespeed
- 108: passbolt
- 109: samba
- 111: romm

**Services (Ansible)**:
- Caddy, Portainer, n8n, Wakapi, Beszel
- Uptime-kuma, ntfy, Grafana
- PostgreSQL, Redis, RabbitMQ, MongoDB, InfluxDB
- GlitchTip, SonarQube

## Quick Start

### Prerequisites

1. **DNS Configuration**:
   ```
   A records:
   semaphore.local.wywiol.eu  → 192.168.0.2
   webhook.wywiol.eu          → 192.168.0.2
   wywiol.eu                  → 192.168.0.2
   ```

2. **Proxmox API Token** (Proxmox VE 8.x / 9.x):

   **Option A: Web UI (recommended)**
   1. Login to Proxmox web interface (`https://PROXMOX_IP:8006`)
   2. Navigate: Datacenter → Permissions → API Tokens
   3. Click "Add"
   4. Configure:
      - User: `root@pam` (or dedicated user like `homelab@pve`)
      - Token ID: `tofu` (any alphanumeric name)
      - Privilege Separation: **Unchecked** (inherit user permissions)
      - Expire: Never (or set expiration date)
   5. Click "Add" and **copy the token value immediately** (shown only once)
   6. Token format: `USER@REALM!TOKENID=UUID`
      - Example: `root@pam!tofu=dc9c9547-5aef-4142-882f-7e141b1c7f57`

   **Option B: CLI**
   ```bash
   # SSH to Proxmox host
   ssh root@192.168.0.200

   # Create token (copy the output - shown only once!)
   pveum user token add root@pam tofu --privsep 0

   # Verify token exists
   pveum user token list root@pam
   ```

   **Required Permissions** (if using dedicated user with privsep=1):
   ```bash
   # Grant permissions to token
   pveum acl modify / -token 'homelab@pve!tofu' -role Administrator
   # Or minimal permissions:
   pveum acl modify /vms -token 'homelab@pve!tofu' -role PVEVMAdmin
   pveum acl modify /storage -token 'homelab@pve!tofu' -role PVEDatastoreAdmin
   ```

   **Test API Token** (use single quotes to avoid bash `!` expansion):
   ```bash
   curl -k -H 'Authorization: PVEAPIToken=root@pam!tofu=YOUR-UUID-HERE' \
     'https://192.168.0.200:8006/api2/json/cluster/resources?type=vm'
   ```

3. **GitHub Personal Access Token** (for Semaphore):
   - Settings → Developer Settings → Personal Access Tokens
   - Scope: repo (full)

### Installation

**Step 1: Bootstrap Control Node x000**

```bash
# On local machine - clone and push to x000
git clone https://github.com/PawelWywiol/homelab.git && cd homelab
make push x000

# SSH to x000
ssh code@x000

# Configure and run bootstrap
cp bootstrap.env.example .env
nano .env  # Set: CLOUDFLARE_API_TOKEN, BASE_DOMAIN, CONTROL_NODE_IP, LOCAL_NETWORK_RANGE
make bootstrap
```

**CRITICAL**: Save credentials from output:
- Ansible vault password: `~/.ansible/vault_password`
- Semaphore admin password
- GitHub webhook secret
- SSH key path

**Step 2: Distribute SSH Keys**

```bash
# On x000
# VMs
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.100
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.201
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.202

# LXC containers
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.107
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.108
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.109
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.111

# Test connectivity
cd ~/ansible
ansible all -m ping
```

**Note: Sudo Requirements**

Ansible requires passwordless sudo on all managed hosts. The `init-host.sh` script configures this automatically. For existing hosts, ensure:

```bash
# On each managed host (as root)
apt install -y sudo  # if not installed (common on minimal LXC)
echo "code ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/code
chmod 440 /etc/sudoers.d/code
```

Without this, Ansible fails with `Missing sudo password` or `sudo: not found`.

**Step 3: Configure OpenTofu**

```bash
# On x000
cd ~/infra/tofu

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Add your values:
```hcl
proxmox_endpoint   = "https://192.168.0.200:8006"
proxmox_api_token  = "homelab@pve!tofu=YOUR_TOKEN_HERE"
proxmox_insecure   = true
ssh_public_key     = "ssh-ed25519 AAAA... ansible@x000"
proxmox_node       = "pve"
```

Import existing VMs:
```bash
tofu init
tofu validate
tofu import proxmox_virtual_environment_vm.x100 pve/100
tofu import proxmox_virtual_environment_vm.x199 pve/199
tofu import proxmox_virtual_environment_vm.x201 pve/201
tofu import proxmox_virtual_environment_vm.x202 pve/202
tofu plan
# Only apply if changes look correct
tofu apply
```

**Step 4: Configure Semaphore UI**

1. Start Semaphore:
   ```bash
   make semaphore up
   ```

2. Access: `http://semaphore.local.wywiol.eu` (from local network)

3. Login: credentials from setup output

4. Create Project:
   - Name: `homelab`
   - Alert: none

5. Create Key Store:
   - Name: `ansible-ssh-key`
   - Type: SSH Key
   - Upload: `~/.ssh/id_ed25519` (private key)

6. Create Repository:
   - Name: `homelab-repo`
   - URL: `file:///repo`
   - Branch: `main`
   - Key: none (local filesystem)

7. Create Environment:
   - Name: `production`
   - Variables:
     ```json
     {
       "ansible_user": "code",
       "ansible_ssh_private_key_file": "/etc/semaphore/keys/ansible-ssh-key"
     }
     ```

8. Create Inventory:
   - Name: `homelab-inventory`
   - Type: File
   - Path: `ansible/inventory/hosts.yml`
   - SSH Key: `ansible-ssh-key`

9. Create Templates:
   - **Template 1: x202-services**
     - Name: `deploy-x202-services`
     - Playbook: `ansible/playbooks/deploy-service.yml`
     - Inventory: `homelab-inventory`
     - Environment: `production`
     - Extra variables: `{"target_host": "x202"}`

   - **Template 2: x201-services**
     - Name: `deploy-x201-services`
     - Playbook: `ansible/playbooks/deploy-service.yml`
     - Inventory: `homelab-inventory`
     - Environment: `production`
     - Extra variables: `{"target_host": "x201"}`

   - **Template 3: ansible-check**
     - Name: `ansible-check`
     - Playbook: `ansible/playbooks/deploy-service.yml`
     - Inventory: `homelab-inventory`
     - Environment: `production`
     - Options: `--syntax-check`

10. Create API Token:
    - User Settings → API Tokens → Create
    - Copy token

**Step 5: Configure Webhook Handler**

Update webhook config with Semaphore API token:
```bash
nano docker/config/webhook/.env
```

Update:
```bash
SEMAPHORE_API_TOKEN=your-token-from-step-4
SEMAPHORE_PROJECT_ID=1
SEMAPHORE_TEMPLATE_X202=1
SEMAPHORE_TEMPLATE_X201=2
SEMAPHORE_TEMPLATE_ANSIBLE_CHECK=3
```

Restart webhook:
```bash
make webhook restart
```

**Step 6: Configure GitHub Webhook**

1. GitHub repo → Settings → Webhooks → Add webhook
2. Payload URL: `https://webhook.wywiol.eu/hooks/deploy-x202-services`
3. Content type: `application/json`
4. Secret: from `~/docker/config/webhook/.env` (`GITHUB_WEBHOOK_SECRET`)
5. Events: Just the push event
6. Active: ✓

Add additional webhooks:
- `https://webhook.wywiol.eu/hooks/deploy-x201-services` (x201 changes)
- `https://webhook.wywiol.eu/hooks/update-infrastructure` (tofu changes)
- `https://webhook.wywiol.eu/hooks/check-ansible` (ansible changes)

Test:
```bash
curl https://webhook.wywiol.eu/hooks/health
# Should return: {"status":"ok","message":"Webhook service healthy"}
```

**Step 7: Setup Backups**

Control node backups:
```bash
# Create cron job for daily backups
crontab -e
```

Add:
```cron
# Daily control node backup at 3 AM
0 3 * * * /home/code/backup-control-node.sh /opt/backups/control-node

# Verify backups at 4 AM
0 4 * * * /home/code/verify-backups.sh /opt/backups/control-node
```

Proxmox VM/LXC backups:
```bash
# On Proxmox host (192.168.0.200)
# VM backups (2 AM)
pvesh create /cluster/backup \
  --schedule "0 2 * * *" \
  --storage pbs \
  --mode snapshot \
  --compress zstd \
  --vmid 100,199,201,202 \
  --mailto admin@wywiol.eu \
  --prune-backups keep-daily=7,keep-weekly=4,keep-monthly=6

# LXC backups (3 AM)
pvesh create /cluster/backup \
  --schedule "0 3 * * *" \
  --storage pbs \
  --mode snapshot \
  --compress zstd \
  --vmid 107,108,109,111 \
  --prune-backups keep-daily=7,keep-weekly=4
```

## Component Details

### Webhook System

**Location**: `~/docker/config/webhook/`

**Service**: adnanh/webhook (Go-based, lightweight)

**Configuration**:
- `compose.yml`: Docker service definition
- `hooks.yml`: Endpoint definitions + routing
- `scripts/common.sh`: Shared utilities (logging, ntfy, API calls)
- `scripts/trigger-semaphore.sh`: Semaphore API integration
- `scripts/trigger-tofu.sh`: OpenTofu automation
- `.env`: Secrets + configuration

**Endpoints**:

1. **`/hooks/deploy-x202-services`**
   - Triggers: Changes in `pve/x202/`
   - Action: Calls Semaphore template for x202
   - Payload: GitHub push event

2. **`/hooks/deploy-x201-services`**
   - Triggers: Changes in `pve/x201/`
   - Action: Calls Semaphore template for x201

3. **`/hooks/update-infrastructure`**
   - Triggers: Changes in `infra/tofu/`
   - Action: Runs `tofu plan` (manual apply by default)
   - Safety: `TOFU_AUTO_APPLY=false` default

4. **`/hooks/check-ansible`**
   - Triggers: Changes in `ansible/`
   - Action: Syntax check via Semaphore

5. **`/hooks/health`**
   - Public endpoint for monitoring
   - No authentication required

**Security Layers**:
1. Caddy IP whitelist (GitHub IP ranges)
2. HMAC-SHA256 signature verification
3. Repository filter (`PawelWywiol/homelab` only)
4. Branch filter (`main` only)
5. Path-based selective routing

**Environment Variables**:
```bash
GITHUB_WEBHOOK_SECRET=<hex-secret>
SEMAPHORE_URL=http://localhost:3001
SEMAPHORE_API_TOKEN=<api-token>
SEMAPHORE_PROJECT_ID=1
SEMAPHORE_TEMPLATE_X202=1
SEMAPHORE_TEMPLATE_X201=2
SEMAPHORE_TEMPLATE_ANSIBLE_CHECK=3
TOFU_AUTO_APPLY=false
NTFY_ENABLED=true
NTFY_URL=https://ntfy.sh
NTFY_TOPIC=homelab-webhooks
LOG_LEVEL=info
```

**Documentation**: See `pve/x000/docker/config/webhook/README.md` for full details.

### Ansible Configuration

**Location**: `~/ansible/` (on x000), `pve/x000/ansible/` (in repo)

**Structure**:
```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # All managed hosts
├── group_vars/
│   └── all/
│       ├── vars.yml        # Common variables
│       └── vault.yml       # Encrypted secrets
├── playbooks/
│   ├── deploy-service.yml  # Main deployment playbook
│   └── rollback-service.yml # Rollback playbook
└── roles/
    └── docker_compose/
        └── tasks/
            └── main.yml    # Docker Compose deployment role
```

**Inventory Groups**:
- `vms`: All virtual machines
- `lxc_containers`: All LXC containers
- `dns_vms`: DNS services (x201)
- `web_vms`: Web services (x202)
- `dev_vms`: Development (x100)
- `control_nodes`: Control node (x000)

**Host Variables**:
- `ansible_host`: IP address
- `ansible_user`: SSH user (code)
- `ansible_ssh_private_key_file`: SSH key path
- `compose_project_path`: Docker Compose file location
- `compose_style`: Project structure (legacy/x201/x202)

**Playbook Features**:
- Idempotent deployments
- Health checks with retries
- Automatic rollback on failure
- Service state verification
- Notification integration

**Vault Management**:
```bash
# View encrypted vars
ansible-vault view ansible/group_vars/all/vault.yml

# Edit encrypted vars
ansible-vault edit ansible/group_vars/all/vault.yml

# Encrypt new file
ansible-vault encrypt ansible/group_vars/all/vault.yml

# Re-key vault (change password)
ansible-vault rekey ansible/group_vars/all/vault.yml
```

**Common Commands**:
```bash
# Test connectivity
ansible all -m ping

# Run deployment
ansible-playbook ansible/playbooks/deploy-service.yml \
  -e "target_host=x202" \
  -e "service_name=caddy"

# Dry run
ansible-playbook ansible/playbooks/deploy-service.yml \
  -e "target_host=x202" \
  --check

# Verbose output
ansible-playbook ansible/playbooks/deploy-service.yml \
  -e "target_host=x202" \
  -vvv
```

### OpenTofu Infrastructure

**Location**: `~/infra/tofu/` (on x000), `pve/x000/infra/tofu/` (in repo)

**Files**:
- `provider.tf`: Proxmox provider configuration
- `variables.tf`: Input variables
- `vms.tf`: VM resource definitions
- `outputs.tf`: Output values
- `terraform.tfvars`: Secrets (not in git)
- `.gitignore`: State file protection

**VM Definitions**:

All VMs use Debian 12 cloud images with cloud-init:

```hcl
# x100: Development VM
resource "proxmox_virtual_environment_vm" "x100" {
  vm_id     = 100
  name      = "x100"
  node_name = var.proxmox_node

  cpu {
    cores   = 2
    sockets = 2  # 4 vCPUs total
  }

  memory {
    dedicated = 12288  # 12GB RAM
  }

  disk {
    datastore_id = "local-lvm"
    size         = 64
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.100/24"
        gateway = "192.168.0.1"
      }
    }
    user_account {
      username = "code"
      keys     = [var.ssh_public_key]
    }
  }
}
```

**State Management**:
- Local state files (not in git)
- Manual state protection
- Import existing VMs before management

**Common Commands**:
```bash
# Initialize
tofu init

# Validate syntax
tofu validate

# Plan changes
tofu plan

# Apply changes
tofu apply

# Import existing VM (format: node/vmid)
tofu import proxmox_virtual_environment_vm.x199 pve/199

# Show current state
tofu show

# Refresh state from Proxmox
tofu refresh

# Target specific resource
tofu apply -target=proxmox_virtual_environment_vm.x202
```

**Best Practices**:
- Always run `tofu plan` before `apply`
- Import existing resources before managing
- Keep `terraform.tfvars` out of git
- Back up state file regularly
- Use descriptive commit messages
- Test changes in development first

### Caddy Reverse Proxy

**Location**: `~/docker/config/caddy/` (on x000)

**Configuration**:
- `compose.yml`: Docker service
- `Caddyfile`: Routing configuration
- `config/`: Caddy state
- `data/`: Let's Encrypt certificates

**Endpoints**:

1. **`semaphore.local.wywiol.eu`** (Local network only)
   ```
   @local {
       remote_ip 192.168.0.0/24
   }
   handle @local {
       reverse_proxy localhost:3001
   }
   respond "Access denied" 403
   ```

2. **`webhook.wywiol.eu`** (GitHub IPs only)
   ```
   @github {
       remote_ip 140.82.112.0/20 185.199.108.0/22 192.30.252.0/22
   }
   handle @github {
       reverse_proxy localhost:8097
   }
   respond "Access denied" 403
   ```

3. **`wywiol.eu`** (Public status page)
   ```
   respond "Control Node" 200
   ```

**Features**:
- Automatic HTTPS via Let's Encrypt
- HTTP/3 support
- IP-based access control
- Zero-downtime certificate renewal
- Automatic HTTP → HTTPS redirect

**Management**:
```bash
# View logs
docker compose logs -f caddy

# Reload config
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Validate config
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# Force certificate renewal
docker compose exec caddy caddy reload --force
```

### Semaphore UI

**Location**: `~/docker/config/semaphore/` (on x000)

**Configuration**:
- `compose.yml`: Docker service
- `.env`: Environment variables
- `~/.semaphore/config/`: BoltDB database

**Features**:
- Web UI for Ansible
- Task scheduling
- Audit log
- Multi-user support
- API access
- Template management

**Database**:
- BoltDB (embedded)
- Location: `~/.semaphore/config/database.boltdb`
- Backup: Included in control node backups

**API Usage**:
```bash
# Get projects
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/api/projects

# Create task
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"template_id": 1}' \
  http://localhost:3001/api/project/1/tasks

# Get task status
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/api/project/1/tasks/123
```

**Management**:
```bash
# View logs
make semaphore logs

# Restart
make semaphore restart

# Backup database
cp ~/.semaphore/config/database.boltdb /opt/backups/

# Reset admin password
docker compose -f docker/config/semaphore/compose.yml exec semaphore semaphore user change-by-login \
  --admin --login admin --password NEW_PASSWORD
```

## Operations

### Deployment Workflow

**Automated (via GitHub webhook)**:
1. Developer pushes to main branch
2. GitHub sends webhook to `webhook.wywiol.eu`
3. Caddy validates GitHub IP
4. Webhook handler verifies HMAC signature
5. Handler checks repository + branch
6. Handler parses changed files
7. Handler calls appropriate Semaphore template
8. Semaphore executes Ansible playbook
9. Ansible deploys service via Docker Compose
10. Handler sends ntfy notification

**Manual (via Semaphore UI)**:
1. Access `http://semaphore.local.wywiol.eu`
2. Select project → template
3. Click "Run"
4. Monitor task progress
5. View logs in real-time

**Manual (via CLI)**:
```bash
# SSH to x000
ssh code@192.168.0.2

# Run playbook directly
cd ~/ansible
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202" \
  -e "service_name=caddy"
```

### Rollback Procedure

**Automatic rollback**:
- Triggered on health check failure
- Reverts to previous Docker Compose state
- Sends notification

**Manual rollback via Semaphore**:
1. Access Semaphore UI
2. Select `rollback-service` template
3. Specify target host and service
4. Click "Run"

**Manual rollback via CLI**:
```bash
# SSH to x000
ssh code@192.168.0.2
cd ~/ansible

# Rollback specific service
ansible-playbook playbooks/rollback-service.yml \
  -e "target_host=x202" \
  -e "service_name=caddy"
```

**Manual rollback via Git**:
```bash
# Find last working commit
git log --oneline pve/x202/docker/config/caddy/

# Revert to specific commit
git revert <commit-hash>
git push origin main

# Automated deployment will trigger
```

### Service Updates

**Update control node services**:
```bash
# Ansible
ansible-galaxy collection install community.docker --upgrade

# OpenTofu
curl --proto '=https' --tlsv1.2 -fsSL \
  https://get.opentofu.org/install-opentofu.sh | sudo bash

# Semaphore
make semaphore pull && make semaphore up

# Caddy
make caddy pull && make caddy up

# Webhook
make webhook pull && make webhook up
```

**Update managed services** (automatic via git push):
1. Edit service compose file locally
2. Commit + push to main
3. GitHub webhook triggers deployment

### Monitoring

**Service Status**:
```bash
# Control node services
docker ps
docker compose ps  # per service

# Managed services (via Ansible)
ansible all -m shell -a "docker ps"
```

**Logs**:
```bash
# Webhook logs
make webhook logs

# Semaphore logs
make semaphore logs

# Caddy logs
make caddy logs

# Service logs on x202
ssh code@192.168.0.202
docker compose -f docker/config/caddy/compose.yml logs -f
```

**Notifications**:
- All deployments send ntfy.sh notifications
- Subscribe: https://ntfy.sh/homelab-webhooks
- Mobile app available (iOS/Android)

**Health Checks**:
```bash
# Webhook health
curl https://webhook.wywiol.eu/hooks/health

# Semaphore health
curl http://semaphore.local.wywiol.eu/api/ping

# Caddy health
curl https://wywiol.eu
```

### Backup & Restore

**Control Node Backups** (automated via cron):

**What's backed up**:
- Ansible vault password (`~/.ansible/vault_password`)
- SSH keys (GPG encrypted)
- Semaphore database
- Caddy certificates
- OpenTofu state files
- terraform.tfvars (GPG encrypted)

**Backup location**: `/opt/backups/control-node/`

**Manual backup**:
```bash
make backup
# Or with custom destination:
./backup-control-node.sh /opt/backups/control-node
```

**Verify backups**:
```bash
make verify
# Or with custom path:
./verify-backups.sh /opt/backups/control-node
```

**Restore procedure**:
```bash
# Find latest backup
ls -lh /opt/backups/control-node/

# Restore Ansible vault
cp /opt/backups/control-node/YYYYMMDD-HHMMSS/vault_password \
   ~/.ansible/vault_password
chmod 600 ~/.ansible/vault_password

# Restore SSH keys (GPG encrypted)
gpg --decrypt /opt/backups/control-node/YYYYMMDD-HHMMSS/ssh-keys.tar.gz.gpg | \
  tar xzf - -C ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Restore Semaphore
tar xzf /opt/backups/control-node/YYYYMMDD-HHMMSS/semaphore-config.tar.gz \
  -C ~/.semaphore/
sudo chown -R 1001:1001 ~/.semaphore/config

# Restore Caddy
tar xzf /opt/backups/control-node/YYYYMMDD-HHMMSS/caddy-data.tar.gz \
  -C ~/docker/config/caddy/

# Restore OpenTofu state
cp /opt/backups/control-node/YYYYMMDD-HHMMSS/terraform.tfstate \
   ~/infra/tofu/
gpg --decrypt /opt/backups/control-node/YYYYMMDD-HHMMSS/terraform.tfvars.gpg \
  > ~/infra/tofu/terraform.tfvars
chmod 600 ~/infra/tofu/terraform.tfvars

# Restart services
make semaphore restart
make caddy restart
```

**VM/LXC Backups** (Proxmox Backup Server):

**Schedule**:
- VMs: Daily at 2 AM (keep 7 daily, 4 weekly, 6 monthly)
- LXC: Daily at 3 AM (keep 7 daily, 4 weekly)

**Restore VM**:
```bash
# On Proxmox host
pvesr restore <backup-id> <vmid>

# Or via UI
# Datacenter → Backup → Select backup → Restore
```

**Restore LXC**:
```bash
# On Proxmox host
pct restore <ctid> <backup-file>
```

## Security

### Multi-Layer Security

**Layer 1: Network (Caddy)**
- IP whitelisting for Semaphore (192.168.0.0/24)
- IP whitelisting for webhook (GitHub ranges)
- Let's Encrypt TLS certificates
- Automatic HTTPS enforcement

**Layer 2: Application (Webhook)**
- HMAC-SHA256 signature verification
- Repository filtering (`PawelWywiol/homelab` only)
- Branch filtering (`main` only)
- Path-based selective triggers

**Layer 3: SSH**
- Key-based authentication only
- Password authentication disabled
- Separate key for Ansible
- Keys distributed manually

**Layer 4: Secrets (Ansible Vault)**
- All secrets encrypted with AES256
- Vault password stored securely
- Automatic vault password on playbook run

**Layer 5: API Access**
- Semaphore API tokens with expiration
- Proxmox API tokens with minimal permissions
- GitHub tokens scoped to repo only

### Secret Management

**Ansible Vault Password**:
- Primary: `~/.ansible/vault_password` (control node)
- Backup: Password manager (1Password/Bitwarden)
- Tertiary: Physical secure location

**SSH Keys**:
- Control node: `~/.ssh/id_ed25519`
- Backup: GPG encrypted in control node backup
- Never commit to git

**API Tokens**:
- Semaphore: Generated via UI, stored in webhook `.env`
- Proxmox: Generated via UI, stored in `terraform.tfvars`
- GitHub: Generated via Settings, stored in Semaphore only

**GitHub Webhook Secret**:
- Generated during setup
- Stored in webhook `.env`
- Configured in GitHub repo settings

**Encryption Keys**:
- Semaphore: Auto-generated, stored in `.env`
- GPG: For backup encryption

### Access Control

**Semaphore UI**:
- Local network only (192.168.0.0/24)
- Username/password authentication
- API token for webhook integration

**Webhook Endpoint**:
- GitHub IP ranges only
- HMAC verification required
- No direct access from local network

**Proxmox API**:
- API token authentication
- Minimal required permissions
- IP-restricted access (optional)

**SSH Access**:
- Key-based only
- `code` user on all hosts
- sudo privileges where needed

### Security Best Practices

1. **Regular updates**:
   ```bash
   # Monthly updates on all hosts
   ansible all -m apt -a "update_cache=yes upgrade=dist" -b
   ```

2. **Audit logs**:
   - Semaphore task history
   - Webhook logs
   - Git commit history

3. **Least privilege**:
   - API tokens scoped minimally
   - Ansible user non-root
   - Docker non-root where possible

4. **Secrets rotation**:
   - Rotate vault password annually
   - Rotate API tokens quarterly
   - Rotate SSH keys as needed

5. **Backup verification**:
   - Daily automated verification
   - Test restores quarterly
   - Off-site backup copy

## Troubleshooting

### Webhook Issues

**Webhook not receiving events**:
```bash
# Check GitHub webhook delivery
# GitHub repo → Settings → Webhooks → Recent Deliveries

# Check Caddy logs
docker compose -f ~/docker/config/caddy/compose.yml logs -f

# Check webhook logs
docker compose -f ~/docker/config/webhook/compose.yml logs -f

# Test webhook manually
curl -X POST https://webhook.wywiol.eu/hooks/health
```

**HMAC verification failed**:
- Verify secret matches in GitHub and webhook `.env`
- Check webhook logs for signature details
- Regenerate secret if needed:
  ```bash
  openssl rand -hex 32
  # Update in GitHub + webhook .env
  ```

**Webhook triggers but Semaphore fails**:
```bash
# Check Semaphore API token
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/api/projects

# Check template IDs in webhook .env
# View logs
docker compose -f ~/docker/config/webhook/compose.yml logs -f
```

### Ansible Issues

**Connectivity problems**:
```bash
# Test with verbose output
ansible all -m ping -vvv

# Test specific host
ansible x202 -m ping -vvv

# Check SSH key
ssh -i ~/.ssh/id_ed25519 code@192.168.0.202

# Regenerate known_hosts
ssh-keygen -R 192.168.0.202
ssh code@192.168.0.202  # Accept new fingerprint
```

**Vault password errors**:
```bash
# Verify vault password file exists
cat ~/.ansible/vault_password

# Test vault access
ansible-vault view ansible/group_vars/all/vault.yml

# Re-encrypt if corrupted
ansible-vault decrypt ansible/group_vars/all/vault.yml
ansible-vault encrypt ansible/group_vars/all/vault.yml
```

**Playbook failures**:
```bash
# Run with verbose output
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202" \
  -vvv

# Dry run (check mode)
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202" \
  --check

# Step through playbook
ansible-playbook playbooks/deploy-service.yml \
  -e "target_host=x202" \
  --step
```

### OpenTofu Issues

**State drift**:
```bash
# Refresh state
tofu refresh

# Compare state to reality
tofu plan

# Force state sync (caution)
tofu apply -refresh-only
```

**Import failures**:
```bash
# Verify VM ID exists in Proxmox
pvesh get /cluster/resources --type vm

# Import with correct ID (format: node/vmid)
tofu import proxmox_virtual_environment_vm.x199 pve/199

# Check for existing state
tofu state list
tofu state show proxmox_virtual_environment_vm.x199
```

**Provider authentication errors**:
```bash
# Test Proxmox API access
curl -k -H "Authorization: PVEAPIToken=homelab@pve!tofu=TOKEN" \
  https://192.168.0.200:8006/api2/json/cluster/resources

# Verify token permissions in Proxmox UI
# Datacenter → Permissions → API Tokens

# Regenerate token if needed
```

### Semaphore Issues

**Cannot access UI**:
```bash
# Check if running
docker compose -f ~/docker/config/semaphoreui/compose.yml ps

# Check logs
docker compose -f ~/docker/config/semaphoreui/compose.yml logs -f

# Verify network access (from local machine)
curl http://192.168.0.2:3001/api/ping

# Restart service
docker compose -f ~/docker/config/semaphoreui/compose.yml restart
```

**Database errors**:
```bash
# Check database file
ls -lh ~/.semaphore/config/database.boltdb

# Check permissions
sudo chown -R 1001:1001 ~/.semaphore/config
sudo chmod -R 755 ~/.semaphore/config

# Restore from backup if corrupted
cp /opt/backups/control-node/latest/semaphore-config.tar.gz .
tar xzf semaphore-config.tar.gz -C ~/.semaphore/
```

**Task execution failures**:
- Check Ansible connectivity from Semaphore container
- Verify SSH key mounted correctly
- Check repository path `/repo` exists
- Review task logs in UI

### Caddy Issues

**Certificate problems**:
```bash
# Check certificate status
docker compose -f ~/docker/config/caddy/compose.yml \
  exec caddy caddy list-certificates

# Force renewal
docker compose -f ~/docker/config/caddy/compose.yml \
  exec caddy caddy reload --force

# Check DNS resolution
dig +short wywiol.eu
dig +short webhook.wywiol.eu
dig +short semaphore.local.wywiol.eu
```

**Access denied errors**:
```bash
# Verify IP ranges in Caddyfile
docker compose -f ~/docker/config/caddy/compose.yml \
  exec caddy caddy validate --config /etc/caddy/Caddyfile

# Check client IP
curl https://ifconfig.me

# Test from correct network
# For Semaphore: must be from 192.168.0.0/24
# For webhook: must be from GitHub IPs
```

### Common Error Messages

**"Host key verification failed"**:
```bash
# Clear known_hosts entry
ssh-keygen -R 192.168.0.202
# Reconnect and accept new fingerprint
ssh code@192.168.0.202
```

**"Permission denied (publickey)"**:
```bash
# Verify SSH key exists
ls -l ~/.ssh/id_ed25519

# Check key permissions
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Verify key distributed
ssh-copy-id -i ~/.ssh/id_ed25519.pub code@192.168.0.202
```

**"Vault password file not found"**:
```bash
# Restore from backup
cp /opt/backups/control-node/latest/vault_password \
   ~/.ansible/vault_password
chmod 600 ~/.ansible/vault_password
```

**"Error: Invalid API token"**:
```bash
# Regenerate Proxmox API token
# Update terraform.tfvars
# Re-run tofu init
```

## Maintenance

### Daily Operations

```bash
# Check service status
ansible all -m ping
docker ps

# View recent deployments
# Semaphore UI → Tasks

# Check webhook activity
make webhook logs

# Verify backups
make verify
```

### Weekly Tasks

```bash
# Update Ansible collections
ansible-galaxy collection install community.docker --upgrade

# Review Semaphore task history
# Check for failed deployments

# Verify disk space
df -h

# Check backup sizes
du -sh /opt/backups/control-node/*
```

### Monthly Tasks

```bash
# Update all VMs
ansible all -m apt -a "update_cache=yes upgrade=dist" -b

# Update Docker images
make semaphore pull && make semaphore up
make caddy pull && make caddy up
make webhook pull && make webhook up

# Review security logs
# Check for failed SSH attempts
# Review webhook denied requests

# Test backup restore
# Verify quarterly
```

### Quarterly Tasks

```bash
# Rotate API tokens
# Semaphore: Generate new token, update webhook
# Proxmox: Generate new token, update terraform.tfvars

# Test disaster recovery
# Restore control node from backup
# Verify all services functional

# Review and update documentation
# Update this file with any changes
```

### Annual Tasks

```bash
# Rotate Ansible vault password
ansible-vault rekey ansible/group_vars/all/vault.yml

# Rotate SSH keys
ssh-keygen -t ed25519 -C "ansible@x000" -f ~/.ssh/id_ed25519_new
# Distribute new key
# Update Ansible configuration
# Remove old key

# Review infrastructure architecture
# Identify optimization opportunities
# Plan upgrades
```

## Reference

### Service URLs

| Service | URL | Access | Port |
|---------|-----|--------|------|
| Semaphore UI | http://semaphore.local.wywiol.eu | Local network | 3001 |
| Webhook (x202) | https://webhook.wywiol.eu/hooks/deploy-x202-services | GitHub IPs | 8097 |
| Webhook (x201) | https://webhook.wywiol.eu/hooks/deploy-x201-services | GitHub IPs | 8097 |
| Webhook (Tofu) | https://webhook.wywiol.eu/hooks/update-infrastructure | GitHub IPs | 8097 |
| Webhook (Ansible) | https://webhook.wywiol.eu/hooks/check-ansible | GitHub IPs | 8097 |
| Webhook Health | https://webhook.wywiol.eu/hooks/health | Public | 8097 |
| Status Page | https://wywiol.eu | Public | 80/443 |

### File Locations

**In repository (pve/x000/):**

| Purpose | Location |
|---------|----------|
| Bootstrap script | `pve/x000/bootstrap.sh` |
| Backup script | `pve/x000/backup-control-node.sh` |
| Verify script | `pve/x000/verify-backups.sh` |
| Docker services | `pve/x000/docker/config/` |
| Webhook config | `pve/x000/docker/config/webhook/` |
| Caddy config | `pve/x000/docker/config/caddy/` |
| Semaphore config | `pve/x000/docker/config/semaphore/` |
| Ansible config | `pve/x000/ansible/ansible.cfg` |
| Ansible inventory | `pve/x000/ansible/inventory/hosts.yml` |
| Ansible playbooks | `pve/x000/ansible/playbooks/` |
| OpenTofu config | `pve/x000/infra/tofu/` |

**On x000 (after sync):**

| Purpose | Location |
|---------|----------|
| Bootstrap script | `~/bootstrap.sh` |
| Docker services | `~/docker/config/` |
| Ansible config | `~/ansible/` |
| OpenTofu config | `~/infra/tofu/` |
| Semaphore data | `~/.semaphore/` |
| Vault password | `~/.ansible/vault_password` |
| SSH keys | `~/.ssh/id_ed25519` |
| Backups | `/opt/backups/control-node/` |

### Key Commands

**Ansible**:
```bash
ansible all -m ping                          # Test connectivity
ansible-playbook playbooks/deploy-service.yml  # Run deployment
ansible-vault view group_vars/all/vault.yml  # View secrets
ansible-inventory --list                     # List inventory
```

**OpenTofu**:
```bash
tofu init                                    # Initialize
tofu plan                                    # Preview changes
tofu apply                                   # Apply changes
tofu import proxmox_virtual_environment_vm.x202 pve/202  # Import VM
tofu show                                    # Show state
```

**Docker Compose**:
```bash
docker compose up -d                         # Start services
docker compose down                          # Stop services
docker compose restart                       # Restart services
docker compose logs -f                       # View logs
docker compose pull                          # Update images
```

**Git**:
```bash
git status                                   # Check status
git add .                                    # Stage changes
git commit -m "message"                      # Commit
git push origin main                         # Push (triggers deployment)
git revert <commit>                          # Revert changes
```

### GitHub IP Ranges

For webhook IP whitelisting:
- `140.82.112.0/20`
- `185.199.108.0/22`
- `192.30.252.0/22`

Updated list: https://api.github.com/meta

### Notification Topics

**ntfy.sh topics**:
- `homelab-webhooks`: All deployment events
- `homelab-alerts`: Critical alerts
- `homelab-backups`: Backup status

Subscribe: https://ntfy.sh/homelab-webhooks

### Useful Resources

- [Ansible Docker Module](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html)
- [OpenTofu Proxmox Provider](https://github.com/bpg/terraform-provider-proxmox)
- [Semaphore Documentation](https://docs.semaphoreui.com/)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [adnanh/webhook](https://github.com/adnanh/webhook)
- [ntfy Documentation](https://docs.ntfy.sh/)

---

**Last Updated**: 2025-11-26
**Version**: 1.0
**Status**: Production-ready
