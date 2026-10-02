"""claude-bud (Shaun item 4): drivable Synty vehicles. BuyPathStatic-safe (every name _sy-prefixed).

Proves: SyntyVehicleConfig is owner-first (NEW-OWNER-FIRST), uses Shaun's audited Synty pack 119390702773907, dresses the
wheeled vehicles only (ArmoredTruck / ArmedJeep / ScoutCar; no tank), every row's refs are dress-only Kit bodies
(Fit = "Kit", HideKit, StripDecals, Yaw 180, the Armed 4x4 keeps its own gun visible); VisualAssetService splits the
candidates out of the pack (pieceRefsFor) and TryAttachVehicleVisual tries them first for a live owner and falls back to
today's body (resolveVehicleRef); the REAL config's Refs / RefsFor in Luau. The Part-kit chassis, controls and physics
are untouched (no VehicleService / VehicleConfig / VisualAssetConfig edit).
"""
import os as _sy_os
import subprocess as _sy_sp
import sys as _sy_sys
import tempfile as _sy_tmp
from pathlib import Path as _SYP

if "ok" not in globals():
    def ok(m):
        print("PASS " + m)

    def bad(m):
        print("FAIL " + m)


def _sy_rd(p):
    q = _SYP(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_sy_cfg = _sy_rd("src/ReplicatedStorage/Shared/Configs/SyntyVehicleConfig.luau")
_sy_vas = _sy_rd("src/ServerScriptService/Server/Services/VisualAssetService.luau")
(ok if "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud item 4)" in _sy_cfg and "Enabled = true" in _sy_cfg else bad)("SyntyVehicleConfig: Enabled, owner-first (NEW-OWNER-FIRST)")
(ok if "PackId = 119390702773907" in _sy_cfg else bad)("SyntyVehicleConfig uses Shaun's audited Synty Polygon Military Vehicles pack")
(ok if "Tank" not in _sy_cfg.split("Rows = {")[1].split("} ::")[0] else bad)("no tank rows (tanks keep their Part kits + turrets)")
(ok if ("SV.PackId == assetId" in _sy_vas and "SV.Refs()" in _sy_vas) else bad)("VisualAssetService splits the Synty candidates out of the pack (pieceRefsFor)")
_sy_veh = _sy_rd("src/ServerScriptService/Server/Services/VehicleService.luau")
(ok if ("syntyFor[coroutine.running()]" in _sy_vas and "function VisualAssetService.TryAttachSyntyVehicleVisual(" in _sy_vas
        and "VisualAssetService.TryAttachSyntyVehicleVisual(model, def.Id or \"\", family, ownerUserId) then" in _sy_veh) else bad)(
    "VehicleService tries the Synty body first (same attach path, per-thread hand-over), else today's body")
_sy_fn = _sy_vas[_sy_vas.find("function VisualAssetService.SyntyRef("):]
_sy_fn = _sy_fn[:_sy_fn.find("\nend\n")]
(ok if (".Live(SV, ownerUserId)" in _sy_fn and "templateForRef(r :: AssetRef) ~= nil" in _sy_fn) else bad)(
    "SyntyRef: owner-first by the vehicle owner, first candidate the pack really holds")

_sy_env = dict(_sy_os.environ)
if "LUAU" not in _sy_env and _sy_env.get("LUAU_COMPILE"):
    _sy_x = _sy_env["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _sy_os.path.isfile(_sy_x):
        _sy_env["LUAU"] = _sy_x
if not _sy_env.get("LUAU"):
    bad("Synty vehicles Luau proof needs LUAU / LUAU_COMPILE (fail closed)")
else:
    _sy_sys.path.insert(0, "tools/sim")
    from run_kit_detail_test import PRELUDE as _SY_PRELUDE  # noqa: E402
    _sy_test = r'''
local fails = 0
local function check(c, m) print((c and "ok    " or "FAIL  ") .. m); if not c then fails += 1 end end
local SV = require(node("Configs/SyntyVehicleConfig"))
local all = SV.Refs()
local n = 0
for _ in pairs(SV.Rows) do n += 1 end
check(n == 3 and SV.Rows.ArmoredTruck and SV.Rows.ArmedJeep and SV.Rows.ScoutCar, "3 wheeled vehicles: ArmoredTruck, ArmedJeep, ScoutCar")
local good = #all > 0
for _, r in ipairs(all) do
  if r.ModelAssetId ~= SV.PackId or type(r.ChildName) ~= "string" or r.Fit ~= "Kit" or r.HideKit ~= true or r.StripDecals ~= true or r.Yaw ~= 180 then good = false end
end
check(good, #all .. " candidate refs: dress-only Kit bodies from the pack (Fit Kit, HideKit, StripDecals, Yaw 180)")
local j = SV.RefsFor("ArmedJeep")
check(#j >= 1 and j[1].ChildName == "SM_Veh_Pickup_Technical_01" and j[1].KeepVisible and j[1].KeepVisible[1] == "GunMount", "the Armed 4x4 tries the Synty technical first and keeps its own gun visible")
check(#SV.RefsFor("LightTank") == 0 and #SV.RefsFor("Nope") == 0, "no Synty body for tanks / unknown vehicles (today's look)")
check(SV.Refs() == all, "refs are built once (cached)")
print(string.format("SY LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''
    with _sy_tmp.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _sy_fh:
        _sy_fh.write("\n".join([_SY_PRELUDE, "SOURCES['Configs/SyntyVehicleConfig'] = function(script)\n%s\nend" % _sy_cfg, _sy_test]))
        _sy_path = _sy_fh.name
    _sy_r = _sy_sp.run([_sy_env["LUAU"], _sy_path], capture_output=True, text=True, timeout=100)
    for _sy_line in _sy_r.stdout.splitlines():
        if _sy_line.startswith("FAIL"):
            bad("Synty: " + _sy_line[6:])
    (ok if (_sy_r.returncode == 0 and "SY LUA: 0 failed" in _sy_r.stdout) else bad)(
        "the REAL SyntyVehicleConfig refs in Luau" + ("" if _sy_r.returncode == 0 else " :: " + _sy_r.stderr.strip()[-300:]))
