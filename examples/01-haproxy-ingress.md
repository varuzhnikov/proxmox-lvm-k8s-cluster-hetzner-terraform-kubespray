# HAProxy Ingress Controller Setup

This guide explains how to install HAProxy Ingress Controller in your Kubernetes cluster using Helm with NodePort service type and DaemonSet deployment.

## Prerequisites

- Kubernetes cluster is deployed and accessible
- `kubectl` is configured and working
- `helm` is installed (version 3.x)

## Installation Steps

### 1. Add HAProxy Ingress Helm Repository

```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
```

### 2. Install HAProxy Ingress

Install HAProxy Ingress Controller with NodePort service and DaemonSet:

**Option A: From project root directory:**
```bash
# From project root
helm install haproxy-ingress haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  -f examples/01-haproxy-ingress/values.yaml
```

**Option B: From examples directory:**
```bash
# Navigate to examples directory first
cd examples
helm install haproxy-ingress haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  -f 01-haproxy-ingress/values.yaml
```

### 3. Verify Installation

Check if pods are running:

```bash
kubectl get pods -n haproxy-controller -o wide
```

You should see one HAProxy Ingress pod per worker node (DaemonSet).

Check the service:

```bash
kubectl get svc -n haproxy-controller
```

You should see NodePort service with ports 30080 (HTTP) and 30443 (HTTPS).

**Note:** The service name is typically the same as the Helm release name (`haproxy-ingress` in this example). If you used a different release name, the service name will match it.

### 4. Test Connectivity

From your Proxmox host, test if NodePort is accessible:

```bash
curl -I http://<worker-node-ip>:30080
```

## Configuration Details

The `values.yaml` file configures:

- **DaemonSet**: One pod per node for local traffic processing
- **NodePort**: Ports 30080 (HTTP) and 30443 (HTTPS)
- **externalTrafficPolicy: Local**: Ensures traffic is processed locally on the node, avoiding double-hop
- **PROXY Protocol**: Enabled (`use-proxy-protocol: "true"`) to receive real client IPs from Proxmox HAProxy
  - Proxmox HAProxy sends PROXY protocol v2 headers to preserve client IP information
  - This is **required** for HTTPS traffic (TCP mode) where HTTP headers cannot be used
  - For HTTP traffic, PROXY protocol is more reliable than X-Forwarded-For headers
- **IngressClass**: Creates IngressClass resource named "haproxy" for modern Ingress configuration

**Important:** The Proxmox HAProxy configuration (in `terraform/templates/haproxy.cfg.tftpl`) must have `send-proxy-v2` enabled on backend server definitions for PROXY protocol to work. This ensures real client IPs are preserved throughout the entire chain: Client → Proxmox HAProxy → HAProxy Ingress Controller → Application Pods.

## Troubleshooting

### Pods not starting

Check pod logs:
```bash
kubectl logs -n haproxy-controller -l app.kubernetes.io/instance=haproxy-ingress
```

### Service not accessible

Verify NodePort is listening:
```bash
kubectl get svc -n haproxy-controller haproxy-ingress-kubernetes-ingress -o yaml
```

If the service name is different, first check:
```bash
kubectl get svc -n haproxy-controller
```

Check firewall rules on worker nodes if needed.

### Traffic not reaching pods

Verify `externalTrafficPolicy: Local` is set.
```bash
kubectl get svc -n haproxy-controller haproxy-ingress-kubernetes-ingress -o jsonpath='{.spec.externalTrafficPolicy}'
```

If the service name is different, first check:
```bash
kubectl get svc -n haproxy-controller
```

## Next Steps

After HAProxy Ingress is installed, proceed to:
- [Let's Encrypt Setup](02-letsencrypt.md) - Configure SSL certificates
- [Podinfo Deployment](03-podinfo.md) - Deploy a sample application
