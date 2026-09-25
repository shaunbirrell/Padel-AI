#!/usr/bin/env python3
"""Paste uploaded nation-flag image ids into src/ReplicatedStorage/Shared/Configs/NationFlagIds.luau.

Usage:
    python3 tools/wire-nation-flag-ids.py Europe=123 Americas=456 ... [--force] [--dry-run]
    python3 tools/wire-nation-flag-ids.py ids.json [--force] [--dry-run] [--config PATH] [--nation-config PATH]

JSON shape (either section may be left out):
    {"Atlas": {"Europe": 123, "Americas": 456, "Asia": 1, "Africa": 2, "MiddleEast": 3, "Oceania": 4, "Review": 5},
     "Flags": {"IE": 789}}
A KEY=ID argument is an Atlas key when KEY is an atlas group (Europe ... Review), else a nation id for Flags
(Flags.IE=789 / Atlas.Europe=123 also work).

Ids are the IMAGE ids of the uploaded PNGs (Studio > Asset Manager > Images > right-click > Copy ID), uploaded as the
account or group that owns the game. A Decal id is a different number and shows nothing.

Rules (same spirit as tools/wire-monetization-ids.py):
  * Atlas keys must already be in NationFlagIds.Atlas and in NationConfig.Atlas.Groups; Flags keys must be
    NationConfig nation ids (NEUTRAL has no flag). The tool never invents an atlas row.
  * Ids must be positive integers. A non-zero id is never overwritten unless --force (the same id again is a no-op).
  * One image id may appear only once across Atlas and Flags, even with --force (each upload is one image).
  * Nothing is written unless every entry passes, and the result is compiled with luau-compile when it is available
    (LUAU_COMPILE=/path/luau-compile or on PATH).
After a paste: build, publish, and check a flag of each wired atlas in game (the picker and your base flagpole).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IDS = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Configs" / "NationFlagIds.luau"
DEFAULT_NATION_CONFIG = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Configs" / "NationConfig.luau"
MANIFEST = ROOT / "assets" / "flags" / "atlas_manifest.json"

ATLAS_BLOCK = re.compile(r"(\n\tAtlas = \{\n)(.*?)(\n\t\} :: \{ \[string\]: number \},\n)", re.S)
FLAGS_BLOCK = re.compile(r"(\n\tFlags = \{\n)(.*?)(\t\} :: \{ \[string\]: number \},\n)", re.S)
ATLAS_LINE = re.compile(r"^\t\t([A-Za-z]+) = (\d+),$")
FLAG_LINE = re.compile(r'^\t\t\["([A-Z]{2}(?:-[A-Z]{3})?)"\] = (\d+),$')


def err(msg: str) -> None:
    print(f"ERROR {msg}", file=sys.stderr)


def nation_config(path: Path) -> tuple[list[str], set[str]]:
    text = path.read_text(encoding="utf-8")
    gm = re.search(r"^\t\tGroups = \{([^}]*)\}", text, re.M)
    groups = re.findall(r'"(\w+)"', gm.group(1)) if gm else []
    ids = set(re.findall(r'^\t\t\{ Id = "([^"]+)",', text, re.M))
    return groups, ids


def parse_ids(text: str) -> tuple[dict[str, int], dict[str, int]]:
    am = ATLAS_BLOCK.search(text)
    fm = FLAGS_BLOCK.search(text)
    if not am or not fm:
        raise ValueError("Atlas / Flags blocks not found (the file must keep the generated layout)")
    atlas: dict[str, int] = {}
    for line in am.group(2).split("\n"):
        m = ATLAS_LINE.match(line)
        if not m:
            raise ValueError(f"unexpected line in Atlas: {line!r}")
        atlas[m.group(1)] = int(m.group(2))
    flags: dict[str, int] = {}
    for line in fm.group(2).split("\n"):
        if line.strip() == "":
            continue
        m = FLAG_LINE.match(line)
        if not m:
            raise ValueError(f"unexpected line in Flags: {line!r}")
        flags[m.group(1)] = int(m.group(2))
    return atlas, flags


def render_ids(text: str, atlas: dict[str, int], flags: dict[str, int]) -> str:
    am = ATLAS_BLOCK.search(text)
    assert am
    order = [ATLAS_LINE.match(line).group(1) for line in am.group(2).split("\n")]  # type: ignore[union-attr]
    abody = "\n".join(f"\t\t{k} = {atlas[k]}," for k in order)
    text = text[: am.start(2)] + abody + text[am.end(2):]
    fm = FLAGS_BLOCK.search(text)
    assert fm
    fbody = "".join(f'\t\t["{k}"] = {flags[k]},\n' for k in sorted(flags))
    return text[: fm.start(2)] + fbody + text[fm.end(2):]


def as_id(raw) -> int | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str) and raw.isascii() and raw.isdigit():
        return int(raw)
    return None


def collect(args_in: list[str], groups: list[str]) -> dict[str, dict]:
    if len(args_in) == 1 and args_in[0].endswith(".json"):
        data = json.loads(Path(args_in[0]).read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError('JSON must be an object like {"Atlas": {"Europe": 123}}')
        return data
    data: dict[str, dict] = {"Atlas": {}, "Flags": {}}
    for a in args_in:
        if "=" not in a:
            raise ValueError(f"expected KEY=ID, got {a!r}")
        key, val = a.split("=", 1)
        section = "Atlas" if key in groups else "Flags"
        if "." in key:
            section, key = key.split(".", 1)
        if key in data.get(section, {}):
            raise ValueError(f"{section}.{key} is given twice (a typo for another key?)")
        data.setdefault(section, {})[key] = val
    return data


def compile_ok(text: str) -> bool | None:
    exe = os.environ.get("LUAU_COMPILE") or shutil.which("luau-compile")
    if not exe:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as tf:
        tf.write(text)
        tmp = tf.name
    try:
        r = subprocess.run([exe, "--binary", tmp], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if r.returncode != 0:
            err(f"luau-compile: {(r.stderr or '').strip().splitlines()[:1]}")
        return r.returncode == 0
    finally:
        os.unlink(tmp)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Paste nation-flag image ids into NationFlagIds.luau")
    ap.add_argument("entries", nargs="+", help="ids.json, or KEY=ID pairs")
    ap.add_argument("--force", action="store_true", help="allow overwriting a non-zero (live) id")
    ap.add_argument("--dry-run", action="store_true", help="check and print, write nothing")
    ap.add_argument("--config", default=str(DEFAULT_IDS), help="NationFlagIds.luau to edit")
    ap.add_argument("--nation-config", default=str(DEFAULT_NATION_CONFIG))
    args = ap.parse_args(argv)

    cfg = Path(args.config)
    groups, nation_ids = nation_config(Path(args.nation_config))
    if not groups or not nation_ids:
        err(f"could not read the groups / roster from {args.nation_config}")
        return 1
    text = cfg.read_text(encoding="utf-8")
    try:
        atlas, flags = parse_ids(text)
        data = collect(args.entries, groups)
    except (OSError, ValueError) as e:
        err(str(e))
        print("nothing written", file=sys.stderr)
        return 1

    errors: list[str] = []
    changes: list[str] = []
    new_atlas, new_flags = dict(atlas), dict(flags)
    touched: set[str] = set()
    for section, mapping in data.items():
        if section not in ("Atlas", "Flags"):
            errors.append(f"unknown section {section!r} (expected Atlas or Flags)")
            continue
        if not isinstance(mapping, dict):
            errors.append(f"{section} must map keys to ids")
            continue
        for key, raw in mapping.items():
            label = f"{section}.{key}"
            pid = as_id(raw)
            if pid is None or pid <= 0:
                errors.append(f"{label}: id must be a positive integer (never 0), got {raw!r}")
                continue
            if pid >= 2**53:  # NationTexture.Source ignores ids a Luau number cannot hold exactly
                errors.append(f"{label}: {pid} is too large to be a Roblox asset id (check the paste)")
                continue
            if section == "Atlas":
                if key not in atlas or key not in groups:
                    errors.append(f"{label}: unknown atlas (expected one of {', '.join(groups)})")
                    continue
                current = atlas[key]
            else:
                if key not in nation_ids:
                    errors.append(f"{label}: {key!r} is not a NationConfig nation id")
                    continue
                current = flags.get(key, 0)
            if current == pid:
                print(f"unchanged {label} = {pid}")
                continue
            if current != 0 and not args.force:
                errors.append(f"{label}: refusing to overwrite live id {current} with {pid} (use --force)")
                continue
            (new_atlas if section == "Atlas" else new_flags)[key] = pid
            touched.add(label)
            changes.append(f"{label}: {current} -> {pid}")

    # one image, one slot: an id used twice means a wrong paste (a region would show another region's cells)
    owners: dict[int, list[str]] = {}
    for k, v in new_atlas.items():
        if v:
            owners.setdefault(v, []).append(f"Atlas.{k}")
    for k, v in new_flags.items():
        if v:
            owners.setdefault(v, []).append(f"Flags.{k}")
    for pid, who in sorted(owners.items()):
        if len(who) > 1 and any(w in touched for w in who):
            errors.append(f"id {pid} is used by {', '.join(who)} (each uploaded image goes in one slot)")

    if errors:
        for e in errors:
            err(e)
        print("nothing written", file=sys.stderr)
        return 1
    out = render_ids(text, new_atlas, new_flags)
    if parse_ids(out) != (new_atlas, new_flags):
        err("internal: the rewritten file does not read back the same ids; nothing written")
        return 1
    compiled = compile_ok(out)
    if compiled is False:
        print("nothing written", file=sys.stderr)
        return 1
    for c in changes:
        print(f"set {c}")
    missing = [g for g in groups if new_atlas.get(g, 0) == 0]
    if missing:
        print(f"atlases still 0: {', '.join(missing)} (the picker opens by itself only for admins until all are set)")
    else:
        print("all atlases wired: after this publish the picker opens by itself for everyone (LiveRequiresArt)")
    if MANIFEST.is_file():
        man = json.loads(MANIFEST.read_text(encoding="utf-8"))
        for c in changes:
            if c.startswith("Atlas."):
                g = c.split(":")[0].split(".", 1)[1]
                a = man.get("atlases", {}).get(g, {})
                print(f"  check: Atlas.{g} must be the image id of assets/flags/{a.get('file')}")
    if compiled is None:
        print("note: luau-compile not found, the parse gate was skipped (set LUAU_COMPILE)")
    if args.dry_run:
        print("dry run: nothing written")
        return 0
    if changes:
        cfg.write_text(out, encoding="utf-8")
    print(f"done ({len(changes)} change(s)) -> {cfg}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
