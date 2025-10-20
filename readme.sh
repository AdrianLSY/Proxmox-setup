# Proxmox Setup (Ext4 RAID1 + IOMMU + VFIO)

A repo for my Proxmox setup

---

## Steps

1. Replace these files with the versions from this repo:

   * `/etc/kernel/cmdline`
   * `/etc/modules-load.d/vfio.conf`
   * `/etc/network/interfaces`

2. Apply changes:

   ```bash
   proxmox-boot-tool refresh
   update-initramfs -u -k all
   ```

3. Reboot:

   ```bash
   reboot
   ```

4. Verify configuration:

   ```bash
   lspci -nnk | grep -A3 I226       # should show vfio-pci
   dmesg | grep -e DMAR -e IOMMU    # should show IOMMU enabled
   ip a                             # ensure vmbr0 is up
   ```

5. Install ISOs (example: OPNsense):

   ```bash
   wget -O /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2 \
     https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2 && \
     bunzip2 /var/lib/vz/template/iso/OPNsense-25.7-dvd-amd64.iso.bz2
   ```

6. Install VMs (example: OPNsense):

   ```bash
   qm create 100 --name opnsense --memory 16384 --cores 4 --sockets 1 --cpu host --machine q35
   qm set 100 --scsihw virtio-scsi-pci --scsi0 local-lvm:64,cache=writeback,discard=on,aio=native
   qm set 100 --ide2 local:iso/OPNsense-25.7-dvd-amd64.iso,media=cdrom
   qm set 100 --net0 virtio=BC:24:11:0D:0E:DE,bridge=vmbr0,queues=6
   qm set 100 --hostpci0 0000:01:00.0,pcie=1
   qm set 100 --boot "order=ide2;scsi0" --vga std --serial0 socket --balloon 0
   ```
