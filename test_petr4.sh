#!/bin/bash
set -euo pipefail

# This script takes the location of Pktgen-DPDK as a command-line argument.

# First, run setup_test_env.sh on every boot.

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires sudo privileges."
    echo "Please run with: sudo $0 <pktgen_directory>"
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

# Petr4 P4 interpreter
SWITCH_APP="/home/my_user/src/petr4/_build/install/default/bin/petr4"
# Your P4 program
P4_PROGRAM="./conditional_ffi.p4"
#P4_PROGRAM="./vss_v1model_fixtables_bmv2.p4"
#P4_PROGRAM="./fabric_border_router.p4"
# P4 include path
P4_INCLUDE="/home/my_user/src/p4c/p4include"
# CPU mask for switch (CPU 1), note 1-indexation
CPU_MASK="0x2"
PKTGEN_LCORES="0,2,3"
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

echo "=== Setting up veth pairs ==="

# Create veth pairs with optimized settings
ip link add veth1 type veth peer name s1-eth1
ip link add veth2 type veth peer name s1-eth2

# Cleanup trap
cleanup() {
    echo "Cleaning up..."
    [[ -n "${SWITCH_PID:-}" ]] && kill -TERM "$SWITCH_PID" 2>/dev/null || true
    [[ -n "${SWITCH_PID:-}" ]] && wait "$SWITCH_PID" 2>/dev/null || true

    for iface in veth1 veth2; do
        ip link del "$iface" 2>/dev/null || true
    done

    for iface in veth1 veth2 s1-eth1 s1-eth2; do
        iptables -D OUTPUT -o "$iface" -p udp --dport 5353 -j DROP 2>/dev/null || true
    done
}
trap cleanup EXIT

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

# Disable IPv6
# Without this, you may see IPv6 SLAAC
sysctl -w net.ipv6.conf.veth1.disable_ipv6=1
sysctl -w net.ipv6.conf.veth2.disable_ipv6=1
sysctl -w net.ipv6.conf.s1-eth1.disable_ipv6=1
sysctl -w net.ipv6.conf.s1-eth2.disable_ipv6=1

# Disable kernel features that may add overhead
for iface in s1-eth1 s1-eth2; do
    ethtool -K $iface gro off 2>/dev/null || true
done

# Block mDNS traffic specifically on test interfaces
iptables -A OUTPUT -o veth1 -p udp --dport 5353 -j DROP
iptables -A OUTPUT -o veth2 -p udp --dport 5353 -j DROP
iptables -A OUTPUT -o s1-eth1 -p udp --dport 5353 -j DROP
iptables -A OUTPUT -o s1-eth2 -p udp --dport 5353 -j DROP

# Bring up the interfaces
ip link set veth1 up
ip link set veth2 up
ip link set s1-eth1 up
ip link set s1-eth2 up

# Configure IP addresses
# TODO: Needed?
ip addr add 10.0.0.1/24 dev veth1
ip addr add 10.0.0.2/24 dev veth2

# Paranoia
sleep 1

echo "Starting petr4 P4 switch (pinned to CPU(s) with mask $CPU_MASK)..."
taskset $CPU_MASK "$SWITCH_APP" switch -i 1@s1-eth1 -i 2@s1-eth2 -I "$P4_INCLUDE" "$P4_PROGRAM" &
SWITCH_PID=$!

# Give the switch time to initialize
sleep 5

# AF_PACKET parameters
FRAME_SIZE=2048
BLOCK_SIZE=4096  # Using 4K blocks (power of 2, must be >= frame size)
FRAME_COUNT=512  # Number of frames per block

echo "=== Launching Pktgen ==="
export LUA_PATH="${LUA_PATH:-;;};$PKTGEN_DIR/?.lua"
taskset -c $PKTGEN_LCORES "$PKTGEN_DIR/builddir/app/pktgen" -l $PKTGEN_LCORES --proc-type primary --file-prefix=pktgen_$$ --no-pci \
    --vdev="net_af_packet0,iface=veth1,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    --vdev="net_af_packet1,iface=veth2,qpairs=1,blocksz=$BLOCK_SIZE,framesz=$FRAME_SIZE,framecnt=$FRAME_COUNT" \
    -- -P -m "2.0" -m "3.1" -T -f "$PKTGEN_DIR/scripts/$TEST_SCRIPT"

echo "=== petr4 test completed ==="
