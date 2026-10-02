# Code Bot v107 (2026-09-29): ship Claude Bud BOARDS (Town Centre notice boards live for all).
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb107_.
_cb107_S = "src/ServerScriptService/Server/"
_cb107_SH = "src/ReplicatedStorage/Shared/"
_cb107_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_cb107_LB = _cb107_SH + "Configs/LeaderboardConfig.luau"
_cb107_ES = _cb107_S + "Services/EngagementService.luau"
_cb107_PS = _cb107_S + "Modules/ProfileSchema.luau"

# v108 (Code Bot): retired build pins, superseded in tools/checks/codebot_v108.py:
# for _f in (_cb107_S + "Services/DataService.luau", _cb107_S + "Services/BaseService.luau", _cb107_S + "EarlyRemotes.server.luau"):
#     must_contain(_f, 'SetAttribute("WE_Build", 107)', "CODEBOT v107: WE_Build=107 " + _f.rsplit("/", 1)[-1])
# must_contain(_cb107_S + "Services/DataService.luau", "WE_Build=107", "CODEBOT v107: DataService profile-loaded log says WE_Build=107")

# ── BOARDS live for all ──
must_contain(_cb107_LB, '{ Id = "Kills", Title = "MOST KILLS"', "CODEBOT v107: LeaderboardConfig MOST KILLS")
must_contain(_cb107_LB, '{ Id = "Supporters", Title = "TOP SUPPORTERS"', "CODEBOT v107: LeaderboardConfig TOP SUPPORTERS")
must_contain(_cb107_ES, "local LeaderboardConfig = require(Shared.Configs.LeaderboardConfig)", "CODEBOT v107: EngagementService uses LeaderboardConfig")
must_contain(_cb107_ES, '-- v107: flush on leave but still respect WriteDue (leave/rejoin spam cannot flood stores)', "CODEBOT v107: board write on leave (throttled)")
must_contain(_cb107_CL + "Modules/EngagementClient.luau", "LeaderboardConfig", "CODEBOT v107: EngagementClient boards UI")
must_contain(_cb107_CL + "Controllers/SettingsController.luau", "WE_SupporterOptOut", "CODEBOT v107: Settings supporter opt-out")

# ── keep v104 exploit guards across the BOARDS merge ──
must_contain(_cb107_ES, "FriendsDailyCap", "CODEBOT v107: friends daily cap kept")
must_contain(_cb107_ES, "ComebackPaidFor", "CODEBOT v107: comeback once-per-absence kept")
must_contain(_cb107_ES, "isBoardExcluded", "CODEBOT v107: admin/playtest off boards kept")
must_contain(_cb107_PS, "profile.FriendsDay = nonNegInt(profile.FriendsDay)", "CODEBOT v107: ProfileSchema FriendsDay")
must_contain(_cb107_PS, "profile.ComebackPaidFor = nonNegInt(profile.ComebackPaidFor)", "CODEBOT v107: ProfileSchema ComebackPaidFor")
must_contain(_cb107_PS, "lb.KillsW = nonNegInt(lb.KillsW)", "CODEBOT v107: ProfileSchema LB.KillsW")

# ── keep v105/v106 content ──
must_contain(_cb107_S + "Configs/CodesConfig.luau", "BUDSQUAD", "CODEBOT v107: BUDSQUAD code kept")
must_contain(_cb107_SH + "Configs/SocialConfig.luau", 'DiscordInvite = "https://discord.gg/tkjA2DFBmZ"', "CODEBOT v107: Discord invite kept")
must_contain(_cb107_SH + "Configs/GameFeelConfig.luau", 'KillFeed = "all"', "CODEBOT v107: GameFeel KillFeed still all")
must_contain(_cb107_SH + "Configs/SecurityConfig.luau", 'Rollout = "observe"', "CODEBOT v107: RemoteGate still observe")

# ── untouched ──
must_contain(_cb107_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v107: WE_Building untouched")
must_not_contain(_cb107_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v107: PreferMesh stays OFF")
