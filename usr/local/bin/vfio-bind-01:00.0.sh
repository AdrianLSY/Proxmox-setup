#!/bin/sh
# Bind 0000:01:00.0 to vfio-pci reliably at early boot.

DEV="0000:01:00.0"
VENDOR="8086"
DEVICE="125c"

# register id if needed (ignore errors)
echo $VENDOR $DEVICE > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true

# if a driver currently bound -> unbind it
if [ -L /sys/bus/pci/devices/$DEV/driver ]; then
  CUR=$(readlink -f /sys/bus/pci/devices/$DEV/driver)
  # only unbind if it's not already vfio-pci
  case "$CUR" in
    */vfio-pci) exit 0 ;;
    *) echo -n $DEV > "$CUR/unbind" 2>/dev/null || true ;;
  esac
fi

# bind to vfio
echo -n $DEV > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
