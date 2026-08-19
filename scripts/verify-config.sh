#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

config="${1:-}"
[[ -n "$config" ]] || die "usage: $0 <kernel-.config>"
require_file "$config"

expect_line() {
  local expected="$1"
  grep -Fxq "$expected" "$config" || die "required config line missing: $expected"
}

expect_line 'CONFIG_DEVTMPFS=y'
expect_line '# CONFIG_DEVTMPFS_MOUNT is not set'
expect_line 'CONFIG_KSU=y'
expect_line '# CONFIG_KSU_DEBUG is not set'
expect_line '# CONFIG_KSU_TOOLKIT_SUPPORT is not set'
expect_line 'CONFIG_KSU_FULL_NAME_FORMAT="%COMMIT_SHA%@%REPO_NAME%"'
expect_line 'CONFIG_KSU_MULTI_MANAGER_SUPPORT=y'
expect_line '# CONFIG_KSU_TRACEPOINT_HOOK is not set'
expect_line 'CONFIG_KSU_MANUAL_HOOK=y'
expect_line '# CONFIG_KSU_SUSFS is not set'
expect_line 'CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y'
expect_line 'CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y'
expect_line 'CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y'

# Preserve the shipped Android security/build model.
expect_line 'CONFIG_SECURITY_SELINUX=y'
expect_line 'CONFIG_SECURITY_SELINUX_DEVELOP=y'
expect_line '# CONFIG_SECURITY_SELINUX_DISABLE is not set'
expect_line 'CONFIG_DEFAULT_SECURITY="selinux"'
expect_line '# CONFIG_MODULES is not set'
expect_line 'CONFIG_KALLSYMS=y'
if grep -Fxq 'CONFIG_KALLSYMS_ALL=y' "$config"; then
  die 'CONFIG_KALLSYMS_ALL was unexpectedly enabled'
fi

if grep -Eq '^CONFIG_KSU_SUSFS(_[A-Z0-9_]+)?=y$' "$config"; then
  die 'SUSFS or a SUSFS subfeature was unexpectedly enabled'
fi

log 'Final config assertions passed (manual hooks, devtmpfs, no SUSFS)'
