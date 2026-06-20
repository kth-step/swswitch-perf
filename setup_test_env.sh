#!/usr/bin/env bash
set -uo pipefail

# Sets the environment up for running Pktgen-DPDK.
#
# Re-running this should be safe.
#
# Usage with optional parameters:
#   sudo TEST_CORES=1-4 ./setup_test_env.sh

# NOTE: If you change cores used in test scripts, update this.
TEST_CORES="${TEST_CORES:-1-5}"

# Disable any CPU idle state whose exit latency exceeds this (microseconds).
# Should keep POLL and C1, not C1E/C3/C6.
MAX_CSTATE_LAT_US="${MAX_CSTATE_LAT_US:-10}"

have() { command -v "$1" >/dev/null 2>&1; }

expand_cpus() {
  # "1-5,7" -> "1 2 3 4 5 7"
  local spec="$1" part lo hi c out=""
  local IFS=','
  for part in $spec; do
    if [[ "$part" == *-* ]]; then
      lo="${part%-*}"; hi="${part#*-}"
      for ((c=lo; c<=hi; c++)); do out+="$c "; done
    else
      out+="$part "
    fi
  done
  echo "$out"
}

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }

echo "=== Setting up test environment for cores: test_cores=$TEST_CORES ==="

# ----------------------------------------------------------------------------
# 1. Setup hugepages
# ----------------------------------------------------------------------------
./setup_1G_hugepages.sh

# ----------------------------------------------------------------------------
# 2. Disable deep C-states on the test cores
#    (possibly useful for latency tests).
# ----------------------------------------------------------------------------
cstate_total=0
for cpu in $(expand_cpus "$TEST_CORES"); do
  base="/sys/devices/system/cpu/cpu${cpu}/cpuidle"
  [ -d "$base" ] || { echo "cpu$cpu: no cpuidle dir; skipping"; continue; }
  n=0
  for st in "$base"/state*/; do
    [ -e "$st/disable" ] || continue
    lat=$(cat "$st/latency" 2>/dev/null || echo 0)
    if [ "${lat:-0}" -gt "$MAX_CSTATE_LAT_US" ]; then
      echo 1 > "$st/disable" 2>/dev/null && n=$((n+1))
    fi
  done
  [ "$n" -gt 0 ] && cstate_total=$((cstate_total+n))
done
echo "disabled $cstate_total deep C-state(s) (> ${MAX_CSTATE_LAT_US}us) across test cores"

# ----------------------------------------------------------------------------
# 3. Set CPU governor to performance
# ----------------------------------------------------------------------------
cpupower frequency-set --governor performance

# ----------------------------------------------------------------------------
# 4. Stop distributing IRQ handling across cores (defaults to core 0)
# ----------------------------------------------------------------------------
if have systemctl && systemctl is-active --quiet irqbalance; then
  systemctl stop irqbalance
fi
