# Code Bot Roblox v138 (2026-09-30): owner (Shaun, 14:44 Dublin) "turn aircraft weapons ON for everyone".
# The gate was AircraftWeaponConfig.WeaponsLive = false + LiveFor's AdminConfig.IsPlaytestOwner override (owner-only).
# Flip: WeaponsLive = true. Damage stays on the one shared hostility / protection path (CombatService.ApplyHit ->
# hurtPlayer/pvpBlock, ArmyHostility; ApplyRadiusDamage -> hurtPlayer; ally / novice / raid / new-player base shields).
# PreferMesh OFF; fast travel stays REMOVED; RolloutKeys unchanged; no Robux price changes; WE_Building* untouched.
from pathlib import Path as _P138


def _cb138(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd138(p):
    q = _P138(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_S138 = "src/ServerScriptService/Server/"
_C138 = "src/ReplicatedStorage/Shared/Configs/"
for _f in (_S138 + "Services/DataService.luau", _S138 + "Services/BaseService.luau", _S138 + "EarlyRemotes.server.luau"):
    _cb138('SetAttribute("WE_Build", 138)' in _rd138(_f), "CODEBOT v138: WE_Build=138 " + _f.rsplit("/", 1)[-1])
_cb138("WE_Build=138" in _rd138(_S138 + "Services/DataService.luau"), "CODEBOT v138: DataService profile-loaded log says WE_Build=138")

# ── aircraft weapons live for everyone ──
_AWC = _rd138(_C138 + "AircraftWeaponConfig.luau")
_AWS = _rd138(_S138 + "Services/AirWeaponService.luau")
_AWCL = _rd138("src/StarterPlayer/StarterPlayerScripts/Client/Modules/AirWeaponsClient.luau")
_cb138("\tWeaponsLive = true, -- v138" in _AWC, "CODEBOT v138: AircraftWeaponConfig.WeaponsLive = true (everyone)")
_cb138("function AircraftWeaponConfig.LiveFor(userId: any): boolean\n\tif AircraftWeaponConfig.WeaponsLive == true then\n\t\treturn true\n\tend" in _AWC,
       "CODEBOT v138: LiveFor returns true for any UserId once WeaponsLive (the owner override is only the fallback)")
_cb138("\tif not CFG.LiveFor(player.UserId) then\n\t\treturn refuse(\"off\")" in _AWS, "CODEBOT v138: the server fire gate is LiveFor (no other owner gate)")
_cb138("IsPlaytestOwner" not in _AWS and "470626172" not in _AWS and "IsPlaytestOwner" not in _AWCL and "470626172" not in _AWCL,
       "CODEBOT v138: no owner / admin check in AirWeaponService or AirWeaponsClient")
_cb138("player:SetAttribute(CFG.LiveAttribute, if CFG.LiveFor(player.UserId) then true else nil)" in _AWS,
       "CODEBOT v138: WE_AirWeaponsLive attribute follows LiveFor (true for every player)")
_cb138("local live = lp():GetAttribute(CFG.LiveAttribute) == true" in _AWCL, "CODEBOT v138: client fire buttons key off the server attribute only")

# ── one shared hostility / protection rule ──
_CS = _rd138(_S138 + "Services/CombatService/init.luau")
_cb138("local ok, res = pcall(CombatService.ApplyHit, attacker, part, amount, opts)" in _AWS, "CODEBOT v138: aircraft direct hits go through CombatService.ApplyHit")
_cb138("pcall(CombatService.ApplyRadiusDamage, attacker, center, radius, def.Damage, {" in _AWS, "CODEBOT v138: aircraft splash goes through CombatService.ApplyRadiusDamage")
_cb138("elseif pvpBlock(attacker, victim) ~= nil then -- v124: THE shared PvP rule" in _CS, "CODEBOT v138: player damage (hurtPlayer) uses pvpBlock (spawn / novice shield, PvP off)")
_cb138("local may, why = CombatService.ArmyHostility(attacker, owner)" in _CS, "CODEBOT v138: army soldier hits use ArmyHostility")
_cb138("if ownerUid == nil or allyUid(attacker, ownerUid) or AirWeaponService.BaseShielded(ownerUid) then" in _AWS, "CODEBOT v138: gate / guard splash skips allied / shielded bases")
_cb138("return uid ~= nil and not allyUid(attacker, uid) and not AirWeaponService.BaseShielded(uid)" in _AWS, "CODEBOT v138: direct gate hits skip allied / shielded bases")
_cb138("return ownerProtected(attacker, uid)" in _AWS and "if not noviceShielded(attacker) then" in _AWS, "CODEBOT v138: vehicle splash skips allies / novice-shielded owners; a shielded pilot deals no splash")
_cb138("CombatService.EndNoviceShield, player, \"fire\"" in _AWS, "CODEBOT v138: firing ends the pilot's own novice shield (like any shot)")

# ── unchanged guard rails ──
_MON = _rd138(_C138 + "MonetizationConfig.luau")
_cb138("\tRolloutKeys = { ImpulseSpeed = true, RebirthKeepBase = true, GoldenPumpjack = true, PV_Skylance = true, PV_Stormwing = true, PV_Leviathan = true, PV_Tidebreaker = true, PV_Warlord = true, PV_Razorfang = true, BiggerArmy = true, ExtraGarageSlot = true, SoldierRefill = true, PlazaAirstrike = true } :: { [string]: boolean }," in _MON,
       "CODEBOT v138: MonetizationConfig.RolloutKeys unchanged")
_cb138("PreferMeshWhenAssetIdSet = false" in _rd138(_C138 + "StructureVisualConfig.luau"), "CODEBOT v138: PreferMesh stays OFF")
_cb138("FastTravelEnabled = false" in _rd138(_C138 + "MapConfig.luau"), "CODEBOT v138: fast travel stays REMOVED")
