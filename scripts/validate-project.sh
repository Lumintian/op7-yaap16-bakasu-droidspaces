#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd bash
require_cmd python3

for script in "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/packaging/anykernel.sh; do
  bash -n "$script"
done

python3 -m py_compile \
  "$ROOT_DIR/scripts/verify-config-diff.py" \
  "$ROOT_DIR/scripts/verify-fragment.py"
python3 -m unittest discover -s "$ROOT_DIR/tests" -p 'test_*.py' -v

actual_patch_sha="$(sha256_file "$ROOT_DIR/$MANUAL_HOOK_PATCH")"
[[ "$actual_patch_sha" == "$MANUAL_HOOK_PATCH_SHA256" ]] \
  || die "patch checksum differs from config/pins.sh: $actual_patch_sha"

log 'Project validation passed'
