variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g., https://192.168.0.200:8006)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.proxmox_endpoint))
    error_message = "Proxmox endpoint must start with https://"
  }
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@pve!tokenid=secret)"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^.+@.+!.+=.+$", var.proxmox_api_token))
    error_message = "API token must be in format: user@pve!tokenid=secret"
  }
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (from control node)"
  type        = string

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-)", var.ssh_public_key))
    error_message = "Must be a valid SSH public key"
  }
}

variable "vm_username" {
  description = "Default username for VMs"
  type        = string
  default     = "code"
}

variable "vm_password" {
  description = "Default password for VMs (only used for initial setup)"
  type        = string
  sensitive   = true
  default     = null
}

variable "network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default gateway for VMs"
  type        = string
  default     = "192.168.0.1"
}

variable "dns_servers" {
  description = "DNS servers for VMs"
  type        = list(string)
  default     = ["192.168.0.201", "1.1.1.1"]
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "local"
}

variable "storage_pool" {
  description = "Storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "iso_storage" {
  description = "Storage for ISO images"
  type        = string
  default     = "local"
}
