#!/bin/bash

# Usage:
#   update_vf_mac_by_pci_id.sh <pci_id> <mac_prefix> [offset]
#
# Example:
#   update_vf_mac_by_pci_id.sh 0000:03:00.0 02:aa:bb:cc:dd 32

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <pci_id> <mac_prefix> [offset]"
    exit 1
fi

PCI_ID="$1"
MAC_PREFIX="$2"
OFFSET="$3"

SYSFS_PCI="/sys/bus/pci/devices/${PCI_ID}"

# Validate PCI device
if [ ! -d "${SYSFS_PCI}" ]; then
    echo "Error: PCI device ${PCI_ID} not found"
    exit 1
fi

# Check PF capability (SR-IOV)
if [ ! -f "${SYSFS_PCI}/sriov_totalvfs" ]; then
    echo "Error: PCI device ${PCI_ID} is not a PF or does not support SR-IOV"
    exit 1
fi

# Get PF interface name(s)
NET_PATH="${SYSFS_PCI}/net"

if [ ! -d "${NET_PATH}" ]; then
    echo "Error: No network interface found for PCI device ${PCI_ID}"
    exit 1
fi

# Use the first interface by default
PF=$(ls "${NET_PATH}" | head -n 1)

if [ -z "${PF}" ]; then
    echo "Error: Failed to resolve PF interface from PCI ID ${PCI_ID}"
    exit 1
fi

echo "PCI ID : ${PCI_ID}"
echo "PF     : ${PF}"
echo

# Locate update_vf_mac.sh (same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="${SCRIPT_DIR}/update_vf_mac.sh"

if [ ! -f "${UPDATE_SCRIPT}" ]; then
    echo "Error: update_vf_mac.sh not found"
    exit 1
fi

# Forward arguments
if [ -n "${OFFSET}" ]; then
    bash "${UPDATE_SCRIPT}" "${PF}" "${MAC_PREFIX}" "${OFFSET}"
else
    bash "${UPDATE_SCRIPT}" "${PF}" "${MAC_PREFIX}"
fi
