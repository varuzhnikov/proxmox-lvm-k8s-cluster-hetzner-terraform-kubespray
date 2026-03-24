# Proxmox + LVM + K8s Cluster on Hetzner with Terraform & Kubespray

This repo helps you deploy a **Kubernetes cluster** on top of **Proxmox VE**, using:
- 💽 LVM-backed storage (vg0)
- 🌐 NAT-based networking via vmbr0
- 🏗️ Automated setup via **Ansible**
- ☁️  Virtual machine provisioning via **Terraform**
- ⚙️  Cluster bootstrap via **Kubespray**

## 🧱 Architecture

- **Host**: Hetzner EX44 (Debian 12, Proxmox VE, RAID-0, LVM)
- **VMs**: Ubuntu cloud-init images
- **Cluster**: Kubernetes 1.x with kube-vip, metrics-server, etc.

## 📦 Contents

- `ansible/` — installs Proxmox VE on Debian, configures vmbr0 NAT bridge, connects LVM, builds Ubuntu 22.04 LTS Proxmox VM Template, generates role, user and Proxmox API token for Terraform, installs HAProxy as an entry point to the cluster and deploys rendered by Terraform HAProxy config. 
- `terraform/` — provisions VMs on Proxmox, generates the Kubespray inventory with SSH ProxyJump, and creates an HAProxy configuration to distribute traffic among the Kubernetes control plane and worker nodes
- `kubespray/` — cluster bootstrap using generated via Terraform Kubespray inventory 

## 🚀 Quickstart

### 🧰 Prepare Hetzner Server (Rescue Mode + LVM layout)

To prepare a Hetzner dedicated server for Proxmox + K8s deployment, start with Rescue Mode and configure software RAID-0 and LVM:

#### 1. Boot into Rescue Mode

* Go to robot.hetzner.com/server
* Select your server → Rescue
* Choose Linux 64-bit
* Click Activate rescue system
* Reboot with Execute an automatic hardware reset

The temporary root password will appear directly in the Rescue tab.

```
ssh root@<your-server-ip>
```

#### 2. Run installimage Tool

```
installimage
```

In the interactive menu select Debian 12.

#### 3. Disk layout recommendation

In the partitioning step, use a minimal layout like this:

```
# Disks
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1

# Software RAID
SWRAID 1
SWRAIDLEVEL 0        # 0 = RAID0 (speed/space), use 1 for RAID1 (redundancy)

HOSTNAME kube-lab

# Partitions
PART /boot/efi esp 256M
PART /boot ext4 512M

# LVM
PART lvm vg0 all

# Logical Volumes
LV vg0 root / ext4 50G
LV vg0 swap swap swap 8G

# <-- Do not define LV data here! leave the remaining space free in the VG -->
```

#### 4. Finish Installation

After confirming:

* ```installimage``` will partition disks, setup LVM & RAID-0
* Debian 12 will be installed
* After reboot, you’ll have a clean Debian with vg0 available

#### 5. Run ansible to install proxmox and setup NAT network and lvm storage

Clone the repo and copy ```.env.example```:
```
cp .env.example .env
``` 

Adjust a dedicated server ip address, ssh key paths for the dedicated server itself and for Proxmox VMs to be created.
After that source ```prepare_env.sh```:
```
source prepare_env.sh
```
It will generate an ansible/inventory/hosts.ini with one entry - dedicated server itself and export all required ENV variables for both Ansible and Terraform.

After that:
```bash
cd ansible/
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventory/hosts.ini playbooks/site.yml --tags bootstrap
```

Terraform token will be saved under ansible/secrets folder(ignored by Git)

📌 For a full step-by-step guide, see [64GB RAM Kubernetes Cluster for €39/month - Part 1: Proxmox & LVM](https://open.substack.com/pub/ruzhnikov/p/64gb-ram-kubernetes-cluster-for-39month?r=734lmp&utm_campaign=post&utm_medium=web&showWelcomeOnShare=true)

#### 6. Spin up six Ubuntu VM (3 Control Planes + 3 Worker nodes) on Proxmox VE via Terraform

Copy terraform.tfvars.example:
```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Put the token from the file obtained on step 5 (ansible/secrets folder) into the terraform.tfvars, adjust a server ip address, and your pub ssh key.

📌 Set up HCP Terraform for remote state storing and lock acquiring, see [How to Store Terraform State in Terraform Cloud (Free Tier)](https://blog.hogmetrics.com/how-to-store-terraform-state-in-terraform-cloud-free-tier/) 

Spin up a cluster VMs:

```
terraform init
terraform plan -out "k8s"
terraform apply "k8s"
```

#### 7. Deploy Kubernetes cluster behind NAT using Kubespay:

Move to kubespray folder:

```
cd kubespray
./deploy_cluster.sh
```

#### 8. Deploy HAProxy to load balance API endpoints and worker nodes

**8a. Prepare domain allowlist:**

Before deploying HAProxy, create and edit the domain allowlist file locally. This file will be automatically deployed to the Proxmox host via Ansible:

```bash
cd ansible/playbooks/roles/haproxy/files/
cp allow_domains.txt.example allow_domains.txt
vi allow_domains.txt
# Or use: nano allow_domains.txt (if you prefer)
```

Add your domains (one per line):
- Exact domain: `example.com`
- Exact subdomain: `www.example.com`
- Wildcard subdomain: `.example.com` (with leading dot, matches `*.example.com`)

Example content:
```
example.com
www.example.com
api.example.com
.example.com          # Matches *.example.com (any subdomain)
```

**Important:** This file must exist locally before running the HAProxy Ansible playbook. Ansible will copy it to `/etc/haproxy/allow_domains.txt` on the Proxmox host automatically.

**8b. Deploy HAProxy:**

Deploy HAProxy for load balancing API endpoints on 6443 port and worker nodes on 443 port:
```
cd ansible
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventory/hosts.ini playbooks/site.yml --tags haproxy
```

#### 9. Connect to cluster

In case you're running WSL on Ubuntu or Debian based systems, install kubectl if you don't have it:
```
cd kubespray
./install_kubectl_deb.sh
```
Download kubeconfig:
```
./download_kube_config.sh
```
Follow the  instruction to export KUBECONFIG, something like that (running in WSL in my case ):
```
export KUBECONFIG=/root/.kube/kube-lab.conf
```

Then from the folder kubespray use tmux:
```
tmux new -s kube-lab
```
Type ```Ctrl + B then C``` to create a new tab.
When move to the first tab using ```Ctrl + B then P```
Run SSH port forwarding script to get access to the cluster behind NAT:
```
./ssh_forward_kube_api.sh
```
Move to the second tab using ```Ctrl + B then N```.
Then list all available nodes:
```
kubectl get nodes -o wide
```

#### 10. Deploy examples (HAProxy Ingress, cert-manager, podinfo)

**Prerequisites:** Configure DNS to point your domain to the Proxmox host IP address.

**10a. Deploy HAProxy Ingress Controller:**

```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
helm install haproxy-ingress haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  -f examples/01-haproxy-ingress/values.yaml
```

**10b. Install cert-manager for Let's Encrypt SSL certificates:**

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true
```

Wait for cert-manager pods to be ready:
```bash
kubectl get pods -n cert-manager
```

**10c. Create ClusterIssuer:**

Copy the example file and edit it locally with your email:

```bash
cd examples
cp 02-letsencrypt/cluster-issuer.yaml.example 02-letsencrypt/cluster-issuer.yaml
# Edit cluster-issuer.yaml and replace 'your-email@example.com' with your email
vi 02-letsencrypt/cluster-issuer.yaml
# Or use: nano 02-letsencrypt/cluster-issuer.yaml (if you prefer)
kubectl apply -f 02-letsencrypt/cluster-issuer.yaml
```

**10d. Deploy podinfo application with HTTPS:**

Copy example files and edit them locally:

```bash
cd examples

# Deploy podinfo
kubectl apply -f 03-podinfo/deployment.yaml

# Create Ingress (start with staging issuer for testing)
cp 03-podinfo/ingress.yaml.example 03-podinfo/ingress.yaml
# Edit ingress.yaml:
# 1. Replace 'your-domain.com' with your actual domain
# 2. Set cluster-issuer to "letsencrypt-staging" for testing
vi 03-podinfo/ingress.yaml
# Or use: nano 03-podinfo/ingress.yaml (if you prefer)
kubectl apply -f 03-podinfo/ingress.yaml

# Wait for certificate (1-2 minutes)
kubectl get certificate podinfo-tls -n default -w

# After staging certificate works, switch to production issuer:
# Edit ingress.yaml and change cluster-issuer to "letsencrypt-prod"
vi 03-podinfo/ingress.yaml
kubectl apply -f 03-podinfo/ingress.yaml
```

Your podinfo application is now accessible via HTTPS at `https://your-domain.com`

#### 11. Install ArgoCD (HA Stateless Configuration)

Install ArgoCD with high availability and stateless configuration that prevents hanging when worker nodes are shut down or become unreachable:

```bash
cd kubespray
./install_argocd.sh
```

This configuration uses fast pod eviction (90s), 3 replicas with pod anti-affinity, and Deployment instead of StatefulSet to ensure ArgoCD remains available even when nodes are shut down for maintenance or fail.


**Access ArgoCD UI:**

Set up port forwarding to access ArgoCD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Get the admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

Login to ArgoCD:
- Open browser: `https://localhost:8080`
- Username: `admin`
- Password: (use the password from the command above)

**Deploy app-of-apps pattern:**
```bash
kubectl apply -f examples/argocd/applications/app-of-apps.yaml
```

#### 12. Install OpenClaw via ArgoCD

OpenClaw's official Kubernetes deployment is a Kustomize-based minimal starting point, so this repository manages it as a repo-local ArgoCD application instead of a Helm chart.

Create the runtime secret first. The gateway token is required. Add at least one provider API key if you want the assistant to call models immediately:

```bash
kubectl create namespace openclaw

kubectl create secret generic openclaw-secrets -n openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"

# Optional: patch in one or more model provider keys later
kubectl patch secret openclaw-secrets -n openclaw \
  -p '{"stringData":{"OPENAI_API_KEY":"your-openai-api-key"}}'
```

Apply the OpenClaw ArgoCD application:

```bash
kubectl apply -f examples/argocd/applications/apps/openclaw.yaml
```

Port-forward the OpenClaw gateway to your workstation:

```bash
kubectl port-forward svc/openclaw -n openclaw 18789:18789
```

Get the gateway token and open the UI:

```bash
kubectl get secret openclaw-secrets -n openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d && echo
```

- Open browser: `http://localhost:18789`
- Paste the gateway token from the command above into the Control UI

#### 13. Destroy the cluster

After playing with that in case you don't need it anymore, destroy with:
```
cd terraform
terraform destroy
```

📌 For a full step-by-step guide, see:
 
1. [64GB RAM Kubernetes Cluster for €39/month](https://open.substack.com/pub/ruzhnikov/p/64gb-ram-kubernetes-cluster-for-39month?r=734lmp&utm_campaign=post&utm_medium=web&showWelcomeOnShare=true)
2. [Turning Proxmox into a Private Cloud](https://open.substack.com/pub/ruzhnikov/p/turning-proxmox-into-a-private-cloud?r=734lmp&utm_campaign=post&utm_medium=web&showWelcomeOnShare=true)
3. [Proxmox Terraform: Automatically Creating VMs](https://open.substack.com/pub/ruzhnikov/p/proxmox-terraform-automatically-creating?r=734lmp&utm_campaign=post&utm_medium=web&showWelcomeOnShare=true)
4. [Kubespray SSH ProxyJump: Deploying Kubernetes](https://open.substack.com/pub/ruzhnikov/p/kubespray-ssh-proxyjump-deploying?r=734lmp&utm_campaign=post&utm_medium=web&showWelcomeOnShare=true)
5. [Dual HAProxy Setup on Proxmox & Ingress Controller](LINK_PLACEHOLDER)
6. [Stateless ArgoCD for Bare Metal Kubernetes](https://open.substack.com/pub/ruzhnikov/p/stateless-argocd-for-bare-metal-kubernetes?r=734lmp&utm_campaign=post&utm_medium=web&showWelcomeOnShare=true)



## 🛠️ Features

* ✅ Full control over disk layout (RAID-0, LVM)
* ✅ NAT networking for isolated K8s VMs
* ✅ No ZFS overhead
* ✅ Declarative provisioning

## 🔜 Roadmap

* ✅ Ansible role for Proxmox + LVM + NAT + [Cloud Init Ubuntu 22.04 VM Template] + [ Terraform User Token Role Creation ]   
* ✅ Terraform Proxmox provider setup
* ✅ Kubespray integration
* ✅ HAProxy integration

📌 Author

Follow Vitaly Ruzhnikov on [LinkedIn](https://www.linkedin.com/in/vitaly-ruzhnikov-86109234/)
