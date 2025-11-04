### PROXMOX VARIABLES

variable "pm_api_url" {
    type        = string
    description = "Proxmox API URL (https://<host>:8006/api2/json)"
}

variable "pm_api_token" {
    type        = string
    description = "Proxmox API token ID and secret"
    sensitive   = true
}

variable "pm_ssh_username" {
    type        = string
    description = "SSH username using to uploading Cloud-init snippets on Proxmox host"
    default     = "root"
}

variable "pm_ssh_private_key_path" {
    type        = string
    description = "SSH private key path using to uploading Cloud-init snippets on Proxmox host"
    default     = "~/.ssh/id_rsa"  
}

variable "pm_tls_insecure" {
    type        = bool
    default     = true
    description = "Allow self-signed Proxmox certs"
}

variable "pm_node_name" {
    type        = string
    default     = "kube-lab"
    description = "On which Proxmox node should we operate"
}

variable pm_lvm_datastore_id {
    type        = string
    default     = "local-lvm"
    description = "LVM Datastore ID used for allocation disk space for cloned VM"
}

variable pm_snippets_datastore_id {
    type        = string
    default     = "local"
    description = "Datastore ID used for persisting cloud-init snippets. Cannot be LVM"
}

### CLOUD-INIT VARIABLES

variable "ci_ssh_public_key" {
    type        = string
    description = "Default ssh public key for cloud init"
}

variable "ci_username" {
    type        = string
    description = "Default user for ubuntu for cloud init"
}

variable "ci_password" {
    type        = string
    sensitive   = true
    description = "Default password for ubuntu for cloud init"
}