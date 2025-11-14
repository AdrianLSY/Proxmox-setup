# Proxmox Setup (ZFS + IOMMU + VFIO)

A Configuration repository for Proxmox VE with PCI passthrough, CPU pinning, and NUMA optimization.
A reference by me for future me.

Or YOU if you so happen to have this specific machine with the Intel Core 3-N355. [Topton 6 LAN 2.5G i226-V - AliExpress](https://www.aliexpress.com/item/1005005942080539.html)

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

### 1. Deploy Configuration Files

* `etc/resolv.conf` → `/etc/resolv.conf`
* `etc/kernel/cmdline` → `/etc/kernel/cmdline`
* `etc/network/interfaces` → `/etc/network/interfaces`
* `etc/systemd/system/vm-pin@.service` → `/etc/systemd/system/vm-pin@.service`
* `usr/local/bin/vm-pin.sh` → `/usr/local/bin/vm-pin.sh`
* `var/lib/vz/snippets/100.hook` → `/var/lib/vz/snippets/100.hook`
* `var/lib/vz/snippets/101.hook` → `/var/lib/vz/snippets/101.hook`

### Execute Commands

```bash
rm -f /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources
apt-get update
apt-get upgrade -y

chmod +x /usr/local/bin/vm-pin.sh
chmod +x /var/lib/vz/snippets/100.hook
chmod +x /var/lib/vz/snippets/101.hook

systemctl daemon-reload

update-initramfs -u -k all
proxmox-boot-tool refresh

wget -O /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2 \
  https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2

wget -O /var/lib/vz/template/iso/ubuntu-24.04.3-live-server-amd64.iso \
  https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso
  
bunzip2 /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2

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
  --scsi0 local-zfs:32,cache=none,discard=on,aio=native

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
  --scsi0 local-zfs:64,cache=none,discard=on,aio=native

qm set 101 \
  --ide2 local:iso/ubuntu-24.04.3-live-server-amd64.iso,media=cdrom

qm set 101 \
  --net0 virtio,bridge=vmbr0

qm set 101 \
  --boot "order=ide2;scsi0" \
  --vga std \
  --serial0 socket \
  --balloon 0 \
  --onboot 1

qm set 101 --hookscript local:snippets/101.hook

reboot
```
---

## Remove Disks

```bash
qm set 100 --delete ide2
qm set 101 --delete ide2
```

## CPU Pinning Verification

```bash
systemctl status vm-pin@100-2-3.service
systemctl status vm-pin@101-4-7.service
```

---

## CPU Core Allocation

| Cores | Assignment        |
| ----- | ----------------- |
| 0-1   | Proxmox Host      |
| 2-3   | VM 100 (OPNsense) |
| 4-7   | VM 101 (Ubuntu)   |


#### Opnsense Setup

After the VM reboots into OPNsense, configure the network interfaces:

**Step 1: Assign Interfaces**

1. Press `1` to assign interfaces
2. Configure LAGG? Enter `n`
3. Configure VLANs? Enter `n`
4. Interface assignment:
   - Available interfaces: `igc0` (Intel I226-V passthrough) and `vtnet0` (VirtIO bridge)
   - **WAN interface:** Enter `igc0`
   - **LAN interface:** Enter `vtnet0`
   - **Optional interfaces:** Press Enter to skip
5. Confirm with `y`

**Step 2: Set LAN IP Address**

1. Press `2` to set interface IP address
2. Select `1` for LAN

3. **IPv4 Configuration:**
   - Configure IPv4 address LAN interface via DHCP? `n`
   - Enter new LAN IPv4 address: `192.168.0.1`
   - Enter new LAN IPv4 subnet bit count: `24`
   - For a WAN, enter upstream gateway (press Enter for none): Press Enter

4. **IPv6 Configuration:**
   - Configure IPv6 address interface via WAN tracking? `n`
   - Configure IPv6 address LAN interface via DHCP6? `n`
   - Enter new LAN IPv6 address (press Enter for none): Press Enter

5. **DHCP Server:**
   - Enable DHCP server on LAN? `y`
   - Enter start address: `192.168.0.100`
   - Enter end address: `192.168.0.200`

6. **Web GUI:**
   - Change web GUI protocol from HTTPS to HTTP? `n`
   - Generate new self-signed web GUI certificate? `y`
   - Restore web GUI access defaults? `y`

After configuration completes, access the OPNsense web interface at `https://192.168.0.1` from a device on the LAN network (vmbr0). Default credentials are `root` / `opnsense`.

## Ubuntu Setup
Set up networking. Add to `/etc/netplan/50-cloud-init.yaml`
```bash
network:
  version: 2
  ethernets:
    enp6s18:
      dhcp4: no
      addresses:
        - 192.168.0.3/24
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
```

Update the system:

```bash
sudo apt update
sudo apt upgrade -y
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
sudo reboot
```
---
