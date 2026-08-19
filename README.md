# YAAP16 OnePlus 7：Droidspaces + ReSukiSU 内核构建器

本仓库是一个**仅针对 OnePlus 7（`guacamoleb`）和指定 YAAP16 版本**的 GitHub Actions 构建封装。它会：

- 从 YAAP 官方 Linux 4.14.336 内核的固定提交构建；
- 启用 `CONFIG_DEVTMPFS=y`，供 Droidspaces 硬件访问模式挂载 devtmpfs；
- 保持 `CONFIG_DEVTMPFS_MOUNT` 关闭，不改变 Android 主机 `/dev` 的启动挂载行为；
- 集成固定提交的 ReSukiSU，使用 Linux 4.14 支持的 manual hook；
- **不启用 SUSFS**；
- 生成仅替换内核 `Image`、保留当前 ramdisk/DTB/AVB flags 的 AnyKernel3 ZIP；
- 输出原始 `Image`、最终 `.config`、构建元数据及 SHA-256 校验文件。

> 当前代码已通过补丁、上游 hook 检查器、配置策略和打包安全规则的本地验证。真正用于刷机前，必须先让 GitHub Actions 完整编译成功，并按 [`docs/INSTALL.md`](docs/INSTALL.md) 完成备份和检查。

## 严格兼容范围

| 项目 | 固定值 |
|---|---|
| 设备 | OnePlus 7 `guacamoleb` |
| ROM | `16-Banshee-guacamoleb-20260522` |
| Android build | `BP4A.251205.006` |
| YAAP kernel | `3a3c6bb4fa9cbeca5aed90f46ba2d907980e2b56` |
| ReSukiSU | `06390a6acbb7e966b3e1cda00fc1b93e89f11086` |
| Clang | AOSP `clang-r547379`，prebuilt commit `9916fb51…` |
| AnyKernel3 | `e4b1bb25ca2aabcfd57f694a5998d87130701b71` |

刷机脚本同时检查设备名、Android 16、完整 build fingerprint 和 incremental。ROM 更新后会主动终止，而不是猜测兼容性。

## 快速开始

1. 将本目录创建为 Git 仓库并推送到你自己的 GitHub 仓库，默认分支使用 `main`。
2. 打开 **Actions → Build YAAP16 guacamoleb Droidspaces + ReSukiSU kernel → Run workflow**。
3. 等待所有步骤成功，下载 `YAAP16-guacamoleb-Droidspaces-ReSuki` artifact。
4. 在 artifact 目录校验：

   ```sh
   sha256sum -c SHA256SUMS
   # macOS: shasum -a 256 -c SHA256SUMS
   ```

5. 阅读并严格执行 [`docs/INSTALL.md`](docs/INSTALL.md)。

完整构建流程见 [`docs/BUILD.md`](docs/BUILD.md)。

## 安全设计

- 上游源码、Actions、工具链目录和补丁都使用不可变提交或 SHA-256 固定。
- ReSuki 完整 Git 历史用于生成稳定 version code；显示名称只使用 commit SHA，不依赖可后加的 tag。
- baseline/final `.config` 自动比较，只允许 `CONFIG_KSU*` 与 devtmpfs 两类变化。
- 最终配置强制 SELinux、无模块、`KALLSYMS_ALL=n`、manual hook、SUSFS 关闭。
- AnyKernel3 只处理当前 active slot；不改 ramdisk，不自动改 AVB flags。
- 原始 `Image` 仅供审计，**不能当作完整 `boot.img` 用 fastboot 直接刷入**。

## 目录

```text
.github/workflows/build.yml       固定版本的 CI 流程
config/pins.sh                    所有不可变输入和目标 ROM 标识
config/*.config                   baseline 与最终 Kconfig fragment
patches/                          YAAP 4.14 manual-hook 精确补丁
scripts/                          获取、验证、配置、构建和打包脚本
packaging/anykernel.sh            严格设备/ROM 检查的刷机脚本
tests/                            本地静态与策略测试
docs/BUILD.md                     CI 构建说明
docs/INSTALL.md                   刷机、验证和回滚说明
```

## 明确不包含

- 不包含或下载 ReSuki Manager APK；只应从 ReSukiSU 官方渠道获取与该内核兼容的管理器。
- 不提供 SUSFS、隐藏功能补丁或跨 ROM/跨设备兼容承诺。
- 不生成通用 boot image；ZIP 依赖设备上现有的、完全匹配的 YAAP boot image。

上游代码各自受其原许可证约束，详见 [`NOTICE.md`](NOTICE.md)。
