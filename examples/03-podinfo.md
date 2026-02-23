# Podinfo Application Deployment

This guide explains how to deploy the [podinfo](https://github.com/stefanprodan/podinfo) sample application with HAProxy Ingress and Let's Encrypt SSL certificate.

## Prerequisites

- HAProxy Ingress Controller is installed and working
- cert-manager is installed and ClusterIssuer is configured
- Domain name is configured in DNS pointing to your Proxmox host IP
- Domain name is added to `/etc/haproxy/allow_domains.txt` on Proxmox host

## Deployment Steps

### 1. Deploy Podinfo Application

Deploy the podinfo application:

```bash
kubectl apply -f 03-podinfo/deployment.yaml
```

Verify the deployment:

```bash
kubectl get pods -l app=podinfo
kubectl get svc -l app=podinfo
```

### 2. Create Ingress with SSL

**Recommended: Test with Staging First, Then Switch to Production**

This two-step approach prevents hitting Let's Encrypt rate limits while testing your configuration.

**Step 2a: Test with Staging Issuer**

First, copy the example file and edit it with your domain:

```bash
# Copy the example file
cp 03-podinfo/ingress.yaml.example 03-podinfo/ingress.yaml

# Edit ingress.yaml:
# 1. Replace 'your-domain.com' with your actual domain
# 2. Change cluster-issuer to "letsencrypt-staging" for testing
vi 03-podinfo/ingress.yaml
# Or use: nano 03-podinfo/ingress.yaml (if you prefer)
```

In the file, set:
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-staging"  # Use staging for testing
```

Then apply:
```bash
kubectl apply -f 03-podinfo/ingress.yaml
```

**Step 2b: Verify Staging Certificate**

Check if staging certificate is issued (may take 1-2 minutes):
```bash
kubectl get certificate podinfo-tls -n default
kubectl describe certificate podinfo-tls -n default
```

**Note:** Browser will show certificate warning for staging - this is normal and expected.

**Step 2c: Switch to Production Issuer**

Once staging certificate works, switch to production:

```bash
# Edit ingress.yaml and change cluster-issuer to production
vi 03-podinfo/ingress.yaml
```

Change to:
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Switch to production
```

Apply again:
```bash
kubectl apply -f 03-podinfo/ingress.yaml
```

**Why this workflow?** See [Let's Encrypt Setup](02-letsencrypt.md) for detailed explanation of staging vs production issuers.

### 3. Verify Certificate Issuance

Check if certificate is being issued:

```bash
kubectl get certificate -n default
kubectl describe certificate podinfo-tls -n default
```

Wait for certificate to be ready (may take 1-2 minutes):

```bash
kubectl get certificate podinfo-tls -n default -w
```

### 4. Test Application

Once certificate is issued, test the application:

```bash
# Test HTTP (should redirect to HTTPS)
curl -I http://your-domain.com

# Test HTTPS
curl -I https://your-domain.com
```

Or open in browser:
- `http://your-domain.com` (should redirect to HTTPS)
- `https://your-domain.com` (should show podinfo page)

## Configuration Details

### Deployment

The `deployment.yaml` creates:
- Deployment with 2 replicas of podinfo
- Service exposing podinfo on port 9898

### Ingress

The `ingress.yaml` creates:
- Ingress resource with HAProxy Ingress class (using modern `ingressClassName` field)
- TLS configuration with cert-manager annotations
- Automatic SSL certificate provisioning
- HTTP to HTTPS redirect (handled by HAProxy Ingress)

## Customization

### Change Domain Name

Copy and edit `ingress.yaml.example`:

```bash
cp 03-podinfo/ingress.yaml.example 03-podinfo/ingress.yaml
vi 03-podinfo/ingress.yaml
# Or use: nano 03-podinfo/ingress.yaml (if you prefer)
```

Replace `your-domain.com` with your domain:

```yaml
spec:
  rules:
  - host: your-domain.com  # Change this
    ...
  tls:
  - hosts:
    - your-domain.com  # Change this
```

### Change Number of Replicas

Edit `deployment.yaml`:

```yaml
spec:
  replicas: 2  # Change this
```

### Switch Between Staging and Production

To test with staging issuer, edit `ingress.yaml` and change ClusterIssuer:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-staging"  # Use staging for testing
```

After testing, switch back to production:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Use production for real certificates
```

**See Step 2 above for the recommended workflow** - always test with staging first to avoid rate limits.

## Troubleshooting

### Pods not starting

Check pod status:
```bash
kubectl describe pod -l app=podinfo
kubectl logs -l app=podinfo
```

### Restart Certificate Issuance

If you need to restart certificate issuance (e.g., after updating ClusterIssuer configuration):

```bash
# Step 1: Delete the current certificate
kubectl delete certificate podinfo-tls -n default

# Step 2: Delete the challenge ingress (if exists)
kubectl delete ingress -n default -l acme.cert-manager.io/http01-solver=true

# Step 3: Cert-manager will automatically recreate the certificate
# Watch the certificate status
kubectl get certificate podinfo-tls -n default -w

# Step 4: Verify new challenge ingress is created with correct ingressClassName
kubectl get ingress -A | grep acme
# Should show ingress with CLASS: haproxy
```

**Note:** After updating ClusterIssuer to use `ingressClassName` instead of `class`, you must delete and recreate the certificate for the changes to take effect.

### Certificate not issued

If certificate is stuck in "Issuing" state, follow these diagnostic steps:

**Step 1: Check Certificate Status**
```bash
kubectl describe certificate podinfo-tls -n default
```

Look for:
- Status: Should eventually become "Ready: True"
- Events: Check for any error messages
- Conditions: "Issuing" is normal initially, should change to "Ready"

**Step 2: Check CertificateRequest**
```bash
# List all CertificateRequests
kubectl get certificaterequest -n default

# Describe the specific request (name usually matches certificate with suffix)
kubectl describe certificaterequest podinfo-tls-1 -n default
```

Look for:
- Status: Should show "Approved" and "Ready"
- Events: Check for ACME order creation

**Step 3: Check ACME Challenges**
```bash
# List all challenges
kubectl get challenge -A

# Describe challenge (if exists)
kubectl describe challenge -n default
```

Look for:
- State: Should be "valid" or "processing"
- Events: Check for HTTP-01 challenge validation

**Step 4: Check cert-manager Logs**
```bash
# Check cert-manager controller logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check cert-manager webhook logs (if issues with validation)
kubectl logs -n cert-manager -l app=webhook --tail=50
```

**Step 5: Verify HTTP-01 Challenge Path**

The challenge should be accessible at:
```
http://podinfo.thenextgen.store/.well-known/acme-challenge/<token>
```

Test from outside:
```bash
curl -v http://podinfo.thenextgen.store/.well-known/acme-challenge/test
```

**Common Issues:**

1. **Domain not in allow_domains.txt on Proxmox host**
   - Add domain to `/etc/haproxy/allow_domains.txt`
   - Restart HAProxy: `systemctl restart haproxy`

2. **DNS not pointing to Proxmox host**
   - Verify: `dig podinfo.thenextgen.store`
   - Should resolve to your Proxmox host IP

3. **Port 80 not accessible**
   - Check firewall rules
   - Verify HAProxy is listening on port 80

4. **HAProxy Ingress not processing challenge**
   - Check HAProxy Ingress logs (see "Ingress not working" section)
   - Verify ingress class is "haproxy"

**Step 6: Watch Certificate Status**
```bash
# Watch certificate until it becomes ready (may take 1-2 minutes)
kubectl get certificate podinfo-tls -n default -w
```

Expected progression:
- Initially: `Ready: False, Issuing: True`
- After challenge: `Ready: True, Issuing: False`

### Ingress not working

Check Ingress status:
```bash
kubectl describe ingress podinfo
```

Verify HAProxy Ingress is processing it:
```bash
kubectl logs -n haproxy-controller -l app.kubernetes.io/name=haproxy-ingress
```

### Domain not accessible

Verify:
- DNS points to Proxmox host IP
- Domain is in `allow_domains.txt` on Proxmox host
- HAProxy on Proxmox is running and configured
- Firewall allows ports 80 and 443

## Cleanup

To remove podinfo:

```bash
kubectl delete -f 03-podinfo/
```

This will remove:
- Deployment and pods
- Service
- Ingress
- Certificate (cert-manager will clean up)
