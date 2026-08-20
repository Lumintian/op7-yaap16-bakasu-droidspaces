#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

kernel_dir="${1:-}"
out_dir="${2:-}"
clang_dir="${3:-}"
fragment="${4:-$ROOT_DIR/config/yaap16-droidspaces-resukisu.fragment}"
[[ -n "$kernel_dir" && -n "$out_dir" && -n "$clang_dir" ]] \
  || die "usage: $0 <kernel-dir> <out-dir> <clang-dir> [config-fragment]"

kernel_dir="$(canonical_dir "$kernel_dir")"
clang_dir="$(canonical_dir "$clang_dir")"
fragment="$(cd -- "$(dirname -- "$fragment")" && pwd)/$(basename -- "$fragment")"
require_file "$fragment"
require_file "$kernel_dir/arch/arm64/configs/$KERNEL_DEFCONFIG"
require_file "$kernel_dir/arch/arm64/configs/$KERNEL_DEBUG_FRAGMENT"
assert_toolchain "$clang_dir"

case "$out_dir" in
  ''|'/') die 'refusing unsafe output directory' ;;
esac
if [[ -e "$out_dir" ]]; then
  [[ -d "$out_dir" ]] || die "output path is not a directory: $out_dir"
  [[ -z "$(find "$out_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
    || die "output directory must be empty: $out_dir"
else
  mkdir -p "$out_dir"
fi
out_dir="$(canonical_dir "$out_dir")"

export PATH="$clang_dir/bin:$PATH"
make_args=(-C "$kernel_dir" O="$out_dir" ARCH=arm64 LLVM=1 LLVM_IAS=1)

log "Generating $KERNEL_DEFCONFIG"
make "${make_args[@]}" "$KERNEL_DEFCONFIG"

log "Merging YAAP debug config and $(basename -- "$fragment")"
"$kernel_dir/scripts/kconfig/merge_config.sh" -m -O "$out_dir" \
  "$out_dir/.config" \
  "$kernel_dir/arch/arm64/configs/$KERNEL_DEBUG_FRAGMENT" \
  "$fragment"
make "${make_args[@]}" olddefconfig

require_file "$out_dir/.config"
python3 "$SCRIPT_DIR/verify-fragment.py" \
  "$kernel_dir/arch/arm64/configs/$KERNEL_DEBUG_FRAGMENT" "$out_dir/.config"
python3 "$SCRIPT_DIR/verify-fragment.py" "$fragment" "$out_dir/.config"
log "Generated and fragment-verified config: $out_dir/.config"
