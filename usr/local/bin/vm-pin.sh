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
  log "ERROR" "invalid format '$input' (expected: vmid-cpulist, e.g., 100-2-3)"
  exit 1
fi

# Validate vmid is numeric
if ! echo "$vmid" | grep -Eq '^[0-9]+$'; then
  log "ERROR" "vmid '$vmid' is not numeric"
  exit 1
fi

# Validate cpulist format (basic check)
if ! echo "$cpulist" | grep -Eq '^[0-9,\-]+$'; then
  log "ERROR" "cpulist '$cpulist' contains invalid characters (expected: 0-2 or 0,2,4)"
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

# Wait for VM threads to spawn (vCPU threads may not exist immediately)
log "INFO" "waiting for VM threads to spawn..."
sleep 15

# Pin main process first
if ! taskset -pc "$cpulist" "$pid" >/dev/null 2>&1; then
  log "ERROR" "failed to set CPU affinity for main pid $pid to cpulist $cpulist"
  log "ERROR" "check if cpulist is valid for your system: lscpu"
  exit 1
fi

log "INFO" "pinned main process $pid to CPUs $cpulist"

# Pin all threads individually (including vCPU, vhost, and other threads)
thread_count=0
failed_count=0

if [ -d "/proc/$pid/task" ]; then
  for tid in /proc/$pid/task/*; do
    tid=$(basename "$tid")

    # Skip if thread no longer exists
    if ! [ -d "/proc/$pid/task/$tid" ]; then
      continue
    fi

    # Apply pinning to this thread
    if taskset -pc "$cpulist" "$tid" >/dev/null 2>&1; then
      thread_count=$((thread_count + 1))
    else
      failed_count=$((failed_count + 1))
      log "WARN" "failed to pin thread $tid"
    fi
  done
fi

log "INFO" "successfully pinned $thread_count threads to CPUs $cpulist"

if [ $failed_count -gt 0 ]; then
  log "WARN" "failed to pin $failed_count threads"
fi

# Verify affinity was set correctly for main process
actual_affinity=$(taskset -pc "$pid" 2>/dev/null | awk '{print $NF}')
log "INFO" "VM $vmid (pid $pid) affinity: $actual_affinity"

# Final verification - check a few threads to ensure pinning stuck
sleep 1
sample_threads=$(ls /proc/$pid/task/ 2>/dev/null | head -3)
verify_ok=0
verify_total=0

for tid in $sample_threads; do
  if [ -d "/proc/$pid/task/$tid" ]; then
    verify_total=$((verify_total + 1))
    thread_affinity=$(taskset -pc "$tid" 2>/dev/null | awk '{print $NF}' || echo "error")
    if [ "$thread_affinity" = "$cpulist" ]; then
      verify_ok=$((verify_ok + 1))
    else
      log "WARN" "thread $tid has affinity $thread_affinity (expected $cpulist)"
    fi
  fi
done

if [ $verify_total -gt 0 ] && [ $verify_ok -eq $verify_total ]; then
  log "INFO" "verification passed: all sampled threads correctly pinned"
elif [ $verify_total -gt 0 ]; then
  log "WARN" "verification: only $verify_ok/$verify_total sampled threads correctly pinned"
fi

exit 0
