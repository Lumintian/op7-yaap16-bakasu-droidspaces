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

# Droidspaces namespaces, cgroups, seccomp, overlayfs, and NAT prerequisites.
for key in \
  CONFIG_SYSCTL CONFIG_SYSVIPC CONFIG_POSIX_MQUEUE CONFIG_POSIX_MQUEUE_SYSCTL \
  CONFIG_NAMESPACES \
  CONFIG_PID_NS CONFIG_UTS_NS CONFIG_IPC_NS CONFIG_NET_NS CONFIG_CGROUPS \
  CONFIG_CGROUP_DEVICE CONFIG_CGROUP_PIDS CONFIG_CGROUP_SCHED \
  CONFIG_FAIR_GROUP_SCHED CONFIG_CGROUP_FREEZER CONFIG_CGROUP_NET_PRIO \
  CONFIG_SECCOMP CONFIG_SECCOMP_FILTER CONFIG_OVERLAY_FS \
  CONFIG_TMPFS_POSIX_ACL CONFIG_TMPFS_XATTR CONFIG_FW_LOADER \
  CONFIG_FW_LOADER_USER_HELPER CONFIG_VETH \
  CONFIG_BRIDGE CONFIG_NETFILTER CONFIG_BRIDGE_NETFILTER \
  CONFIG_NETFILTER_ADVANCED CONFIG_NF_CONNTRACK CONFIG_IP_NF_IPTABLES \
  CONFIG_IP_NF_FILTER CONFIG_NF_NAT \
  CONFIG_IP_NF_TARGET_MASQUERADE \
  CONFIG_NETFILTER_XT_TARGET_TCPMSS CONFIG_NETFILTER_XT_TARGET_CHECKSUM \
  CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
  CONFIG_NF_CT_NETLINK CONFIG_NF_NAT_REDIRECT \
  CONFIG_IP_ADVANCED_ROUTER CONFIG_IP_MULTIPLE_TABLES \
  CONFIG_NF_CONNTRACK_IPV4 CONFIG_NF_NAT_IPV4 CONFIG_IP_NF_NAT \
  CONFIG_NF_NAT_IPV6 CONFIG_NF_NAT_MASQUERADE_IPV6 \
  CONFIG_IP6_NF_NAT CONFIG_IP6_NF_TARGET_MASQUERADE \
  CONFIG_MACVLAN CONFIG_USER_NS; do
  expect_line "$key=y"
done

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
