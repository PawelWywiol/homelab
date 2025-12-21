# =============================================================================
# OpenTofu VM Management - x202 Web Services
# Currently managing: x202
# Extensible: add new VM resources following x202 pattern
# =============================================================================

# x202: Web Services (primary VM)
resource "proxmox_virtual_environment_vm" "x202" {
  name        = "x202"
  description = "Web applications and services"
  node_name   = var.proxmox_node
  vm_id       = 202

  # UEFI configuration
  bios    = "ovmf"
  machine = "q35"

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 2 # 4 vCPUs total
    type    = "host"
  }

  memory {
    dedicated = 12288
  }

  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = 128
    discard      = "on"
    ssd          = true
  }

  efi_disk {
    datastore_id      = "local-zfs"
    pre_enrolled_keys = true
    type              = "4m"
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["webdev"]

  # Prevent destruction from cloud-init changes
  lifecycle {
    ignore_changes = [
      initialization,
      disk[0].file_id,
      cdrom,
    ]
  }
}
