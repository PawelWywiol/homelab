terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50.0"
    }
  }

  # Optional: PostgreSQL backend for state management
  # Uncomment and configure when ready
  # backend "pg" {
  #   conn_str = "postgres://user:pass@localhost/terraform_backend"
  # }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent    = true
    username = "root"
  }
}
