#!/usr/bin/env python3
"""Merge managed MCP servers into Claude Desktop's config file.

Usage: merge-mcp-config.py CONFIG_PATH PATCH_JSON_PATH

PATCH_JSON_PATH must contain a JSON object whose non-empty ``mcpServers``
object holds the desired server definitions. Only those entries are upserted;
all other top-level keys and servers are preserved. The file is re-serialised
only when a managed server actually changes.

The target is app-owned mutable state: it is refused if it is a symlink or a
non-regular file, and an original copy is kept once at CONFIG_PATH +
".mcp-backup" (mode 0600) before the first modification.
"""

import json
import os
import stat
import sys
import tempfile
from pathlib import Path

USAGE = "usage: merge-mcp-config.py CONFIG_PATH PATCH_JSON_PATH"


class MergeError(Exception):
    """A failure that is safe to print: never includes config contents."""


def _load_json(path, label):
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise MergeError(f"cannot read {label} {path}: {exc.strerror}") from None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise MergeError(f"{label} {path} is not valid UTF-8") from None
    try:
        return raw, json.loads(text)
    except json.JSONDecodeError as exc:
        raise MergeError(
            f"{label} {path} is not valid JSON: {exc.msg} "
            f"at line {exc.lineno} column {exc.colno}"
        ) from None


def _load_patch(path):
    _, patch = _load_json(path, "patch")
    if not isinstance(patch, dict):
        raise MergeError("patch must be a JSON object")
    unexpected = sorted(set(patch) - {"mcpServers"})
    if unexpected:
        raise MergeError(
            "patch has unsupported top-level keys: "
            + ", ".join(json.dumps(key) for key in unexpected)
        )
    servers = patch.get("mcpServers")
    if not isinstance(servers, dict) or not servers:
        raise MergeError("patch.mcpServers must be a non-empty JSON object")
    for name, definition in servers.items():
        if not isinstance(definition, dict):
            raise MergeError(
                f"patch.mcpServers[{json.dumps(name)}] must be a JSON object"
            )
    return servers


def _target_servers(target, path):
    if not isinstance(target, dict):
        raise MergeError(f"target {path} must contain a JSON object")
    if "mcpServers" not in target:
        return {}
    servers = target["mcpServers"]
    if not isinstance(servers, dict):
        raise MergeError(f"target {path} mcpServers must be a JSON object")
    return servers


def _serialise(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _write_backup(path, raw):
    backup = path.with_name(path.name + ".mcp-backup")
    if os.path.lexists(backup):
        return
    try:
        fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return
    except OSError as exc:
        raise MergeError(f"cannot create backup {backup}: {exc.strerror}") from None
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(backup, 0o600)
    except OSError as exc:
        try:
            backup.unlink()
        except OSError:
            pass
        raise MergeError(f"cannot write backup {backup}: {exc.strerror}") from None


def _create_config(path, servers):
    parent = path.parent
    data = _serialise({"mcpServers": servers})
    previous_umask = os.umask(0o077)
    try:
        parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    except OSError as exc:
        raise MergeError(f"cannot create directory {parent}: {exc.strerror}") from None
    finally:
        os.umask(previous_umask)

    try:
        fd, temp_name = tempfile.mkstemp(
            prefix=".claude_desktop_config.", suffix=".tmp", dir=parent
        )
    except OSError as exc:
        raise MergeError(
            f"cannot create temporary file in {parent}: {exc.strerror}"
        ) from None
    temp = Path(temp_name)
    try:
        try:
            with os.fdopen(fd, "wb") as handle:
                os.fchmod(handle.fileno(), 0o600)
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            # Hard-link publication is atomic and fails if another writer won
            # the race for the still-absent target, unlike check-then-replace.
            os.link(temp, path)
        except FileExistsError:
            raise MergeError(f"target {path} appeared while merging; rerun") from None
        except OSError as exc:
            raise MergeError(f"cannot create {path}: {exc.strerror}") from None
    finally:
        try:
            temp.unlink()
        except OSError:
            pass


def _replace_config(path, original_raw, mode, value):
    data = _serialise(value)
    fd, temp_name = tempfile.mkstemp(
        prefix=".claude_desktop_config.", suffix=".tmp", dir=path.parent
    )
    temp = Path(temp_name)
    replaced = False
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, mode)
        try:
            current_raw = path.read_bytes()
        except OSError as exc:
            raise MergeError(f"cannot re-read {path}: {exc.strerror}") from None
        if current_raw != original_raw:
            raise MergeError(
                f"target {path} changed while merging; refusing to overwrite "
                "(quit Claude Desktop and retry)"
            )
        os.replace(temp, path)
        replaced = True
    finally:
        if not replaced:
            try:
                temp.unlink()
            except OSError:
                pass


def merge_mcp_config(config_path, patch_path):
    """Upsert managed MCP servers, raising MergeError on any unsafe input."""
    config_path = Path(config_path)
    patch_path = Path(patch_path)

    desired = _load_patch(patch_path)

    try:
        target_stat = os.lstat(config_path)
    except FileNotFoundError:
        target_stat = None
    except OSError as exc:
        raise MergeError(f"cannot inspect {config_path}: {exc.strerror}") from None

    if target_stat is None:
        _create_config(config_path, desired)
        return

    if stat.S_ISLNK(target_stat.st_mode):
        raise MergeError(f"refusing symlink target {config_path}")
    if not stat.S_ISREG(target_stat.st_mode):
        raise MergeError(f"refusing non-regular target {config_path}")

    original_raw, target = _load_json(config_path, "target")
    servers = _target_servers(target, config_path)
    if all(
        name in servers and servers[name] == definition
        for name, definition in desired.items()
    ):
        return

    updated = dict(target)
    merged_servers = dict(servers)
    merged_servers.update(desired)
    updated["mcpServers"] = merged_servers

    _write_backup(config_path, original_raw)
    _replace_config(
        config_path, original_raw, stat.S_IMODE(target_stat.st_mode), updated
    )


def main(argv=None):
    args = sys.argv[1:] if argv is None else list(argv)
    if len(args) != 2:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        merge_mcp_config(args[0], args[1])
    except MergeError as exc:
        print(f"merge-mcp-config: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
