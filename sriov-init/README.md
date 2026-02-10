# SR-IOV 初始化脚本说明

本目录包含一组用于在 Linux 上配置 SR-IOV（Single Root I/O Virtualization）和管理 VF（Virtual Function）的辅助脚本。大多数脚本需要以 root 权限运行。

**Scripts**

- `enable_sriov.sh`: 在指定的 PCI 设备上启用 SR-IOV（将 `sriov_numvfs` 设置为最大值）。
	- 用法: `enable_sriov.sh <PCI_ID>`，例如 `enable_sriov.sh 0000:03:00.0`
	- 作用: 检查设备是否支持 SR-IOV，重置已启用的 VFs（若存在），并将 VF 数设置为设备支持的最大值。

- `update_vf_mac.sh`: 为指定 PF（物理网口）上的每个 VF 设置连续的 MAC 地址并打开 trust。
	- 用法: `update_vf_mac.sh <pf> <mac_prefix> [offset]`，其中 `mac_prefix` 为 5 字节，例如 `02:aa:bb:cc:dd`。
	- 作用: 通过 `ip link set <pf> vf <i> mac <MAC>` 和 `ip link set <pf> vf <i> trust on` 设置每个 VF 的 MAC；若 VF 在宿主机上有 netdev，也会更新 netdev 的 MAC（不改动链路状态）。

- `update_vf_mac_by_pci_id.sh`: 根据 PF 的 PCI ID 查找其网口并调用 `update_vf_mac.sh`。
	- 用法: `update_vf_mac_by_pci_id.sh <PCI_ID> <mac_prefix> [offset]`
	- 作用: 将 PCI ID 映射到 PF 接口名并转发参数到 `update_vf_mac.sh`。

- `bind_vf_to_vfio.sh`: 将指定 PF 上的所有 VF 绑定到 `vfio-pci` 驱动。
	- 用法: `bind_vf_to_vfio.sh <pf>`（`<pf>` 为 PF 的网络接口名，例如 `eth0`）
	- 作用: 为每个 VF 查找 PCI ID，读取 vendor/device id，向 `vfio-pci` 注册并将 VF 绑定到 `vfio-pci` 驱动。若 VF 已是 `vfio-pci`，则跳过。

- `sriov_init_by_vendor.sh`: 按 `vendor:device`（如 `8086:158b`）批量对匹配的 PF 执行 SR-IOV 初始化流程（启用 SR-IOV、设置 VF MAC、绑定 vfio）。
	- 用法: `sriov_init_by_vendor.sh <vendor:device>`，例如 `sriov_init_by_vendor.sh 8086:158b`
	- 作用: 查找所有匹配的 PF（跳过已是 VF 的设备），按顺序调用 `enable_sriov.sh`、`update_vf_mac_by_pci_id.sh`、`bind_vf_to_vfio.sh`。

注意事项
- 所有脚本假设在常见的 Linux sysfs 路径（如 `/sys/bus/pci/devices`、`/sys/class/net`）和常用工具（`ip`、`lspci`、`modprobe`）可用。
- 执行脚本通常需要 root 权限（或使用 `sudo`）。
- 在生产环境变更之前，建议先在测试环境验证或先查看相关 sysfs 文件（如 `sriov_totalvfs`、`sriov_numvfs`）。

示例流程

1. 启用 PF 的 SR-IOV（按 PCI ID）：

```
sudo ./enable_sriov.sh 0000:03:00.0
```

2. 为 PF 分配 VF MAC 并打开 trust：

```
sudo ./update_vf_mac_by_pci_id.sh 0000:03:00.0 02:aa:bb:cc:dd
```

3. 将 PF 的 VFs 绑定到 vfio：

```
sudo ./bind_vf_to_vfio.sh eth0
```

或对整个厂商/设备批量运行：

```
sudo ./sriov_init_by_vendor.sh 8086:158b
```

