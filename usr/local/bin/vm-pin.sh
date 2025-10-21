#!/bin/sh
# /usr/local/bin/vm-pin.sh <vmid>-<cpulist>
# Example instance: vm-pin@100-2-5.service (will pass "100-2-5" as $1)
#
# Pins a QEMU VM process to specific CPU cores for performance isolation.
#
set -eu

# Logging helper
log() {
  echo "vm-pin[$1]: $2" >&2
}

# Usage check
if [ $# -ne 1 ]; then
  log "ERROR" "usage: $0 <vmid>-<cpulist>"
  log "ERROR" "example: $0 100-2-5"
  exit 1
fi

# Parse vmid-cpulist with validation
input="$1"
vmid="${input%%-*}"
cpulist="${input#*-}"

# Validate parsing succeeded
if [ -z "$vmid" ] || [ -z "$cpulist" ] || [ "$vmid" = "$cpulist" ]; then
  log "ERROR" "invalid format '$input' (expected: vmid-cpulist, e.g., 100-2-5)"
  exit 1
fi

# Validate vmid is numeric
if ! echo "$vmid" | grep -Eq '^[0-9]+$'; then
  log "ERROR" "vmid '$vmid' is not numeric"
  exit 1
fi

# Validate cpulist format (basic check)
if ! echo "$cpulist" | grep -Eq '^[0-9,\-]+$'; then
  log "ERROR" "cpulist '$cpulist' contains invalid characters (expected: 0-3 or 0,2,4)"
  exit 1
fi

log "INFO" "attempting to pin VM $vmid to CPUs $cpulist"

pidfile="/var/run/qemu-server/${vmid}.pid"

# Wait up to 10 seconds for pidfile if VM just started
max_wait=20
found=0
for i in $(seq 1 $max_wait); do
  if [ -s "$pidfile" ]; then
    found=1
    if [ $i -gt 1 ]; then
      log "INFO" "pidfile found after $i attempts"
    fi
    break
  fi
  sleep 0.5
done

if [ $found -eq 0 ]; then
  log "ERROR" "pidfile not found for VM $vmid at $pidfile after ${max_wait} attempts"
  log "ERROR" "is the VM running? check: qm status $vmid"
  exit 1
fi

# Read and validate PID
pid=$(cat "$pidfile")
if [ -z "$pid" ]; then
  log "ERROR" "pidfile is empty for VM $vmid"
  exit 1
fi

if ! echo "$pid" | grep -Eq '^[0-9]+$'; then
  log "ERROR" "pidfile contains invalid PID: $pid"
  exit 1
fi

# Verify process is running
if ! kill -0 "$pid" 2>/dev/null; then
  log "ERROR" "process $pid not running (stale pidfile?)"
  exit 1
fi

# Get process name for verification
proc_name=""
if [ -r "/proc/$pid/comm" ]; then
  proc_name=$(cat "/proc/$pid/comm" 2>/dev/null || echo "unknown")
fi

log "INFO" "found QEMU process: pid=$pid comm=$proc_name"

# Apply CPU affinity
if ! taskset -pc "$cpulist" "$pid" >/dev/null 2>&1; then
  log "ERROR" "failed to set CPU affinity for pid $pid to cpulist $cpulist"
  log "ERROR" "check if cpulist is valid for your system: lscpu"
  exit 1
fi

# Verify affinity was set correctly
actual_affinity=$(taskset -pc "$pid" 2>/dev/null | awk '{print $NF}')
log "INFO" "successfully pinned VM $vmid (pid $pid) to CPUs: $actual_affinity"

exit 0
