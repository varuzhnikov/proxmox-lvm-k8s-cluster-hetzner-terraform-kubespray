terraform {

    backend "remote" {
        hostname     = "app.terraform.io"
        organization = "kube-lab"

        workspaces {
            name = "proxmox-stage"
        }
    }

    
    required_providers {
        proxmox = {
            source = "bpg/proxmox"
            version = "0.83.1"
        }
    }
}

provider "proxmox" {
    endpoint = var.pm_api_url
    api_token = var.pm_api_token
    insecure = var.pm_tls_insecure

    ssh {
    	agent       = false
    	private_key = file(var.pm_ssh_private_key_path)
  		username    = var.pm_ssh_username
    }
}

# Upload the cloud-init snippet file to the Proxmox datastore
resource "proxmox_virtual_environment_file" "cloud_init_snippet" {
  content_type = "snippets"
  datastore_id = var.pm_snippets_datastore_id
  node_name    = var.pm_node_name
  source_raw {
  	data = <<EOF
#cloud-config
hostname: test-ubuntu
timezone: UTC
chpasswd:
  expire: false

users:
  - name: ${var.ci_username}
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: ${var.ci_password}
    ssh_authorized_keys:
      - ${trimspace(var.ci_ssh_public_key)}

# Workaround for bpg Terraform proxmox provider. 
# We use ssh auth by login and password for cloud-init by default for tty access from proxmox web console
# and then disable password auth and provide ssh pub key in cloud-init-snippet 
write_files:
  - path: /etc/ssh/sshd_config.d/10-no-password.conf
    permissions: '0644'
    content: |
      # Disable password authentication for all SSH connections
      PasswordAuthentication no

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - net-tools
  - curl
runcmd:
  - systemctl restart sshd
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - reboot now

    EOF

    file_name = "cloud_init_snippet.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name        = "ubuntu-test"
  node_name   = var.pm_node_name

  clone {
    vm_id        = 9000
    full         = true
    datastore_id = var.pm_lvm_datastore_id
  }

  bios    = "ovmf"
  machine = "q35"

  description     = "Managed by Terraform"
  started         = true
  stop_on_destroy = true

  cpu {
    cores = 4
    type  = "host"
  }
  memory {
    dedicated = 4096
  }
  agent {
    enabled = true
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = 20
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
  	user_data_file_id = proxmox_virtual_environment_file.cloud_init_snippet.id

    ip_config {
      ipv4 {
        address = "172.16.16.2/24"
        gateway = "172.16.16.1"
      }
    }

    user_account {
      # Workaround for bpg Terraform proxmox provider. 
      # We use ssh auth by login and password for cloud-init by default for tty access from proxmox web console
      # and then disable password auth and provide ssh pub key in cloud-init-snippet 
      username = var.ci_username
      password = var.ci_password
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
  }
}

