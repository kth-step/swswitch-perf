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
SWITCH_APP="/home/my_user/src/petr4/_build/install/default/bin/petr4"  # Petr4 path
P4_PROGRAM="./conditional_ffi.p4"  # P4 program
#P4_PROGRAM="./vss_v1model_fixtables_bmv2.p4"  # P4 program
#P4_PROGRAM="./fabric_border_router.p4"
P4_INCLUDE="/home/my_user/src/p4c/p4include"  # P4 include path
CPU_MASK="0x1"  # CPU mask for switch (CPU 0)
PKTGEN_LCORES="1,2,3,4"  # CPU cores for pktgen
#TEST_SCRIPT="zero_load_latency.lua"
TEST_SCRIPT="rfc_2544_throughput.lua"

# Hard-code the MAC addresses you want to use
VETH1_MAC="02:11:22:33:44:01"
VETH2_MAC="02:11:22:33:44:02"
S1ETH1_MAC="02:11:22:33:44:03"
S1ETH2_MAC="02:11:22:33:44:04"

check_mac_in_use() {
    local mac=$1
    # Normalize the MAC format for comparison
    mac=$(echo $mac | tr '[:upper:]' '[:lower:]' | tr -d ':.-')
    
    # Get all current MAC addresses in the system (normalized for comparison)
    local current_macs=$(ip -o link | awk '{print $(NF-2)}' | tr '[:upper:]' '[:lower:]' | tr -d ':.-')
    
    if echo "$current_macs" | grep -q "$mac"; then
        return 0  # MAC is in use
    else
        return 1  # MAC is not in use
    fi
}

echo "=== Setting up DPDK environment ==="

# Load required kernel modules
modprobe uio
modprobe uio_pci_generic
modprobe vfio-pci

# Create veth pairs with optimized settings
ip link add veth1 type veth peer name s1-eth1
ip link add veth2 type veth peer name s1-eth2

for mac in "$VETH1_MAC" "$VETH2_MAC" "$S1ETH1_MAC" "$S1ETH2_MAC"; do
    if check_mac_in_use "$mac"; then
        echo "Error: MAC address $mac is already in use. Please choose a different MAC address."
        exit 1
    fi
done
echo "All MAC addresses in configuration are available. Proceeding with setup..."

# Assign hard-coded MAC addresses
ip link set veth1 address $VETH1_MAC
ip link set veth2 address $VETH2_MAC
ip link set s1-eth1 address $S1ETH1_MAC
ip link set s1-eth2 address $S1ETH2_MAC

# Optimize the interfaces for better performance
# Increase ring buffer sizes
ip link set veth1 txqueuelen 1024
ip link set veth2 txqueuelen 1024
ip link set s1-eth1 txqueuelen 1024
ip link set s1-eth2 txqueuelen 1024

# Disable IPv6 only on the interfaces we're using
sysctl -w net.ipv6.conf.veth1.disable_ipv6=1
sysctl -w net.ipv6.conf.veth2.disable_ipv6=1
sysctl -w net.ipv6.conf.s1-eth1.disable_ipv6=1
sysctl -w net.ipv6.conf.s1-eth2.disable_ipv6=1

# Disable various kernel features that add overhead
for iface in veth1 veth2 s1-eth1 s1-eth2; do
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
ip link set s1-eth1 up
ip link set s1-eth2 up

# Configure IP addresses
ip addr add 10.0.0.1/24 dev veth1
ip addr add 10.0.0.2/24 dev veth2

# Set interrupt affinity to isolate network interrupts from our cores
for irq in $(grep eth /proc/interrupts | awk '{print $1}' | tr -d ':'); do
  echo 0 > /proc/irq/$irq/smp_affinity_list 2>/dev/null || true
done

# Set CPU to performance mode
cpupower frequency-set --governor performance

# Pin switch process to CPU 0 (using taskset)
echo "Starting petr4 P4 switch (pinned to CPU(s) with mask $CPU_MASK)..."
# Expand the tilde in paths
SWITCH_APP_PATH=$(eval echo $SWITCH_APP)
P4_PROGRAM_PATH=$(eval echo $P4_PROGRAM)
P4_INCLUDE_PATH=$(eval echo $P4_INCLUDE)

# Start the petr4 switch with the specified parameters
taskset $CPU_MASK $SWITCH_APP_PATH switch -i 1@s1-eth1 -i 2@s1-eth2 -I $P4_INCLUDE_PATH $P4_PROGRAM_PATH &
SWITCH_PID=$!

# Give the switch time to initialize
sleep 5

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
taskset -c $PKTGEN_LCORES pktgen -l $PKTGEN_LCORES --proc-type auto \
    --vdev="net_af_packet0,iface=veth1,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    --vdev="net_af_packet1,iface=veth2,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    -- -P -m "2.0" -m "3.1" -T -f $CURR_DIR/$TEST_SCRIPT

# Terminate the switch
echo "Sending termination signal to switch process..."
kill -TERM $SWITCH_PID 2>/dev/null || true
wait $SWITCH_PID 2>/dev/null || true

# Clean up
echo "Cleaning up interfaces..."
ip link del veth1 2>/dev/null || true
ip link del veth2 2>/dev/null || true

echo "Test completed"
