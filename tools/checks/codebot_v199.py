# Code Bot Roblox v199 (2026-10-01): claude-bud JOB 67 (1) turret tiers OwnerFirst (assets PENDING).
# VisualAssetConfig.Job67 OwnerFirst; GateDefense.AutoGunT1..T5 PendingAssetId=109072907337393 (ModelAssetId 0);
# TurretTierFor(Guns 0..10)->T1..T5; GateDefenseService pack-piece loader with 40-part refusal (today's gun until
# WE_CHECK2 promote). PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
# JOB 62 ExperienceNotify intentionally NOT included.
import os
import re
import subprocess
from pathlib import Path

# claude-bud JOB 66 (2026-10-01): the ONLY MonetizationConfig change allowed past this ship guard is the Shaun-approved
# JOB 66 block (the two 5 R$ starter rows, the Starter5 switch, the SkuLiveFor LiveBlock lines), removed exactly here
# before the byte-identical compare. Everything else in the file must still match.
def _bud_j66(t):
    t = (t or "").replace("\r\n", "\n")
    a = t.find("\t-- claude-bud JOB 66 (price approved by Shaun")
    if a >= 0:
        b = t.find("\n", t.find("\tBoost2x10m = {", a)) + 1
        t = t[:a] + t[b:]
    a = t.find("-- claude-bud JOB 66: the two 5 R$ starter products")
    if a >= 0:
        t = t[:a] + t[t.find("function MonetizationConfig.SkuLiveFor", a):]
    a = t.find("\t-- claude-bud JOB 66: a row tied to an owner-first switch (LiveBlock)")
    if a >= 0:
        b = t.find("\tend\n", a) + len("\tend\n")
        t = t[:a] + t[b:]
    return t


ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V199_PREV", "22befca")  # v198 code tip (place 196)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def code(src):
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    return "\n".join(l.split("--", 1)[0] for l in src.splitlines())


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 220'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 220'),
    (S + "Services/DataService.luau", "WE_Build=220"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 220'),
):
    check(needle in read(rel), "CODEBOT v199: WE_Build=220 " + rel.rsplit("/", 1)[-1])

VA = read(C + "VisualAssetConfig.luau")
j67 = VA.split("Job67 = {")[1].split("\n\t},")[0] if "Job67 = {" in VA else ""
check(
    "Enabled = true," in j67
    and "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in j67
    and "TurretTierAt = { 1, 4, 7, 10 }" in j67
    and '"AutoGunT1"' in j67,
    "CODEBOT v199: VisualAssetConfig.Job67 OwnerFirst + TurretTierAt",
)
check(
    all(("AutoGunT%d = { ModelAssetId = 0, PendingAssetId = 109072907337393" % i) in VA for i in range(1, 6))
    or all(("AutoGunT%d = { ModelAssetId = 109072907337393, Yaw = 180, ChildName = " % i) in VA for i in range(1, 6)),  # v200 promote
    "CODEBOT v199: AutoGunT1..T5 PENDING (ModelAssetId 0) until WE_CHECK2 promote (v200: promoted)",
)
check("function VisualAssetConfig.TurretTierFor(" in VA, "CODEBOT v199: TurretTierFor helper")

GD = read(S + "Services/GateDefenseService.luau")
piece = GD.split("local function loadCatalogPiece")[1].split("\nend\n")[0] if "local function loadCatalogPiece" in GD else ""
check(
    "local function loadCatalogPiece(" in GD
    and "catalogRefusal(model)" in piece
    and "spawnAutoGun(slot, at, folder, tier" in GD
    and "local template = tierTemplate or loadCatalogModel(assetId)" in GD,
    "CODEBOT v199: GateDefenseService tier pack loader + 40-part refusal fallback",
)
check("function GateDefenseService.TurretTier(" in GD, "CODEBOT v199: GateDefenseService.TurretTier")

W = read("tools/wire-asset-ids.py")
check(
    "('MinigunTurretPack', 'GATE DEFENSE', 'PENDING-GET', 109072907337393" in W,
    "CODEBOT v199: MinigunTurretPack registry row in wire-asset-ids",
)

# JOB 62 must NOT ship
check("ExperienceNotifyService" not in read(S + "Bootstrap.server.luau"),
      "CODEBOT v199: ExperienceNotify (JOB 62) NOT shipped")
r_names = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
names = (r_names.stdout or "").splitlines()
check(not any("ExperienceNotify" in n for n in names), "CODEBOT v199: no ExperienceNotify files vs " + PREV)

MON = read(C + "MonetizationConfig.luau")
prev_mon = shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v199's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v199_own_mon = 'SetAttribute("WE_Build", 199)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
check((not _v199_own_mon) or (prev_mon is not None and _bud_j66(prev_mon) == _bud_j66(MON)), "CODEBOT v199: MonetizationConfig byte-identical to " + PREV)

check("PreferMesh = true" not in VA, "CODEBOT v199: PreferMesh stays OFF (VisualAssetConfig)")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"),
      "CODEBOT v199: PreferMeshWhenAssetIdSet false")
prj = read("default.project.json")
check('"StreamingEnabled": true' not in prj, "CODEBOT v199: StreamingEnabled stays OFF")

r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
check(r.returncode == 0 and not touched, "CODEBOT v199: no WE_Building* diffs vs " + PREV)

check(any("VisualAssetConfig" in n or "GateDefenseService" in n for n in names),
      "CODEBOT v199: JOB 67 turret files in diff vs PREV")
