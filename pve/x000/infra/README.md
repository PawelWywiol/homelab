# Infrastructure as Code

OpenTofu configuration for Proxmox VM management.

## Overview

Manages Proxmox VMs declaratively using OpenTofu (Terraform fork). Currently managing x202 (primary web/app VM).

## Structure

```
infra/
└── tofu/
    ├── provider.tf              # Proxmox provider configuration
    ├── variables.tf             # Input variable definitions
    ├── terraform.tfvars.example # Variable values template
    ├── vms.tf                   # x202 VM definition
    ├── outputs.tf               # Output values
    └── .gitignore              # Excludes state files and secrets
```

## VMs Managed

| VM | ID | IP | vCPUs | RAM | Disk | Purpose |
|----|----|----|-------|-----|------|---------|
| x202 | 202 | 192.168.0.202 | 4 | 12GB | 128GB | Web/application services |

**Note:** Control node (x000) not managed by OpenTofu.

## Prerequisites

### Proxmox API Token Setup

**1. Create User (Datacenter → Permissions → Users → Add):**
- User name: `homelab`
- Realm: `pam` (Linux PAM)
- Group: `automation` (create if needed)

**2. Create Group (Datacenter → Permissions → Groups → Create):**
- Group ID: `automation`

**3. Create API Token (Datacenter → Permissions → API Tokens → Add):**
- User: `homelab@pam`
- Token ID: `tofu`
- Privilege Separation: ✓ (checked)
- **Save the secret** - shown only once!

**4. Assign Permissions (Datacenter → Permissions → Add → API Token Permission):**
- Path: `/`
- API Token: `homelab@pam!tofu`
- Role: `Administrator`
- Propagate: ✓ (checked)

**Result:** Token format: `homelab@pam!tofu=YOUR_SECRET`

**Verify token works:**
```bash
curl -sk -H 'Authorization: PVEAPIToken=homelab@pam!tofu=YOUR_SECRET' \
  'https://192.168.0.200:8006/api2/json/nodes/pve/qemu' | jq '.data[] | {vmid, name}'
```

### OpenTofu

```bash
# Installed by setup.sh on x000 (control node)
tofu --version
```

## Setup

### 1. Configure Variables

```bash
cd infra/tofu

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Required variables:**
```hcl
proxmox_endpoint   = "https://192.168.0.200:8006"
proxmox_api_token  = "homelab@pve!tofu=YOUR_TOKEN_SECRET_HERE"
proxmox_insecure   = true  # For self-signed certs
ssh_public_key     = "ssh-ed25519 AAAA... ansible@x000"
proxmox_node       = "pve"
```

### 2. Initialize OpenTofu

```bash
cd infra/tofu

# Initialize providers and modules
tofu init

# Validate configuration
tofu validate
```

### 3. Import Existing VM

If x202 already exists in Proxmox:

```bash
# Import by VM ID
tofu import proxmox_virtual_environment_vm.x202 pve/202

# Verify state
tofu show
```

### 4. Plan Changes

```bash
# Preview changes
tofu plan

# Review output carefully
# Should show "No changes" if VM matches configuration
```

### 5. Apply Changes

```bash
# Apply configuration
tofu apply

# Confirm with 'yes'
```

## Common Commands

**Check current state:**
```bash
tofu show
```

**Preview changes:**
```bash
tofu plan
```

**Apply changes:**
```bash
tofu apply
```

**Refresh state:**
```bash
tofu refresh
```

**View outputs:**
```bash
tofu output
```

**Destroy infrastructure (DANGEROUS):**
```bash
tofu destroy  # Only use for testing!
```

## VM Configuration

VMs are defined in `vms.tf`. Current configuration:

```hcl
resource "proxmox_virtual_environment_vm" "x202" {
  name        = "x202"
  description = "Web and application services"
  node_name   = var.proxmox_node
  vm_id       = 202

  cpu {
    cores   = 2
    sockets = 2  # 4 vCPUs total
  }

  memory {
    dedicated = 12288  # 12GB
  }

  disk {
    datastore_id = "local-zfs"
    size         = 128
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"  # Linux 2.6+ kernel
  }
}
```

## Webhook Integration

Infrastructure changes trigger automatically via GitHub webhook:

**Workflow:**
1. Push changes to `pve/x000/infra/tofu/*` on main branch
2. GitHub webhook → `webhook.wywiol.eu/hooks/homelab`
3. `trigger-homelab.sh` detects tofu changes
4. OpenTofu plan executed
5. Notification sent via ntfy.sh
6. Manual approval required (unless `TOFU_AUTO_APPLY=true`)

**Auto-apply:** Disabled by default for safety

## State Management

**State storage:** Local file (`terraform.tfstate`)

**IMPORTANT:**
- State file contains sensitive data (API tokens, IPs)
- Never commit state files to git (.gitignore protects)
- Backup state file regularly
- Consider remote backend for team collaboration

**Backup state:**
```bash
# Automated (included in backup-control-node.sh)
/home/code/scripts/backup-control-node.sh

# Manual
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
```

## Troubleshooting

### API Token Invalid

```bash
# Test Proxmox API manually
curl -k -H "Authorization: PVEAPIToken=homelab@pve!tofu=YOUR_TOKEN" \
  https://192.168.0.200:8006/api2/json/version

# Should return JSON with version info
```

**Fix:** Regenerate token in Proxmox UI and update `terraform.tfvars`

### State Lock Error

```bash
# If state is locked (e.g., interrupted apply)
# Only use if you're certain no other process is running
tofu force-unlock <LOCK_ID>
```

### VM Import Failed

```bash
# Check VM exists in Proxmox
pvesh get /cluster/resources --type vm

# Verify VM ID matches
tofu import proxmox_virtual_environment_vm.x202 pve/202
```

### Configuration Drift

If Proxmox VM modified outside OpenTofu:

```bash
# Detect drift
tofu plan
# Shows differences between desired and actual state

# Option 1: Update OpenTofu to match current state
tofu refresh
# Then update .tf files to match

# Option 2: Force VM to match OpenTofu config
tofu apply
# Reverts manual changes
```

### Provider Version Issues

```bash
# Clear provider cache
rm -rf .terraform/

# Reinitialize
tofu init
```

## Best Practices

1. **Always run plan before apply** - Review changes carefully
2. **Never auto-apply in production** - Manual approval for safety
3. **Version control everything** - Except state files and secrets
4. **Backup state regularly** - Critical for disaster recovery
5. **Use variables** - Never hardcode values in .tf files
6. **Document changes** - Git commit messages should explain why
7. **Import existing resources** - Don't recreate running VMs
8. **Protect state file** - Contains sensitive data

## Security

**Secrets protection:**
- `terraform.tfvars` in .gitignore
- `terraform.tfstate` in .gitignore
- API token stored in Ansible Vault
- Minimal Proxmox permissions (PVEVMAdmin only)

**Access control:**
- Only x000 control node has API access
- Token-based auth (no passwords)
- Audit trail via git commits
- Webhook HMAC verification for remote triggers

## References

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [OpenTofu Proxmox Provider](https://github.com/bpg/terraform-provider-proxmox)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
