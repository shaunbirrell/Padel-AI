# claude-bud JOB 31 (2026-09-30): real detail (WorldDetailConfig + WorldKits detailed builders), the new sites
# (WorldSitesConfig + Modules/WorldSites) and their garrisons / activities (SiteActivityConfig + SiteActivityService +
# the Missions panel's ACTIVITIES rows). Static pins + two real-code tests in the Luau CLI.
import os as _j31_os
import subprocess as _j31_sp
import sys as _j31_sys
from pathlib import Path as _J31P

if "ok" not in globals():
    _j31_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j31_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J31P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j31(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J31: " + msg)


def _j31_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j31_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j31_src(path).splitlines())


_DC = _j31_src("src/ReplicatedStorage/Shared/Configs/WorldDetailConfig.luau")
_WK = _j31_code("src/ServerScriptService/Server/Modules/WorldKits.luau")
_SC = _j31_src("src/ReplicatedStorage/Shared/Configs/WorldSitesConfig.luau")
_WS = _j31_code("src/ServerScriptService/Server/Modules/WorldSites.luau")
_AC = _j31_src("src/ReplicatedStorage/Shared/Configs/SiteActivityConfig.luau")
_AS = _j31_code("src/ServerScriptService/Server/Services/SiteActivityService.luau")
_MC = _j31_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau")
_MD = _j31_code("src/ServerScriptService/Server/Modules/MapDressing.luau")

# detail: kill switch, one allowance, plain planning untouched
_j31("local WorldDetailConfig = {\n\tEnabled = true,\n\tMaxExtraParts = 900," in _DC, "kill switch WorldDetailConfig.Enabled; ONE world allowance for the extra parts")
_j31("if tryDetail(kitId, b) then" in _WK and "return if plain then plain.Parts else #b.Parts" in _WK and "WorldKits.DetailStats.Extra + extra > cap" in _WK,
     "detailed kits return the PLAIN count (section caps unchanged) and stop at MaxExtraParts")
_j31("Builders[kitId](b)" in _WK and "local function tryDetail(" in _WK, "Footprint (the planner) still measures the plain kit")
_j31('WorldKits.DetailSpecs = {\n\tWreck = { tank = 21, truck = 15, gun = 10 },' in _j31_src("src/ServerScriptService/Server/Modules/WorldKits.luau"),
     "the tank wreck is 21 parts (hull, glacis, tracks, wheels, fenders, turret, bustle, mantlet, barrel, muzzle, hatch)")
_j31('runtimeDoor(put(b, "BunkerDoor"' in _WK and _WK.count('runtimeDoor(put(b, "BunkerDoor"') == 2, "the detailed bunker keeps its runtime door")
_j31("p.Material = if mat == Enum.Material.Neon then Enum.Material.SmoothPlastic else mat" in _WK and "Enum.Material.Neon" not in _WK.split("local Detail:", 1)[1].split("WorldKits.DetailSpecs", 1)[0],
     "detailed kits go through the one factory (never Neon) and name no Neon")
# sites
_j31("local WorldSitesConfig = {\n\tEnabled = true,\n\tMaxParts = 240," in _SC, "kill switch WorldSitesConfig.Enabled; sites capped at 240 plain parts")
_j31("clearOfParts(cand[1], cand[2], kind.R)" in _WS and "WorldSites.PlaceOk(cand[1], cand[2], kind.R)" in _WS and "PlotClearStuds" in _WS,
     "a site stands only on clear ground: no parts, off the plots and named areas")
_j31('Source = "site",' in _WS and "wk.Finish(cluster, folder)" in _WS, "sites are WorldKits clusters (QualityGovernor decor rules; buildings never culled)")
_j31('getWorldModule("WorldSites")' in _MD and "pcall(wsites.Build, quality, wk)" in _MD, "sites build right after WorldFill")
# activities: owner-first, server-authoritative
_j31("local SiteActivityConfig = {\n\tEnabled = true,\n\tOwnerFirst = true, -- only UserId 470626172" in _AC, "kill switch SiteActivityConfig.Enabled, owner-first")
_j31('RemoteGate).Check(player, "RequestSiteActivity", action, id)' in _AS and 'pcall(es.AddCash, player, d.Cash, "activity")' in _AS,
     "activities are gated and paid on the server")
_j31("killer == player and onPerch" in _AS and "who.UserId ~= owner" in _AS and "(r0.Position - crate.Position).Magnitude > C.PromptStuds + 4" in _AS,
     "sniper kills count only from the deck; the cache pays only its owner, close by")
_j31("OverCap" not in _AS, "garrisons and activity NPCs use normal NPC slots (never the special over-cap)")
_j31('"ACTIVITIES"' in _MC and 'fire(Constants.RemoteNames.RequestSiteActivity, "start", id)' in _MC and "closePanel()" in _MC,
     "the Missions panel lists ACTIVITIES with START / GO")

_luau = _j31_os.environ.get("LUAU")
if _luau is None and _j31_os.environ.get("LUAU_COMPILE"):
    _cand = _j31_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j31_os.path.isfile(_cand) else None
if _luau:
    for _t, _want in (("tools/sim/run_kit_detail_test.py", "KIT DETAIL TEST: 0 failed"), ("tools/sim/run_sites_test.py", "SITES TEST: 0 failed")):
        _r = _j31_sp.run([_j31_sys.executable, _t], capture_output=True, text=True, env=dict(_j31_os.environ, LUAU=_luau))
        _j31(_r.returncode == 0 and _want in _r.stdout, _t + " (real WorldKits / WorldSites / SiteActivityService in the Luau CLI)")
else:
    print("SKIP CLAUDE-BUD J31: Luau CLI tests (set LUAU)")
