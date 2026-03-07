#!/usr/bin/env bash

# Strict mode: 
# -e exit on any command failure 
# -u fail on undefined variables 
# -o pipefail fail if any command in a pipeline fails 
set -euo pipefail

NAMESPACE="argocd"
VALUES_FILE="values-ha-stateless.yaml"

echo "🚀 Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "📦 Installing/Upgrading ArgoCD in namespace $NAMESPACE..."
helm upgrade --install argocd argo/argo-cd \
    --namespace $NAMESPACE \
    --create-namespace \
    -f argocd/$VALUES_FILE

echo "✅ Installation completed. Checking pods..."
kubectl get pods -n $NAMESPACE