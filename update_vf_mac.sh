#!/bin/bash

# Usage:
#   update_vf_mac.sh <pf> <mac_prefix> [offset]

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <pf> <mac_prefix> [offset]"
    exit 1
fi

PF="$1"
MAC_PREFIX="$2"
OFFSET="${3:-0}"

# Validate PF
if ! ip link show "${PF}" >/dev/null 2>&1; then
    echo "Error: PF interface ${PF} not found"
    exit 1
fi

# Validate MAC prefix (5 bytes)
if ! [[ "${MAC_PREFIX}" =~ ^([0-9a-fA-F]{2}:){4}[0-9a-fA-F]{2}$ ]]; then
    echo "Error: mac_prefix must be 5 bytes (xx:xx:xx:xx:xx)"
    exit 1
fi

# Validate offset
if ! [[ "${OFFSET}" =~ ^[0-9]+$ ]]; then
    echo "Error: offset must be a non-negative integer"
    exit 1
fi

SYSFS_DEV="/sys/class/net/${PF}/device"

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

echo "PF        : ${PF}"
echo "VF count  : ${VF_COUNT}"
echo "MAC prefix: ${MAC_PREFIX}"
echo "Offset    : ${OFFSET}"
echo

for ((i=0; i<${VF_COUNT}; i++)); do
    LAST_BYTE=$((OFFSET + i))

    if [ "${LAST_BYTE}" -gt 255 ]; then
        echo "Error: MAC overflow at VF ${i}"
        exit 1
    fi

    MAC=$(printf "%s:%02x" "${MAC_PREFIX}" "${LAST_BYTE}")

    echo "VF ${i} -> MAC ${MAC}, trust on"

    # PF-side configuration
    ip link set "${PF}" vf "${i}" mac "${MAC}"
    ip link set "${PF}" vf "${i}" trust on

    # Update VF netdev MAC if VF exists on host (do NOT change link state)
    VF_NET_PATH="${SYSFS_DEV}/virtfn${i}/net"
    if [ -d "${VF_NET_PATH}" ]; then
        VF_NETDEV=$(ls "${VF_NET_PATH}" | head -n 1)
        if [ -n "${VF_NETDEV}" ]; then
            echo "  -> Updating VF netdev ${VF_NETDEV} MAC"
            ip link set "${VF_NETDEV}" address "${MAC}"
        fi
    fi
done

echo
echo "VF MAC and trust configuration completed (link state preserved)"
