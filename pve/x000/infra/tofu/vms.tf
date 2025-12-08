# =============================================================================
# EXISTING VMs - Imported into OpenTofu state
# These VMs already exist in Proxmox. Configuration matches actual state.
# =============================================================================

# x100: Development VM (SeaBIOS - NOT UEFI)
resource "proxmox_virtual_environment_vm" "x100" {
  name        = "x100"
  description = "Development and testing VM"
  node_name   = var.proxmox_node
  vm_id       = 100

  # SeaBIOS (default) - no UEFI
  # machine type: pc-i440fx

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 2
    type    = "host"
  }

  memory {
    dedicated = 12288
  }

  # Existing disk - no file_id (already provisioned)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 64
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["redro"]

  # Prevent destruction from cloud-init changes
  lifecycle {
    ignore_changes = [
      initialization,
      disk[0].file_id,
      cdrom,
    ]
  }
}

# x199: Control Node (Ansible + OpenTofu)
resource "proxmox_virtual_environment_vm" "x199" {
  name        = "x199"
  description = "Ansible + OpenTofu control node"
  node_name   = var.proxmox_node
  vm_id       = 199

  # Match existing UEFI configuration
  bios    = "ovmf"
  machine = "q35"

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  # Existing disk - no file_id (already provisioned)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 64
    discard      = "on"
    ssd          = true
  }

  efi_disk {
    datastore_id      = "local-lvm"
    pre_enrolled_keys = true
    type              = "4m"
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["control"]

  # Prevent destruction from cloud-init changes
  lifecycle {
    ignore_changes = [
      initialization,
      disk[0].file_id,
      cdrom,
    ]
  }
}

# x201: DNS Services
resource "proxmox_virtual_environment_vm" "x201" {
  name        = "x201"
  description = "DNS and network services"
  node_name   = var.proxmox_node
  vm_id       = 201

  # Match existing UEFI configuration
  bios    = "ovmf"
  machine = "q35"

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  # Existing disk on local-zfs
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = 64
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

  tags = ["dns"]

  # Prevent destruction from cloud-init changes
  lifecycle {
    ignore_changes = [
      initialization,
      disk[0].file_id,
      cdrom,
    ]
  }
}

# x202: Web Services
resource "proxmox_virtual_environment_vm" "x202" {
  name        = "x202"
  description = "Web applications and services"
  node_name   = var.proxmox_node
  vm_id       = 202

  # Match existing UEFI configuration
  bios    = "ovmf"
  machine = "q35"

  agent {
    enabled = true
  }

  cpu {
    cores   = 2
    sockets = 2 # 4 vCPUs total (matches actual)
    type    = "host"
  }

  memory {
    dedicated = 12288
  }

  # Existing disk on local-zfs
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
