#!/usr/bin/env python3
"""Reject final config changes outside the explicit Droidspaces/Docker/ReSukiSU allowlist."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_config(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        if raw.startswith("CONFIG_") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value
        elif raw.startswith("# CONFIG_") and raw.endswith(" is not set"):
            key = raw.split()[1]
            values[key] = "n"
    return values


DROIDSPACES_KEYS = {
    "CONFIG_BRIDGE",
    "CONFIG_BRIDGE_NETFILTER",
    "CONFIG_CGROUP_DEVICE",
    "CONFIG_CGROUP_FREEZER",
    "CONFIG_CGROUP_NET_PRIO",
    "CONFIG_CGROUP_PIDS",
    "CONFIG_CGROUP_SCHED",
    "CONFIG_CGROUPS",
    "CONFIG_DEVTMPFS",
    "CONFIG_DEVTMPFS_MOUNT",
    "CONFIG_FAIR_GROUP_SCHED",
    "CONFIG_FW_LOADER",
    "CONFIG_FW_LOADER_USER_HELPER",
    "CONFIG_IP_ADVANCED_ROUTER",
    "CONFIG_IPC_NS",
    "CONFIG_IP_MULTIPLE_TABLES",
    "CONFIG_IP_NF_FILTER",
    "CONFIG_IP_NF_IPTABLES",
    "CONFIG_IP_NF_NAT",
    "CONFIG_IP_NF_TARGET_MASQUERADE",
    "CONFIG_IP6_NF_NAT",
    "CONFIG_IP6_NF_TARGET_MASQUERADE",
    "CONFIG_MACVLAN",
    "CONFIG_NAMESPACES",
    "CONFIG_NETFILTER",
    "CONFIG_NETFILTER_ADVANCED",
    "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE",
    "CONFIG_NETFILTER_XT_MATCH_PHYSDEV",
    "CONFIG_NETFILTER_XT_TARGET_CHECKSUM",
    "CONFIG_NETFILTER_XT_TARGET_TCPMSS",
    "CONFIG_NET_NS",
    "CONFIG_NF_CONNTRACK",
    "CONFIG_NF_CONNTRACK_IPV4",
    "CONFIG_NF_CT_NETLINK",
    "CONFIG_NF_NAT",
    "CONFIG_NF_NAT_IPV4",
    "CONFIG_NF_NAT_IPV6",
    "CONFIG_NF_NAT_MASQUERADE_IPV6",
    "CONFIG_NF_NAT_REDIRECT",
    "CONFIG_OVERLAY_FS",
    "CONFIG_PID_NS",
    "CONFIG_POSIX_MQUEUE",
    "CONFIG_POSIX_MQUEUE_SYSCTL",
    "CONFIG_SECCOMP",
    "CONFIG_SECCOMP_FILTER",
    "CONFIG_SYSCTL",
    "CONFIG_SYSVIPC",
    "CONFIG_TMPFS_POSIX_ACL",
    "CONFIG_TMPFS_XATTR",
    "CONFIG_USER_NS",
    "CONFIG_UTS_NS",
    "CONFIG_VETH",
}


def allowed(key: str) -> bool:
    return key.startswith("CONFIG_KSU") or key in DROIDSPACES_KEYS


def effective(values: dict[str, str], key: str) -> str:
    # Invisible Kconfig entries have the same meaning as "is not set".
    return values.get(key, "n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("final", type=Path)
    args = parser.parse_args()

    baseline = parse_config(args.baseline)
    final = parse_config(args.final)
    changed = {
        key: (baseline.get(key, "<absent>"), final.get(key, "<absent>"))
        for key in sorted(baseline.keys() | final.keys())
        if effective(baseline, key) != effective(final, key)
    }
    unexpected = {key: values for key, values in changed.items() if not allowed(key)}

    print(f"config changes: {len(changed)}; allowlisted: {len(changed) - len(unexpected)}")
    for key, (before, after) in unexpected.items():
        print(f"UNEXPECTED {key}: {before} -> {after}")

    if unexpected:
        return 1
    print("CONFIG_DIFF_ALLOWLIST=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
