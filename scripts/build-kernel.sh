#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

kernel_dir="${1:-}"
out_dir="${2:-}"
clang_dir="${3:-}"
log_file="${4:-$ROOT_DIR/work/build.log}"
[[ -n "$kernel_dir" && -n "$out_dir" && -n "$clang_dir" ]] \
  || die "usage: $0 <kernel-dir> <out-dir> <clang-dir> [build-log]"

kernel_dir="$(canonical_dir "$kernel_dir")"
out_dir="$(canonical_dir "$out_dir")"
clang_dir="$(canonical_dir "$clang_dir")"
require_file "$out_dir/.config"
require_cmd make
require_cmd tee
require_cmd strings
assert_git_head "$kernel_dir" "$YAAP_KERNEL_COMMIT"
assert_toolchain "$clang_dir"
"$SCRIPT_DIR/verify-config.sh" "$out_dir/.config"

source_date_epoch="$(git -C "$kernel_dir" show -s --format=%ct HEAD)"
build_timestamp="$(date -u -d "@$source_date_epoch" '+%a %b %d %H:%M:%S UTC %Y')"
jobs="${JOBS:-$(cpu_count)}"
mkdir -p "$(dirname -- "$log_file")"

export PATH="$clang_dir/bin:$PATH"
export SOURCE_DATE_EPOCH="$source_date_epoch"
export KBUILD_BUILD_TIMESTAMP="$build_timestamp"
export KBUILD_BUILD_USER=yaap-ci
export KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1

make_args=(
  -C "$kernel_dir"
  O="$out_dir"
  ARCH=arm64
  LLVM=1
  LLVM_IAS=1
  LOCALVERSION="$KERNEL_LOCALVERSION"
)

log "Building $KERNEL_IMAGE_NAME with $jobs jobs"
set +e
make -j"$jobs" "${make_args[@]}" "$KERNEL_IMAGE_NAME" 2>&1 | tee "$log_file"
build_status="${PIPESTATUS[0]}"
set -e
[[ "$build_status" -eq 0 ]] || die "kernel build failed with exit code $build_status"

image="$out_dir/arch/arm64/boot/$KERNEL_IMAGE_NAME"
require_file "$image"
image_size="$(wc -c < "$image" | tr -d '[:space:]')"
(( image_size > 1048576 )) || die "kernel image is implausibly small: $image_size bytes"
(( image_size < BOOT_PARTITION_SIZE )) \
  || die "kernel image exceeds the declared boot partition: $image_size bytes"

kernel_release="$(cat "$out_dir/include/config/kernel.release")"
[[ "$kernel_release" == "$EXPECTED_KERNEL_VERSION"* ]] \
  || die "unexpected kernel release: $kernel_release"
[[ "$kernel_release" == *"$KERNEL_LOCALVERSION" ]] \
  || die "kernel release lacks deterministic localversion: $kernel_release"
strings "$image" | grep -Fqm1 "Linux version $EXPECTED_KERNEL_VERSION" \
  || die 'built Image does not contain the expected Linux version string'

cat > "$out_dir/build-metadata.txt" <<EOF_METADATA
source_date_epoch=$source_date_epoch
build_timestamp=$build_timestamp
kernel_release=$kernel_release
image_size=$image_size
EOF_METADATA

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'image=%s\nkernel_release=%s\n' "$image" "$kernel_release" >> "$GITHUB_OUTPUT"
fi
log "Built $kernel_release ($image_size bytes)"
