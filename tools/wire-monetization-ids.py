#!/usr/bin/env python3
"""Paste Creator Dashboard product Ids into MonetizationConfig.luau from a JSON map.

Usage:
    python3 tools/wire-monetization-ids.py ids.json [--force] [--dry-run] [--config PATH]

JSON shape (only these two sections):
    {"GamePasses": {"PV_Warlord": 123}, "DevProducts": {"Nuke": 456, "GoldenPumpjack": 789}}

Rules (v71 money, M0):
  * The config path is repo-relative (src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau next to this
    tools/ folder). --config points it at another file (used by the temp-copy tests).
  * Each key is looked up only inside its own section block (GamePasses / DevProducts), as a direct entry of that
    block, with whole-word matching. DevProducts.AutoCollect never touches GamePasses.AutoCollect.
  * A key that is not already in its section exits 1 (add the config entry first; the tool never invents rows).
  * A non-zero Id is never overwritten unless --force is given (pasting the same Id again is a no-op).
  * Ids must be positive integers. Never set a live Id to 0.
  * An Id another entry of the same section already has is refused, even with --force (ProcessReceipt would
    grant either row).
  * Nothing is written unless every key in the JSON passes these checks.
  * An entry with SoldFrom = "Panel" is sold from that panel only (e.g. DevProducts.RebirthKeepBase from the
    Rebirth panel): it keeps HideFromShop = true, so no NOTE asks to remove it (F7, owner's 11 features).
After a publish that pastes Ids, the owner runs Migrate to Latest Update (receipts for unknown Ids are retried).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "src" / "ReplicatedStorage" / "Shared" / "Configs" / "MonetizationConfig.luau"
SECTIONS = ("GamePasses", "DevProducts")


def code_mask(text: str) -> list[bool]:
    """True for characters that are Luau code (not inside a string literal or a comment)."""
    n = len(text)
    mask = [True] * n
    i = 0

    def long_bracket_level(pos: int) -> int | None:
        # text[pos] == "[" ; returns level for [[ / [=[ ... or None
        j = pos + 1
        level = 0
        while j < n and text[j] == "=":
            level += 1
            j += 1
        if j < n and text[j] == "[":
            return level
        return None

    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            start = i
            if i + 2 < n and text[i + 2] == "[":
                level = long_bracket_level(i + 2)
                if level is not None:
                    close = "]" + "=" * level + "]"
                    end = text.find(close, i + 2)
                    end = n if end < 0 else end + len(close)
                    for k in range(start, end):
                        mask[k] = False
                    i = end
                    continue
            end = text.find("\n", i)
            end = n if end < 0 else end
            for k in range(start, end):
                mask[k] = False
            i = end
            continue
        if c == "[":
            level = long_bracket_level(i)
            if level is not None:
                close = "]" + "=" * level + "]"
                end = text.find(close, i)
                end = n if end < 0 else end + len(close)
                for k in range(i, end):
                    mask[k] = False
                i = end
                continue
        if c in ('"', "'", "`"):
            start = i
            i += 1
            while i < n and text[i] != c:
                if text[i] == "\\":
                    i += 1
                elif text[i] == "\n" and c != "`":
                    break
                i += 1
            end = min(n, i + 1)
            for k in range(start, end):
                mask[k] = False
            i = end
            continue
        i += 1
    return mask


def match_brace(text: str, mask: list[bool], open_pos: int) -> int:
    """Index of the '}' closing the '{' at open_pos (code characters only)."""
    depth = 0
    for k in range(open_pos, len(text)):
        if not mask[k]:
            continue
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return k
    raise ValueError(f"unbalanced braces from offset {open_pos}")


def direct_entries(text: str, mask: list[bool], open_pos: int, close_pos: int) -> dict[str, tuple[int, int]]:
    """Direct `Key = { ... }` children of the table spanning [open_pos, close_pos]."""
    entries: dict[str, tuple[int, int]] = {}
    depth = 0
    k = open_pos
    pat = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{")
    while k <= close_pos:
        if mask[k]:
            ch = text[k]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            elif depth == 1 and (ch.isalpha() or ch == "_") and (k == 0 or not (text[k - 1].isalnum() or text[k - 1] == "_")):
                m = pat.match(text, k)
                if m and all(mask[j] for j in range(m.start(), m.end())):
                    brace = m.end() - 1
                    end = match_brace(text, mask, brace)
                    entries[m.group(1)] = (brace, end)
                    k = end + 1
                    continue
        k += 1
    return entries


def section_span(text: str, mask: list[bool], section: str) -> tuple[int, int]:
    for m in re.finditer(rf"\b{section}\s*=\s*\{{", text):
        if all(mask[j] for j in range(m.start(), m.end())):
            brace = m.end() - 1
            return brace, match_brace(text, mask, brace)
    raise KeyError(section)


def find_id(text: str, mask: list[bool], open_pos: int, close_pos: int) -> re.Match[str] | None:
    """The entry's own `Id = <digits>` (depth 1 inside the entry, whole word)."""
    depth = 0
    pat = re.compile(r"\bId\s*=\s*(\d+)\b")
    for k in range(open_pos, close_pos + 1):
        if not mask[k]:
            continue
        ch = text[k]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif depth == 1 and ch == "I" and (k == 0 or not (text[k - 1].isalnum() or text[k - 1] == "_")):
            m = pat.match(text, k)
            if m:
                return m
    return None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Paste product Ids into MonetizationConfig.luau")
    ap.add_argument("json_path")
    ap.add_argument("--force", action="store_true", help="allow overwriting a non-zero (live) Id")
    ap.add_argument("--dry-run", action="store_true", help="check and print, write nothing")
    ap.add_argument("--config", default=str(DEFAULT_CONFIG), help="MonetizationConfig.luau to edit")
    args = ap.parse_args(argv)

    cfg = Path(args.config)
    try:
        data = json.loads(Path(args.json_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        print(f"ERROR reading {args.json_path}: {err}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print("ERROR: JSON must be an object like {\"DevProducts\": {\"Key\": 123}}", file=sys.stderr)
        return 1
    text = cfg.read_text(encoding="utf-8")
    mask = code_mask(text)

    errors: list[str] = []
    edits: list[tuple[int, int, str, str]] = []  # (start, end, replacement, label)
    notes: list[str] = []
    for section, mapping in data.items():
        if section not in SECTIONS:
            errors.append(f"unknown section {section!r} (expected one of {', '.join(SECTIONS)})")
            continue
        if not isinstance(mapping, dict):
            errors.append(f"{section} must map keys to Ids")
            continue
        try:
            s_open, s_close = section_span(text, mask, section)
        except KeyError:
            errors.append(f"section {section} not found in {cfg}")
            continue
        entries = direct_entries(text, mask, s_open, s_close)
        # Id each entry of this section will have after the paste (duplicate check below)
        final_ids: dict[str, int] = {}
        for ekey, (eo, ec) in entries.items():
            em = find_id(text, mask, eo, ec)
            if em is not None:
                final_ids[ekey] = int(em.group(1))
        touched: set[str] = set()
        for key, raw in mapping.items():
            label = f"{section}.{key}"
            if isinstance(raw, bool) or not isinstance(raw, int) and not (isinstance(raw, str) and raw.isascii() and raw.isdigit()):
                errors.append(f"{label}: Id must be a positive integer, got {raw!r}")
                continue
            pid = int(raw)
            if pid <= 0:
                errors.append(f"{label}: Id must be a positive integer (never set an Id to 0), got {pid}")
                continue
            if key not in entries:
                errors.append(f"{label}: unknown key (add the config entry first)")
                continue
            e_open, e_close = entries[key]
            m = find_id(text, mask, e_open, e_close)
            if m is None:
                errors.append(f"{label}: entry has no `Id = <number>` field")
                continue
            current = int(m.group(1))
            if current == pid:
                print(f"unchanged {label} = {pid}")
                continue
            if current != 0 and not args.force:
                errors.append(f"{label}: refusing to overwrite live Id {current} with {pid} (use --force)")
                continue
            edits.append((m.start(1), m.end(1), str(pid), f"{label}: {current} -> {pid}"))
            final_ids[key] = pid
            touched.add(key)
            entry_text = text[e_open:e_close + 1]
            if re.search(r"\bHideFromShop\s*=\s*true\b", entry_text):
                feature = re.search(r"\bFeature\s*=\s*\"(\w+)\"", entry_text)
                sold_from = re.search(r"\bSoldFrom\s*=\s*\"(\w+)\"", entry_text)
                if feature:
                    # v71 money (M1): a Feature SKU stays hidden until its feature ships (M3 feature gate, J3)
                    notes.append(
                        f"NOTE {label} is a Feature SKU ({feature.group(1)}): keep HideFromShop = true until the publish "
                        f"that makes that feature live (pasting the Id alone does not sell it)"
                    )
                elif sold_from:
                    # F7: sold from its own panel (SoldFrom), never from the Shop list: HideFromShop stays, no NOTE
                    pass
                else:
                    notes.append(f"NOTE {label} still has HideFromShop = true: remove it in the same commit to sell it")
        # Two entries with one Id make ProcessReceipt / the pass cache pick either row (wrong grant): never allowed,
        # not even with --force.
        for key in sorted(touched):
            for other, oid in final_ids.items():
                if other != key and oid == final_ids[key] and (other not in touched or other < key):
                    errors.append(f"{section}.{key}: Id {oid} is also {section}.{other}'s Id (each product needs its own Id)")

    if errors:
        for e in errors:
            print(f"ERROR {e}", file=sys.stderr)
        print("nothing written", file=sys.stderr)
        return 1
    for start, end, repl, lbl in sorted(edits, reverse=True):
        text = text[:start] + repl + text[end:]
    for _, _, _, lbl in sorted(edits):
        print(f"set {lbl}")
    for n in notes:
        print(n)
    if args.dry_run:
        print("dry run: nothing written")
        return 0
    if edits:
        cfg.write_text(text, encoding="utf-8")
    print(f"done ({len(edits)} change(s)) -> {cfg}")
    print("Next: publish, then Creator Hub > Migrate to Latest Update.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
