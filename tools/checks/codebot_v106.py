# Code Bot v106 (2026-09-29): ship Claude Bud JOB 14 (game-feel live for all) + JOB 15 (RemoteGate observe).
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb106_.
_cb106_S = "src/ServerScriptService/Server/"
_cb106_SH = "src/ReplicatedStorage/Shared/"
_cb106_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_cb106_GC = _cb106_SH + "Configs/GameFeelConfig.luau"
_cb106_SC = _cb106_SH + "Configs/SecurityConfig.luau"
_cb106_GS = _cb106_S + "Services/GameFeelService.luau"
_cb106_RG = _cb106_S + "Modules/RemoteGate.luau"

# v107 (Code Bot): retired build pins, superseded in tools/checks/codebot_v107.py:
# for _f in (_cb106_S + "Services/DataService.luau", _cb106_S + "Services/BaseService.luau", _cb106_S + "EarlyRemotes.server.luau"):
#     must_contain(_f, 'SetAttribute("WE_Build", 106)', "CODEBOT v106: WE_Build=106 " + _f.rsplit("/", 1)[-1])
# must_contain(_cb106_S + "Services/DataService.luau", "WE_Build=106", "CODEBOT v106: DataService profile-loaded log says WE_Build=106")

# ── JOB 14 game-feel live for all ──
_cb106_g = read(_cb106_GC) or ""
_cb106_ro = re.search(r"\tRollout = \{(.*?)\n\t\}", _cb106_g, re.S)
_cb106_vals = dict(re.findall(r'(\w+) = "(\w+)"', _cb106_ro.group(1))) if _cb106_ro else {}
for _k in ("KillFeed", "VehicleNumbers", "RaidReport", "SoundPass"):
    (ok if _cb106_vals.get(_k) == "all" else bad)(f"CODEBOT v106: GameFeelConfig.Rollout.{_k} = all ({_cb106_vals.get(_k)})")
must_contain(_cb106_GS, "GameFeelService", "CODEBOT v106: GameFeelService present")
must_contain(_cb106_CL + "Modules/GameFeelClient.luau", 'RegisterTopStack, "KillFeed"', "CODEBOT v106: kill feed in top stack")
must_contain(_cb106_S + "Bootstrap.server.luau", "GameFeelService", "CODEBOT v106: GameFeelService wired in Bootstrap")

# ── JOB 15 RemoteGate observe (safe) ──
must_contain(_cb106_SC, '\t\tRollout = "observe",', "CODEBOT v106: RemoteGate.Rollout = observe")
must_contain(_cb106_SC, '\t\tOthers = "observe",', "CODEBOT v106: RemoteGate.Others = observe")
must_contain(_cb106_SC, "RedeemCode = { \"string:40\" }", "CODEBOT v106: RedeemCode schema kept (v102 Codes)")
must_contain(_cb106_RG, "RemoteGate", "CODEBOT v106: RemoteGate module present")
must_contain(_cb106_S + "Modules/RemoteSetup.luau", "sinkClientOnly", "CODEBOT v106: push-only remotes sinked")

# ── keep v104/v105 content ──
must_contain(_cb106_S + "Configs/CodesConfig.luau", "BUDSQUAD", "CODEBOT v106: BUDSQUAD code kept")
must_contain(_cb106_SH + "Configs/SocialConfig.luau", 'DiscordInvite = "https://discord.gg/tkjA2DFBmZ"', "CODEBOT v106: Discord invite kept")
_cb106_ec = read(_cb106_SH + "Configs/EngagementConfig.luau") or ""
_cb106_ero = re.search(r"\tRollout = \{(.*?)\n\t\}", _cb106_ec, re.S)
_cb106_evals = dict(re.findall(r'(\w+) = "(\w+)"', _cb106_ero.group(1))) if _cb106_ero else {}
for _k in ("Events", "Leaderboards", "Invite", "Friends", "Comeback"):
    (ok if _cb106_evals.get(_k) == "all" else bad)(f"CODEBOT v106: Engagement still all ({_k}={_cb106_evals.get(_k)})")

# ── untouched ──
must_contain(_cb106_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v106: WE_Building untouched")
must_not_contain(_cb106_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v106: PreferMesh stays OFF")
