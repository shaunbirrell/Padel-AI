# Code Bot Roblox v200 (2026-10-01): JOB 67 turret tiers PROMOTED after WE_CHECK2 (Open Cloud Luau, live place v197,
# docs/we_check2_minigun_v200.txt). Shaun's paid Minigun Turret Pack 109072907337393 = Folder of 10 Models
# minigun_l01..l10, 4 MeshParts each, 1 README Script (stripped), 0 Humanoids; AutoGunT1..T5 = Lvl 1/3/5/8/10.
# Every pack part faces -Z with the barrel on +Z: Yaw 180 + AimHitbox (an invisible -Z box = the aim part / Turret HP
# hitbox). The pieces carry GetScale() ~0.02 from their import: the tier scale is relative (scaleModelLongAxis).
# Job67 stays OwnerFirst. PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes; MonetizationConfig unchanged.
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
PREV = os.environ.get("CODEBOT_V200_PREV", "8a77631")  # v199 tip (place 197)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"


def _v200_read(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _v200_shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def _v200(cond, label):
    label = "CODEBOT v200: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


for _rel, _needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 205)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 205)'),
    (S + "Services/DataService.luau", "WE_Build=205"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 205)'),
):
    _v200(_needle in _v200_read(_rel), "WE_Build=205 " + _rel.rsplit("/", 1)[-1])

_VA = _v200_read(C + "VisualAssetConfig.luau")
_j = _VA.split("Job67 = {")[1].split("\n\t},")[0] if "Job67 = {" in _VA else ""
_v200("Enabled = true," in _j and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _j, "Job67 stays Enabled + OwnerFirst")
_rows = [l for l in _VA.splitlines() if re.match(r"\s*AutoGunT[1-5] = \{", l)]
_want = [(1, "minigun_l01", 5.5), (2, "minigun_l03", 5.8), (3, "minigun_l05", 6.1), (4, "minigun_l08", 6.5), (5, "minigun_l10", 7.0)]
_v200(len(_rows) == 5 and all(
    ('AutoGunT%d = { ModelAssetId = 109072907337393, Yaw = 180, ChildName = "%s", LongAxisStuds = %s, AimHitbox = true,' % (i, c, s)) in _VA
    for i, c, s in _want), "AutoGunT1..T5 promoted: pack Lvl 1/3/5/8/10, Yaw 180, AimHitbox, LongAxisStuds 5.5 < 5.8 < 6.1 < 6.5 < 7.0")
_v200(all("PendingAssetId" not in l for l in _rows), "AutoGunT1..T5 carry no PendingAssetId after the promote")
_v200("GateDefense.AutoGunT1" in _v200_read("docs/ASSET_LICENSES.md").split("109072907337393")[-1][:2000],
      "docs/ASSET_LICENSES.md row for 109072907337393")
_wc = _v200_read("docs/we_check2_minigun_v200.txt")
_v200("WE_CHECK2 109072907337393 HEAD via=InsertService parts=40 loader=40" in _wc and " hum=0 " in _wc
      and "WE_CHECK2 0 DONE ids=1 ok=1 fail=0 err=0" in _wc, "WE_CHECK2 record: 40 MeshParts (10 x 4), hum=0, DONE ok")
_v200("    109072907337393: ('Minigun Turret Pack (Lvl 1-10)', 'Hoshizora_N1', 8723125177, 'User', 10, '2026-09-13', 26380, 1)"
      in _v200_read("tools/wire-asset-ids.py"), "wire-asset-ids STORE record (paid pack, 26,380 tris, 1 script)")

_G = _v200_read(S + "Services/GateDefenseService.luau")
_prep = _G.split("local function prepareAimTemplate")[1].split("\nend\n")[0] if "local function prepareAimTemplate" in _G else ""
_v200('template:GetAttribute("WE_AimHitbox") == true' in _prep and 'box.Name = "WE_AimHitbox"' in _prep
      and "box.Transparency = 1" in _prep and "box.CanCollide = false" in _prep and "box.CanQuery = true" in _prep
      and 'box:SetAttribute("WE_AimPart", true)' in _prep, "prepareAimTemplate: AimHitbox = invisible non-colliding -Z aim box")
_v200('tierTemplate:SetAttribute("WE_AimHitbox", true)' in _G and "tierHitbox = ref.AimHitbox == true" in _G,
      "spawnAutoGun: only a promoted tier ref with AimHitbox gets the hitbox")
_v200("model:ScaleTo(if relative == true then model:GetScale() * factor else factor)" in _G
      and "else (GateDefenseConfig.AutoGunLongAxisStuds or 5.5), tierTemplate ~= nil)" in _G,
      "tier pieces scale relative to their own scale (today's AutoGun / nests / bags: absolute, unchanged)")
_v200("if template and not prepareAimTemplate(template, assetId, yawDeg) then" in _G
      and "local template = tierTemplate or loadCatalogModel(assetId)" in _G, "today's AutoGun path unchanged (fallback)")

# the claude/desktop-bud branch carries unshipped work (JOB 62 ExperienceNotify, JOB 66 products): the ship-only checks
# below (byte-identical money config, the src diff scope) apply to phase-7-polish only
_v200_bud = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()
_mon = _v200_read(C + "MonetizationConfig.luau")
_pm = _v200_shipped(C + "MonetizationConfig.luau", PREV)
# Code Bot v203: this byte-identical MonetizationConfig pin is v200's own ship scope (a later build may change
# Shaun-approved text, e.g. v203's 2x Offline Cash Description); the newest codebot_vNNN.py carries the live money guard.
_v200_own_mon = 'SetAttribute("WE_Build", 200)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
_v200((not _v200_own_mon) or (_v200_bud or (_pm is not None and _bud_j66(_pm) == _bud_j66(_mon))), "MonetizationConfig byte-identical to " + PREV + " (no price changes; JOB 66 block allowed)" + (" [bud branch: ship-only, skipped]" if _v200_bud else ""))
_v200("PreferMesh = true" not in _VA, "PreferMesh stays OFF (VisualAssetConfig)")
_v200("PreferMeshWhenAssetIdSet = false" in _v200_read(C + "StructureVisualConfig.luau"), "PreferMeshWhenAssetIdSet false")
_v200('"StreamingEnabled": true' not in _v200_read("default.project.json"), "StreamingEnabled stays OFF")
_r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
_names = (_r.stdout or "").splitlines()
_v200(_r.returncode == 0 and not [n for n in _names if "WE_Building" in n], "no WE_Building* diffs vs " + PREV)
# Code Bot v201: the src-scope + DataService pins below are v200's own ship scope (vs its PREV); a later build changes
# other files, so they apply only while WE_Build is 200 (superseded in tools/checks/codebot_v201.py)
_v200_later = 'SetAttribute("WE_Build", 200)' not in _v200_read(S + "Services/DataService.luau")
_allowed = {C + "VisualAssetConfig.luau", S + "Services/GateDefenseService.luau", S + "Services/BaseService.luau",
            S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"}
_v200(_r.returncode == 0 and (_v200_bud or _v200_later or set(_names) <= _allowed), "src diff vs %s only the tier config + GateDefense + WE_Build (%s)" % (PREV, ",".join(sorted(set(_names) - _allowed)) or "ok"))
_ds = _v200_read(S + "Services/DataService.luau")
_pds = _v200_shipped(S + "Services/DataService.luau", PREV) or ""
_v200(_v200_bud or _v200_later or _pds.replace("WE_Build\", 199)", "WE_Build\", 200)").replace("WE_Build=199", "WE_Build=200") == _ds,
      "DataService: only the WE_Build number changed (save keys kept)")
_v200(_v200_bud or "ExperienceNotifyService" not in _v200_read(S + "Bootstrap.server.luau"), "ExperienceNotify (JOB 62) still NOT shipped")
