#!/usr/bin/env bash

# Strict mode: 
# -e exit on any command failure 
# -u fail on undefined variables 
# -o pipefail fail if any command in a pipeline fails 
set -euo pipefail

IMAGE="quay.io/kubespray/kubespray:v2.29.1"
INVENTORY="/nat_cluster/inventory/inventory.ini"
docker run --rm -it \
	-v "$(pwd):/nat_cluster" \
	-v "$HOME/.ssh:/root/.ssh" \
	$IMAGE \
	ansible-playbook -i "$INVENTORY" -b cluster.yml
