# Infrastructure as Code

OpenTofu configuration for Proxmox VM management.

## Overview

Manages Proxmox VMs declaratively using OpenTofu (Terraform fork). All VM definitions, resources, and infrastructure state tracked in version control.

## Structure

```
infra/
└── tofu/
    ├── provider.tf              # Proxmox provider configuration
    ├── variables.tf             # Input variable definitions
    ├── terraform.tfvars.example # Variable values template
    ├── vms.tf                   # VM resource definitions
    ├── outputs.tf               # Output values
    └── .gitignore              # Excludes state files and secrets
```

## VMs Managed

| VM | ID | IP | vCPUs | RAM | Disk | Purpose |
|----|----|----|-------|-----|------|---------|
| x100 | 100 | 192.168.0.100 | 2 | 12GB | 64GB | Development/test |
| x199 | 199 | 192.168.0.199 | 2 | 4GB | 64GB | Legacy VM |
| x201 | 201 | 192.168.0.201 | 2 | 2GB | 64GB | DNS services |
| x202 | 202 | 192.168.0.202 | 4 | 12GB | 128GB | Web/application services |

**Note:** Control node (x000), not managed by OpenTofu.

## Prerequisites

**Proxmox API Token:**
1. Proxmox UI → Datacenter → Permissions → API Tokens
2. Create token: `homelab@pve!tofu`
3. Copy token ID and secret
4. Set permissions: PVEVMAdmin + PVEDatastoreUser

**OpenTofu installed:**
```bash
# Installed by bootstrap.sh on x000 (control node)
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
ssh_public_key     = "ssh-ed25519 AAAA... ansible@x199"
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

### 3. Import Existing VMs

If VMs already exist in Proxmox:

```bash
# Import each VM by ID
tofu import proxmox_virtual_environment_vm.x100 100
tofu import proxmox_virtual_environment_vm.x199 199
tofu import proxmox_virtual_environment_vm.x201 201
tofu import proxmox_virtual_environment_vm.x202 202

# Verify state
tofu show
```

### 4. Plan Changes

```bash
# Preview changes
tofu plan

# Review output carefully
# Should show "No changes" if VMs match configuration
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

**Destroy infrastructure (⚠️ DANGEROUS):**
```bash
tofu destroy  # Only use for testing!
```

## VM Configuration

VMs are defined in `vms.tf`. Example configuration:

```hcl
resource "proxmox_virtual_environment_vm" "x202" {
  name        = "x202"
  description = "Web and application services"
  node_name   = var.proxmox_node
  vm_id       = 202

  cpu {
    cores = 4
  }

  memory {
    dedicated = 12288  # 12GB
  }

  disk {
    datastore_id = "local-lvm"
    size         = 128
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"  # Linux 2.6+ kernel
  }

  # Cloud-init configuration
  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.202/24"
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

## Webhook Integration

Infrastructure changes trigger automatically via GitHub webhook:

**Workflow:**
1. Push changes to `infra/tofu/*` on main branch
2. GitHub webhook → `webhook.wywiol.eu/hooks/update-infrastructure`
3. Webhook handler runs `trigger-tofu.sh`
4. OpenTofu plan executed
5. Notification sent via ntfy.sh
6. Manual approval required (unless `TOFU_AUTO_APPLY=true`)

**Configuration:** `pve/x000/docker/config/webhook/.env`

**Auto-apply:** Disabled by default for safety

See: `pve/x000/docker/config/webhook/README.md`

## State Management

**State storage:** Local file (`terraform.tfstate`)

**⚠️ IMPORTANT:**
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

**Remote backend (optional):**

For production, consider PostgreSQL backend:

```hcl
# backend.tf
terraform {
  backend "pg" {
    conn_str = "postgres://user:pass@localhost/terraform_state"
  }
}
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
# ⚠️ Only use if you're certain no other process is running
tofu force-unlock <LOCK_ID>
```

### VM Import Failed

```bash
# Check VM exists in Proxmox
pvesh get /cluster/resources --type vm

# Verify VM ID matches
tofu import proxmox_virtual_environment_vm.x202 202
```

### Configuration Drift

If Proxmox VMs modified outside OpenTofu:

```bash
# Detect drift
tofu plan
# Shows differences between desired and actual state

# Option 1: Update OpenTofu to match current state
tofu refresh
# Then update .tf files to match

# Option 2: Force VMs to match OpenTofu config
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
5. **Test in x100 first** - Use dev VM before production changes
6. **Use variables** - Never hardcode values in .tf files
7. **Document changes** - Git commit messages should explain why
8. **Import existing resources** - Don't recreate running VMs
9. **Protect state file** - Contains sensitive data
10. **Review provider docs** - OpenTofu Proxmox provider changes

## Migration from Terraform

OpenTofu is a Terraform fork with identical syntax:

```bash
# Replace 'terraform' commands with 'tofu'
terraform init  →  tofu init
terraform plan  →  tofu plan
terraform apply →  tofu apply

# State files are compatible
# No migration needed for existing .tf files
```

## Advanced Configuration

### Cloud-Init Templates

Use cloud-init for VM initialization:

```hcl
initialization {
  datastore_id = "local-lvm"

  ip_config {
    ipv4 {
      address = "192.168.0.202/24"
      gateway = "192.168.0.1"
    }
  }

  user_account {
    username = "code"
    keys     = [var.ssh_public_key]
    password = var.default_password  # Optional
  }

  user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
}
```

### VM Templates

Create base templates for faster provisioning:

```hcl
resource "proxmox_virtual_environment_vm" "template" {
  name      = "debian-12-template"
  template  = true

  # ... configuration ...
}

# Clone from template
resource "proxmox_virtual_environment_vm" "new_vm" {
  clone {
    vm_id = proxmox_virtual_environment_vm.template.vm_id
  }
}
```

### Modules

Organize repeated configurations:

```hcl
# modules/debian-vm/main.tf
variable "vm_name" {}
variable "vm_id" {}
variable "ip_address" {}

resource "proxmox_virtual_environment_vm" "vm" {
  name = var.vm_name
  # ... shared configuration ...
}

# Usage in vms.tf
module "x202" {
  source     = "./modules/debian-vm"
  vm_name    = "x202"
  vm_id      = 202
  ip_address = "192.168.0.202"
}
```

## Security

**Secrets protection:**
- ✅ `terraform.tfvars` in .gitignore
- ✅ `terraform.tfstate` in .gitignore
- ✅ API token stored in Ansible Vault
- ✅ Minimal Proxmox permissions (PVEVMAdmin only)

**Access control:**
- Only x000 control node has API access
- Token-based auth (no passwords)
- Audit trail via git commits
- Webhook HMAC verification for remote triggers

## References

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [OpenTofu Proxmox Provider](https://github.com/bpg/terraform-provider-proxmox)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
