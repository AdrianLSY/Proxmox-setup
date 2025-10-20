# Proxmox Setup (BTRFS RAID1 + IOMMU + VFIO)

A repo for my Proxmox setup

---

## Steps

1. Update kernel

   ```bash
   apt update && apt upgrade -y
   ```

2. Replace / Create these files with the versions from this repo:

   * `/etc/kernel/cmdline`
   * `/etc/network/interfaces`
   * `/etc/modules-load.d/vfio.conf`
   * `/etc/modprobe.d/vfio.conf`
   * `/etc/systemd/system/vfio-bind@.service`
   * `/usr/local/bin/vfio-bind-01:00.0.sh`

3. Update vfio-pci

   ```bash
   echo '8086 125c' > /sys/bus/pci/drivers/vfio-pci/new_id
   echo -n '0000:01:00.0' > /sys/bus/pci/drivers/vfio-pci/bind
   ```

4. Apply changes:

   ```bash
   chmod +x /usr/local/bin/vfio-bind-01:00.0.sh
   systemctl daemon-reload
   systemctl enable --now vfio-bind@01:00.0.service
   proxmox-boot-tool refresh
   printf '%s\n' vfio vfio_iommu_type1 vfio_pci vfio_virqfd >> /etc/initramfs-tools/modules
   update-initramfs -u -k all
   ```

5. Reboot:

   ```bash
   reboot
   ```

6. Install ISOs:

   ```bash
   wget -O /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2 \
     https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2 && \
     bunzip2 /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2
   ```

7. Install VMs:

   ```bash
   qm create 100 --name opnsense --memory 16384 --cores 4 --sockets 1 --cpu host --machine q35
   qm set 100 --scsihw virtio-scsi-pci --scsi0 local-btrfs:64,cache=writeback,discard=on,aio=native
   qm set 100 --ide2 local:iso/OPNsense-25.7-dvd-amd64.iso,media=cdrom
   qm set 100 --net0 virtio=BC:24:11:0D:0E:DE,bridge=vmbr0,queues=6
   qm set 100 --hostpci0 0000:01:00.0,pcie=1
   qm set 100 --boot "order=ide2;scsi0" --vga std --serial0 socket --balloon 0
   ```
