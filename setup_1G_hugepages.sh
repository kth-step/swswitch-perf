#!/usr/bin/env bash
set -euo pipefail

# Script to allocate and mount hugepages, with some mitigations for memory fragmentation.
#
# This script should not leave anything behind that isn't reset after a fresh boot.
# Note that the default location is /dev/hugepages1G.
#
# Usage:
#   sudo ./setup_1G_hugepages.sh [COUNT] [ATTEMPTS]
#
#   COUNT     number of 1GB pages to allocate    (default: 2)
#   ATTEMPTS  number of retries                  (default: 10)
#
# Optional:
#   MOUNT_DIR   where to mount the 1GB hugetlbfs (default: /dev/hugepages1G)
#               Note you may want to avoid /dev/hugepages, used by some other systems.
#

PAGESIZE_KB=1048576

WANT="${1:-2}"
ATTEMPTS="${2:-10}"
MOUNT_DIR="${MOUNT_DIR:-/dev/hugepages1G}"

# Tested OK with Ubuntu 26.04.
HP_DIR="/sys/kernel/mm/hugepages/hugepages-1048576kB"
NR_FILE="$HP_DIR/nr_hugepages"
PROACT_FILE="/proc/sys/vm/compaction_proactiveness"

mount_hugepages() {
    local dir="$1"
    local pagesize_bytes=$(( PAGESIZE_KB * 1024 ))

    if awk -v t="$dir" '$3=="hugetlbfs" && $2==t {f=1} END{exit !f}' /proc/mounts; then
        echo "hugetlbfs already mounted at $dir"
        return 0
    fi

    mkdir -p "$dir"

    mount -t hugetlbfs -o "pagesize=${pagesize_bytes}" nodev "$dir"

    echo "hugetlbfs now mounted at $dir"
}


if [[ $EUID -ne 0 ]]; then
    echo "Error: This script requires sudo privileges."
    echo "Please run with: sudo $0 $*"
    exit 1
fi

if [[ ! -d "$HP_DIR" ]]; then
    echo "Error: $HP_DIR not found."
    echo "       Kernel has no 1GB hugepage support (needs CONFIG_HUGETLB_PAGE"
    echo "       and a CPU with the pdpe1gb flag — check: grep pdpe1gb /proc/cpuinfo)."
    exit 1
fi

echo "Currently allocated hugepages: $(cat "$NR_FILE")"
echo

ORIG_PROACT=""
if [[ -w "$PROACT_FILE" ]]; then
    ORIG_PROACT="$(cat "$PROACT_FILE")"
fi

restore_proactiveness() {
    if [[ -n "$ORIG_PROACT" && -w "$PROACT_FILE" ]]; then
        echo "$ORIG_PROACT" > "$PROACT_FILE" 2>/dev/null || true
    fi
}
trap restore_proactiveness EXIT

#################################
# Step 1: free reclaimable memory

echo "Flushing buffers and dropping caches..."
sync
echo 3 > /proc/sys/vm/drop_caches

# Nudge the kernel to keep memory tidier during our retry window. Restored on exit.
if [[ -w "$PROACT_FILE" ]]; then
    echo 80 > "$PROACT_FILE"
fi

#####################################
# Step 2: compact + request, retrying

got=0
for ((i = 1; i <= ATTEMPTS; i++)); do
    echo 1 > /proc/sys/vm/compact_memory
    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo "$WANT" > "$NR_FILE"

    got="$(cat "$NR_FILE")"
    echo "    attempt $i: got $got / $WANT"

    if (( got >= WANT )); then
        break
    fi
    sleep 1
done

echo

########################
# Step 3: report + mount

if (( got >= WANT )); then
    echo "Success: $got x 1GB hugepage(s) allocated."
    echo
    mount_hugepages "$MOUNT_DIR"
    echo
    exit 0
fi

echo "Failure: got $got / $WANT"
exit 1
