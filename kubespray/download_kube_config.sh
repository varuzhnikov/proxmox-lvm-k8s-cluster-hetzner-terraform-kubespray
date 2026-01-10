#!/usr/bin/env bash

# Strict mode: 
# -e exit on any command failure 
# -u fail on undefined variables 
# -o pipefail fail if any command in a pipeline fails 
set -euo pipefail

KUBECONFIG_FILE="$HOME/.kube/kube-lab.conf"

ssh -J kube-lab ubuntu@172.16.16.21 "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"

echo "Kubeconfig saved to $KUBECONFIG_FILE"
echo "Run: export KUBECONFIG=$KUBECONFIG_FILE"
