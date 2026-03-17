#!/usr/bin/env bash

# Strict mode: 
# -e exit on any command failure 
# -u fail on undefined variables 
# -o pipefail fail if any command in a pipeline fails 
set -euo pipefail

# Deterministic Versions (matched to your 'helm list' output)
ARGOCD_CHART_VERSION="9.4.10"

# Path configuration
VENDOR_DIR="vendor/argocd"
CHART_DIR="$VENDOR_DIR/chart"

echo "🧹 Cleaning up $VENDOR_DIR..."
rm -rf "$VENDOR_DIR"
mkdir -p "$CHART_DIR"

echo "📦 1. Fetching ArgoCD Helm Chart (version $ARGOCD_CHART_VERSION)..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

# Create a temporary directory for extraction
TEMP_DIR=$(mktemp -d)

# Pull and untar the specific version
helm pull argo/argo-cd --version "$ARGOCD_CHART_VERSION" --untar --untardir "$TEMP_DIR"

# Move content to our local vendor directory
# (helm pull untars into a subfolder named argo-cd)
mv "$TEMP_DIR/argo-cd/"* "$CHART_DIR/"
rm -rf "$TEMP_DIR"

echo "✅ Chart saved to: $CHART_DIR"

echo -e "\n🚀 Success! Your Cursor Knowledge Base is synchronized with your cluster."
echo "💡 Usage in Cursor: '@vendor/argocd/chart/values.yaml - is my source of truth.'"

