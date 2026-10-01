# claude-bud JOB 46 (2026-10-01): rebirth stations: the preview card, the dressing, an activity per area.
import os as _j46_os
import re as _j46_re
import subprocess as _j46_sp
import sys as _j46_sys
from pathlib import Path as _J46P

if "ok" not in globals():
    _j46_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j46_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J46P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j46(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J46: " + msg)


def _j46_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j46_code(path):
    s = _j46_re.sub(r"--\[\[.*?\]\]", "", _j46_src(path), flags=_j46_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_CF = "src/ReplicatedStorage/Shared/Configs/"
_ZC = _j46_src(_CF + "RebirthZonesConfig.luau")
_j46("function cfg.CardFor(" in _ZC and "function cfg.Gains(" in _ZC and all(z in _ZC.split("cfg.Info = {")[1].split("\n}")[0] for z in
     ("WestYard", "StrategicYard", "WestStrip", "DroneBay", "EastYard", "EastStrip", "WestFlank")),
     "the card / gains come from ONE config helper; every zone has Info (what you can do, its activity)")
_RZC = _j46_code(_CL + "Controllers/RebirthZoneController.luau")
_j46('prompt.Name == "WE_ZonePrompt"' in _RZC and "ZC.CardFor(zoneId, level" in _RZC and "HudLayout.RegisterTopStack" in _RZC,
     "the preview card shows with the zone prompt, from CardFor, in the HUD top stack (no overlaps)")
_RZS = _j46_code(_SV + "Services/RebirthZoneService.luau")
_j46('p:SetAttribute("Level", level)' in _RZS and "Dressing.Build" in _RZS and "checkApron(plotId, zoneId)" in _RZS and "addActivityPrompt" in _RZS,
     "a built zone gets its dressing + activity kiosk on a checked apron; the prompt carries the level")
_act = _RZS.split("function RebirthZoneService.Activity")[1].split("\nend\n")[0]
_j46('es.AddCash(player, cash, "rebirthzone_ship")' in _act and "ZC.Shipment.CooldownMinutes" in _act and "lv < 1" in _act,
     "activities are server-side, owner-only, built zones only; shipments have a saved cooldown")
_DR = _j46_code(_SV + "Modules/RebirthZoneDressing.luau")
_j46("WE_Building" not in _DR and "Neon" not in _DR and "PointLight" not in _DR and "SpotLight" not in _DR,
     "the dressing never touches WE_Building*, no Neon, no lights")
_j46(not _j46_re.search(r"PivotTo|Teleport", _RZS + _RZC), "no teleport / fast travel")
_j46("RebirthZoneController" in _j46_src(_CL + "Bootstrap.client.luau"), "the client controller is wired")

_luau = _j46_os.environ.get("LUAU")
if _luau is None and _j46_os.environ.get("LUAU_COMPILE"):
    _cand = _j46_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j46_os.path.isfile(_cand) else None
if _luau:
    _r = _j46_sp.run([_j46_sys.executable, "tools/sim/run_rebirth_stations_test.py"], capture_output=True, text=True, env=dict(_j46_os.environ, LUAU=_luau))
    _j46(_r.returncode == 0 and "REBIRTH STATIONS TEST: 0 failed" in _r.stdout, "run_rebirth_stations_test.py (card = config for 7 zones x 4 levels, dressing, activities)")
else:
    print("SKIP CLAUDE-BUD J46: Luau CLI tests (set LUAU)")
