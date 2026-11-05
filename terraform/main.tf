# This is a basic Terraform configuration to clone a VM from a template using the bpg/proxmox provider.
# Fill in the variables below with your specific Proxmox environment details.
# This block tells Terraform to use the bpg/proxmox provider.
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = ">=0.80.0" 
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.18.63:8006/"
  api_token = var.token
  insecure = true
  ssh {
    agent    = false 
    username = "root"    
    private_key = file("C:\\Users\\olomg\\.ssh\\id_ed25519") 
  }
}


module "k3s_nodes" {
  source = "./modules/proxmox_vm"

  for_each = {
    "master-01" = { cpu = 2, memory = 4096}
    "worker-01" = { cpu = 2, memory = 4096}
    "worker-02" = { cpu = 2, memory = 4096}
  }

  hostname   = each.key
  cores      = each.value.cpu
  memory     = each.value.memory
  
}
