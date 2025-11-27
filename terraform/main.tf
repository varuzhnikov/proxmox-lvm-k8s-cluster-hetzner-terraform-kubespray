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
      source  = "bpg/proxmox"
      version = "0.83.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = var.pm_api_token
  insecure  = var.pm_tls_insecure

  ssh {
    agent       = false
    private_key = file(var.pm_ssh_private_key_path)
    username    = var.pm_ssh_username
  }
}


# ---------- LOCALS ----------
locals {
  # Base network configuration
  network_cidr = "172.16.16.0/24"
  network_mask = 24
  # Generates "172.16.16.1" address in our case
  network_gateway_ip = cidrhost(local.network_cidr, 1)

  # IP offsets inside the subnet
  control_plane_ip_offset = 20
  worker_ip_offset        = 30

  # Number of VMs
  control_plane_count = 3
  worker_count        = 3
}

# ---------- CLOUD-INIT FILES PER WORKER NODE ----------
# Each worker VM gets its own cloud-init file with a unique hostname.
# The Proxmox provider doesn't support hostname overrides,
# so we generate separate snippets dynamically.

resource "proxmox_virtual_environment_file" "cloud_init_worker" {
  # "for_each" fans out resources; it needs a set of unique string keys.
  # We generate {"0","1","2"} for worker_count = 3.
  for_each = toset([for i in range(local.worker_count) : tostring(i)])

  content_type = "snippets"
  datastore_id = var.pm_snippets_datastore_id
  node_name    = var.pm_node_name

  source_raw {
    data = templatefile("${path.module}/templates/cloud-init-base.tftpl", {
      username       = var.ci_username
      password       = var.ci_password
      ssh_public_key = trimspace(var.ci_ssh_public_key)
      hostname       = "k8s-node-${tonumber(each.value) + 1}"
      enable_k8s     = true
    })

    # Make file names unique per node
    file_name = "cloud-init-worker-${tonumber(each.value) + 1}.yaml"
  }
}


# ---------- CLOUD-INIT FILES PER CONTROL-PLANE NODE ----------
# The same logic as above
resource "proxmox_virtual_environment_file" "cloud_init_control_plane" {
  for_each = toset([for i in range(local.control_plane_count) : tostring(i)])

  content_type = "snippets"
  datastore_id = var.pm_snippets_datastore_id
  node_name    = var.pm_node_name

  source_raw {
    data = templatefile("${path.module}/templates/cloud-init-base.tftpl", {
      username       = var.ci_username
      password       = var.ci_password
      ssh_public_key = trimspace(var.ci_ssh_public_key)
      hostname       = "k8s-control-${tonumber(each.value) + 1}"
      enable_k8s     = true
    })

    file_name = "cloud-init-control-plane-${tonumber(each.value) + 1}.yaml"
  }
}


# ---------- CONTROL-PLANE NODES ----------
# Each VM uses its own cloud-init snippet via for_each
resource "proxmox_virtual_environment_vm" "control_planes" {
  for_each = proxmox_virtual_environment_file.cloud_init_control_plane

  depends_on = [
    proxmox_virtual_environment_file.cloud_init_control_plane
  ]

  name            = "k8s-control-${tonumber(each.key) + 1}"
  node_name       = var.pm_node_name
  description     = "Kubernetes control-plane node"
  started         = true
  stop_on_destroy = true

  clone {
    vm_id        = 9000
    full         = true
    datastore_id = var.pm_lvm_datastore_id
  }

  bios    = "ovmf"
  machine = "q35"

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
    # Link to the specific snippet generated above
    user_data_file_id = each.value.id

    ip_config {
      ipv4 {
        address = format(
          "%s/%d",
          cidrhost(local.network_cidr, local.control_plane_ip_offset + tonumber(each.key) + 1),
          local.network_mask
        )
        gateway = local.network_gateway_ip
      }
    }

    # Workaround for bpg Terraform proxmox provider. 
    # We use ssh auth by login and password for cloud-init by default for tty access from proxmox web console
    # and then disable password auth and provide ssh pub key in cloud-init-snippet
    user_account {
      username = var.ci_username
      password = var.ci_password
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
  }
}


# ---------- WORKER NODES ----------
# Each VM uses its own cloud-init snippet via for_each
resource "proxmox_virtual_environment_vm" "workers" {
  for_each = proxmox_virtual_environment_file.cloud_init_worker

  depends_on = [
    proxmox_virtual_environment_file.cloud_init_worker
  ]

  name            = "k8s-node-${tonumber(each.key) + 1}"
  node_name       = var.pm_node_name
  description     = "Kubernetes worker node"
  started         = true
  stop_on_destroy = true

  clone {
    vm_id        = 9000
    full         = true
    datastore_id = var.pm_lvm_datastore_id
  }

  bios    = "ovmf"
  machine = "q35"

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
    # Link to the specific snippet generated above
    user_data_file_id = each.value.id

    ip_config {
      ipv4 {
        address = format(
          "%s/%d",
          cidrhost(local.network_cidr, local.worker_ip_offset + tonumber(each.key) + 1),
          local.network_mask
        )
        gateway = local.network_gateway_ip
      }
    }

    # Workaround for bpg Terraform proxmox provider. 
    # We use ssh auth by login and password for cloud-init by default for tty access from proxmox web console
    # and then disable password auth and provide ssh pub key in cloud-init-snippet
    user_account {
      username = var.ci_username
      password = var.ci_password
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
  }
}

