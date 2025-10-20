#!/bin/sh
# /usr/local/bin/vm-pin.sh <vmid>-<cpulist>
# Example instance: vm-pin@100-2-5.service (will pass "100-2-5" as $1)
#
set -eu

IFS='-' read -r vmid cpulist <<EOF
$1
EOF

pidfile="/var/run/qemu-server/${vmid}.pid"

# wait a short while for pidfile if VM just started
for i in 1 2 3 4 5; do
  if [ -s "$pidfile" ]; then break; fi
  sleep 0.5
done

if [ ! -s "$pidfile" ]; then
  echo "vm-pin: pidfile not found for VM $vmid at $pidfile" >&2
  exit 1
fi

pid=$(cat "$pidfile")
if ! kill -0 "$pid" 2>/dev/null; then
  echo "vm-pin: process $pid not running" >&2
  exit 1
fi

# apply affinity to the QEMU process
taskset -pc "$cpulist" "$pid"
exit 0
