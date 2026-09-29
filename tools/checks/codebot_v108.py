# Code Bot v108 (2026-09-29): ship Claude Bud army Flank formation (soldiers beside owner, in front of phone camera).
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb108_.
_cb108_S = "src/ServerScriptService/Server/"
_cb108_SH = "src/ReplicatedStorage/Shared/"
_cb108_AC = _cb108_SH + "Configs/ArmyConfig.luau"
_cb108_AF = _cb108_S + "Modules/ArmyFollow.luau"

# ── build ──
for _f in (_cb108_S + "Services/DataService.luau", _cb108_S + "Services/BaseService.luau", _cb108_S + "EarlyRemotes.server.luau"):
    must_contain(_f, 'SetAttribute("WE_Build", 108)', "CODEBOT v108: WE_Build=108 " + _f.rsplit("/", 1)[-1])
must_contain(_cb108_S + "Services/DataService.luau", "WE_Build=108", "CODEBOT v108: DataService profile-loaded log says WE_Build=108")

# ── Flank formation (live for all via Follow2.Tidy) ──
must_contain(_cb108_AC, '\t\t\tFormation = "Flank",', 'CODEBOT v108: ArmyConfig.Follow2.Tidy.Formation = Flank')
must_contain(_cb108_AC, "FlankFront = -1,", "CODEBOT v108: FlankFront ahead of owner")
must_contain(_cb108_AC, "FlankRowBack = 3,", "CODEBOT v108: FlankRowBack")
must_contain(_cb108_AC, "FlankSide = 3.5,", "CODEBOT v108: FlankSide")
must_contain(_cb108_AC, "FlankRowSide = 2.6,", "CODEBOT v108: FlankRowSide")
must_contain(_cb108_AF, 'back = tnum("FlankFront", -1) + (row - 1) * tnum("FlankRowBack", 3)', "CODEBOT v108: ArmyFollow flank row math")
must_contain(_cb108_AC, '\t\t\tRollout = "all", -- v101', "CODEBOT v108: Tidy still Rollout all")

# ── keep prior launch content ──
must_contain(_cb108_S + "Configs/CodesConfig.luau", "BUDSQUAD", "CODEBOT v108: BUDSQUAD code kept")
must_contain(_cb108_SH + "Configs/SocialConfig.luau", 'DiscordInvite = "https://discord.gg/tkjA2DFBmZ"', "CODEBOT v108: Discord invite kept")
must_contain(_cb108_SH + "Configs/GameFeelConfig.luau", 'KillFeed = "all"', "CODEBOT v108: GameFeel KillFeed still all")
must_contain(_cb108_SH + "Configs/SecurityConfig.luau", 'Rollout = "observe"', "CODEBOT v108: RemoteGate still observe")
must_contain(_cb108_SH + "Configs/LeaderboardConfig.luau", '{ Id = "Kills", Title = "MOST KILLS"', "CODEBOT v108: BOARDS MOST KILLS kept")

# ── untouched ──
must_contain(_cb108_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v108: WE_Building untouched")
must_not_contain(_cb108_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v108: PreferMesh stays OFF")
