# Proxmox Setup (BTRFS RAID1 + IOMMU + VFIO)

A Configuration repository for Proxmox VE with PCI passthrough, CPU pinning, and NUMA optimization.
A reference by me for future me

Or YOU if you so happen to have this specific machine with the Intel Core 3-N355.
[Topton 6 LAN 2.5G i226-V - AliExpress](https://www.aliexpress.com/item/1005005942080539.html?spm=a2g0o.order_list.order_list_main.5.18ed1802mnKkhV)

BTRFS seems to fit my needs for a modern filesystem and integrated raid support on install. I did not want to manually configure ext4 with raid support.

I've had issues setting this up with ZFS and some time googgling and asking chatgpt. The issue points to extremely poor VM disk performance due to ZFS’s heavy sync and copy-on-write behavior. Even non-ZFS guests like UFS suffer because each guest write forces ZFS to flush its own transaction groups.

In short, ZFS adds too much overhead for VM workloads with frequent small writes, making installs and updates painfully slow. I dont have the patience to sit and wait for installs and updates to complete and have to benchmark opnsense performance under this constraint.

---

## Repository Structure

This repository mirrors the Proxmox filesystem structure. Files are organized by their target system paths:

```
.
├── etc
│   ├── initramfs-tools
│   │   └── modules
│   ├── kernel
│   │   └── cmdline
│   ├── modprobe.d
│   │   └── vfio.conf
│   ├── modules-load.d
│   │   └── vfio.conf
│   ├── network
│   │   └── interfaces
│   └── systemd
│       └── system
│           ├── vfio-bind@.service
│           └── vm-pin@.service
├── modprobe.d
├── README.md
└── usr
    └── local
        └── bin
            ├── vfio-bind-01:00.0.sh
            └── vm-pin.sh
```

To deploy, copy files from their repository path to the corresponding system path (e.g., `etc/kernel/cmdline` → `/etc/kernel/cmdline`).

---

## Setup Steps

### 1. Update System

```bash
apt-get update
apt-get upgrade -y
```

### 2. Deploy Configuration Files

Add a directory for hook scripts
```bash
mkdir /var/lib/vz/snippets/
```

Copy files from this repository to their corresponding system locations:

* `etc/kernel/cmdline` → `/etc/kernel/cmdline`
* `etc/network/interfaces` → `/etc/network/interfaces`
* `etc/modules-load.d/vfio.conf` → `/etc/modules-load.d/vfio.conf`
* `etc/modprobe.d/vfio.conf` → `/etc/modprobe.d/vfio.conf`
* `etc/initramfs-tools/modules` → `/etc/initramfs-tools/modules`
* `etc/systemd/system/vfio-bind@.service` → `/etc/systemd/system/vfio-bind@.service`
* `etc/systemd/system/vm-pin@.service` → `/etc/systemd/system/vm-pin@.service`
* `usr/local/bin/vfio-bind-01:00.0.sh` → `/usr/local/bin/vfio-bind-01:00.0.sh`
* `usr/local/bin/vm-pin.sh` → `/usr/local/bin/vm-pin.sh`
* `var/lib/vz/snippets/100.hook` → `/var/lib/vz/snippets/100.hook`

### 3. Apply Changes

```bash
# Set execute permissions
chmod +x /usr/local/bin/vfio-bind-01:00.0.sh
chmod +x /usr/local/bin/vm-pin.sh
chmod +x /var/lib/vz/snippets/100.hook

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable --now vfio-bind@01:00.0.service
systemctl enable --now vm-pin@100-2-5.service

# Update boot configuration and initramfs
proxmox-boot-tool refresh
update-initramfs -u -k all
```

### 4. Reboot

```bash
reboot
```

### 5. Verify Configuration

After reboot, verify IOMMU and VFIO setup:

```bash
# Check IOMMU is enabled
dmesg | grep -e IOMMU -e DMAR

# Verify PCI device is bound to vfio-pci
lspci -nnk -d 8086:125c

# Check service status
systemctl status vfio-bind@01:00.0.service
systemctl status vm-pin@100-2-5.service
```

### 6. Download ISOs

```bash
wget -O /var/lib/pve/local-btrfs/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2 \
  https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2

bunzip2 /var/lib/pve/local-btrfs/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2
```

### 7. Create VMs

#### OPNsense Router VM (ID: 100)

```bash
qm create 100 \
  --name opnsense \
  --memory 16384 \
  --cores 4 \
  --sockets 1 \
  --cpu host \
  --machine q35

qm set 100 \
  --numa 1 \
  --numa0 cpus=0-3,hostnodes=0,memory=16384,policy=bind

qm set 100 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-btrfs:64,cache=none,discard=on,aio=native

qm set 100 \
  --ide2 local-btrfs:iso/OPNsense-25.7-dvd-amd64.iso,media=cdrom

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

# Enable hook script for automatic CPU pinning on VM start
qm set 100 --hookscript local:snippets/100.hook
```

### 8. Start VM and Verify CPU Pinning

The hook script will automatically apply CPU pinning when the VM starts.

```bash
# Start the VM
qm start 100

# Wait a moment for the hook to execute, then verify
sleep 2

# Check hook execution in system logs
journalctl -t "vm-hook[100]" --since "1 minute ago"

# Verify CPU pinning was applied
systemctl status vm-pin@100-2-5.service

# Check CPU affinity
taskset -pc $(cat /var/run/qemu-server/100.pid)
```

**Note:** The hook script (`/var/lib/vz/snippets/100.hook`) automatically triggers CPU pinning every time the VM starts, whether from a manual start or after a host reboot. This guarantees the VM is always pinned to the correct cores.

#### OPNsense Installation

Access the VM console through Proxmox web UI and proceed with installation:

1. **Login credentials:**
   - Username: `installer`
   - Password: `opnsense`

2. **Installation options:**
   - Choose **UFS** filesystem (recommended for best network performance)
   - UFS with soft updates provides lower overhead than ZFS
   - Accept default partitioning scheme
   - When prompted for 8GB swap: select **Yes**

3. **Post-installation:**
   - After installation completes and VM reboots, remove the ISO:
     ```bash
     qm set 100 --delete ide2
     ```

#### Initial Interface Configuration

After the VM reboots into OPNsense, configure the network interfaces:

**Step 1: Assign Interfaces**

1. Press `1` to assign interfaces
2. Configure LAGG? Enter `no`
3. Configure VLANs? Enter `no`
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
   - Configure IPv4 address LAN interface via DHCP? `no`
   - Enter new LAN IPv4 address: `192.168.0.1`
   - Enter new LAN IPv4 subnet bit count: `24`
   - For a WAN, enter upstream gateway (press Enter for none): Press Enter

4. **IPv6 Configuration:**
   - Configure IPv6 address interface via WAN tracking? `no`
   - Configure IPv6 address LAN interface via DHCP6? `no`
   - Enter new LAN IPv6 address (press Enter for none): Press Enter

5. **DHCP Server:**
   - Enable DHCP server on LAN? `yes`
   - Enter start address: `192.168.0.100`
   - Enter end address: `192.168.0.200`

6. **Web GUI:**
   - Change web GUI protocol from HTTPS to HTTP? `no`
   - Generate new self-signed web GUI certificate? `yes`
   - Restore web GUI access defaults? `yes`

After configuration completes, access the OPNsense web interface at `https://192.168.0.1` from a device on the LAN network (vmbr0). Default credentials are `root` / `opnsense`.
