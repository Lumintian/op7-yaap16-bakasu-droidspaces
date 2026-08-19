#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

kernel_dir="${1:-}"
resuki_dir="${2:-}"
[[ -n "$kernel_dir" && -n "$resuki_dir" ]] || die "usage: $0 <kernel-dir> <resuki-dir>"

kernel_dir="$(canonical_dir "$kernel_dir")"
resuki_dir="$(canonical_dir "$resuki_dir")"
require_cmd make
require_file "$resuki_dir/kernel/tools/manual_hook_check.mk"
require_file "$resuki_dir/kernel/tools/static_export_check.mk"

grep -Fq 'Support for kernel 3.4+' "$resuki_dir/kernel/Kconfig" \
  || die 'pinned ReSuki Kconfig no longer declares Linux 3.4+ manual-hook support'

tmp_makefile="$(mktemp)"
cleanup() {
  rm -f "$tmp_makefile"
}
trap cleanup EXIT

cat > "$tmp_makefile" <<EOF_MAKE
include $resuki_dir/kernel/tools/manual_hook_check.mk
include $resuki_dir/kernel/tools/static_export_check.mk
.PHONY: all
all:
	@printf '%s\\n' 'PINNED_RESUKI_SOURCE_CHECKS=PASS'
EOF_MAKE

make --no-print-directory -f "$tmp_makefile" \
  srctree="$kernel_dir" \
  VERSION=4 PATCHLEVEL=14 \
  REPO_NAME=ReSukiSU \
  CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y \
  CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y \
  CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y \
  all
