# Code Bot v110 (2026-09-29): ship Claude Bud JOB 20 real base guards (live for all).
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb110_.
_cb110_S = "src/ServerScriptService/Server/"
_cb110_SH = "src/ReplicatedStorage/Shared/"
_cb110_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"

# ── build ──
for _f in (_cb110_S + "Services/DataService.luau", _cb110_S + "Services/BaseService.luau", _cb110_S + "EarlyRemotes.server.luau"):
    must_contain(_f, 'SetAttribute("WE_Build", 141)', "CODEBOT v110: WE_Build=110 " + _f.rsplit("/", 1)[-1])
must_contain(_cb110_S + "Services/DataService.luau", "WE_Build=141", "CODEBOT v110: DataService profile-loaded log says WE_Build=110")

# ── JOB 20 real base guards (live for all) ──
must_contain(_cb110_SH + "Configs/GuardConfig.luau", "\tEnabled = true,", "CODEBOT v110: GuardConfig Enabled (live for all)")
must_not_contain(_cb110_SH + "Configs/GuardConfig.luau", "IsPlaytestOwner", "CODEBOT v110: GuardConfig no owner gate")
must_contain(_cb110_S + "Modules/BaseGuards.luau", "function BaseGuards.ThinkGuard", "CODEBOT v110: BaseGuards.ThinkGuard")
must_contain(_cb110_S + "Modules/BaseGuards.luau", "function BaseGuards.ThinkTowers", "CODEBOT v110: BaseGuards.ThinkTowers")
must_contain(_cb110_S + "Services/GateDefenseService.luau", "bgMod.ThinkGuard(def, g, stats, tnow, (GateDefenseService :: any)._H)", "CODEBOT v110: GateDefenseService hooks ThinkGuard")
must_contain(_cb110_S + "Services/GateDefenseService.luau", "local okTw, errTw = pcall(bgMod.ThinkTowers, def, tnow, (GateDefenseService :: any)._H)", "CODEBOT v110: GateDefenseService hooks ThinkTowers")
must_contain(_cb110_S + "Modules/BaseGuards.luau", "pcall(cd.TagCreator, t.Humanoid, owner, false) -- CombatService credits the owner (cash, XP, board, feed)", "CODEBOT v110: guard kills credit owner")
must_contain(_cb110_S + "Modules/BaseGuards.luau", "if flat.Magnitude > C.LeashStuds then", "CODEBOT v110: leash")
must_contain(_cb110_SH + "Configs/ResearchConfig.luau", "TowerGuards", "CODEBOT v110: ResearchConfig TowerGuards")

# ── keep prior launch content ──
must_contain(_cb110_S + "Modules/PurchaseStands.luau", 'pp.ActionText = "Buy - " .. ROBUX', "CODEBOT v110: PurchaseStands kept")
must_contain(_cb110_SH + "Configs/WorldFillConfig.luau", "\tFill2 = {", "CODEBOT v110: WorldFill2 kept")
must_contain(_cb110_SH + "Configs/LightingConfig.luau", "\tEnabled = true,", "CODEBOT v110: night lighting kept")
must_contain(_cb110_SH + "Configs/ArmyConfig.luau", '\t\t\tFormation = "Flank",', "CODEBOT v110: Flank formation kept")
must_contain(_cb110_S + "Configs/CodesConfig.luau", "BUDSQUAD", "CODEBOT v110: BUDSQUAD code kept")
must_contain(_cb110_SH + "Configs/SocialConfig.luau", 'DiscordInvite = "https://discord.gg/tkjA2DFBmZ"', "CODEBOT v110: Discord invite kept")
must_contain(_cb110_SH + "Configs/GameFeelConfig.luau", 'KillFeed = "all"', "CODEBOT v110: GameFeel KillFeed still all")
must_contain(_cb110_SH + "Configs/SecurityConfig.luau", 'Rollout = "observe"', "CODEBOT v110: RemoteGate still observe")
must_contain(_cb110_SH + "Configs/LeaderboardConfig.luau", '{ Id = "Kills", Title = "MOST KILLS"', "CODEBOT v110: BOARDS MOST KILLS kept")
must_contain(_cb110_SH + "Configs/MonetizationConfig.luau", "RobuxPrice = 99, -- 2026-09-29 owner repriced 5 -> 99 in Creator Hub", "CODEBOT v110: Speed Pass display 99 R$")

# ── untouched ──
must_contain(_cb110_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v110: WE_Building untouched")
must_not_contain(_cb110_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v110: PreferMesh stays OFF")
