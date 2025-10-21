# Proxmox Setup (BTRFS RAID1 + IOMMU + VFIO)

Configuration repository for Proxmox VE with PCI passthrough, CPU pinning, and NUMA optimization.

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

### 3. Apply Changes

```bash
# Set execute permissions
chmod +x /usr/local/bin/vfio-bind-01:00.0.sh
chmod +x /usr/local/bin/vm-pin.sh

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
  --balloon 0
```

---

## Configuration Details

### VFIO PCI Passthrough

- **Device**: `0000:01:00.0` (Intel 82574L Gigabit Ethernet)
- **Vendor ID**: `8086`
- **Device ID**: `125c`

The `vfio-bind@.service` template allows binding any PCI device to vfio-pci at boot time. Create instances for additional devices as needed.

### CPU Pinning

The `vm-pin@.service` template pins VM QEMU processes to specific CPU cores for performance isolation.

**Usage**: `vm-pin@<vmid>-<cpulist>.service`

**Example**: `vm-pin@100-2-5.service` pins VM 100 to physical CPUs 2-5 (isolated cores)

### NUMA Configuration

OPNsense VM uses NUMA binding to ensure memory and CPU locality, reducing latency for network operations. The VM has 4 vCPUs (0-3) which are pinned via `vm-pin@100-2-5.service` to physical CPUs 2-5 (isolated cores). These cores are reserved for VM use via kernel parameters `isolcpus=2-7 nohz_full=2-7 rcu_nocbs=2-7`, leaving physical cores 0-1 for host system tasks.

---

## Customization

To adapt this setup for your hardware:

1. **PCI Device IDs**: Update vendor/device IDs in `vfio-bind-*.sh` scripts
2. **CPU Pinning**: Adjust CPU lists in `vm-pin@.service` instances based on your CPU topology
3. **NUMA Nodes**: Modify NUMA configuration based on `numactl --hardware` output
4. **Network Interfaces**: Update bridge and MAC addresses in VM configurations

---

## Troubleshooting

### IOMMU not enabled
- Check BIOS settings for VT-d/AMD-Vi
- Verify kernel command line contains `intel_iommu=on` or `amd_iommu=on`

### Device not binding to vfio-pci
- Check `systemctl status vfio-bind@01:00.0.service`
- Verify device ID matches: `lspci -nn | grep 01:00.0`
- Check dmesg for errors: `dmesg | grep vfio`

### CPU pinning not working
- Verify service is running: `systemctl status vm-pin@100-2-5.service`
- Check VM is running: `qm status 100`
- Verify affinity: `taskset -pc $(cat /var/run/qemu-server/100.pid)`
- Confirm isolated cores: `cat /sys/devices/system/cpu/isolated`
