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
patch_file="$ROOT_DIR/$MANUAL_HOOK_PATCH"

require_cmd git
require_cmd python3
require_file "$patch_file"
assert_git_head "$kernel_dir" "$YAAP_KERNEL_COMMIT"
assert_git_head "$resuki_dir" "$RESUKI_COMMIT"
assert_git_clean "$kernel_dir"
assert_git_clean "$resuki_dir"

actual_patch_sha="$(sha256_file "$patch_file")"
[[ "$actual_patch_sha" == "$MANUAL_HOOK_PATCH_SHA256" ]] \
  || die "manual-hook patch checksum mismatch: $actual_patch_sha"

log 'Applying the exact YAAP 4.14 manual-hook patch'
git -C "$kernel_dir" apply --check "$patch_file"
git -C "$kernel_dir" apply "$patch_file"

log 'Wiring the pinned ReSuki checkout into the legacy drivers tree'
python3 - "$kernel_dir" "$resuki_dir" <<'PY'
import os
import pathlib
import sys

kernel = pathlib.Path(sys.argv[1]).resolve()
resuki = pathlib.Path(sys.argv[2]).resolve()
makefile = kernel / "drivers" / "Makefile"
kconfig = kernel / "drivers" / "Kconfig"
link = kernel / "drivers" / "kernelsu"

make_line = "obj-$(CONFIG_KSU) += kernelsu/"
make_text = makefile.read_text()
if make_line in make_text:
    raise SystemExit("error: ReSuki Makefile wiring already exists")
makefile.write_text(make_text.rstrip("\n") + "\n" + make_line + "\n")

source_line = 'source "drivers/kernelsu/Kconfig"'
kconfig_text = kconfig.read_text()
if source_line in kconfig_text:
    raise SystemExit("error: ReSuki Kconfig wiring already exists")
anchor = "\nendmenu\n"
if kconfig_text.count(anchor) != 1:
    raise SystemExit("error: expected one final drivers/Kconfig endmenu anchor")
kconfig.write_text(kconfig_text.replace(anchor, f"\n{source_line}\n\nendmenu\n"))

if link.exists() or link.is_symlink():
    raise SystemExit("error: drivers/kernelsu already exists")
target = os.path.relpath(resuki / "kernel", link.parent)
link.symlink_to(target)
if link.resolve() != (resuki / "kernel").resolve():
    raise SystemExit("error: drivers/kernelsu does not resolve to pinned ReSuki source")
PY

"$SCRIPT_DIR/run-upstream-checks.sh" "$kernel_dir" "$resuki_dir"
git -C "$kernel_dir" diff --check

expected_files="$(cat <<'EOF_EXPECTED'
drivers/Kconfig
drivers/Makefile
fs/exec.c
fs/open.c
fs/stat.c
kernel/cgroup/cgroup.c
kernel/reboot.c
security/selinux/selinuxfs.c
EOF_EXPECTED
)"
actual_files="$(git -C "$kernel_dir" diff --name-only -- | LC_ALL=C sort)"
[[ "$actual_files" == "$expected_files" ]] || {
  printf 'Expected tracked changes:\n%s\nActual tracked changes:\n%s\n' \
    "$expected_files" "$actual_files" >&2
  die 'prepared kernel changed files outside the allowlist'
}

[[ -L "$kernel_dir/drivers/kernelsu" ]] || die 'drivers/kernelsu symlink was not created'
log 'Kernel source preparation and pinned upstream checks passed'
