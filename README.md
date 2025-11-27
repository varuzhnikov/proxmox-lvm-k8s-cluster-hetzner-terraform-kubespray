# Proxmox + LVM + K8s Cluster on Hetzner with Terraform & Kubespray

This repo helps you deploy a **Kubernetes cluster** on top of **Proxmox VE**, using:
- 💽 LVM-backed storage (vg0)
- 🌐 NAT-based networking via vmbr0
- 🏗️ Automated setup via **Ansible**
- ☁️ Virtual machine provisioning via **Terraform**
- ⚙️ Cluster bootstrap via **Kubespray**

## 🧱 Architecture

- **Host**: Hetzner EX44 (Debian 12, Proxmox VE, RAID-0, LVM)
- **VMs**: Ubuntu cloud-init images
- **Cluster**: Kubernetes 1.x with kube-vip, metrics-server, etc.

## 📦 Contents

- `ansible/` — installs Proxmox VE on Debian, configures vmbr0 NAT bridge, and connects LVM
- `terraform/` — (in progress) spins up VMs on Proxmox
- `kubespray/` — (planned) cluster bootstrap

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

Clone repo and adjust a server ip address in the ```ansible/inventory/hosts.ini```

After that:
```bash
cd ansible/
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventory/hosts.ini playbooks/site.yml --tags bootstrap
```

Terraform token will be saved under ansible/secrets folder(ignored by Git)

📌 For a full step-by-step guide, see the [companion article](https://blog.hogmetrics.com/64gb-ram-kubernetes-cluster-for-eu39-month-part-1-proxmox-lvm/)

#### 6. Spin up six Ubuntu VM (3 Control Planes + 3 Worker nodes) on Proxmox VE via Terraform

Copy terraform.tfvars.example:
```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Put the token from the file obtained on step 5 (ansible/secrets folder) into the terraform.tfvars, adjust a server ip address, and your pub ssh key.

📌 Set up HCP Terraform for remote state storing and lock acquiring, see the [companion article](https://blog.hogmetrics.com/how-to-store-terraform-state-in-terraform-cloud-free-tier/) 

Spin up a cluster VMs:

```
terraform init
terraform plan -out "k8s"
terraform apply "k8s"
```

After playing with that in case you don't need it anymore, destroy with:

```
terraform destroy
```

📌 For a full step-by-step guide, see the :
 
* [companion article part 2](https://blog.hogmetrics.com/how-to-create-a-proxmox-vm-template-with-ubuntu-22-04-cloud-init-and-deploy-vm-clones-via-terraform-bpg-proxmox/)
* [companion article part 3]


## 🛠️ Features

* ✅ Full control over disk layout (RAID-0, LVM)
* ✅ NAT networking for isolated K8s VMs
* ✅ No ZFS overhead
* ✅ Declarative provisioning

## 🔜 Roadmap

* ✅ Ansible role for Proxmox + LVM + NAT + [Cloud Init Ubuntu 22.04 VM Template] + [ Terraform User Token Role Creation ]   
* Terraform Proxmox provider setup (In progress)
* Kubespray integration
* Monitoring + observability layer (Prometheus, Grafana)

📌 Author

Follow Vitaly Ruzhnikov on [LinkedIn](https://www.linkedin.com/in/vitaly-ruzhnikov-86109234/)
