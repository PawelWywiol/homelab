# Ansible Configuration

Ansible automation for homelab infrastructure management.

**Working directory:** Run all Ansible commands from this `ansible/` directory.

## Overview

Manages deployment and configuration of Docker Compose services on the control
node and the managed VMs.

## Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # x000, x202, x203 host definitions
├── group_vars/
│   └── all/
│       ├── vars.yml            # Common variables
│       └── vault.yml.example   # Vault template (unused)
├── playbooks/
│   ├── deploy-service.yml  # Deploy Docker Compose services
│   ├── stop-service.yml    # Stop & remove containers
│   ├── rollback-service.yml # Rollback to previous version
│   └── _deploy_single.yml  # Helper task
└── roles/
    └── docker_compose/
        └── tasks/
            └── main.yml    # Docker Compose deployment tasks
```

## Inventory

**Managed hosts:**
- x000 (localhost, `ansible_connection: local`) - Control node
- x201 (192.168.0.201) - Web apps
- x202 (192.168.0.202) - Web/app services
- x203 (192.168.0.203) - File sharing

Groups: `control` (x000), `vms` (x201, x202, x203), `docker_hosts` (both).

## Secrets Management

**Current approach:** Services use `.env` files for secrets (gitignored).

**Ansible Vault:** Available but currently unused. Infrastructure configured if needed:
- `ansible.cfg` references `~/.ansible/vault_password`
- `vault.yml.example` template available

## Common Commands

**Test connectivity:**
```bash
ansible all -m ping
```

**Deploy service:**
```bash
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202 service=grafana"
```

**Rollback service:**
```bash
ansible-playbook playbooks/rollback-service.yml -e "target_host=x202 service=grafana"
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
- `target_host` - Target host/group (x000, x201, x202, x203, or a group)
- `service` - Service name (optional, deploys all if not specified)

**Example:**
```bash
# Deploy all x202 services
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202"

# Deploy specific service
ansible-playbook playbooks/deploy-service.yml -e "target_host=x202 service=grafana"
```

### rollback-service.yml

Rolls back service to previous version.

**Required variables:**
- `target_host` - Target host/group
- `service` - Service name

**Example:**
```bash
ansible-playbook playbooks/rollback-service.yml -e "target_host=x202 service=grafana"
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
- `pve/x000/docker/config/*` → Deploy x000 services
- `pve/x201/docker/config/*` → Deploy x201 services
- `pve/x202/docker/config/*` → Deploy x202 services
- `pve/x203/docker/config/*` → Deploy x203 services

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
2. **Tag playbooks** - Use tags for selective execution
3. **Idempotent tasks** - Playbooks should be safe to run multiple times
4. **Version control** - Commit all playbook/role changes

## Troubleshooting

**Connection refused:**
```bash
# Test SSH manually
ssh -i ~/.ssh/ansible_ed25519 code@192.168.0.202

# Check SSH key permissions
ls -l ~/.ssh/ansible_ed25519
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
ansible x202 -a "docker compose config" -e "service=grafana"
```

## References

- [Ansible Documentation](https://docs.ansible.com/)
- [Docker Compose Module](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html)
