# Code Bot v100 (2026-09-29): ship Claude Bud JOB 9–11 + PREMIUM (tip 3cf54f2) onto phase-7-polish (v99 c32bd9a).
# Keep v99 Creator Hub Ids + army/rifle fixes. Feature pins live in claude_bud_q2.py / claude_bud_premium.py / codebot_v99.py.
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb100_.
import re as _cb100_re

# ── build ──
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 100)', "CODEBOT v100: WE_Build=100 DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 100)', "CODEBOT v100: WE_Build=100 BaseService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 100)', "CODEBOT v100: WE_Build=100 EarlyRemotes")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=100", "CODEBOT v100: DataService profile-loaded log says WE_Build=100")

# ── v99 Creator Hub Ids kept (do not regress to Id 0) ──
_cb100_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_cb100_M = read(_cb100_mc) or ""
for _key, _id, _price in (("PV_Skylance", 2001602422, 899), ("PV_Stormwing", 2001722392, 999), ("PV_Leviathan", 2001398410, 1199),
                          ("PV_Tidebreaker", 1999263465, 299), ("PV_Warlord", 2001320428, 799), ("PV_Razorfang", 2002484380, 199),
                          ("BiggerArmy", 2001734404, 249), ("ExtraGarageSlot", 1999359549, 199),
                          ("SoldierRefill", 3715442523, 49), ("PlazaAirstrike", 3715442542, 79)):
    _m = _cb100_re.search(r"\n\t\t" + _key + r" = \{[^\n]*\n\t\t\tId = (\d+),.*?RobuxPrice = (\d+),", _cb100_M, _cb100_re.S)
    (ok if bool(_m) and int(_m.group(1)) == _id and int(_m.group(2)) == _price else bad)(f"CODEBOT v100: {_key} Id {_id}, {_price} R$ (v99 pin kept)")

# ── v99 army / rifle surfaces kept (Claude JOB9–11 must not undo) ──
must_contain("src/ServerScriptService/Server/Modules/ArmyFollow.luau", "function ArmyFollow.AttackPoint(", "CODEBOT v100: ArmyFollow AttackPoint kept")
must_contain("src/ServerScriptService/Server/Modules/ArmyFollow.luau", "local holdOut = st._afTidy and st._afInBase", "CODEBOT v100: army gate hold kept")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", '\tFollow2 = {\n\t\tEnabled = true,\n\t\tRollout = "all",', "CODEBOT v100: Follow2 kept")
must_contain("src/ReplicatedStorage/Shared/Configs/HudConfig.luau", "\tTouchTapHolsters = true,", "CODEBOT v100: TouchTapHolsters kept")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau", "HolsterAutoDrawGraceSeconds", "CODEBOT v100: holster grace kept")

# ── JOB 9 / 10 / 11 + PREMIUM key needles ──
must_contain("src/ReplicatedStorage/Shared/Configs/BalanceConfig.luau", 'Rollout = "owner"', "CODEBOT v100: BalanceConfig owner-only")
must_contain("src/ReplicatedStorage/Shared/Configs/JuiceConfig.luau", 'Rollout = "owner"', "CODEBOT v100: JuiceConfig owner-only")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/Juice.luau", "burst(J)", "CODEBOT v100: Juice purchase burst")
must_contain("src/ServerScriptService/Server/Services/PremiumWeaponService.luau", "PremiumWeaponService", "CODEBOT v100: PremiumWeaponService present")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/PremiumWeaponsClient.luau", "PremiumWeaponsClient", "CODEBOT v100: PremiumWeaponsClient present")
must_contain("src/ServerScriptService/Server/Bootstrap.server.luau", 'safeInit("PremiumWeaponService"', "CODEBOT v100: PremiumWeaponService init")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau", 'safeInit("Juice"', "CODEBOT v100: Juice client init")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau", 'safeInit("PremiumWeaponsClient"', "CODEBOT v100: PremiumWeaponsClient init")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "ModelAssetId = 16692908395", "CODEBOT v100: no real-world PT-boat body")
must_not_contain("default.project.json", '"StreamingEnabled": true', "CODEBOT v100: StreamingEnabled stays OFF")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false,", "CODEBOT v100: PreferMesh stays OFF")
