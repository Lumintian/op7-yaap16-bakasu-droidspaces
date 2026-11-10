# Immutable upstream inputs. Keep values shell-safe: this file is sourced by CI scripts.
YAAP_KERNEL_REPO=https://github.com/yaap/kernel_oneplus_sm8150.git
YAAP_KERNEL_COMMIT=3a3c6bb4fa9cbeca5aed90f46ba2d907980e2b56

RESUKI_REPO=https://github.com/Baka-SU/BakaSU.git
# Pinned BakaSU v4.2.0-rc3 release tag commit; keep the checkout immutable.
RESUKI_COMMIT=239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb

ANYKERNEL_REPO=https://github.com/osm0sis/AnyKernel3.git
ANYKERNEL_COMMIT=e4b1bb25ca2aabcfd57f694a5998d87130701b71

CLANG_PREBUILT_COMMIT=9916fb51ccb914d62d35ad9a7b9b21d2ef046928
CLANG_RELEASE=clang-r547379
CLANG_VERSION=20.0.0
CLANG_LLVM_REVISION=b718bcaf8c198c82f3021447d943401e3ab5bd54
CLANG_ARCHIVE_URL=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9916fb51ccb914d62d35ad9a7b9b21d2ef046928/clang-r547379.tar.gz

MANUAL_HOOK_PATCH=patches/0001-resukisu-manual-hooks-linux-4.14.patch
MANUAL_HOOK_PATCH_SHA256=3bf4861c48b4ca7715f169f728004cfe4ca4dce15f0a2ee85610121b0f5cad7a

DEVICE_CODENAME=guacamoleb
EXPECTED_ANDROID_VERSION=16
EXPECTED_ROM_VERSION=16-Banshee-guacamoleb-20260522
EXPECTED_ROM_INCREMENTAL=eng.androi.20260522.192638
EXPECTED_ROM_FINGERPRINT=OnePlus/yaap_guacamoleb/guacamoleb:16/BP4A.251205.006/eng.androi.20260522.192638:user/release-keys
EXPECTED_KERNEL_VERSION=4.14.336

KERNEL_DEFCONFIG=gulch_defconfig
KERNEL_DEBUG_FRAGMENT=vendor/debugfs.config
KERNEL_IMAGE_NAME=Image
KERNEL_LOCALVERSION=-yaap16-droidspaces-bakasu
BOOT_PARTITION_SIZE=100663296
