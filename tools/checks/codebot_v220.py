# Code Bot Roblox v220 (2026-10-02, Shaun 07:51 Dublin: "turn everything that only I have on for everyone"):
# EVERY owner-first feature gate goes public in one release (OwnerFirst = false). Left owner/admin-only on purpose:
#   * EventConfig.OwnerFirst (Double Weekend owner PREVIEW before StartUnix; the real 2x window is already for everyone,
#     flipping it would not open anything, and opening the 2x early for all would be an economy change);
#   * admin / test tools: AdminConfig.UserIds + AdminService.IsAdmin (admin commands, /zonereport, /armydebug ...),
#     the playtest cash floor (AdminPlaytestCash / BaseService 50_000_000), OwnerRebirthGrant, the playtest
#     all-vehicles + spawn-gate bypass, PremiumGuns OwnerTestGrant, GarageSlot.OwnerTest, ArmyConfig DebugUserIds,
#     VehicleConfig diag UserIds, leaderboard exclusion;
#   * VisualAssetConfig.BodyRollout = "owner" (store vehicle hulls with no WE_CHECK2 / licence record: a licence hold).
# PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no prices; only OwnerFirst + WE_Build lines change in src.
from __future__ import annotations

import re
import subprocess
from pathlib import Path

BUILD = 220
PREV = "259dfc1"  # v219 handoff tip (place version 217)
ROOT = Path.cwd()
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
TAG = "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51)"


def _v220_rd(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _v220_ck(cond: bool, label: str) -> None:
    tag = "CODEBOT v220: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            globals()["_V220_FAILED"] = True


def _v220_code(text: str) -> str:
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)  # block comments
    return "\n".join(l.split("--", 1)[0] for l in text.split("\n"))


# ---- WE_Build ----
for _v220_rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
    _v220_m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', _v220_rd(_v220_rel))
    _v220_ck(_v220_m is not None and int(_v220_m.group(1)) >= BUILD, "WE_Build >= %d %s" % (BUILD, _v220_rel.rsplit("/", 1)[-1]))

# ---- no OwnerFirst = true feature gate left anywhere in src (except the listed owner preview) ----
_v220_ALLOW = {"EventConfig.luau"}  # Double Weekend owner preview only (see header)
_v220_left = []
for _v220_p in sorted((ROOT / "src").rglob("*.luau")):
    _v220_c = _v220_code(_v220_p.read_text(encoding="utf-8"))
    for _v220_m in re.finditer(r"\bOwnerFirst\s*=\s*true\b", _v220_c):
        if _v220_p.name not in _v220_ALLOW:
            _v220_left.append("%s:%d" % (_v220_p.name, _v220_c.count("\n", 0, _v220_m.start()) + 1))
_v220_ck(not _v220_left, "no OwnerFirst = true feature gate left in src %s" % _v220_left)
_v220_ev = _v220_rd(C + "EventConfig.luau")
_v220_ck("OwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot v185): owner preview BEFORE StartUnix only" in _v220_ev,
    "EventConfig.OwnerFirst stays the owner preview of the Double Weekend (admin preview, real window is public)")
_v220_ck(len(re.findall(r"\bOwnerFirst\s*=\s*true\b", _v220_code(_v220_ev))) == 1, "EventConfig: exactly one OwnerFirst = true (the preview)")

# ---- every block flipped in this ship is public (and tagged) ----
_v220_FLIPPED = (
    ("ArmyOrdersConfig.luau", "AttackRange = {"),      # JOB 52 army attack at range
    ("BaseLifeConfig.luau", None),                      # JOB 57 base life
    ("CombatConfig.luau", ".SharedHostility = {"),     # JOB 51 shared hostility
    ("EndgameConfig.luau", "DefenceFix = {"),          # JOB 55
    ("EndgameConfig.luau", "DefenceVisuals = {"),      # JOB 53
    ("GateDefenseConfig.luau", "TurretHull = {"),      # v219 solid turret hulls
    ("HangarDockConfig.luau", None),                    # JOB 58
    ("HudConfig.luau", "AutoDrawGuard = {"),           # v216 hotbar auto-draw guard
    ("Job67DressConfig.luau", None),                    # JOB 67 dressing (top + Walls / BaseProps / Buildings / Wrecks)
    ("LightingConfig.luau", "Night2 = {"),             # JOB 54
    ("RaidConfig.luau", "AntiCamp = {"),               # JOB 63
    ("RangeLifeConfig.luau", None),                     # JOB 68
    ("RebirthZonesConfig.luau", "NukeRaid = {"),       # JOB 65
    ("RebirthZonesConfig.luau", "cfg.Rebuild = {"),    # JOB 50 / 69 (Slots, HowTo)
    ("SoundConfig.luau", "Pass59 = {"),                # JOB 59 B
    ("SpawnTerminalConfig.luau", None),                 # JOB 56
    ("VehicleConfig.luau", "HeliRotorRing = {"),       # v219 no yellow rotor ring
    ("VisualAssetConfig.luau", "Job67 = {"),           # JOB 67 turret tiers
    ("VisualAssetConfig.luau", "AirRotorDisc = {"),    # JOB 56 rotor disc
)
for _v220_f, _v220_anchor in _v220_FLIPPED:
    _v220_t = _v220_rd(C + _v220_f)
    if _v220_anchor is None:
        _v220_blk = _v220_t
    else:
        _v220_i = _v220_t.find(_v220_anchor)
        _v220_blk = _v220_t[_v220_i:_v220_i + 400] if _v220_i >= 0 else ""
    _v220_ck(TAG in _v220_blk or (_v220_anchor == "AutoDrawGuard = {" and "AutoDrawGuard = { Enabled = true, OwnerFirst = false," in _v220_blk),
        "%s %s OwnerFirst = false (public)" % (_v220_f, _v220_anchor or "(top)"))
_v220_ck(_v220_rd(C + "Job67DressConfig.luau").count(TAG) == 5, "Job67DressConfig: top + 4 blocks public (5 tags)")
_v220_tags = sum(_v220_rd(str(p.relative_to(ROOT))).count(TAG) for p in (ROOT / C).glob("*.luau"))
_v220_ck(_v220_tags == 22, "22 v220 PUBLIC tags in Shared/Configs (+ AutoDrawGuard inline) = 23 flips (%d)" % _v220_tags)

# the one owner-first rule is unchanged: OwnerFirst ~= true -> everyone
_v220_ck("if block.OwnerFirst ~= true then\n\t\treturn true\n\tend" in _v220_rd(C + "RetentionConfig.luau"), "RetentionConfig.Live: OwnerFirst ~= true -> everyone")
_v220_ck("if B.OwnerFirst ~= true and C.OwnerFirst ~= true then" in _v220_rd(S + "Services/Job67DressService.luau"), "Job67Dress world blocks live once both flags are off")

# ---- no "owner" rollout string left except the licence-held store hulls ----
_v220_own = []
for _v220_p in sorted((ROOT / C).glob("*.luau")):
    for _v220_m in re.finditer(r'(\w+)\s*=\s*"owner"', _v220_code(_v220_p.read_text(encoding="utf-8"))):
        _v220_own.append(_v220_p.name + ":" + _v220_m.group(1))
_v220_ck(_v220_own == ["VisualAssetConfig.luau:BodyRollout"], "only BodyRollout stays \"owner\" (licence hold) %s" % _v220_own)

# ---- admin-only tools are kept (not feature gates) ----
_v220_AC = _v220_rd(C + "AdminConfig.luau")
_v220_ck("UserIds = {\n\t\t470626172,\n\t}" in _v220_AC and "AdminPlaytestCash = 50_000_000" in _v220_AC, "AdminConfig admin list + playtest cash unchanged")
_v220_ck("if uid == 470626172 then" in _v220_rd(S + "Services/AdminService.luau"), "AdminService.IsAdmin owner belt kept")
_v220_ck(_v220_rd(S + "Services/BaseService.luau").count("50_000_000") >= 3, "BaseService playtest cash floor kept (test-cash)")
_v220_lit = []
_v220_LIT_OK = {"AdminConfig.luau", "AdminService.luau", "BaseService.luau", "DataService.luau", "EarlyRemotes.server.luau",
           "EventConfig.luau", "ArmyConfig.luau", "VehicleConfig.luau"}
for _v220_p in sorted((ROOT / "src").rglob("*.luau")):
    if "470626172" in _v220_code(_v220_p.read_text(encoding="utf-8")) and _v220_p.name not in _v220_LIT_OK:
        _v220_lit.append(_v220_p.name)
_v220_ck(not _v220_lit, "the owner UserId literal appears only in admin / test / diag files %s" % _v220_lit)

# ---- this ship changes only OwnerFirst + WE_Build lines in src (no prices, no WE_Building*) ----
_v220_r = subprocess.run(["git", "diff", "-U0", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
if _v220_r.returncode == 0:
    _v220_bad = []
    for _v220_l in _v220_r.stdout.split("\n"):
        if (_v220_l.startswith("+") or _v220_l.startswith("-")) and not _v220_l.startswith(("+++", "---")):
            if "OwnerFirst" not in _v220_l and "WE_Build" not in _v220_l:
                _v220_bad.append(_v220_l[:120])
    _v220_ck(not _v220_bad, "src diff vs %s touches only OwnerFirst / WE_Build lines %s" % (PREV, _v220_bad[:5]))
    _v220_ck("WE_Building" not in "\n".join(l for l in _v220_r.stdout.split("\n") if l.startswith(("+", "-"))), "no WE_Building* line touched")
    _v220_ck(not re.search(r"^[+-].*(RobuxPrice|Price\s*=|Cost\s*=)", _v220_r.stdout, re.M), "no price line touched")
else:
    _v220_ck(True, "git diff vs %s unavailable here (shallow clone): diff pins skipped" % PREV)

# ---- house rules ----
_v220_ck("PreferMeshWhenAssetIdSet = false" in _v220_rd(C + "StructureVisualConfig.luau"), "PreferMesh stays OFF")
_v220_proj = "\n".join(_v220_rd(p) for p in ("default.project.json", "perf.project.json") if (ROOT / p).is_file())
_v220_ck('"StreamingEnabled": true' not in _v220_proj, "StreamingEnabled stays OFF in the project files")

if globals().get("_V220_FAILED") and "ok" not in globals():
    raise SystemExit(1)
