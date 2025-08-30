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
- `terraform/` — spins up VMs on Proxmox
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


```bash
cd ansible/
ansible-playbook -i inventory.yaml install-proxmox.yml
```

📌 For a full step-by-step guide, see the companion article: ...

## 🛠️ Features

* ✅ Full control over disk layout (RAID-0, LVM)
* ✅ NAT networking for isolated K8s VMs
* ✅ No ZFS overhead
* ✅ Declarative provisioning

## 🔜 Roadmap

* ✅ Ansible role for Proxmox + LVM
* Terraform Proxmox provider setup
* Kubespray integration
* Monitoring + observability layer (Prometheus, Grafana)

📌 Author

Follow Vitalii Ruzhnikov on LinkedIn