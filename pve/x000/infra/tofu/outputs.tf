output "vm_ids" {
  description = "Map of VM names to their IDs"
  value = {
    x100 = proxmox_virtual_environment_vm.x100.vm_id
    x199 = proxmox_virtual_environment_vm.x199.vm_id
    x201 = proxmox_virtual_environment_vm.x201.vm_id
    x202 = proxmox_virtual_environment_vm.x202.vm_id
  }
}

output "vm_ips" {
  description = "Map of VM names to their IP addresses"
  value = {
    x100 = "192.168.0.100"
    x199 = "192.168.0.199"
    x201 = "192.168.0.201"
    x202 = "192.168.0.202"
  }
}

output "vm_names" {
  description = "List of all managed VM names"
  value       = ["x100", "x199", "x201", "x202"]
}

output "ansible_inventory_hint" {
  description = "Hint for generating Ansible inventory"
  value       = <<-EOT
    Add to ansible/inventory/hosts.yml:

    all:
      children:
        vms:
          hosts:
            x199:
              ansible_host: 192.168.0.199
            x201:
              ansible_host: 192.168.0.201
            x202:
              ansible_host: 192.168.0.202
  EOT
}
