#!/usr/bin/env bash
set -Eeuo pipefail

COMMON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$COMMON_DIR/.." && pwd)"
PINS_FILE="$ROOT_DIR/config/pins.sh"

if [[ ! -f "$PINS_FILE" ]]; then
  printf 'error: missing pins file: %s\n' "$PINS_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PINS_FILE"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_dir() {
  [[ -d "$1" ]] || die "directory not found: $1"
}

require_file() {
  [[ -f "$1" ]] || die "file not found: $1"
}

canonical_dir() {
  (cd -- "$1" && pwd -P)
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die 'neither sha256sum nor shasum is available'
  fi
}

assert_git_head() {
  local repo="$1" expected="$2" actual
  require_dir "$repo/.git"
  actual="$(git -C "$repo" rev-parse HEAD)"
  [[ "$actual" == "$expected" ]] || die "unexpected HEAD in $repo: $actual (expected $expected)"
}

assert_git_clean() {
  local repo="$1"
  git -C "$repo" diff --quiet -- || die "tracked files are modified in $repo"
  git -C "$repo" diff --cached --quiet -- || die "index is modified in $repo"
  [[ -z "$(git -C "$repo" ls-files --others --exclude-standard)" ]] || die "untracked files exist in $repo"
}

assert_toolchain() {
  local clang_dir="$1" version
  [[ -x "$clang_dir/bin/clang" ]] || die "clang executable not found in $clang_dir/bin"
  version="$("$clang_dir/bin/clang" --version)"
  grep -Fq "clang version $CLANG_VERSION" <<<"$version" || die "unexpected clang version"
  grep -Fq "$CLANG_LLVM_REVISION" <<<"$version" || die "unexpected LLVM revision"
}

cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  else
    sysctl -n hw.ncpu
  fi
}
