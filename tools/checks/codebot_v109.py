# Code Bot v109 (2026-09-29): ship Claude Bud JOBs 17–19 (night lighting, WorldFill 2, purchase stands) live for all.
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb109_.
_cb109_S = "src/ServerScriptService/Server/"
_cb109_SH = "src/ReplicatedStorage/Shared/"
_cb109_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"

# v110 (Code Bot): retired build pins, superseded in tools/checks/codebot_v110.py:
# for _f in (_cb109_S + "Services/DataService.luau", _cb109_S + "Services/BaseService.luau", _cb109_S + "EarlyRemotes.server.luau"):
#     must_contain(_f, 'SetAttribute("WE_Build", 109)', "CODEBOT v109: WE_Build=109 " + _f.rsplit("/", 1)[-1])
# must_contain(_cb109_S + "Services/DataService.luau", "WE_Build=109", "CODEBOT v109: DataService profile-loaded log says WE_Build=109")

# ── JOB 17 night (live for all) ──
must_contain(_cb109_SH + "Configs/LightingConfig.luau", "\tEnabled = true,", "CODEBOT v109: LightingConfig Enabled")
must_contain(_cb109_S + "Modules/NightLights.luau", "WE_NightLights", "CODEBOT v109: NightLights folder")
must_contain(_cb109_S + "Modules/WorldAtmosphere.luau", "LightingConfig", "CODEBOT v109: WorldAtmosphere uses LightingConfig")

# ── JOB 18 WorldFill 2 (live for all) ──
must_contain(_cb109_SH + "Configs/WorldFillConfig.luau", "\tFill2 = {", "CODEBOT v109: WorldFillConfig.Fill2")
must_contain(_cb109_S + "Modules/WorldFill.luau", "Build2", "CODEBOT v109: WorldFill.Build2")
must_contain(_cb109_S + "Modules/WorldKits.luau", "Builders.CropField", "CODEBOT v109: WorldKits Fill2 kits")

# ── JOB 19 purchase stands (live for all) ──
must_contain(_cb109_S + "Modules/PurchaseStands.luau", 'pp.ActionText = "Buy - " .. ROBUX', "CODEBOT v109: PurchaseStands prompt")
must_contain(_cb109_S + "Services/PremiumPadService.luau", 'if part:GetAttribute("WE_Stand") == true then', "CODEBOT v109: PremiumPadService stand branch")
must_contain(_cb109_CL + "Modules/StandFx.luau", "StandFx", "CODEBOT v109: StandFx client module")

# ── keep prior launch content ──
must_contain(_cb109_SH + "Configs/ArmyConfig.luau", '\t\t\tFormation = "Flank",', "CODEBOT v109: Flank formation kept")
must_contain(_cb109_S + "Configs/CodesConfig.luau", "BUDSQUAD", "CODEBOT v109: BUDSQUAD code kept")
must_contain(_cb109_SH + "Configs/SocialConfig.luau", 'DiscordInvite = "https://discord.gg/tkjA2DFBmZ"', "CODEBOT v109: Discord invite kept")
must_contain(_cb109_SH + "Configs/GameFeelConfig.luau", 'KillFeed = "all"', "CODEBOT v109: GameFeel KillFeed still all")
must_contain(_cb109_SH + "Configs/SecurityConfig.luau", 'Rollout = "observe"', "CODEBOT v109: RemoteGate still observe")
must_contain(_cb109_SH + "Configs/LeaderboardConfig.luau", '{ Id = "Kills", Title = "MOST KILLS"', "CODEBOT v109: BOARDS MOST KILLS kept")
must_contain(_cb109_SH + "Configs/MonetizationConfig.luau", "RobuxPrice = 99, -- 2026-09-29 owner repriced 5 -> 99 in Creator Hub", "CODEBOT v109: Speed Pass display 99 R$")

# ── untouched ──
must_contain(_cb109_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v109: WE_Building untouched")
must_not_contain(_cb109_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v109: PreferMesh stays OFF")
