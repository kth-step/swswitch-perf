#!/bin/bash
set -euo pipefail

# This script sets everything up (once per boot, or again after messing with system settings) to run Pktgen-DPDK measurements.
# It takes the location of DPDK as a command-line argument.

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires sudo privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

if [ $# -ne 1 ]; then
    echo "Error: Missing required argument"
    echo "Usage: sudo $0 <dpdk_directory>"
    echo "Example: sudo $0 /home/my_user/src/dpdk/"
    exit 1
fi
DPDK_DIR="${1%/}"
if [ ! -d "$DPDK_DIR" ]; then
    echo "Error: Directory '$DPDK_DIR' does not exist"
    exit 1
fi

# Set CPU governor to performance mode
cpupower frequency-set --governor performance

# Set hugepages
python3 "$DPDK_DIR/usertools/dpdk-hugepages.py" -p 1G --setup 2G
