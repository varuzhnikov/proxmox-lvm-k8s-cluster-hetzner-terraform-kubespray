#!/usr/bin/env bash

source .env

# Export Terraform variables
# pm is a shorthand for proxmox
export TF_VAR_pm_ip="${PROXMOX_HOST_IP}"
export TF_VAR_pm_api_url="https://${PROXMOX_HOST_IP}:8006/api2/json"
export TF_VAR_pm_host_ssh_private_key_path="${PROXMOX_HOST_SSH_KEY}"
export TF_VAR_pm_vms_ssh_private_key_path="${PROXMOX_VMS_SSH_KEY}"

echo "Exported Terraform variables"

cat > ansible/inventory/hosts.ini <<EOF
[proxmox]
${PROXMOX_HOST_IP} ansible_user=${PROXMOX_HOST_SSH_USER}
EOF

echo "Generated inventory/hosts.ini"

#Print SSH Config block for dedicated server
echo
echo "SSH Config block for dedicated server(copy manually if needed):"
echo "---------------------------------------------------------------"
cat <<EOF
Host kube-lab
    HostName ${PROXMOX_HOST_IP}
    User ${PROXMOX_HOST_SSH_USER}
    IdentityFile ${PROXMOX_HOST_SSH_KEY}
    ServerAliveInterval 30
    ServerAliveCountMax 5
EOF

# Set KUBECONFIG for this project
KUBECONFIG_FILE="$HOME/.kube/kube-lab.conf"
export KUBECONFIG="$KUBECONFIG_FILE"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  ATTENTION: KUBECONFIG has been set to: $KUBECONFIG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
