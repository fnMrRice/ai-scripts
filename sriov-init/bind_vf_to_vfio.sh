#!/bin/bash

# Usage:
#   bind_vf_to_vfio.sh <pf>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <pf>"
    exit 1
fi

PF="$1"
SYSFS_DEV="/sys/class/net/${PF}/device"

# Validate PF
if ! ip link show "${PF}" >/dev/null 2>&1; then
    echo "Error: PF interface ${PF} not found"
    exit 1
fi

# Check SR-IOV
if [ ! -f "${SYSFS_DEV}/sriov_numvfs" ]; then
    echo "Error: SR-IOV not enabled on ${PF}"
    exit 1
fi

VF_COUNT=$(cat "${SYSFS_DEV}/sriov_numvfs")

if [ "${VF_COUNT}" -le 0 ]; then
    echo "Error: No VFs enabled on ${PF}"
    exit 1
fi

# Load vfio-pci
if ! lsmod | grep -q "^vfio_pci"; then
    echo "Loading vfio-pci module"
    modprobe vfio-pci || exit 1
fi

echo "PF       : ${PF}"
echo "VF count : ${VF_COUNT}"
echo

for ((i=0; i<${VF_COUNT}; i++)); do
    VF_PATH="${SYSFS_DEV}/virtfn${i}"

    [ -e "${VF_PATH}" ] || continue

    VF_PCI=$(basename "$(readlink -f "${VF_PATH}")")
    VF_SYS="/sys/bus/pci/devices/${VF_PCI}"

    echo "VF ${i}: PCI ${VF_PCI}"

    # Unbind current driver if exists
    if [ -L "${VF_SYS}/driver" ]; then
        CUR_DRIVER=$(basename "$(readlink -f ${VF_SYS}/driver)")
        if [ "${CUR_DRIVER}" = "vfio-pci" ]; then
            echo "  Already bound to vfio-pci"
            continue
        fi

        echo "  Unbinding from ${CUR_DRIVER}"
        echo "${VF_PCI}" > "/sys/bus/pci/drivers/${CUR_DRIVER}/unbind"
    fi

    # Read vendor and device ID
    VENDOR=$(cat "${VF_SYS}/vendor")
    DEVICE=$(cat "${VF_SYS}/device")

    echo "  Vendor: ${VENDOR}, Device: ${DEVICE}"

    # Register ID with vfio-pci (ignore error if already exists)
    echo "${VENDOR} ${DEVICE}" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true

    # Bind to vfio-pci
    echo "  Binding to vfio-pci"
    echo "${VF_PCI}" > /sys/bus/pci/drivers/vfio-pci/bind
done

echo
echo "All VFs successfully bound to vfio-pci"
