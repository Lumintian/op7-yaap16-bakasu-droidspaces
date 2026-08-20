from __future__ import annotations

import hashlib
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PINS = (ROOT / "config/pins.sh").read_text()


def pin(name: str) -> str:
    match = re.search(rf"^{re.escape(name)}=(.+)$", PINS, re.MULTILINE)
    if not match:
        raise AssertionError(f"missing pin: {name}")
    return match.group(1)


class ProjectTests(unittest.TestCase):
    def test_all_git_inputs_are_immutable(self) -> None:
        for name in (
            "YAAP_KERNEL_COMMIT",
            "RESUKI_COMMIT",
            "ANYKERNEL_COMMIT",
            "CLANG_PREBUILT_COMMIT",
            "CLANG_LLVM_REVISION",
        ):
            self.assertRegex(pin(name), r"^[0-9a-f]{40}$", name)
        self.assertIn(pin("CLANG_PREBUILT_COMMIT"), pin("CLANG_ARCHIVE_URL"))
        self.assertIn(pin("CLANG_RELEASE"), pin("CLANG_ARCHIVE_URL"))

    def test_manual_hook_patch_is_pinned_and_scoped(self) -> None:
        patch_path = ROOT / pin("MANUAL_HOOK_PATCH")
        patch = patch_path.read_bytes()
        self.assertEqual(hashlib.sha256(patch).hexdigest(), pin("MANUAL_HOOK_PATCH_SHA256"))
        text = patch.decode()
        files = re.findall(r"^diff --git a/(\S+) b/", text, re.MULTILINE)
        self.assertEqual(
            files,
            [
                "fs/exec.c",
                "fs/open.c",
                "fs/stat.c",
                "kernel/reboot.c",
                "security/selinux/selinuxfs.c",
            ],
        )
        for symbol in (
            "ksu_handle_execveat",
            "ksu_handle_faccessat",
            "ksu_handle_stat",
            "ksu_handle_newfstat_ret",
            "ksu_handle_fstat64_ret",
            "ksu_handle_sys_reboot",
        ):
            self.assertIn(symbol, text)
        self.assertNotIn("SUSFS", text.upper())

    def test_final_fragment_selects_droidspaces_docker_and_manual_hook(self) -> None:
        config = (ROOT / "config/yaap16-kernel-overrides.fragment").read_text()
        required = (
            "CONFIG_SYSCTL=y",
            "CONFIG_SYSVIPC=y",
            "CONFIG_POSIX_MQUEUE=y",
            "CONFIG_POSIX_MQUEUE_SYSCTL=y",
            "CONFIG_NAMESPACES=y",
            "CONFIG_PID_NS=y",
            "CONFIG_UTS_NS=y",
            "CONFIG_IPC_NS=y",
            "CONFIG_NET_NS=y",
            "CONFIG_CGROUPS=y",
            "CONFIG_CGROUP_DEVICE=y",
            "CONFIG_CGROUP_PIDS=y",
            "CONFIG_CGROUP_SCHED=y",
            "CONFIG_FAIR_GROUP_SCHED=y",
            "CONFIG_CGROUP_FREEZER=y",
            "CONFIG_CGROUP_NET_PRIO=y",
            "CONFIG_SECCOMP=y",
            "CONFIG_SECCOMP_FILTER=y",
            "CONFIG_DEVTMPFS=y",
            "# CONFIG_DEVTMPFS_MOUNT is not set",
            "CONFIG_OVERLAY_FS=y",
            "CONFIG_TMPFS_POSIX_ACL=y",
            "CONFIG_TMPFS_XATTR=y",
            "CONFIG_FW_LOADER=y",
            "CONFIG_FW_LOADER_USER_HELPER=y",
            "CONFIG_VETH=y",
            "CONFIG_BRIDGE=y",
            "CONFIG_NETFILTER=y",
            "CONFIG_BRIDGE_NETFILTER=y",
            "CONFIG_NETFILTER_ADVANCED=y",
            "CONFIG_NF_CONNTRACK=y",
            "CONFIG_IP_NF_IPTABLES=y",
            "CONFIG_IP_NF_FILTER=y",
            "CONFIG_NF_NAT=y",
            "CONFIG_IP_NF_TARGET_MASQUERADE=y",
            "CONFIG_NETFILTER_XT_TARGET_TCPMSS=y",
            "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y",
            "CONFIG_NF_CT_NETLINK=y",
            "CONFIG_NF_NAT_REDIRECT=y",
            "CONFIG_IP_ADVANCED_ROUTER=y",
            "CONFIG_IP_MULTIPLE_TABLES=y",
            "CONFIG_NF_CONNTRACK_IPV4=y",
            "CONFIG_NF_NAT_IPV4=y",
            "CONFIG_IP_NF_NAT=y",
            "CONFIG_USER_NS=y",
            "CONFIG_KSU=y",
            "CONFIG_KSU_MANUAL_HOOK=y",
            "# CONFIG_KSU_TRACEPOINT_HOOK is not set",
            "# CONFIG_KSU_SUSFS is not set",
        )
        for line in required:
            self.assertIn(line, config)
        self.assertNotRegex(config, r"^CONFIG_KSU_SUSFS(?:_[A-Z0-9_]+)?=y$", re.MULTILINE)
        for omitted in (
            "CONFIG_MEMCG=y",
            "CONFIG_NF_TABLES=y",
            "CONFIG_CFS_BANDWIDTH=y",
            "CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y",
        ):
            self.assertNotIn(omitted, config)
        allowlist = (ROOT / "scripts/verify-config-diff.py").read_text()
        self.assertIn('"CONFIG_POSIX_MQUEUE_SYSCTL"', allowlist)
        self.assertIn('"CONFIG_NETFILTER_XT_MATCH_PHYSDEV"', allowlist)

    def test_resuki_pin_is_current_main_head(self) -> None:
        self.assertEqual(pin("RESUKI_COMMIT"), "06390a6acbb7e966b3e1cda00fc1b93e89f11086")

    def test_anykernel_has_strict_device_rom_and_boot_safety_guards(self) -> None:
        script = (ROOT / "packaging/anykernel.sh").read_text()
        self.assertIn("\ndo.devicecheck=1\n", script)
        self.assertIn("device.name1=guacamoleb", script)
        self.assertIn("supported.versions=16", script)
        self.assertIn(pin("EXPECTED_ROM_FINGERPRINT"), script)
        self.assertIn(pin("EXPECTED_ROM_INCREMENTAL"), script)
        self.assertIn("IS_SLOT_DEVICE=1", script)
        self.assertIn("SLOT_SELECT=active", script)
        self.assertIn("PATCH_VBMETA_FLAG=0", script)
        self.assertIn("split_boot;", script)
        self.assertIn("flash_boot;", script)
        self.assertNotIn("write_boot;", script)

    def test_workflow_actions_are_sha_pinned_and_not_pr_triggered(self) -> None:
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        uses = re.findall(r"^\s*uses:\s*([^\s]+)$", workflow, re.MULTILINE)
        self.assertGreaterEqual(len(uses), 4)
        for action in uses:
            self.assertRegex(action, r"^[^@]+@[0-9a-f]{40}$")
        self.assertNotRegex(workflow, r"^\s*pull_request\s*:", re.MULTILINE)
        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertIn("persist-credentials: false", workflow)

    def test_successful_build_adds_matching_resuki_release_summary(self) -> None:
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        resolver = (ROOT / "scripts/attach-resuki-release.py").read_text()
        self.assertIn("Add matching ReSukiSU Manager release to run summary", workflow)
        self.assertIn("if: success()", workflow)
        self.assertIn("attach-resuki-release.py", workflow)
        self.assertIn("GITHUB_STEP_SUMMARY", resolver)
        self.assertIn('"head_sha"', resolver)
        self.assertIn('"Manager-release"', resolver)
        self.assertIn('WORKFLOW_FILE = "build-manager.yml"', resolver)
        self.assertIn("actions/workflows/", resolver)

    def test_shell_files_parse(self) -> None:
        scripts = sorted((ROOT / "scripts").glob("*.sh")) + [ROOT / "packaging/anykernel.sh"]
        for script in scripts:
            subprocess.run(["bash", "-n", str(script)], check=True)

    def test_config_diff_allowlist(self) -> None:
        checker = ROOT / "scripts/verify-config-diff.py"
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            baseline = temp_path / "baseline"
            final = temp_path / "final"
            baseline.write_text(
                "# CONFIG_KSU is not set\n"
                "# CONFIG_DEVTMPFS is not set\n"
                "# CONFIG_NAMESPACES is not set\n"
                "CONFIG_FOO=y\n"
            )
            final.write_text(
                "CONFIG_KSU=y\n"
                "CONFIG_DEVTMPFS=y\n"
                "CONFIG_NAMESPACES=y\n"
                "CONFIG_FOO=y\n"
            )
            ok = subprocess.run(
                ["python3", str(checker), str(baseline), str(final)],
                text=True,
                capture_output=True,
            )
            self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)

            final.write_text("CONFIG_KSU=y\nCONFIG_DEVTMPFS=y\n# CONFIG_FOO is not set\n")
            bad = subprocess.run(
                ["python3", str(checker), str(baseline), str(final)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("UNEXPECTED CONFIG_FOO", bad.stdout)

    def test_fragment_verifier(self) -> None:
        checker = ROOT / "scripts/verify-fragment.py"
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            fragment = temp_path / "fragment"
            config = temp_path / "config"
            fragment.write_text("CONFIG_ONE=y\n# CONFIG_TWO is not set\n")
            config.write_text("CONFIG_ONE=y\n# CONFIG_TWO is not set\n")
            ok = subprocess.run(
                ["python3", str(checker), str(fragment), str(config)],
                text=True,
                capture_output=True,
            )
            self.assertEqual(ok.returncode, 0, ok.stdout + ok.stderr)
            config.write_text("# CONFIG_ONE is not set\n# CONFIG_TWO is not set\n")
            bad = subprocess.run(
                ["python3", str(checker), str(fragment), str(config)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("FRAGMENT_MISMATCH CONFIG_ONE", bad.stdout)

    def test_source_scripts_do_not_use_moving_checkout_refs(self) -> None:
        fetch = (ROOT / "scripts/fetch-sources.sh").read_text()
        prepare = (ROOT / "scripts/prepare-kernel.sh").read_text()
        self.assertNotIn("git pull", fetch + prepare)
        self.assertIn("assert_git_head", fetch)
        self.assertIn("MANUAL_HOOK_PATCH_SHA256", prepare)


if __name__ == "__main__":
    unittest.main()
