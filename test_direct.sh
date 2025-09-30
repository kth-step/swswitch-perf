#!/bin/bash

# This script takes the location of Pktgen-DPDK as a command-line argument.

# First, set up hugepages: sudo python3 dpdk-hugepages.py -p 1G --setup 2G

# Check if script is run with sudo
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
PKTGEN_DIR="$1"
# Verify PKTGEN_DIR exists
if [ ! -d "$PKTGEN_DIR" ]; then
    echo "Error: Directory '$PKTGEN_DIR' does not exist"
    exit 1
fi

# Configuration
HUGEPAGES=1024
PKTGEN_LCORES="1,2,3,4"  # CPU cores for pktgen
#TEST_SCRIPT="zero_load_latency.lua"
TEST_SCRIPT="rfc_2544_throughput.lua"
#TEST_SCRIPT="line_rate_test.lua"

echo "=== Setting up DPDK environment ==="

# Load required kernel modules
modprobe uio
modprobe uio_pci_generic
modprobe vfio-pci

# Create veth pairs for direct connection
ip link add veth1 type veth peer name veth2

# Optimize the interfaces for better performance
# Increase ring buffer sizes
ip link set veth1 txqueuelen 1024
ip link set veth2 txqueuelen 1024

# Disable IPv6 on the interfaces we're using
sysctl -w net.ipv6.conf.veth1.disable_ipv6=1
sysctl -w net.ipv6.conf.veth2.disable_ipv6=1

# Disable various kernel features that add overhead
for iface in veth1 veth2; do
  # Disable generic segmentation offload
  ethtool -K $iface gso off tso off gro off 2>/dev/null || true
  # Disable TCP segmentation offload
  ethtool -K $iface tx off rx off sg off 2>/dev/null || true
  # Set MTU
  ip link set $iface mtu 1500 2>/dev/null || true
done

# Bring up the interfaces
ip link set veth1 up
ip link set veth2 up

# Configure IP addresses
ip addr add 10.0.0.1/24 dev veth1
ip addr add 10.0.0.2/24 dev veth2

# Set interrupt affinity to isolate network interrupts
for irq in $(grep eth /proc/interrupts | awk '{print $1}' | tr -d ':'); do
  echo 0 > /proc/irq/$irq/smp_affinity_list 2>/dev/null || true
done

# Set CPU governor to performance mode
cpupower frequency-set --governor performance 2>/dev/null || true

# Start pktgen with correctly sized AF_PACKET options
echo "Starting pktgen with fixed AF_PACKET parameters..."
CURR_DIR=$(pwd)
cd $PKTGEN_DIR

# Calculate proper AF_PACKET parameters (block size must be >= frame size)
# Also, blocksz must be a power of 2
FRAME_SIZE=2048
BLOCK_SIZE=4096  # Using 4K blocks (power of 2)
FRAME_COUNT=512  # Number of frames per block

# Use taskset to pin pktgen to specific cores
echo "Running AF_PACKET direct test - no switch in between"
taskset -c $PKTGEN_LCORES pktgen -l $PKTGEN_LCORES --proc-type auto \
    --vdev="net_af_packet0,iface=veth1,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    --vdev="net_af_packet1,iface=veth2,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    -- -P -m "2.0" -m "3.1" -T -f $CURR_DIR/$TEST_SCRIPT

# Clean up
echo "Cleaning up interfaces..."
ip link del veth1 2>/dev/null || true

echo "Direct veth pair test completed"
