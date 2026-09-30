# claude-bud JOB 33 (2026-09-30): the rebirth overhaul, owner-first (RebirthConfig.Live): zones + effects
# (RebirthZonesConfig / RebirthZoneService / RebirthZoneBuilder), the silo nukes (NukeService / NukeController), the vehicle
# and gun grants (PrestigeConfig.RebirthUnlocks, WeaponConfig rebirth guns), perks, rank, the richer rebirth screen and
# the pacing (PrestigeConfig.MinLevelFor). Static pins + the real-code test (tools/sim/run_rebirth_test.py).
import os as _j33_os
import subprocess as _j33_sp
import sys as _j33_sys
from pathlib import Path as _J33P

if "ok" not in globals():
    _j33_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j33_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J33P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j33(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J33: " + msg)


def _j33_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j33_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j33_src(path).splitlines())


_RC = _j33_src("src/ReplicatedStorage/Shared/Configs/RebirthConfig.luau")
_PC = _j33_src("src/ReplicatedStorage/Shared/Configs/PrestigeConfig.luau")
_ZS = _j33_code("src/ServerScriptService/Server/Services/RebirthZoneService.luau")
_NS = _j33_code("src/ServerScriptService/Server/Services/NukeService.luau")
_PS = _j33_code("src/ServerScriptService/Server/Services/PrestigeService.luau")
_VS = _j33_code("src/ServerScriptService/Server/Services/VehicleService.luau")
_MO = _j33_src("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")

_OWN = "OwnerFirst = false, -- codebot_v131 launch: everyone (JOB 33 handoff)"
_j33("\tLive = {\n\t\tEnabled = true,\n\t\t" + _OWN in _RC and "function RebirthConfig.LiveFor(userId: any, part: string): boolean" in _RC,
     "one owner-first gate with per-part kill switches (RebirthConfig.Live)")
_j33("\tZonesLive = true," in _RC and "\tWeaponsLive = true," in _RC and "return RebirthConfig.ZonesLive == true" in _RC,
     "ZonesLive / WeaponsLive published for everyone (codebot_v131 launch); LiveFor still gates parts")
# no new Robux items
_ZC = _j33_src("src/ReplicatedStorage/Shared/Configs/RebirthZonesConfig.luau")
_j33("MarketplaceService" not in _ZS + _NS and "ProductId" not in _ZC and "DevProduct" not in _ZS + _NS + _ZC and "GamePass" not in _ZS + _NS + _ZC,
     "zones, silo and rush are Cash only (no new Robux item)")
# zones: server-side upgrades, effects wired into their owners
_j33('deps.EconomyService.SpendCash(player, cost, "rebirthzone_" .. zoneId)' in _ZS and "levelOf(profile, zoneId)" in _ZS and "if lv >= Z.MaxLevel then" in _ZS,
     "zone upgrades: owner-only, server-checked, Cash, max level 3")
_BS = _j33_code("src/ServerScriptService/Server/Services/BaseService.luau")
_SS = _j33_code("src/ServerScriptService/Server/Services/SoldierService.luau")
_MS = _j33_code("src/ServerScriptService/Server/Services/MissileStrikeService.luau")
_MC = _j33_code("src/ServerScriptService/Server/Services/MoneyCollectorService.luau")
_j33("RZ.FlatIncomePerTick, profile, player" in _BS and "RZ.ArmyBonus, profile" in _SS and "RZ.MissileReloadCut, attacker" in _MS and "RZ.RaidShieldBonus, vProfile" in _MC,
     "zone effects: income per tick, army cap, missile reload, raid shield (read by the services that own them)")
_j33("pcall(es.CollectPendingCash, player)" in _ZS, "the Drone Hangar empties the owner's ATM")
_j33("checkSlot(plotId, zoneId)" in _ZS and "Z.ClearableSources[src] == true" in _ZS, "an annex never lands on a road / POI / site: only procedural decor is cleared")
# nuke
_j33("pcall(cs.ApplyRadiusDamage," in _NS and "N.BaseClearStuds" in _NS and "profile.NukeLastLaunch = os.time()" in _NS and "cooldownLeft(profile) > 0" in _NS,
     "nuke: the shared PvP rule (ApplyRadiusDamage), never near a base, saved player cooldown + server cooldown")
_j33('deps.EconomyService.SpendCash(player, cost, "nuke_rush")' in _NS, "silo rush is Cash, server-priced")
# vehicles / guns / perks / pacing / screen
_j33('Gate = "Vehicles"' in _PC and 'Gate = "Weapons"' in _PC and "local gateOk = (u :: any).Gate == nil or RebirthConfig.LiveFor(player.UserId, (u :: any).Gate)" in _PS,
     "the added vehicle / gun grants go through the owner-first gate")
_j33("not VehicleService._IsPlaytestOwner(player) and not rebirthGranted" in _VS, "granted rebirth vehicles are usable at once (any level / base)")
_j33("RebirthConfig.StartingCash(profile.Prestige, false)" in _PS and "RebirthConfig.GoldBonus(profile.Prestige, false)" in _PS,
     "perks: starting cash steps and gold 50 + 10 / rebirth")
_j33("PrestigeConfig.MinLevelPerPrestige = 4" in _PC and "PrestigeConfig.MinLevelMax = 90" in _PC and "MinLevel = minLevelFor(player, profile)" in _PS,
     "pacing: later rebirths need more levels (sim: 33.6 / 34.1 / 37.4 / 41.5 ... min)")
_j33('"REBIRTH_CONFIRMED"' in _PS and '"REBIRTH_AVAILABLE"' in _PS and "RebirthOpened" in _j33_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ProgressionController/init.luau"),
     "analytics rebirth_available / rebirth_opened / rebirth_confirmed with level and play minutes")
_j33("(payload :: any).Next3 = if screenLive then PrestigeConfig.NextRebirths(prestige, 3, zoneAt) else nil" in _PS, "the rebirth screen previews the next 3 rebirths")

_luau = _j33_os.environ.get("LUAU")
if _luau is None and _j33_os.environ.get("LUAU_COMPILE"):
    _cand = _j33_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j33_os.path.isfile(_cand) else None
if _luau:
    _r = _j33_sp.run([_j33_sys.executable, "tools/sim/run_rebirth_test.py"], capture_output=True, text=True, env=dict(_j33_os.environ, LUAU=_luau))
    _j33(_r.returncode == 0 and "REBIRTH TEST: 0 failed" in _r.stdout, "run_rebirth_test.py (real zone builder / nuke / zone service / configs)")
else:
    print("SKIP CLAUDE-BUD J33: Luau CLI test (set LUAU)")
