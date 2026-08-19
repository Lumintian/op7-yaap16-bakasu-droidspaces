#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_cmd git

work_dir="${1:-$ROOT_DIR/work}"
mkdir -p "$work_dir"
work_dir="$(canonical_dir "$work_dir")"

fetch_shallow_commit() {
  local name="$1" url="$2" commit="$3" destination="$4"
  [[ ! -e "$destination" ]] || die "$name destination already exists: $destination"

  log "Fetching pinned $name commit $commit"
  git init -q "$destination"
  git -C "$destination" remote add origin "$url"
  git -C "$destination" -c protocol.version=2 fetch --quiet --depth=1 --no-tags origin "$commit"
  git -C "$destination" checkout --quiet --detach FETCH_HEAD
  assert_git_head "$destination" "$commit"
  assert_git_clean "$destination"
}

fetch_full_resuki_history() {
  local destination="$1" shallow
  [[ ! -e "$destination" ]] || die "ReSukiSU destination already exists: $destination"

  log "Fetching full ReSukiSU history for deterministic version code"
  git clone --quiet --filter=blob:none --no-checkout "$RESUKI_REPO" "$destination"
  git -C "$destination" fetch --quiet --force --tags origin
  git -C "$destination" checkout --quiet --detach "$RESUKI_COMMIT"
  assert_git_head "$destination" "$RESUKI_COMMIT"
  assert_git_clean "$destination"
  shallow="$(git -C "$destination" rev-parse --is-shallow-repository)"
  [[ "$shallow" == false ]] || die 'ReSukiSU checkout is shallow; version metadata would be wrong'
}

fetch_shallow_commit 'YAAP kernel' "$YAAP_KERNEL_REPO" "$YAAP_KERNEL_COMMIT" "$work_dir/kernel"
fetch_full_resuki_history "$work_dir/resuki"
fetch_shallow_commit 'AnyKernel3' "$ANYKERNEL_REPO" "$ANYKERNEL_COMMIT" "$work_dir/anykernel"

log "Pinned source checkouts are ready in $work_dir"
