terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.80.0"
    }
  }
}
resource "proxmox_virtual_environment_vm" "vm_template" {
  node_name = "proxmox-host" 
  name = var.hostname
  clone {
    vm_id = 100
    full  = true
  }
  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }
  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ansible"
      keys     = [
        trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEydF5Lf1Y5ejHPQ0eCGV7yJX84SiaDrc5YVt0+4mgzp ansible-controller") 
      ]
    }
    
  }
}
