#!/bin/bash

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <PCI_ID>"
    echo "Example: $0 0000:03:00.0"
    exit 1
fi

PCI_ID="$1"
SYSFS_PATH="/sys/bus/pci/devices/${PCI_ID}"

# Check PCI device existence
if [ ! -d "${SYSFS_PATH}" ]; then
    echo "Error: PCI device ${PCI_ID} not found"
    exit 1
fi

# Check SR-IOV support
if [ ! -f "${SYSFS_PATH}/sriov_totalvfs" ]; then
    echo "Error: This device does not support SR-IOV"
    exit 1
fi

TOTAL_VFS=$(cat "${SYSFS_PATH}/sriov_totalvfs")

if [ "${TOTAL_VFS}" -le 0 ]; then
    echo "Error: Maximum SR-IOV VF count is 0"
    exit 1
fi

echo "Detected maximum SR-IOV VFs: ${TOTAL_VFS}"

# Reset existing VFs if enabled
if [ -f "${SYSFS_PATH}/sriov_numvfs" ]; then
    CURRENT_VFS=$(cat "${SYSFS_PATH}/sriov_numvfs")
    if [ "${CURRENT_VFS}" -ne 0 ]; then
        echo "Currently enabled VFs: ${CURRENT_VFS}, resetting to 0..."
        echo 0 > "${SYSFS_PATH}/sriov_numvfs"
    fi
fi

# Enable maximum VFs
echo "Enabling ${TOTAL_VFS} VFs..."
echo "${TOTAL_VFS}" > "${SYSFS_PATH}/sriov_numvfs"

echo "SR-IOV configuration completed successfully"
