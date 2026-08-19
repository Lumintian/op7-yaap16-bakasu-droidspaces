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

    def test_final_fragment_selects_manual_hook_without_susfs(self) -> None:
        config = (ROOT / "config/yaap16-resuki.config").read_text()
        required = (
            "CONFIG_DEVTMPFS=y",
            "# CONFIG_DEVTMPFS_MOUNT is not set",
            "CONFIG_KSU=y",
            "CONFIG_KSU_MANUAL_HOOK=y",
            "# CONFIG_KSU_TRACEPOINT_HOOK is not set",
            "# CONFIG_KSU_SUSFS is not set",
        )
        for line in required:
            self.assertIn(line, config)
        self.assertNotRegex(config, r"^CONFIG_KSU_SUSFS(?:_[A-Z0-9_]+)?=y$", re.MULTILINE)

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
            baseline.write_text("# CONFIG_KSU is not set\n# CONFIG_DEVTMPFS is not set\nCONFIG_FOO=y\n")
            final.write_text("CONFIG_KSU=y\nCONFIG_DEVTMPFS=y\nCONFIG_FOO=y\n")
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
