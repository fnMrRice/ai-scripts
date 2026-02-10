#!/bin/bash

# Usage:
#   sriov_init_by_vendor.sh <vendor:device>
#
# Example:
#   sriov_init_by_vendor.sh 8086:158b

if [ $# -ne 1 ]; then
    echo "Usage: $0 <vendor:device>"
    exit 1
fi

VENDOR_DEVICE="$1"

if ! [[ "${VENDOR_DEVICE}" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]]; then
    echo "Error: vendor:device must be xxxx:xxxx"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ENABLE_SRIOV="${SCRIPT_DIR}/enable_sriov.sh"
UPDATE_MAC="${SCRIPT_DIR}/update_vf_mac_by_pci_id.sh"
BIND_VFIO="${SCRIPT_DIR}/bind_vf_to_vfio.sh"

for s in "${ENABLE_SRIOV}" "${UPDATE_MAC}" "${BIND_VFIO}"; do
    [ -f "${s}" ] || {
        echo "Error: required script not found: ${s}"
        exit 1
    }
done

# Build MAC prefix: 02:vendor:product
VENDOR="${VENDOR_DEVICE%%:*}"
PRODUCT="${VENDOR_DEVICE##*:}"

MAC_PREFIX=$(printf "02:%02x:%02x:%02x:%02x" \
    $((0x${VENDOR:0:2})) \
    $((0x${VENDOR:2:2})) \
    $((0x${PRODUCT:0:2})) \
    $((0x${PRODUCT:2:2}))
)

echo "Vendor:Device = ${VENDOR_DEVICE}"
echo "MAC prefix    = ${MAC_PREFIX}"
echo

# Find all matching PCI devices
PCI_LIST=($(lspci -Dn | awk -v vd="${VENDOR_DEVICE}" '$3 == vd {print $1}'))

PF_INDEX=0

for PCI_ID in "${PCI_LIST[@]}"; do
    SYSFS_PCI="/sys/bus/pci/devices/${PCI_ID}"

    # Skip VFs
    [ -e "${SYSFS_PCI}/physfn" ] && continue

    # Must support SR-IOV
    [ -f "${SYSFS_PCI}/sriov_totalvfs" ] || continue

    MAX_VFS=$(cat "${SYSFS_PCI}/sriov_totalvfs")
    OFFSET=$((PF_INDEX * MAX_VFS))

    echo "================================================="
    echo "PF PCI ID : ${PCI_ID}"
    echo "PF index  : ${PF_INDEX}"
    echo "Max VFs   : ${MAX_VFS}"
    echo "Offset    : ${OFFSET}"
    echo "================================================="

    echo "[1/3] Enable SR-IOV"
    bash "${ENABLE_SRIOV}" "${PCI_ID}" || continue

    echo
    echo "[2/3] Update VF MAC addresses"
    bash "${UPDATE_MAC}" "${PCI_ID}" "${MAC_PREFIX}" "${OFFSET}" || continue

    echo
    echo "[3/3] Bind VFs to vfio-pci"
    PF_IF=$(ls "${SYSFS_PCI}/net" | head -n 1)
    bash "${BIND_VFIO}" "${PF_IF}" || continue

    PF_INDEX=$((PF_INDEX + 1))
    echo
done

echo "SR-IOV initialization completed for vendor ${VENDOR_DEVICE}"
