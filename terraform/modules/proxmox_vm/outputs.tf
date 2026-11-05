output ip_address {
  value = proxmox_virtual_environment_vm.vm_template.ipv4_addresses[1]
}