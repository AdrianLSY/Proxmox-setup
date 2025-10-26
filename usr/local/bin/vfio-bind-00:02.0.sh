#!/bin/sh
# /usr/local/bin/vfio-bind-00:02.0.sh
# Bind 0000:00:02.0 (Intel Alder Lake-N Graphics) to vfio-pci reliably at early boot.
#
# This script ensures the Intel integrated GPU is bound to the vfio-pci driver
# for passthrough to VMs, with proper error handling and verification.
#
set -eu

# Device configuration
DEV="0000:00:02.0"
VENDOR="8086"
DEVICE="46d0"

# Logging helper
log() {
  echo "vfio-bind[$DEV][$1]: $2" >&2
}

log "INFO" "starting VFIO binding process for Intel GPU"

# Check if device exists
if [ ! -e "/sys/bus/pci/devices/$DEV" ]; then
  log "ERROR" "PCI device $DEV does not exist"
  log "ERROR" "verify device with: lspci -nn | grep $DEV"
  exit 1
fi

# Verify device IDs match
actual_vendor=$(cat "/sys/bus/pci/devices/$DEV/vendor" 2>/dev/null | sed 's/0x//')
actual_device=$(cat "/sys/bus/pci/devices/$DEV/device" 2>/dev/null | sed 's/0x//')

if [ -z "$actual_vendor" ] || [ -z "$actual_device" ]; then
  log "ERROR" "failed to read device vendor/device IDs"
  exit 1
fi

if [ "$actual_vendor" != "$VENDOR" ] || [ "$actual_device" != "$DEVICE" ]; then
  log "WARN" "device ID mismatch: expected $VENDOR:$DEVICE, got $actual_vendor:$actual_device"
  log "WARN" "update script with correct IDs from: lspci -nn | grep $DEV"
  log "WARN" "proceeding with actual device IDs: $actual_vendor:$actual_device"
  VENDOR="$actual_vendor"
  DEVICE="$actual_device"
fi

# Check if vfio-pci module is loaded
if ! lsmod | grep -q "^vfio_pci"; then
  log "ERROR" "vfio_pci module not loaded"
  log "ERROR" "check /etc/modules-load.d/vfio.conf and initramfs configuration"
  exit 1
fi

log "INFO" "vfio_pci module is loaded"

# Check if device is already bound to vfio-pci
if [ -L "/sys/bus/pci/devices/$DEV/driver" ]; then
  current_driver=$(readlink -f "/sys/bus/pci/devices/$DEV/driver")
  driver_name=$(basename "$current_driver")

  case "$current_driver" in
    */vfio-pci)
      log "INFO" "device already bound to vfio-pci, nothing to do"
      exit 0
      ;;
    *)
      log "INFO" "device currently bound to: $driver_name"
      log "INFO" "unbinding from $driver_name"

      # Unbind from current driver
      if ! echo "$DEV" > "$current_driver/unbind" 2>/dev/null; then
        log "ERROR" "failed to unbind from $driver_name"
        exit 1
      fi

      log "INFO" "successfully unbound from $driver_name"
      ;;
  esac
else
  log "INFO" "device not currently bound to any driver"
fi

# Register device ID with vfio-pci (idempotent operation)
if echo "$VENDOR $DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null; then
  log "INFO" "registered device ID $VENDOR:$DEVICE with vfio-pci"
else
  # This can fail if ID is already registered, which is fine
  log "DEBUG" "device ID may already be registered (this is normal)"
fi

# Small delay to let udev settle
sleep 0.2

# Bind device to vfio-pci
log "INFO" "binding device to vfio-pci"
if ! echo "$DEV" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null; then
  log "ERROR" "failed to bind device to vfio-pci"

  # Provide diagnostic info
  if [ -e "/sys/bus/pci/devices/$DEV/driver" ]; then
    bound_to=$(readlink -f "/sys/bus/pci/devices/$DEV/driver")
    log "ERROR" "device is bound to: $(basename "$bound_to")"
  else
    log "ERROR" "device is not bound to any driver"
  fi

  exit 1
fi

# Verify final state
if [ ! -L "/sys/bus/pci/devices/$DEV/driver" ]; then
  log "ERROR" "device has no driver after bind operation"
  exit 1
fi

final_driver=$(readlink -f "/sys/bus/pci/devices/$DEV/driver")
if [ "$(basename "$final_driver")" != "vfio-pci" ]; then
  log "ERROR" "device bound to wrong driver: $(basename "$final_driver")"
  exit 1
fi

# Success - log device info
if [ -r "/sys/bus/pci/devices/$DEV/uevent" ]; then
  dev_info=$(grep "PCI_SLOT_NAME\|DRIVER" "/sys/bus/pci/devices/$DEV/uevent" 2>/dev/null || echo "")
  log "INFO" "binding successful: $dev_info"
else
  log "INFO" "binding successful"
fi

log "INFO" "device $DEV (Intel GPU) successfully bound to vfio-pci"
exit 0
