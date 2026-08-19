#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd curl
require_cmd tar

clang_dir="${1:-$ROOT_DIR/work/$CLANG_RELEASE}"
parent_dir="$(dirname -- "$clang_dir")"
mkdir -p "$parent_dir"

if [[ -x "$clang_dir/bin/clang" ]]; then
  log "Verifying cached $CLANG_RELEASE toolchain"
  assert_toolchain "$clang_dir"
  exit 0
fi

[[ ! -e "$clang_dir" ]] || die "incomplete toolchain directory already exists: $clang_dir"

tmp_dir="$(mktemp -d "$parent_dir/.clang.XXXXXX")"
archive="$tmp_dir/$CLANG_RELEASE.tar.gz"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

log "Downloading content-addressed AOSP $CLANG_RELEASE archive"
curl --fail --location --retry 5 --retry-all-errors --connect-timeout 30 \
  "$CLANG_ARCHIVE_URL" --output "$archive"

mkdir -p "$tmp_dir/extracted"
tar -xzf "$archive" -C "$tmp_dir/extracted"
printf '%s  %s\n' "$(sha256_file "$archive")" "$(basename -- "$archive")" \
  > "$tmp_dir/extracted/.archive.sha256"
printf 'commit=%s\nrelease=%s\nurl=%s\n' \
  "$CLANG_PREBUILT_COMMIT" "$CLANG_RELEASE" "$CLANG_ARCHIVE_URL" \
  > "$tmp_dir/extracted/.source"

assert_toolchain "$tmp_dir/extracted"
mv "$tmp_dir/extracted" "$clang_dir"
log "Verified toolchain installed at $clang_dir"
