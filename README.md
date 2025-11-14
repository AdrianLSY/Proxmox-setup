# Proxmox Setup (ZFS + IOMMU + VFIO)

A Configuration repository for Proxmox VE with PCI passthrough, CPU pinning, and NUMA optimization.
A reference by me for future me.

Or YOU if you so happen to have this specific machine with the Intel Core 3-N355.
Topton 6 LAN 2.5G i226-V – AliExpress

---

## Repository Structure

This repository mirrors the Proxmox filesystem structure. Files are organized by their target system paths:

```
etc/
├── kernel/
│   └── cmdline
├── network/
│   └── interfaces
├── resolv.conf
└── systemd/system/
    └── vm-pin@.service

usr/local/bin/
    └── vm-pin.sh

var/lib/vz/snippets/
    ├── 100.hook
    └── 101.hook
```

To deploy, copy files from their repository path to the corresponding system path.

---

## Setup Steps

### 1. Update System

```bash
rm -f /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources
apt-get update
apt-get upgrade -y
```

### 2. Deploy Configuration Files

* `etc/resolv.conf` → `/etc/resolv.conf`
* `etc/kernel/cmdline` → `/etc/kernel/cmdline`
* `etc/network/interfaces` → `/etc/network/interfaces`
* `etc/systemd/system/vm-pin@.service` → `/etc/systemd/system/vm-pin@.service`
* `usr/local/bin/vm-pin.sh` → `/usr/local/bin/vm-pin.sh`
* `var/lib/vz/snippets/100.hook` → `/var/lib/vz/snippets/100.hook`
* `var/lib/vz/snippets/101.hook` → `/var/lib/vz/snippets/101.hook`

### 3. Apply Changes

```bash
chmod +x /usr/local/bin/vm-pin.sh
chmod +x /var/lib/vz/snippets/100.hook
chmod +x /var/lib/vz/snippets/101.hook

systemctl daemon-reload

update-initramfs -u -k all
proxmox-boot-tool refresh
```

### 4. Reboot

```bash
reboot
```

---

## Verify Configuration

```bash
dmesg | grep -e IOMMU -e DMAR
systemctl status vm-pin@100-2-5.service
```

---

## Download ISOs

All ISOs are stored in `local` storage:

```
/var/lib/vz/template/iso/
```

```bash
wget -O /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2 \
  https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2

wget -O /var/lib/vz/template/iso/ubuntu-24.04.3-live-server-amd64.iso \
  https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso
  
bunzip2 /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2
```

---

## Create VMs

```bash
# OPNsense Router VM (ID: 100)
qm create 100 \
  --name opnsense \
  --memory 8192 \
  --cores 2 \
  --sockets 1 \
  --cpu host \
  --machine q35

qm set 100 \
  --numa 1 \
  --numa0 cpus=0-1,hostnodes=0,memory=8192,policy=bind

qm set 100 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-zfs:64,cache=none,discard=on,aio=native

qm set 100 \
  --ide2 local:iso/OPNsense-25.7-dvd-amd64.iso,media=cdrom

qm set 100 \
  --net0 virtio=BC:24:11:0D:0E:DE,bridge=vmbr0,queues=6

qm set 100 \
  --hostpci0 0000:01:00.0,pcie=1

qm set 100 \
  --boot "order=ide2;scsi0" \
  --vga std \
  --serial0 socket \
  --balloon 0 \
  --onboot 1

qm set 100 --hookscript local:snippets/100.hook

# Ubuntu Server VM (ID: 101)
qm create 101 \
  --name ubuntu \
  --memory 16384 \
  --cores 4 \
  --sockets 1 \
  --cpu host \
  --machine q35

qm set 101 \
  --numa 1 \
  --numa0 cpus=0-3,hostnodes=0,memory=16384,policy=bind

qm set 101 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-zfs:256,cache=none,discard=on,aio=native

qm set 101 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom

qm set 101 \
  --net0 virtio,bridge=vmbr0

qm set 101 \
  --boot "order=ide2;scsi0" \
  --vga std \
  --serial0 socket \
  --balloon 0 \
  --onboot 0

qm set 101 --hookscript local:snippets/101.hook
```

---

## CPU Pinning Verification

```bash
qm start 100
sleep 15
systemctl status vm-pin@100-2-3.service
```

```bash
qm start 101
sleep 15
systemctl status vm-pin@101-4-7.service
```

---

## CPU Core Allocation

| Cores | Assignment        |
| ----- | ----------------- |
| 0-1   | Proxmox Host      |
| 2-3   | VM 100 (OPNsense) |
| 4-7   | VM 101 (Ubuntu)   |
