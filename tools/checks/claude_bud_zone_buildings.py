"""claude-bud (Shaun 2026-10-02, item 2): rebirth-zone buildings. BuyPathStatic-safe (every name _zb-prefixed).

Root cause (proven from config): the store-model zone swap costs ~6.9k parts per fully upgraded plot and stops at
StorePropsConfig.Budget.MaxZoneServerParts 16,000 (~2 plots), so the other plots keep the block build; EastYard always
keeps its Part barracks (ZoneKeepParts). Fix: Job67DressConfig.ZoneBuildings swaps each zone's MAIN block building for a
free desert-house model (Prinz 10055885754 / CAG 9939040273 / Imp 15654066038) on every plot that still shows blocks.

Proves: all 7 zones have a row; each row's Cluster is a real cluster the zone's Part build makes at LEVEL 1 at the row's
At spot (parsed from RebirthZoneBuilder); every model is one of the three requested packs; the 7 houses fit
MaxPartsPerPlot; RebirthZoneService calls DressZone after the Part build; DressZone skips store-swapped zones, keeps the
budget, removes the block cluster and the house is the collider; owner-first (NEW-OWNER-FIRST); the REAL ZoneFit scales
into the footprint inside ScaleMin..ScaleMax.
"""
import os as _zb_os
import re as _zb_re
import subprocess as _zb_sp
import sys as _zb_sys
import tempfile as _zb_tmp
from pathlib import Path as _ZBP

if "ok" not in globals():
    def ok(m):
        print("PASS " + m)

    def bad(m):
        print("FAIL " + m)


def _zb_rd(p):
    q = _ZBP(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_zb_cfg = _zb_rd("src/ReplicatedStorage/Shared/Configs/Job67DressConfig.luau")
_zb_svc = _zb_rd("src/ServerScriptService/Server/Services/Job67DressService.luau")
_zb_rzs = _zb_rd("src/ServerScriptService/Server/Services/RebirthZoneService.luau")
_zb_bld = _zb_rd("src/ServerScriptService/Server/Modules/RebirthZoneBuilder.luau")
_zb_blk = _zb_cfg[_zb_cfg.find("Job67DressConfig.ZoneBuildings = {"):]
_zb_blk = _zb_blk[:_zb_blk.find("\n}\n") + 3]
(ok if "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud" in _zb_blk and "Enabled = true" in _zb_blk else bad)(
    "ZoneBuildings: Enabled, owner-first (NEW-OWNER-FIRST)")
_zb_rows = dict(_zb_re.findall(r"\n\t\t(\w+) = \{ (Cluster = [^\n]*)", _zb_blk))
_zb_zones = ("WestYard", "StrategicYard", "WestStrip", "DroneBay", "EastYard", "EastStrip", "WestFlank")
(ok if all(z in _zb_rows for z in _zb_zones) else bad)("ZoneBuildings: a row for all 7 rebirth zones (%s)" % ", ".join(sorted(_zb_rows)))
_zb_models = dict(_zb_re.findall(r"\n\t\t\t(\w+) = \{ Pack = \"(\w+)\"", _zb_cfg[_zb_cfg.find("Buildings = {"):]))
_zb_parts = dict((k, int(v)) for k, v in _zb_re.findall(r"\n\t\t\t(\w+) = \{ Pack = \"\w+\", Name = \"[^\"]+\", Turn = \d+, Parts = (\d+)", _zb_cfg))
_zb_packid = dict(_zb_re.findall(r"\n\t\t(\w+) = (\d+), --", _zb_cfg[_zb_cfg.find("Packs = {"):_zb_cfg.find("PackTriangles")]))
_zb_total = 0
for _zb_z in _zb_zones:
    _zb_r = _zb_rows.get(_zb_z, "")
    _zb_cl = _zb_re.search(r'Cluster = "(\w+)"', _zb_r)
    _zb_at = _zb_re.search(r"At = \{ (-?[\d.]+), (-?[\d.]+) \}", _zb_r)
    _zb_mo = _zb_re.search(r'Model = "(\w+)"', _zb_r)
    if not (_zb_cl and _zb_at and _zb_mo):
        bad("ZoneBuildings %s: row has Cluster / At / Model" % _zb_z)
        continue
    _zb_kit = _zb_cl.group(1)[len(_zb_z) + 1:]
    _zb_x, _zb_zz = float(_zb_at.group(1)), float(_zb_at.group(2))
    _zb_fn = _zb_bld[_zb_bld.find("build.%s = function" % _zb_z):]
    _zb_fn = _zb_fn[:_zb_fn.find("\nend\n")]
    _zb_l1 = _zb_fn[_zb_fn.find("if L >= 1 then"):]
    _zb_l1 = _zb_l1[:_zb_l1.find("\n\tend")]
    if _zb_kit == "Barracks":
        _zb_hit = _zb_re.search(r"barracks\(z, p, f \* CFrame\.new\((-?[\d.]+), 0, (-?[\d.]+)\)", _zb_l1)
    else:
        _zb_hit = None
        for _zb_m in _zb_re.finditer(r'kit\(z, p, f, "%s", (-?[\d.]+), (-?[\d.]+)' % _zb_kit, _zb_l1):
            if abs(float(_zb_m.group(1)) - _zb_x) < 0.01 and abs(float(_zb_m.group(2)) - _zb_zz) < 0.01:
                _zb_hit = _zb_m
    _zb_spot = _zb_hit and abs(float(_zb_hit.group(1)) - _zb_x) < 0.01 and abs(float(_zb_hit.group(2)) - _zb_zz) < 0.01
    (ok if _zb_spot else bad)("ZoneBuildings %s: replaces the level-1 block %s at (%g, %g) the Part build really makes" % (_zb_z, _zb_cl.group(1), _zb_x, _zb_zz))
    _zb_pack = _zb_models.get(_zb_mo.group(1))
    (ok if _zb_packid.get(_zb_pack or "") in ("10055885754", "9939040273", "15654066038") else bad)(
        "ZoneBuildings %s: %s comes from a requested free pack (%s)" % (_zb_z, _zb_mo.group(1), _zb_packid.get(_zb_pack or "")))
    _zb_total += _zb_parts.get(_zb_mo.group(1), 10 ** 6)
_zb_cap = _zb_re.search(r"MaxPartsPerPlot = (\d+)", _zb_blk)
(ok if _zb_cap and _zb_total <= int(_zb_cap.group(1)) else bad)("ZoneBuildings: all 7 houses = %d parts <= MaxPartsPerPlot %s" % (_zb_total, _zb_cap.group(1) if _zb_cap else "?"))
(ok if "pcall(J.DressZone, folder, zoneId, frame, player.UserId)" in _zb_rzs and "task.spawn(function()" in _zb_rzs else bad)(
    "RebirthZoneService dresses the zone right after its Part build, off the build thread")
_zb_dz = _zb_svc[_zb_svc.find("function Job67DressService.DressZone("):]
_zb_dz = _zb_dz[:_zb_dz.find("\nend\n")]
for _zb_needle, _zb_what in (('folder:GetAttribute("WE_StoreProps") == "on"', "skips a zone already wearing store models"),
                             ("Job67DressService.Live(Z, ownerUserId)", "owner-first by the base owner"),
                             ("MaxPartsPerPlot", "keeps the per-plot part budget"),
                             (":Destroy() -- the block building goes", "removes the block building"),
                             ("WorldTemplate(C.Buildings, row.Model)", "uses the audited, stripped, colliding Buildings template"),
                             ("Cfg.ZoneFit(", "scales into the footprint (Cfg.ZoneFit)")):
    (ok if _zb_needle in _zb_dz else bad)("DressZone " + _zb_what)
(ok if "WE_Building" not in _zb_dz else bad)("DressZone never touches WE_Building*")

_zb_env = dict(_zb_os.environ)
if "LUAU" not in _zb_env and _zb_env.get("LUAU_COMPILE"):
    _zb_lx = _zb_env["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _zb_os.path.isfile(_zb_lx):
        _zb_env["LUAU"] = _zb_lx
if not _zb_env.get("LUAU"):
    bad("ZoneBuildings Luau ZoneFit proof needs LUAU / LUAU_COMPILE (fail closed)")
else:
    _zb_sys.path.insert(0, "tools/sim")
    from run_kit_detail_test import PRELUDE as _ZB_PRELUDE  # noqa: E402
    _zb_test = r'''
local fails = 0
local function check(c, m) print((c and "ok    " or "FAIL  ") .. m); if not c then fails += 1 end end
local J = require(node("Configs/Job67DressConfig"))
local Z = J.ZoneBuildings
-- a 40 x 30 house into a 28 x 20 hangar: fits inside (the smaller ratio), x Grow
local s = J.ZoneFit(Vector3.new(40, 12, 30), 28, 20, false)
check(math.abs(s - math.min(28 / 40, 20 / 30) * Z.Grow) < 1e-6, string.format("fits the footprint: %.3f", s))
check(J.ZoneFit(Vector3.new(40, 12, 30), 30, 40, true) == math.clamp(math.min(30 / 30, 40 / 40) * Z.Grow, Z.ScaleMin, Z.ScaleMax), "a turned house swaps its sides")
check(J.ZoneFit(Vector3.new(200, 12, 200), 10, 10, false) == Z.ScaleMin, "never below ScaleMin (doors stay player-sized)")
check(J.ZoneFit(Vector3.new(5, 5, 5), 60, 60, false) == Z.ScaleMax, "never above ScaleMax")
print(string.format("ZB LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''
    with _zb_tmp.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _zb_fh:
        _zb_fh.write("\n".join([_ZB_PRELUDE, "SOURCES['Configs/Job67DressConfig'] = function(script)\n%s\nend" % _zb_cfg, _zb_test]))
        _zb_path = _zb_fh.name
    _zb_res = _zb_sp.run([_zb_env["LUAU"], _zb_path], capture_output=True, text=True, timeout=100)
    for _zb_line in _zb_res.stdout.splitlines():
        if _zb_line.startswith("FAIL"):
            bad("ZoneFit: " + _zb_line[6:])
    (ok if (_zb_res.returncode == 0 and "ZB LUA: 0 failed" in _zb_res.stdout) else bad)(
        "the REAL Job67DressConfig.ZoneFit scales a house into the block footprint within ScaleMin..ScaleMax"
        + ("" if _zb_res.returncode == 0 else " :: " + _zb_res.stderr.strip()[-300:]))
