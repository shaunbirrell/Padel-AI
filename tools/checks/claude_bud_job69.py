"""Static JOB 69 acceptance guards.

This is intentionally fail-closed. JOB 69 is a docs-only queue change here, so the
current tree is expected to report the missing implementation contract. Once the
implementation lands, this check protects it from silently dropping an annex or
registering an activity without a complete HowTo card definition.
"""
from __future__ import annotations

import re
from pathlib import Path

if "ok" not in globals():
    def ok(message: str) -> None:
        print("PASS " + message)

    def bad(message: str) -> None:
        print("FAIL " + message)

ROOT = Path.cwd() if (Path.cwd() / "CLAUDE.md").is_file() else Path(__file__).resolve().parents[2]


def _j69_read(relative: str) -> str:
    path = ROOT / relative
    return path.read_text(encoding="utf-8") if path.is_file() else ""


# ── A. all ten plots × all seven zones ───────────────────────────────────────
base = _j69_read("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau")
max_plots_match = re.search(r"^\s*MaxPlots\s*=\s*(\d+)", base, re.MULTILINE)
max_plots = int(max_plots_match.group(1)) if max_plots_match else 0
zones_config = _j69_read("src/ReplicatedStorage/Shared/Configs/RebirthZonesConfig.luau")
zones_block_match = re.search(
    r"(?ms)^\s*Zones\s*=\s*\{(.*?)^\s*\}\s*::\s*\{\s*\[string\]:\s*ZoneLevels\s*\},",
    zones_config,
)
zone_block = zones_block_match.group(1) if zones_block_match else ""
zone_ids = re.findall(r"^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*\{", zone_block, re.MULTILINE)
expected_plots = list(range(1, max_plots + 1))
expected_zones = list(dict.fromkeys(zone_ids))

# A generic, validated resolver is deliberately required for every pair. A
# single generic loop is enough to satisfy all pairs, but removing it makes all
# pairs fail instead of allowing a builder `continue` to hide one zone.
zone_service = _j69_read("src/ServerScriptService/Server/Services/RebirthZoneService.luau")
resolver_contract = all(
    needle in zones_config + zone_service
    for needle in ("AnnexAlt", "slotFrame(", "WE_AnnexCFrame")
)
missing_pairs = []
for plot_id in expected_plots:
    for zone_id in expected_zones:
        if not resolver_contract:
            missing_pairs.append(f"P{plot_id}/{zone_id}")

if max_plots != 10:
    bad(f"JOB69 zones: expected BaseConfig.MaxPlots=10, found {max_plots or 'missing'}")
elif len(expected_zones) != 7:
    bad(f"JOB69 zones: expected 7 configured zones, found {len(expected_zones)} ({', '.join(expected_zones) or 'none'})")
else:
    ok("JOB69 zones: registry declares P1-P10 and seven zone ids")

if "StrategicYard" not in expected_zones or 'Name = "Nuclear Silo"' not in zone_block:
    bad("JOB69 zones: Nuclear Silo is not present in the seven-zone registry")
elif resolver_contract:
    ok("JOB69 zones: Nuclear Silo is included and fallback resolver contract is present")
else:
    bad(
        "JOB69 zones: missing fallback coverage for every plot × zone pair "
        f"({len(missing_pairs)} pairs: {', '.join(missing_pairs[:12])}"
        + (", …" if len(missing_pairs) > 12 else "")
        + ")"
    )


# ── B. every registered activity/mission has a complete HowTo config ─────────
# Each window starts at a registered Id/Activity row and ends at the next row.
# This deliberately covers the current central registries rather than trusting
# UI copy or comments; adding a new registry should add it to this list.
def _j69_section(text: str, start: str, end: str | None = None) -> str:
    at = text.find(start)
    if at < 0:
        return ""
    body = text[at + len(start):]
    if end:
        stop = body.find(end)
        if stop >= 0:
            body = body[:stop]
    return body


def _j69_registered_windows(body: str, trigger: str) -> list[tuple[str, str]]:
    lines = body.splitlines()
    starts = [i for i, line in enumerate(lines) if re.search(trigger, line)]
    rows: list[tuple[str, str]] = []
    for pos, start in enumerate(starts):
        stop = starts[pos + 1] if pos + 1 < len(starts) else min(len(lines), start + 40)
        # Include a few preceding lines so a multiline HowTo immediately above
        # an Id is still associated with that record.
        window = "\n".join(lines[max(0, start - 5):stop])
        match = re.search(r'(?:Id|Activity)\s*=\s*["\']([^"\']+)', lines[start])
        label = match.group(1) if match else f"row-{start + 1}"
        rows.append((label, window))
    return rows


def _j69_howto_complete(window: str) -> bool:
    if not re.search(r"\bHowTo\s*=", window):
        return False
    return all(
        re.search(pattern, window)
        for pattern in (
            r"\b(?:What|WhatItIs)\s*=\s*[\"']",
            r"\bSteps\s*=\s*\{",
            r"\b(?:TimeLimit|TimeLimitSeconds|Seconds)\s*=",
            r"\bReward\s*=",
        )
    )


registries = [
    (
        "rebirth-zone activities",
        _j69_section(zones_config, "cfg.Info = {", "cfg.Shipment ="),
        r"\bActivity\s*=\s*[\"']",
    ),
    (
        "site activities",
        _j69_section(_j69_read("src/ReplicatedStorage/Shared/Configs/SiteActivityConfig.luau"), "Activities = {", "} :: { ActivityDef }"),
        r"\bId\s*=\s*[\"']",
    ),
    (
        "daily ops",
        _j69_section(_j69_read("src/ReplicatedStorage/Shared/Configs/DailyOpsConfig.luau"), "Ops = {", "} :: { DailyOpDef }"),
        r"\bId\s*=\s*[\"']",
    ),
    (
        "daily missions",
        _j69_section(_j69_read("src/ReplicatedStorage/Shared/Configs/MissionConfig.luau"), "DailyMissions = {", "Core = {"),
        r"\bId\s*=\s*[\"']",
    ),
    (
        "timed missions",
        _j69_section(_j69_read("src/ReplicatedStorage/Shared/Configs/MissionConfig.luau"), "Missions = {", "} :: { [string]: MissionDef }"),
        r"\bId\s*=\s*[\"']",
    ),
    (
        "registered jobs",
        _j69_section(_j69_read("src/ReplicatedStorage/Shared/Configs/OpsConfig.luau"), "-- ── Sites", "return OpsConfig"),
        r"^\s*Id\s*=\s*[\"']",
    ),
]

missing_howto: list[str] = []
registered_count = 0
for registry_name, body, trigger in registries:
    for label, window in _j69_registered_windows(body, trigger):
        registered_count += 1
        if not _j69_howto_complete(window):
            missing_howto.append(f"{registry_name}/{label}")

if missing_howto:
    preview = ", ".join(missing_howto[:12])
    suffix = ", …" if len(missing_howto) > 12 else ""
    bad(
        "JOB69 HowTo: every registered activity/mission/job needs What, Steps, "
        f"TimeLimit and Reward in HowTo config; missing {len(missing_howto)}/{registered_count} ({preview}{suffix})"
    )
else:
    ok(f"JOB69 HowTo: {registered_count} registered activity/mission/job rows have complete HowTo config")


# ── claude-bud (part A): the real resolver over all 10 plots x 7 zones vs the map geometry (roads, plots, channels,
# water, sites, outposts, land edge): 0 blocked, no overlaps; OFF reproduces today's 29 gaps (the proven root cause)
import os as _j69a_os
import subprocess as _j69a_sp
import sys as _j69a_sys

_j69a_e = dict(_j69a_os.environ)
if "LUAU" not in _j69a_e and _j69a_e.get("LUAU_COMPILE"):
    _j69a_c = _j69a_e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j69a_os.path.isfile(_j69a_c):
        _j69a_e["LUAU"] = _j69a_c
if _j69a_e.get("LUAU"):
    _j69a_r = _j69a_sp.run([_j69a_sys.executable, "tools/sim/run_zone_slots_test.py"], capture_output=True, text=True, env=_j69a_e, timeout=150)
    (ok if (_j69a_r.returncode == 0 and "ZONE SLOTS TEST: 0 failed" in _j69a_r.stdout) else bad)(
        "JOB69 zones: run_zone_slots_test.py (70 plot x zone pairs, 0 blocked, no overlaps; OFF = today's gaps)")
_j69a_svc = _j69_read("src/ServerScriptService/Server/Services/RebirthZoneService.luau")
(ok if ('folder:SetAttribute("WE_AnnexCFrame", frame)' in _j69a_svc and "RebirthZoneService._ZoneBoard" in _j69a_svc and "ZC.RebuildLive(owner, \"Slots\")" in _j69a_svc) else bad)(
    "JOB69 zones: the zone folder carries WE_AnnexCFrame, a ZONE BOARD stands in for a zone with no slot, fallbacks are owner-first (Rebuild.Slots)")
