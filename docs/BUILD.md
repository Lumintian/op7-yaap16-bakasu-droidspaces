# 构建说明

## 1. 推荐方式：GitHub Actions

仓库只在 `workflow_dispatch` 或 `main` 分支相关构建文件变更时运行，不接受 `pull_request` 触发。工作流权限仅为 `contents: read`。

首次运行：

1. 把项目推送到 GitHub，默认分支设为 `main`。
2. 在仓库 Settings → Actions 中允许 GitHub Actions。
3. 进入 Actions 页面，手动运行构建工作流。
4. 完整成功后下载主 artifact；失败时会另行上传 `build.log`（如果已经进入编译阶段）。成功运行的 Summary 还会按固定的 ReSukiSU commit 查找 `build-manager.yml` 的 `Manager-release` artifact，并附上对应的 workflow run 和下载页面链接。

## 2. CI 实际执行的门禁

```text
固定 SHA 获取 YAAP / ReSukiSU / AnyKernel3
                   │
                   ▼
校验 AOSP clang-r547379 版本与 LLVM revision
                   │
                   ▼
应用 manual-hook patch，并连接 drivers/kernelsu
                   │
                   ▼
运行 ReSuki manual_hook_check.mk + static_export_check.mk
                   │
                   ▼
生成安全基准 .config（仅作差异基线，KSU=n、DEVTMPFS=n）
                   │
                   ▼
生成最终 .config（Droidspaces/嵌套 Docker 前置条件、ReSukiSU manual、DEVTMPFS=y、SUSFS=n）
                   │
                   ▼
拒绝 allowlist 外的任何 config 变化
                   │
                   ▼
使用固定时间、user、host、LOCALVERSION 构建 raw Image
                   │
                   ▼
AnyKernel3 打包、ZIP 自检、生成 SHA256SUMS
```

这里的 `*.fragment` 不是完整的 `.config`：安全基准 fragment 只服务于 CI 的差异安全门禁，`yaap16-kernel-overrides.fragment` 则合并到 YAAP defconfig 上生成实际编译配置。

最终必须满足的关键配置：

```text
CONFIG_NAMESPACES=y
CONFIG_PID_NS=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_PIDS=y
CONFIG_MEMCG=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_OVERLAY_FS=y
CONFIG_VETH=y
CONFIG_BRIDGE=y
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_NAT=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_DEVTMPFS=y
# CONFIG_DEVTMPFS_MOUNT is not set
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_KSU_TRACEPOINT_HOOK is not set
# CONFIG_KSU_SUSFS is not set
CONFIG_SECURITY_SELINUX=y
# CONFIG_MODULES is not set
# CONFIG_KALLSYMS_ALL is not set
```

## 3. Artifact 内容

```text
YAAP16-20260522-guacamoleb-Droidspaces-ReSuki-06390a6a.zip
Image-guacamoleb-06390a6a
kernel.config
build-info.txt
SHA256SUMS
```

`build-info.txt` 记录所有提交、ReSuki version code、内核 release、工具链身份、补丁/config/Image 哈希和确定性时间戳。

## 4. 本地可运行的检查

不下载源码、不编译内核时，可以运行：

```sh
make test
```

它会检查 shell/Python 语法、固定 SHA、补丁范围与哈希、Kconfig 策略、AnyKernel3 安全门禁，以及 workflow 中所有 Action 是否固定到 40 位 commit。

完整内核编译应留在 Linux GitHub runner。macOS 默认大小写不敏感的文件系统会让 YAAP 树中大小写不同的 netfilter 文件发生碰撞，不能作为权威构建环境。

Docker 运行时仍需在 Droidspaces 中选择 NAT 网络，并使用 ext4 `/data` 或 `rootfs.img`；Linux 4.14 容器建议切换到 `iptables-legacy`，Docker 遇到 cgroup/存储驱动不兼容时使用 `cgroupfs` 和 `vfs`。

## 5. 更新任一上游版本

不要只改一个 SHA 后直接刷机。至少需要：

1. 更新 `config/pins.sh` 中的提交。
2. 对新 YAAP commit 重新生成 manual-hook patch。
3. 重新计算并更新 `MANUAL_HOOK_PATCH_SHA256`。
4. 检查 ReSuki Kconfig、Kbuild、manual/static checker 和 SELinux compatibility path。
5. 重新确认 ROM kernel toolchain、defconfig、boot header、DTB/DTBO 和分区大小。
6. 让 config diff、完整编译和 ZIP 打包全部通过。
7. 在可恢复设备上进行启动、SELinux、root、Droidspaces、网络/GPU 与回滚测试。

任何一个固定提交变化，都应视为一个新的内核移植项目，而不是普通依赖升级。
