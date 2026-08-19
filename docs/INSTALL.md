# 安装、验证与回滚

## 风险提示

自定义内核可能导致 bootloop、数据不可访问或安全边界变化。以下步骤只适用于：

- OnePlus 7，codename `guacamoleb`；
- `16-Banshee-guacamoleb-20260522`；
- 完整 fingerprint：
  `OnePlus/yaap_guacamoleb/guacamoleb:16/BP4A.251205.006/eng.androi.20260522.192638:user/release-keys`；
- bootloader 已解锁，并且你已验证恢复环境和 fastboot 可用。

不要用于 OnePlus 7 Pro 或其他 YAAP16 构建。

## 1. 刷机前检查

连接已正常启动的系统：

```sh
adb shell getprop ro.product.device
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.incremental
adb shell getprop ro.build.fingerprint
adb shell uname -r
```

预期分别包含：

```text
guacamoleb
16
eng.androi.20260522.192638
OnePlus/yaap_guacamoleb/guacamoleb:16/BP4A.251205.006/eng.androi.20260522.192638:user/release-keys
4.14.336
```

然后在解压后的 CI artifact 目录执行：

```sh
sha256sum -c SHA256SUMS
# macOS 使用：shasum -a 256 -c SHA256SUMS
```

任何一项不匹配都应停止。

## 2. 备份当前 active-slot boot image

优先使用你已验证可工作的 custom recovery 的 Boot 分区备份功能，并把备份复制到电脑和另一处离线存储。

也可在 recovery 的 root shell 中备份。先读取 slot，再使用该 slot 对应的完整 boot 分区：

```sh
adb reboot recovery
adb shell getprop ro.boot.slot_suffix
# 输出应为 _a 或 _b；以下以 _a 为例，必须按实际值替换
adb shell 'dd if=/dev/block/bootdevice/by-name/boot_a of=/sdcard/boot-before-resuki-a.img bs=4M && sync'
adb pull /sdcard/boot-before-resuki-a.img
sha256sum boot-before-resuki-a.img
```

部分 recovery 的路径是 `/dev/block/by-name/boot_a`。先用 `ls -l` 确认真实分区，不要猜路径，也不要把 A 槽备份当成 B 槽镜像。

记录以下信息并离线保存：

- active slot；
- boot 备份文件名、字节数和 SHA-256；
- 原始 YAAP ROM 包；
- 当前可用 recovery/fastboot 操作方法。

## 3. 刷入 ZIP

1. 只使用 CI 成功产出的 `YAAP16-20260522-guacamoleb-Droidspaces-ReSuki-06390a6a.zip`。
2. 在 custom recovery 中刷入或 sideload 该 ZIP。
3. AnyKernel3 会再次检查设备、Android 版本、完整 fingerprint 和 incremental；不匹配时应在写入前终止。
4. ZIP 只替换当前 active slot 的 kernel `Image`，保留现有 ramdisk、DTB 相关元数据和 AVB flags。
5. 刷完后先保留 recovery/fastboot 连接条件，再重启系统。

`Image-guacamoleb-06390a6a` 是供审计的 raw kernel，**不是完整 boot image，不能执行 `fastboot flash boot Image-...`**。

## 4. 首次启动验证

启动后先做基础安全检查：

```sh
adb wait-for-device
adb shell uname -r
adb shell getenforce
adb shell 'grep -w devtmpfs /proc/filesystems'
adb shell 'cat /proc/mounts | grep " /dev "'
```

预期：

- kernel release 以 `4.14.336` 开头，并包含 `-yaap16-droidspaces-resuki`；
- SELinux 返回 `Enforcing`；
- `/proc/filesystems` 包含 `devtmpfs`；
- Android 主机 `/dev` 仍可保持原有 tmpfs/ueventd 模型。`CONFIG_DEVTMPFS_MOUNT` 被刻意关闭，因此不要用“主机 `/dev` 必须已经是 devtmpfs”作为成功标准。

如果内核暴露配置，还可检查：

```sh
adb shell 'zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_(DEVTMPFS|KSU|KSU_MANUAL_HOOK|KSU_SUSFS)"'
```

随后：

1. 从 ReSukiSU 官方渠道安装与该内核兼容的 Manager；本 artifact 不捆绑 APK。
2. 确认 Manager 显示内核集成，版本名应包含 `06390a6a@ReSukiSU`。
3. 只给测试终端临时授权 root，确认授权/撤销正常。
4. 运行 Droidspaces v6.5.0 的完整内核检查，确认 devtmpfs 从缺失变为通过，原来已通过的项目没有回退。
5. 创建测试空间，依次检查启动、网络、DNS、存储、GPU/硬件访问和停止/删除。
6. 重启一次，确认不是偶然成功。

## 5. 回滚

### 能进入 recovery

把此前保存的**同一 slot 完整 boot 备份**推回设备，并写回对应分区：

```sh
adb push boot-before-resuki-a.img /sdcard/
adb shell 'dd if=/sdcard/boot-before-resuki-a.img of=/dev/block/bootdevice/by-name/boot_a bs=4M conv=fsync && sync'
```

路径和 `_a`/`_b` 必须按备份记录确认。写完重启并重新检查 `uname -r`。

### 只能进入 bootloader/fastboot

```sh
fastboot getvar current-slot
# 如果确认故障槽和备份都是 a：
fastboot flash boot_a boot-before-resuki-a.img
fastboot reboot
```

不要跨槽刷备份，不要在不理解当前 slot 状态时先切槽。若没有可靠备份，提取并刷回**同一 YAAP16 20260522 ROM** 的正确 boot image，或按该 ROM 的官方恢复流程重装。

回滚后若仍异常，应停止重复刷写，保留 recovery log、`build-info.txt`、CI `build.log` 和设备启动日志再分析。
