#!/bin/bash
set -euo pipefail

# This script takes the location of Pktgen-DPDK as a command-line argument.
# First, run setuptest_env.sh on every boot.

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires sudo privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

if [ $# -ne 1 ]; then
    echo "Error: Missing required argument"
    echo "Usage: sudo $0 <pktgen_directory>"
    echo "Example: sudo $0 /home/my_user/src/Pktgen-DPDK/"
    exit 1
fi
PKTGEN_DIR="${1%/}"
if [ ! -d "$PKTGEN_DIR" ]; then
    echo "Error: Directory '$PKTGEN_DIR' does not exist"
    exit 1
fi

PKTGEN_LCORES="1,2,3,4,5"
#TEST_SCRIPT="zero_load_latency.lua"
TEST_SCRIPT="rfc_2544_throughput.lua"
#TEST_SCRIPT="line_rate_test.lua"

echo "=== Creating veth pair ==="

# Create a veth pair for direct connection
ip link add veth1 type veth peer name veth2

# Cleanup trap
trap 'echo "Cleaning up interfaces..."; ip link del veth1 2>/dev/null || true' EXIT

# Disable IPv6
# Without this, you may see IPv6 SLAAC
sysctl -w net.ipv6.conf.veth1.disable_ipv6=1
sysctl -w net.ipv6.conf.veth2.disable_ipv6=1

# Bring up the interfaces
ip link set veth1 up
ip link set veth2 up

# AF_PACKET parameters
FRAME_SIZE=2048
BLOCK_SIZE=4096  # Using 4K blocks (power of 2, must be >= frame size)
FRAME_COUNT=512  # Number of frames per block

echo "=== Launching Pktgen ==="
export LUA_PATH="${LUA_PATH:-;;};$PKTGEN_DIR/?.lua"
taskset -c $PKTGEN_LCORES "$PKTGEN_DIR/builddir/app/pktgen" \
    -l $PKTGEN_LCORES --proc-type primary --file-prefix=pktgen_$$ \
    --no-pci \
    --vdev="net_af_packet0,iface=veth1,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    --vdev="net_af_packet1,iface=veth2,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    -- -P -m "[2:3].0" -m "[4:5].1" -T -f "$PKTGEN_DIR/scripts/$TEST_SCRIPT"

echo "=== veth pair test completed ==="
