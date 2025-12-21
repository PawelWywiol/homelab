# OpenTofu Outputs - x202 VM info
# Extensible: add outputs for new VMs following x202 pattern

output "vm_ids" {
  description = "Map of VM names to their IDs"
  value = {
    x202 = proxmox_virtual_environment_vm.x202.vm_id
  }
}

output "vm_ips" {
  description = "Map of VM names to their IP addresses"
  value = {
    x202 = "192.168.0.202"
  }
}

output "vm_names" {
  description = "List of all managed VM names"
  value       = ["x202"]
}
