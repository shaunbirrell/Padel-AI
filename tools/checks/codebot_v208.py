# Code Bot Roblox v208 (2026-10-02): JOB 67 remainder BATCH 1 = walls + base props from Shaun's owned packs
# (Military Supplies 70726960831586, Trench Sandbags 71112106874796, Textured Crates 87282634781307, Hesco PBR
# 116015230898207), one central config Shared/Configs/Job67DressConfig + Server/Services/Job67DressService.
# Owner-first (by the base owner). Wall tier = the saved DefensiveWalls level (no new save key); prop tier = the sum of
# the saved structure levels. Part walls stay the colliders. PreferMesh OFF; StreamingEnabled OFF; no WE_Building*.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V208_PREV", "f0f5f9e")
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def _r(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def _c(cond, label):
    label = "CODEBOT v208: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_bud = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file() or \
      'SetAttribute("WE_Build", 208)' not in _r(S + "Services/DataService.luau")  # later build: ship-only pins skip
if not _bud:
    for _rel, _needle in (
        (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 208)'),
        (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 208)'),
        (S + "Services/DataService.luau", "WE_Build=208"),
        (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 208)'),
    ):
        _c(_needle in _r(_rel), "WE_Build=208 " + _rel.rsplit("/", 1)[-1])

CFG = _r(C + "Job67DressConfig.luau")
SVC = _r(S + "Services/Job67DressService.luau")
SKB = _r(S + "Modules/StructureKitBuilder.luau")
BLS = _r(S + "Services/BaseLifeService.luau")
BOOT = _r(S + "Bootstrap.server.luau")
_c(bool(CFG) and bool(SVC), "Job67DressConfig + Job67DressService present")
_c("\tEnabled = true,\n\tOwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST (Code Bot JOB 67 remainder)" in CFG, "Job67DressConfig public since codebot_v220 (was owner-first)")
for _blk in ("Walls", "BaseProps"):
    _i = CFG.find("\t" + _blk + " = {")
    _c(_i > 0 and "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in CFG[_i:_i + 400], _blk + " block public since codebot_v220 (was owner-first)")
for _id in ("70726960831586", "71112106874796", "87282634781307", "116015230898207"):
    _c(_id in CFG, "pack " + _id + " in the central config")
    _c("[" + _id + "](https://create.roblox.com/store/asset/" + _id + ")" in _r("docs/ASSET_LICENSES.md"), "ASSET_LICENSES row " + _id)
    _c("'DRESS-LIVE', " + _id in _r("tools/wire-asset-ids.py"), "wire-asset-ids registry row " + _id)
_c("RetentionConfig.Live(block, ownerUserId)" in SVC and "RetentionConfig.Live(C, ownerUserId)" in SVC, "service gates on the base owner (master + area switch)")
for _cls in ('"LuaSourceContainer"', '"Light"', '"Sound"', '"ParticleEmitter"', '"ProximityPrompt"', '"Humanoid"', '"ValueBase"'):
    _c(_cls in SVC, "pack audit strips " + _cls)
_c("p.CanCollide = false" in SVC and "p.CanQuery = false" in SVC and "p.CanTouch = false" in SVC and "p.CastShadow = shadow" in SVC,
   "clones never collide / query / touch; shadow only when the piece says so")
_c(re.search(r"\.Parent\s*=\s*(workspace|Workspace)\b", SVC) is None or "propsRoot" in SVC, "pack roots never parented to the workspace")
_c("Instance.new(\"PointLight\")" not in SVC and "Instance.new(\"SpotLight\")" not in SVC and "Heartbeat" not in SVC and "RenderStepped" not in SVC,
   "no lights, no per-frame work")
_c("j67.DressWalls(plotId, plotFolder, folder, lv, padTop, centre, bs.GetOwnerUserId(plotId))" in SKB, "SyncPerimeterWalls calls DressWalls (deferred)")
_c('plotFolder:FindFirstChild("WE_J67WallDress")' in SKB, "walls level 0 clears the dressing")
_c("J67.ReplacesKit(row.Kit, ownerUserId)" in BLS, "BaseLife part kits skipped where the model clusters replace them")
_c('safeInit("Job67DressService", Job67DressService, deps)' in BOOT, "Bootstrap starts Job67DressService")
_c("WE_Building" not in SVC and "WE_Building" not in CFG, "never touches WE_Building*")
_c("PreferMeshWhenAssetIdSet = false" in _r(C + "StructureVisualConfig.luau"), "PreferMesh OFF")
_c('"StreamingEnabled": true' not in _r("default.project.json"), "StreamingEnabled stays OFF")
_mc_prev = _shipped(C + "MonetizationConfig.luau", PREV)
if _mc_prev is not None and not _bud:
    _c(_mc_prev == _r(C + "MonetizationConfig.luau"), "MonetizationConfig byte-identical to " + PREV + " (no price changes)")
    _c(_shipped(C + "BaseConfig.luau", PREV) == _r(C + "BaseConfig.luau"), "BaseConfig (levels / costs) byte-identical to " + PREV)
    _ds_prev = re.sub(r"WE_Build\D{0,4}\d+", "", _shipped(S + "Services/DataService.luau", PREV) or "")
    _c(_ds_prev == re.sub(r"WE_Build\D{0,4}\d+", "", _r(S + "Services/DataService.luau")), "DataService save keys unchanged (only WE_Build)")

# pure config functions under luau
if os.path.exists(LUAU):
    import tempfile
    _src = "local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }\n" + CFG.replace("--!strict", "")
    _src = re.sub(r"\nreturn Job67DressConfig\s*$", "\n", _src)
    _src += r'''
local J = Job67DressConfig
local fails = 0
local function ck(c, m) if not c then fails += 1 print("SIMFAIL " .. m) end end
ck(J.WallTier(0) == nil, "L0 no tier")
local prevH, prevP = -1, -1
for lv = 1, 5 do
	local t = J.WallTier(lv)
	ck(t ~= nil and t.Name ~= nil, "tier " .. lv)
	local score = #t.Hesco * 100 + #t.Lines * 10 + t.GateStacks + t.Wire + t.Blockades + (t.Trench and 5 or 0) + (t.CornerStacks and 3 or 0)
	ck(score > prevP, "tier " .. lv .. " visibly more than the one below")
	prevP = score
end
ck(J.PropTier(0) == 0 and J.PropTier(1) == 1 and J.PropTier(75) == 5, "prop tiers")
local n, len = J.HescoSplit(317, 21.5)
ck(n >= 1 and len <= 118.04 * 21.5 / 54.13 * J.Walls.HescoStretch + 1e-6, "hesco split")
ck(J.Walls.Tiers[5].MaxHesco * J.Pieces.HescoBlock.Tris <= 250000, "hesco triangle budget <= 250k per base")
print("J67 CONFIG SIM: " .. fails .. " failed")
'''
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as _f:
        _f.write(_src)
    _o = subprocess.run([LUAU, _f.name], capture_output=True, text=True, timeout=60)
    _c("J67 CONFIG SIM: 0 failed" in _o.stdout, "Job67DressConfig luau sim (tiers rise L1..L5, budgets) " + (_o.stdout + _o.stderr).strip()[-200:])
