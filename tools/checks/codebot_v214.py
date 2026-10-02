# Code Bot Roblox v214 (2026-10-02): JOB 67 remainder BATCHES 2 + 3. Batch 2 = detailed desert buildings over the outlying places'
# Part TownBlock kits (Job67DressConfig.Buildings + Job67DressService.SyncBuildings): Shaun's free Creator Store models
# 10055885754 (PrinzAaron Desert Houses), 9939040273 (CAG Desert house Camp), 15654066038 (ImParadoxial Desert House)
# and 16365964601 (RussianAndRobloxer Desert house). World dressing, owner-first = live once a player it is live for is
# in the server (the JOB 40 ReplaceRows rule). Kits hidden + non-colliding (restored by ClearBuildings); the building's
# large parts collide. No Town house, heist / landmark kit, gutted cache shell or metal shed. PreferMesh / Streaming OFF.
# Batch 3 = Shaun's paid Synty Polygon Military Vehicles (119390702773907) destroyed-vehicle meshes over the outlying POI
# Part wrecks (Job67DressConfig.Wrecks, same world code path): Collide = "Kit" (the Part wreck stays the invisible collider,
# so cover / anchors / NPC posts are unchanged), never a gun-pit wreck.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V214_PREV", "ba38cc1")
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
    label = "CODEBOT v214: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_bud = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip
_own = 'SetAttribute("WE_Build", 222)' in _r(S + "Services/DataService.luau")
if not _bud:
    for _rel, _needle in (
        (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", '),
        (S + "Services/DataService.luau", 'SetAttribute("WE_Build", '),
    ):
        _m = re.search(r'SetAttribute\("WE_Build", (\d+)\)', _r(_rel))
        _c(_m is not None and int(_m.group(1)) >= 214, "WE_Build >= 214 " + _rel.rsplit("/", 1)[-1])

CFG = _r(C + "Job67DressConfig.luau")
SVC = _r(S + "Services/Job67DressService.luau")
_b = CFG[CFG.find("\tBuildings = {"):]
_c("\tBuildings = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in CFG, "Buildings block Enabled + public since codebot_v220 (was owner-first)")
for _id in ("10055885754", "9939040273", "15654066038", "16365964601"):
    _c(_id in CFG, "pack " + _id + " in the central config")
    _c("[" + _id + "](https://create.roblox.com/store/asset/" + _id + ")" in _r("docs/ASSET_LICENSES.md"), "ASSET_LICENSES row " + _id)
    _c("'DRESS-LIVE', " + _id in _r("tools/wire-asset-ids.py"), "wire-asset-ids registry row " + _id)
_rows = re.findall(r'\{ Poi = "(\w+)", Cluster = "(\w+)", Model = "(\w+)" \}', _b)
_c(5 <= len(_rows) <= 12, "Buildings rows 5..12 (%d)" % len(_rows))
# every row names a real TownBlock "block" cluster of that POI's layout, never a heist / landmark / gutted / metal kit
_lay = {}
for _g in ("Frontier", "Industry", "Wilds"):
    _lay[_g] = _r(S + "Modules/POILayouts/" + _g + ".luau")
_wc = _r(C + "WorldConfig.luau")
for _poi, _cl, _mod in _rows:
    _m = re.search(r'\{ Id = "' + _poi + r'", [^\n]*Layout = "(\w+)"', _wc)
    _src = _lay.get(_m.group(1), "") if _m else ""
    _blk = _src[_src.find("\t" + _poi + " = {"):]
    _blk = _blk[:_blk.find("\n\t},\n")]
    _line = re.search(r'\{ Id = "' + _cl + r'", [^\n]*', _blk)
    _ln = _line.group(0) if _line else ""
    _c(bool(_ln) and 'Role = "block"' in _ln and 'Kit = "TownBlock"' in _ln and "gutted" not in _ln and "metal" not in _ln,
       "row %s/%s is a TownBlock block cluster (not heist / landmark / gutted / metal)" % (_poi, _cl))
    _c(("\t\t\t" + _mod + " = {") in _b, "row %s/%s model %s defined" % (_poi, _cl, _mod))
_c('"POI_Town"' not in SVC and 'Poi = "Town"' not in CFG, "never the Town's houses")
_c("WE_Building" not in SVC and "WE_Building" not in CFG, "never touches WE_Building*")
_c("Job67DressService.BuildingsLive()" in SVC and "Job67DressService.Live(B, p.UserId)" in SVC, "owner gate: a live player in the server")
_c('d:SetAttribute("WE_J67T", d.Transparency)' in SVC and 'd:SetAttribute("WE_J67C", d.CanCollide)' in SVC and "x.CanCollide = c0" in SVC,
   "kit parts hidden with their state saved + restored")
_c('x:IsA("Light") or x:IsA("SurfaceGui") or x:IsA("BillboardGui")' in SVC, "the kit's lights / guis switched off under a building")
_c("stripInstance(m)" in SVC and "sanitizePart(d, mxs >= (B.ShadowMinStuds or 8))" in SVC and "mxs >= (B.CollideMinStuds or 4)" in SVC,
   "buildings stripped, anchored, shadow only on big parts, only big parts collide")
_c("PreferMeshWhenAssetIdSet = false" in _r(C + "StructureVisualConfig.luau"), "PreferMesh OFF")
_c('"StreamingEnabled": true' not in _r("default.project.json"), "StreamingEnabled stays OFF")
if _own and not _bud and _shipped(C + "MonetizationConfig.luau", PREV) is not None:
    _c("OwnerFirst = false, -- PUBLIC (Code Bot v215)" in _r(C + "MonetizationConfig.luau") or _shipped(C + "MonetizationConfig.luau", PREV) == _r(C + "MonetizationConfig.luau"), "MonetizationConfig byte-identical to " + PREV + " (or the approved v215 public rollout)")
    _c(_shipped(S + "Modules/WorldPOI.luau", PREV) == _r(S + "Modules/WorldPOI.luau"), "WorldPOI byte-identical (kits still build as before)")
    for _g in ("Frontier", "Industry", "Wilds"):
        _c(_shipped(S + "Modules/POILayouts/" + _g + ".luau", PREV) == _lay[_g], "POILayouts." + _g + " byte-identical")

# ---- batch 3: Wrecks ----
_w = CFG[CFG.find("\tWrecks = {"):CFG.find("\tBuildings = {")]
_c("\tWrecks = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in CFG, "Wrecks block Enabled + public since codebot_v220 (was owner-first)")
_c('Collide = "Kit",' in _w and "if not keepCollide then" in SVC, "Wrecks keep the Part wreck as the collider")
_c("119390702773907" in CFG and "[119390702773907](https://create.roblox.com/store/asset/119390702773907)" in _r("docs/ASSET_LICENSES.md")
   and "'DRESS-LIVE', 119390702773907" in _r("tools/wire-asset-ids.py"), "Synty pack: config + ASSET_LICENSES + registry")
_wr = re.findall(r'\{ Poi = "(\w+)", Cluster = "(\w+)", Kit = "(\w+)", (?:KitIndex = \d, )?Model = "(\w+)" \}', _w)
_c(8 <= len(_wr) <= 14, "Wrecks rows 8..14 (%d)" % len(_wr))
for _poi, _cl, _kit, _mod in _wr:
    _m = re.search(r'\{ Id = "' + _poi + r'", [^\n]*Layout = "(\w+)"', _wc)
    _src = _lay.get(_m.group(1), "") if _m else ""
    _blk = _src[_src.find("\t" + _poi + " = {"):]
    _blk = _blk[:_blk.find("\n\t},\n")]
    _line = re.search(r'\{ Id = "' + _cl + r'", [^\n]*', _blk)
    _ln = _line.group(0) if _line else ""
    _c(bool(_ln) and ('Kit = "' + _kit + '"') in _ln and _kit in ("Wreck", "HeliWreck") and 'Variant = "gun"' not in _ln,
       "wreck row %s/%s is a %s kit (never a gun pit)" % (_poi, _cl, _kit))
    _c(("\t\t\t" + _mod + " = { Pack = \"Synty\"") in _w, "wreck row %s/%s model %s is a Synty mesh" % (_poi, _cl, _mod))
_c("m:ScaleTo(m:GetScale() * s)" in SVC, "pack scale kept relative (Synty models ship at scale 2)")
_c('{ Key = "Wrecks", Folder = "WE_J67Wrecks" }' in SVC, "Wrecks world block registered")
