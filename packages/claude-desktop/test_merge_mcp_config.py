"""CLI safety tests for packages/claude-desktop/merge-mcp-config.py."""

import importlib.util
import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
HELPER = HERE / "merge-mcp-config.py"
SERVER = {"command": "/nix/store/example/bin/ssh",
          "args": ["-T", "-o", "BatchMode=yes", "obsidian@example", "node",
                   "/nix/store/example/index.js", "--stdio"]}
BASE = pathlib.Path("/tmp/opencode")
BASE = str(BASE) if BASE.is_dir() else None


def dump(value, **kwargs):
    return json.dumps(value, ensure_ascii=False, **kwargs)


class MergeMcpConfigTests(unittest.TestCase):
    def setUp(self):
        if not HELPER.is_file():
            self.fail(f"helper not found: {HELPER}")
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="merge-mcp-", dir=BASE))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.cdir = self.root / "config"
        self.pdir = self.root / "patches"
        self.pdir.mkdir()
        self.config = self.cdir / "claude_desktop_config.json"

    def _write(self, path, raw):
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(raw, bytes):
            path.write_bytes(raw)
        else:
            path.write_text(raw, encoding="utf-8")
        return path

    def patch(self, doc=None, raw=None, name="patch.json"):
        return self._write(self.pdir / name, raw if raw is not None else dump(doc))

    def valid_patch(self, server=None, name="patch.json"):
        return self.patch({"mcpServers": {"obsidian-multivault": server or SERVER}}, name=name)

    def write(self, obj=None, raw=None, mode=None, path=None):
        path = self._write(path or self.config, raw if raw is not None else dump(obj))
        if mode is not None:
            os.chmod(path, mode)
        return path

    def invoke(self, patch=None, config=None, umask=None):
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", TMPDIR=str(self.root))
        kwargs = {"preexec_fn": (lambda: os.umask(umask))} if umask is not None else {}
        return subprocess.run(
            [sys.executable, str(HELPER), str(config or self.config),
             str(patch or self.valid_patch())],
            cwd=self.root, capture_output=True, text=True, env=env, **kwargs)

    def entries(self, directory=None):
        directory = directory or self.cdir
        return {p.name for p in directory.iterdir()} if directory.exists() else set()

    def snap(self, path=None):
        path = path or self.config
        st = path.lstat()
        return (path.read_bytes(), st.st_ino, st.st_mtime_ns,
                stat.S_IMODE(st.st_mode))

    def assert_unchanged(self, before, path=None):
        self.assertEqual(self.snap(path), before)

    def assert_mode(self, mode, path=None):
        self.assertEqual(stat.S_IMODE((path or self.config).stat().st_mode), mode)

    def read(self, path=None):
        return json.loads((path or self.config).read_text(encoding="utf-8"))

    def test_first_create_modes_and_no_backup(self):
        patch = self.valid_patch()
        for mask in (0, 0o077):
            with self.subTest(umask=oct(mask)):
                cdir = self.root / f"create-{mask:o}"
                config = cdir / "claude_desktop_config.json"
                result = self.invoke(patch=patch, config=config, umask=mask)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_mode(0o600, config)
                self.assert_mode(0o700, cdir)
                self.assertEqual(self.read(config),
                                 {"mcpServers": {"obsidian-multivault": SERVER}})
                self.assertEqual(self.entries(cdir), {"claude_desktop_config.json"})

    def test_preserves_unrelated_preferences_other_servers_unicode(self):
        existing = {"theme": "dark", "unknownPreference": {"nested": [1, True, None, "café"]},
                    "mcpServers": {"other": {"command": "/bin/other", "env": {"KEEP": "yes"}}}}
        self.write(existing, mode=0o640)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.read()
        self.assertEqual(data["theme"], "dark")
        self.assertEqual(data["unknownPreference"], existing["unknownPreference"])
        self.assertEqual(data["mcpServers"]["other"], existing["mcpServers"]["other"])
        self.assertEqual(data["mcpServers"]["obsidian-multivault"], SERVER)
        self.assert_mode(0o640)
        self.assertEqual(self.entries(), {"claude_desktop_config.json",
                                          "claude_desktop_config.json.mcp-backup"})

    def test_missing_mcp_servers_is_created(self):
        self.write({"theme": "light"})
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.read()
        self.assertEqual(data["theme"], "light")
        self.assertEqual(data["mcpServers"], {"obsidian-multivault": SERVER})

    def test_update_replaces_whole_managed_object(self):
        existing = {"theme": "dark", "mcpServers": {
            "obsidian-multivault": {"command": "/old", "args": ["old"], "env": {"EXTRA": "drop"}},
            "other": {"command": "/other"}}}
        self.write(existing)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.read()
        self.assertEqual(data["mcpServers"]["obsidian-multivault"], SERVER)
        self.assertEqual(data["mcpServers"]["other"], existing["mcpServers"]["other"])
        self.assertEqual(data["theme"], "dark")

    def test_semantic_noop_keeps_bytes_inode_mtime_and_no_backup(self):
        existing = {"theme": "dark", "mcpServers": {"obsidian-multivault": SERVER}}
        self.write(raw=dump(existing, indent=4) + "\n")
        before = self.snap()
        result = self.invoke(patch=self.valid_patch(name="compact.json"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_unchanged(before)
        self.assertEqual(self.entries(), {"claude_desktop_config.json"})

    def test_invalid_current_config_rejected_without_changes(self):
        invalid = [b"{", b"", b"[]", b'{"mcpServers": []}', b'{"mcpServers": null}',
                   b'{"mcpServers": "x"}',
                   b'{"mcpServers": {"other": {"env": {"K": "SENTINEL_DO_NOT_LOG"}}},}']
        for i, raw in enumerate(invalid):
            with self.subTest(case=i):
                config = self.cdir / f"invalid-{i}.json"
                self.write(raw=raw, path=config)
                before, before_entries = self.snap(config), self.entries()
                dir_mtime = self.cdir.stat().st_mtime_ns
                result = self.invoke(config=config)
                self.assertNotEqual(result.returncode, 0)
                self.assert_unchanged(before, config)
                self.assertEqual(self.entries(), before_entries)
                self.assertEqual(self.cdir.stat().st_mtime_ns, dir_mtime)
                self.assertNotIn("SENTINEL_DO_NOT_LOG", result.stdout + result.stderr)

    def test_invalid_patch_rejected_without_touching_config(self):
        self.write({"theme": "dark"})
        before, before_entries = self.snap(), self.entries()
        dir_mtime = self.cdir.stat().st_mtime_ns
        invalid = [b"{", b"", b"[]", b"{}", b'{"mcpServers": {}}',
                   b'{"mcpServers": []}', b'{"mcpServers": "x"}',
                   b'{"mcpServers": {"obsidian-multivault": "nope"}}']
        for i, raw in enumerate(invalid):
            with self.subTest(case=i):
                result = self.invoke(patch=self.patch(raw=raw, name=f"bad-{i}.json"))
                self.assertNotEqual(result.returncode, 0)
                self.assert_unchanged(before)
                self.assertEqual(self.entries(), before_entries)
                self.assertEqual(self.cdir.stat().st_mtime_ns, dir_mtime)
        secret = b'{"mcpServers": {"x": "SENTINEL_DO_NOT_LOG"}}'
        result = self.invoke(patch=self.patch(raw=secret, name="bad-secret.json"))
        self.assertNotEqual(result.returncode, 0)
        self.assert_unchanged(before)
        self.assertEqual(self.entries(), before_entries)
        self.assertEqual(self.cdir.stat().st_mtime_ns, dir_mtime)
        self.assertNotIn("SENTINEL_DO_NOT_LOG", result.stdout + result.stderr)

    def test_symlink_and_directory_targets_rejected(self):
        self.cdir.mkdir()
        real = self.root / "real.json"
        self.write({"mcpServers": {}}, path=real)
        self.config.symlink_to(real)
        before = self.snap(real)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assert_unchanged(before, real)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(self.entries(), {"claude_desktop_config.json"})
        self.config.unlink()
        self.config.mkdir()
        before_entries = self.entries()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.config.is_dir())
        self.assertEqual(self.entries(), before_entries)

    def test_backup_exact_bytes_mode_and_only_once(self):
        original = dump({"theme": "dark", "mcpServers": {"other": {"command": "/other"}}},
                        indent=3) + "\n"
        self.write(raw=original, mode=0o644)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        backup = pathlib.Path(str(self.config) + ".mcp-backup")
        self.assertEqual(backup.read_bytes(), original.encode())
        self.assert_mode(0o600, backup)
        backup_before = self.snap(backup)
        second = {**SERVER, "args": SERVER["args"] + ["--changed"]}
        result = self.invoke(patch=self.valid_patch(server=second, name="second.json"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_unchanged(backup_before, backup)
        self.assertEqual(self.read()["mcpServers"]["obsidian-multivault"], second)
        self.assertEqual(self.entries(), {"claude_desktop_config.json",
                                          "claude_desktop_config.json.mcp-backup"})

    def test_existing_backup_symlink_not_clobbered(self):
        self.write({"theme": "dark"})
        sentinel = self.root / "backup-sentinel"
        sentinel.write_text("KEEP", encoding="utf-8")
        backup = pathlib.Path(str(self.config) + ".mcp-backup")
        backup.symlink_to(sentinel)
        before = self.snap(sentinel)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(backup.is_symlink())
        self.assert_unchanged(before, sentinel)
        self.assertEqual(self.read()["theme"], "dark")
        self.assertEqual(self.entries(), {"claude_desktop_config.json",
                                          "claude_desktop_config.json.mcp-backup"})

    def test_atomic_replace_preserves_hardlink_snapshot(self):
        old = dump({"theme": "dark",
                    "mcpServers": {"obsidian-multivault": {"command": "/old"}}})
        self.write(raw=old)
        snapshot = self.root / "old-inode.json"
        os.link(self.config, snapshot)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(snapshot.read_text(), old)
        self.assertNotEqual(os.stat(snapshot).st_ino, os.stat(self.config).st_ino)
        self.assertEqual(self.read()["mcpServers"]["obsidian-multivault"], SERVER)

    def test_secret_never_logged_and_no_temp_leftovers(self):
        existing = {"theme": "dark", "mcpServers": {
            "other": {"command": "/other", "env": {"TOKEN": "SENTINEL_DO_NOT_LOG"}}}}
        self.write(existing)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("SENTINEL_DO_NOT_LOG", result.stdout + result.stderr)
        self.assertEqual(self.read()["mcpServers"]["other"], existing["mcpServers"]["other"])
        self.assertEqual(self.entries(), {"claude_desktop_config.json",
                                          "claude_desktop_config.json.mcp-backup"})


    def load_helper(self):
        spec = importlib.util.spec_from_file_location("merge_mcp_config_under_test", HELPER)
        module = importlib.util.module_from_spec(spec)
        old = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            spec.loader.exec_module(module)
        finally:
            sys.dont_write_bytecode = old
        return module

    def test_first_create_is_not_visible_before_regular_file_fsync(self):
        patch_path = self.valid_patch()
        module = self.load_helper()
        real_fsync = module.os.fsync
        seen_regular = []

        def checking_fsync(fd):
            if stat.S_ISREG(os.fstat(fd).st_mode):
                seen_regular.append(fd)
                self.assertFalse(os.path.lexists(self.config),
                                 "first-create target visible before fsync")
            return real_fsync(fd)

        with mock.patch.object(module.os, "fsync", side_effect=checking_fsync):
            module.merge_mcp_config(self.config, patch_path)

        self.assertTrue(seen_regular)
        self.assertEqual(self.read(), {"mcpServers": {"obsidian-multivault": SERVER}})
        self.assert_mode(0o600)
        self.assertEqual(self.entries(), {"claude_desktop_config.json"})

    def test_first_create_multiple_ancestors_modes_and_no_temp(self):
        existing = self.root / "existing"
        existing.mkdir(mode=0o750)
        os.chmod(existing, 0o750)
        (existing / "keep.txt").write_text("keep", encoding="utf-8")
        target = existing / "a" / "b" / "c" / "claude_desktop_config.json"
        result = self.invoke(config=target, umask=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_mode(0o600, target)
        self.assert_mode(0o750, existing)
        for directory in (existing / "a", existing / "a" / "b",
                          existing / "a" / "b" / "c"):
            self.assert_mode(0o700, directory)
        self.assertEqual(
            {p.relative_to(existing).as_posix() for p in existing.rglob("*")},
            {"keep.txt", "a", "a/b", "a/b/c", "a/b/c/claude_desktop_config.json"},
        )
        self.assertEqual(self.read(target),
                         {"mcpServers": {"obsidian-multivault": SERVER}})


if __name__ == "__main__":
    unittest.main()
