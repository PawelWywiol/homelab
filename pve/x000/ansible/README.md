# Ansible Configuration

Ansible automation for homelab infrastructure management.

**Working directory:** Run all Ansible commands from this `ansible/` directory.

## Overview

Manages deployment and configuration of services to x202 (primary web/app VM).

## Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # x202 host definition
├── group_vars/
│   └── all/
│       ├── vars.yml            # Common variables
│       ├── vault.yml           # Encrypted secrets (committed)
│       └── vault.yml.example   # Template/documentation
├── playbooks/
│   ├── deploy-service.yml  # Deploy Docker Compose services
│   └── rollback-service.yml # Rollback to previous version
└── roles/
    └── docker_compose/
        └── tasks/
            └── main.yml    # Docker Compose deployment tasks
```

## Inventory

**Managed hosts:**
- x202 (192.168.0.202) - Web/app services

## Secrets Management

**Ansible Vault** encrypts sensitive data in `group_vars/all/vault.yml`:

- `vault.yml` - Encrypted secrets (committed to git, safe)
- `vault.yml.example` - Template/documentation (no secrets)

```bash
# Create vault from template (first time only)
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
nano group_vars/all/vault.yml  # Fill in real secrets
ansible-vault encrypt group_vars/all/vault.yml
git add group_vars/all/vault.yml && git commit -m "Add encrypted vault"

# View secrets
ansible-vault view group_vars/all/vault.yml

# Edit secrets (decrypts, opens editor, re-encrypts)
ansible-vault edit group_vars/all/vault.yml
```

**Vault password:** `~/.ansible/vault_password` (never committed)

**Secrets stored:**
- Proxmox API tokens
- GitHub webhook secret
- Database passwords
- Service API keys
- Backup encryption keys

See `group_vars/all/vault.yml.example` for template.

## Common Commands

**Test connectivity:**
```bash
ansible all -m ping
```

**Deploy service:**
```bash
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202 service=caddy"
```

**Rollback service:**
```bash
ansible-playbook playbooks/rollback-service.yml -e "target_host=x202 service=caddy"
```

**Check syntax:**
```bash
ansible-playbook --syntax-check playbooks/*.yml
```

**Dry run (check mode):**
```bash
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202" --check
```

## Playbooks

### deploy-service.yml

Deploys Docker Compose services to target hosts.

**Required variables:**
- `target_host` - Target host/group (x202)
- `service` - Service name (optional, deploys all if not specified)

**Example:**
```bash
# Deploy all x202 services
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202"

# Deploy specific service
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202 service=caddy"
```

### rollback-service.yml

Rolls back service to previous version.

**Required variables:**
- `target_host` - Target host/group
- `service` - Service name

**Example:**
```bash
ansible-playbook playbooks/rollback-service.yml -e "target_host=x202 service=caddy"
```

## Roles

### docker_compose

Manages Docker Compose service deployments.

**Tasks:**
- Pull latest compose configs from repository
- Validate compose.yml syntax
- Deploy/restart services
- Health checks
- Cleanup old images

## Integration with Webhook

Playbooks triggered via webhook handler → SSH → host scripts:

```
GitHub Push → webhook:8097 → SSH to localhost → scripts/deploy.sh → ansible-playbook
```

**Triggers:**
- `pve/x202/docker/config/*` → Deploy x202 services

See: `pve/x000/docker/config/webhook/README.md`

## Configuration

### ansible.cfg

```ini
[defaults]
inventory = inventory/hosts.yml
vault_password_file = ~/.ansible/vault_password
host_key_checking = False
remote_user = code
private_key_file = ~/.ssh/ansible_ed25519

[ssh_connection]
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r
```

### SSH Key Setup

**On x000 control node:**
```bash
# Generate SSH key (done by setup script)
ssh-keygen -t ed25519 -C "ansible@x000" -f ~/.ssh/ansible_ed25519

# Distribute to x202
ssh-copy-id -i ~/.ssh/ansible_ed25519.pub code@192.168.0.202
```

## Best Practices

1. **Always test with --check** before actual deployment
2. **Use vault for all secrets** - Never commit unencrypted credentials
3. **Backup vault password** - Store in multiple secure locations
4. **Tag playbooks** - Use tags for selective execution
5. **Idempotent tasks** - Playbooks should be safe to run multiple times
6. **Version control** - Commit all playbook/role changes

## Troubleshooting

**Connection refused:**
```bash
# Test SSH manually
ssh -i ~/.ssh/ansible_ed25519 code@192.168.0.202

# Check SSH key permissions
ls -l ~/.ssh/ansible_ed25519
# Should be: -rw------- (600)
```

**Vault password error:**
```bash
# Verify vault password file exists
cat ~/.ansible/vault_password

# Verify file permissions
ls -l ~/.ansible/vault_password
# Should be: -rw------- (600)
```

**Playbook syntax errors:**
```bash
# Validate YAML
ansible-playbook --syntax-check playbooks/deploy-service.yml

# Verbose output
ansible-playbook playbooks/deploy-service.yml -vvv
```

**Service deployment fails:**
```bash
# Check target host connectivity
ansible x202 -m ping

# Check Docker on target
ansible x202 -a "docker ps"

# Check compose file syntax on target
ansible x202 -a "docker compose config" -e "service=caddy"
```

## References

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Docker Compose Module](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html)
