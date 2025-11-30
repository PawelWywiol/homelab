# x100: Development VM
resource "proxmox_virtual_environment_vm" "x100" {
  name        = "x100"
  description = "Development and testing VM"
  node_name   = var.proxmox_node
  vm_id       = 100

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

  disk {
    datastore_id = var.storage_pool
    file_id      = "local:iso/debian-12-generic-amd64.img"
    interface    = "scsi0"
    size         = 64
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.100/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.vm_username
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["managed", "dev", "docker"]
}

# x199: Control Node
resource "proxmox_virtual_environment_vm" "x199" {
  name        = "x199"
  description = "Ansible + OpenTofu control node"
  node_name   = var.proxmox_node
  vm_id       = 199

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

  disk {
    datastore_id = var.storage_pool
    file_id      = "local:iso/debian-12-generic-amd64.img"
    interface    = "scsi0"
    size         = 64
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.199/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.vm_username
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["managed", "control", "ansible", "tofu"]
}

# x201: DNS Services
resource "proxmox_virtual_environment_vm" "x201" {
  name        = "x201"
  description = "DNS and network services"
  node_name   = var.proxmox_node
  vm_id       = 201

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

  disk {
    datastore_id = var.storage_pool
    file_id      = "local:iso/debian-12-generic-amd64.img"
    interface    = "scsi0"
    size         = 64
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.201/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.vm_username
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["managed", "dns", "docker"]
}

# x202: Web Services
resource "proxmox_virtual_environment_vm" "x202" {
  name        = "x202"
  description = "Web applications and services"
  node_name   = var.proxmox_node
  vm_id       = 202

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 12288
  }

  disk {
    datastore_id = var.storage_pool
    file_id      = "local:iso/debian-12-generic-amd64.img"
    interface    = "scsi0"
    size         = 128
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.202/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = var.vm_username
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  tags = ["managed", "web", "docker"]
}
