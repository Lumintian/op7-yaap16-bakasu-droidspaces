#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

anykernel_dir="${1:-}"
kernel_dir="${2:-}"
resuki_dir="${3:-}"
clang_dir="${4:-}"
out_dir="${5:-}"
artifact_dir="${6:-$ROOT_DIR/artifacts}"
[[ -n "$anykernel_dir" && -n "$kernel_dir" && -n "$resuki_dir" && -n "$clang_dir" && -n "$out_dir" ]] \
  || die "usage: $0 <anykernel-dir> <kernel-dir> <resuki-dir> <clang-dir> <out-dir> [artifact-dir]"

anykernel_dir="$(canonical_dir "$anykernel_dir")"
kernel_dir="$(canonical_dir "$kernel_dir")"
resuki_dir="$(canonical_dir "$resuki_dir")"
clang_dir="$(canonical_dir "$clang_dir")"
out_dir="$(canonical_dir "$out_dir")"
image="$out_dir/arch/arm64/boot/$KERNEL_IMAGE_NAME"
config="$out_dir/.config"

require_cmd zip
require_cmd unzip
require_cmd install
require_cmd python3
require_file "$image"
require_file "$config"
require_file "$ROOT_DIR/packaging/anykernel.sh"
assert_git_head "$anykernel_dir" "$ANYKERNEL_COMMIT"
assert_git_head "$kernel_dir" "$YAAP_KERNEL_COMMIT"
assert_git_head "$resuki_dir" "$RESUKI_COMMIT"
assert_toolchain "$clang_dir"

case "$artifact_dir" in
  ''|'/') die 'refusing unsafe artifact directory' ;;
esac
if [[ -e "$artifact_dir" ]]; then
  [[ -d "$artifact_dir" ]] || die "artifact path is not a directory: $artifact_dir"
  [[ -z "$(find "$artifact_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
    || die "artifact directory must be empty: $artifact_dir"
else
  mkdir -p "$artifact_dir"
fi
artifact_dir="$(canonical_dir "$artifact_dir")"
stage="$(mktemp -d "$artifact_dir/.anykernel.XXXXXX")"
cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

cp -a "$anykernel_dir/." "$stage/"
rm -rf "$stage/.git" "$stage/.github" "$stage/modules" "$stage/patch" "$stage/ramdisk"
rm -f "$stage/README.md" "$stage/anykernel.sh"
install -m 0755 "$ROOT_DIR/packaging/anykernel.sh" "$stage/anykernel.sh"
install -m 0644 "$image" "$stage/Image"
install -m 0644 "$config" "$stage/kernel.config"

kernel_release="$(cat "$out_dir/include/config/kernel.release")"
source_date_epoch="$(git -C "$kernel_dir" show -s --format=%ct HEAD)"
source_date_iso="$(python3 - "$source_date_epoch" <<'PY'
import datetime
import sys
print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
resuki_count="$(git -C "$resuki_dir" rev-list --count HEAD)"
resuki_version_code="$((30700 + resuki_count))"
clang_line="$("$clang_dir/bin/clang" --version | head -n1)"
clang_archive_sha=not-recorded
if [[ -f "$clang_dir/.archive.sha256" ]]; then
  clang_archive_sha="$(awk '{print $1}' "$clang_dir/.archive.sha256")"
fi

cat > "$stage/build-info.txt" <<EOF_INFO
project=YAAP16 Droidspaces + ReSukiSU kernel
artifact_target=$EXPECTED_ROM_VERSION
expected_fingerprint=$EXPECTED_ROM_FINGERPRINT
device=$DEVICE_CODENAME
android=$EXPECTED_ANDROID_VERSION
kernel_release=$kernel_release
kernel_repo=$YAAP_KERNEL_REPO
kernel_commit=$YAAP_KERNEL_COMMIT
resuki_repo=$RESUKI_REPO
resuki_commit=$RESUKI_COMMIT
resuki_version_code=$resuki_version_code
resuki_version_name=${RESUKI_COMMIT:0:8}@ReSukiSU
anykernel_repo=$ANYKERNEL_REPO
anykernel_commit=$ANYKERNEL_COMMIT
clang_prebuilt_commit=$CLANG_PREBUILT_COMMIT
clang_release=$CLANG_RELEASE
clang_archive_sha256=$clang_archive_sha
clang_version=$clang_line
manual_hook_patch_sha256=$MANUAL_HOOK_PATCH_SHA256
source_date_epoch=$source_date_epoch
source_date_utc=$source_date_iso
susfs=disabled
devtmpfs=enabled
devtmpfs_mount=disabled
image_size=$(wc -c < "$image" | tr -d '[:space:]')
image_sha256=$(sha256_file "$image")
config_sha256=$(sha256_file "$config")
EOF_INFO

(
  cd "$stage"
  : > SHA256SUMS
  for file in Image kernel.config build-info.txt; do
    printf '%s  %s\n' "$(sha256_file "$file")" "$file" >> SHA256SUMS
  done
)

# Fixed mtimes and sorted entries make the inner flashable ZIP reproducible.
python3 - "$stage" "$source_date_epoch" <<'PY'
import os
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
epoch = int(sys.argv[2])
for path in sorted(root.rglob("*"), reverse=True):
    os.utime(path, (epoch, epoch), follow_symlinks=False)
os.utime(root, (epoch, epoch), follow_symlinks=False)
PY
short_resuki="${RESUKI_COMMIT:0:8}"
zip_name="YAAP16-20260522-${DEVICE_CODENAME}-Droidspaces-ReSuki-${short_resuki}.zip"
zip_path="$artifact_dir/$zip_name"
(
  cd "$stage"
  LC_ALL=C find . -mindepth 1 -print | LC_ALL=C sort | zip -X -9 -y "$zip_path" -@
)
unzip -tq "$zip_path"

image_name="Image-${DEVICE_CODENAME}-${short_resuki}"
install -m 0644 "$image" "$artifact_dir/$image_name"
install -m 0644 "$config" "$artifact_dir/kernel.config"
install -m 0644 "$stage/build-info.txt" "$artifact_dir/build-info.txt"
(
  cd "$artifact_dir"
  : > SHA256SUMS
  for file in "$zip_name" "$image_name" kernel.config build-info.txt; do
    printf '%s  %s\n' "$(sha256_file "$file")" "$file" >> SHA256SUMS
  done
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'artifact_name=%s\nzip_name=%s\n' \
    "YAAP16-${DEVICE_CODENAME}-Droidspaces-ReSuki" "$zip_name" >> "$GITHUB_OUTPUT"
fi
log "Packaged $zip_path"
