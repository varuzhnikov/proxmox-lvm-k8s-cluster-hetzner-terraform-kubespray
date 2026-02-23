# Let's Encrypt SSL Certificate Setup

This guide explains how to configure Let's Encrypt SSL certificates for your domains using cert-manager in Kubernetes.

## Prerequisites

- HAProxy Ingress Controller is installed and working
- Domain names are configured in DNS pointing to your Proxmox host IP
- Domain names are added to `/etc/haproxy/allow_domains.txt` on Proxmox host
- Port 80 is accessible for Let's Encrypt HTTP-01 challenge validation

## Installation Steps

### 1. Install cert-manager

```bash
# Add cert-manager Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
# Option A: Multi-line command (works in native Linux/bash)
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# Option B: Single-line command (recommended for WSL)
# Use this if Option A causes issues in WSL terminal
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true
```

**Note for WSL users:** If the multi-line command (Option A) causes your WSL session to exit, use the single-line version (Option B). This is a known issue with backslash line continuation in WSL when copying commands from Windows.

### 2. Verify cert-manager Installation

Wait for cert-manager pods to be ready:

```bash
kubectl get pods -n cert-manager
```

All pods should be in `Running` state.

### 3. Create ClusterIssuer

First, copy the example file and edit it with your email:

```bash
# Navigate to examples directory
cd examples
cp 02-letsencrypt/cluster-issuer.yaml.example 02-letsencrypt/cluster-issuer.yaml
vi 02-letsencrypt/cluster-issuer.yaml
# Or use: nano 02-letsencrypt/cluster-issuer.yaml (if you prefer)
# Replace 'your-email@example.com' with your actual email address
```

Then apply the ClusterIssuer:

```bash
kubectl apply -f 02-letsencrypt/cluster-issuer.yaml
```

Verify it's created:

```bash
kubectl get clusterissuer
```

### 4. Test Certificate Issuance

You can test certificate issuance by creating a Certificate resource for your domain. This will be done automatically when you create an Ingress resource with cert-manager annotations (see Podinfo example).

## Configuration Details

The `cluster-issuer.yaml` file configures:

- **Let's Encrypt Staging**: For testing (doesn't count against rate limits)
- **Let's Encrypt Production**: For production use
- **HTTP-01 Challenge**: Uses port 80 for validation (required for your setup)

### Why Both Staging and Production?

**Let's Encrypt has strict rate limits:**
- 50 certificates per registered domain per week
- 5 duplicate certificates per week
- 300 new orders per 3 hours per account

**Best Practice Workflow:**

1. **Start with Staging** (`letsencrypt-staging`):
   - Test your configuration without risk
   - Verify DNS, HTTP-01 challenge, and cert-manager setup
   - No rate limits - you can test as many times as needed
   - Certificates are **not trusted** by browsers (shows warning - this is normal for testing)

2. **Switch to Production** (`letsencrypt-prod`):
   - Only after staging works successfully
   - Issues **trusted certificates** for real use
   - Subject to rate limits - use carefully

This two-step approach prevents you from hitting rate limits while debugging configuration issues.

## Using Certificates in Ingress

### Recommended Workflow: Staging First, Then Production

**Step 1: Test with Staging Issuer**

When creating Ingress resources, start with staging issuer for testing:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-staging"  # Start with staging
spec:
  tls:
    - hosts:
        - example.com
      secretName: example-com-tls
```

Apply and verify:
```bash
kubectl apply -f ingress.yaml
kubectl get certificate -n <namespace>
kubectl describe certificate <cert-name> -n <namespace>
```

**Note:** Browser will show certificate warning - this is normal for staging certificates.

**Step 2: Switch to Production Issuer**

Once staging certificate is issued successfully, switch to production:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Switch to production
spec:
  tls:
    - hosts:
        - example.com
      secretName: example-com-tls
```

Apply again:
```bash
kubectl apply -f ingress.yaml
```

cert-manager will automatically:
1. Create a Certificate resource
2. Request certificate from Let's Encrypt
3. Store it in the specified Secret
4. Renew it automatically before expiration

**Important:** When switching from staging to prod, cert-manager will create a new certificate. The old staging certificate will remain but won't be used. You can optionally delete it:

```bash
kubectl delete certificate <cert-name> -n <namespace>
kubectl delete secret <secret-name> -n <namespace>
```

## Troubleshooting

### Certificate not issued

If certificate is stuck in "Issuing" state, follow these diagnostic steps:

**Step 1: Check Certificate Status**
```bash
kubectl describe certificate <certificate-name> -n <namespace>
```

Look for:
- Status: Should eventually become "Ready: True"
- Events: Check for any error messages
- Conditions: "Issuing" is normal initially (first 1-2 minutes), should change to "Ready"

**Step 2: Check CertificateRequest**
```bash
# List all CertificateRequests in namespace
kubectl get certificaterequest -n <namespace>

# Describe the specific request (name usually matches certificate with numeric suffix)
kubectl describe certificaterequest <certificate-name>-<number> -n <namespace>
```

Look for:
- Status: Should show "Approved" and "Ready"
- Events: Check for ACME order creation

**Step 3: Check ACME Challenges**
```bash
# List all challenges across all namespaces
kubectl get challenge -A

# Describe challenge in your namespace (if exists)
kubectl describe challenge -n <namespace>
```

Look for:
- State: Should be "valid" or "processing"
- Events: Check for HTTP-01 challenge validation status

**Step 4: Check cert-manager Logs**
```bash
# Check cert-manager controller logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check cert-manager webhook logs (if issues with validation)
kubectl logs -n cert-manager -l app=webhook --tail=50
```

**Step 5: Watch Certificate Status**
```bash
# Watch certificate until it becomes ready (may take 1-2 minutes)
kubectl get certificate <certificate-name> -n <namespace> -w
```

Expected progression:
- Initially: `Ready: False, Issuing: True`
- After challenge validation: `Ready: True, Issuing: False`

### HTTP-01 challenge failing

**Verify Challenge Path Accessibility**

The HTTP-01 challenge must be accessible at:
```
http://<your-domain>/.well-known/acme-challenge/<token>
```

Test from outside your cluster:
```bash
# Test if challenge path is accessible
curl -v http://<your-domain>/.well-known/acme-challenge/test
```

**Check Prerequisites:**

1. **Port 80 is accessible from internet**
   ```bash
   # From outside, test if port 80 is open
   telnet <proxmox-host-ip> 80
   # Or use: nc -zv <proxmox-host-ip> 80
   ```

2. **Domain is in `allow_domains.txt` on Proxmox host**
   ```bash
   # SSH to Proxmox host and check
   cat /etc/haproxy/allow_domains.txt
   # Should contain your domain (e.g., podinfo.thenextgen.store)
   ```

3. **HAProxy on Proxmox allows `/.well-known/acme-challenge/` path**
   - This should be configured automatically in HAProxy config
   - Check HAProxy config: `grep -A 5 "acme-challenge" /etc/haproxy/haproxy.cfg`

4. **DNS points to correct IP address**
   ```bash
   # Verify DNS resolution
   dig <your-domain>
   # Should resolve to your Proxmox host IP
   ```

5. **HAProxy Ingress Controller is working**
   ```bash
   # Check HAProxy Ingress pods
   kubectl get pods -n haproxy-controller
   
   # Check HAProxy Ingress logs
   kubectl logs -n haproxy-controller -l app.kubernetes.io/name=haproxy-ingress
   ```

### Rate limiting

Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

Use staging issuer for testing to avoid hitting limits.

## Next Steps

After cert-manager is configured, proceed to:
- [Podinfo Deployment](03-podinfo.md) - Deploy a sample application with SSL
