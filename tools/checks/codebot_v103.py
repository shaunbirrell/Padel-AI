# Code Bot v103 (2026-09-29): ship claude-bud JOB 13 (Engagement — events / leaderboards / invite / friends / comeback)
# onto phase-7-polish as owner-only. Cherry-pick of 36779ce; keep v102 Codes / CashBoost in the cash stack.
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb103_.
_cb103_S = "src/ServerScriptService/Server/"
_cb103_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_cb103_SH = "src/ReplicatedStorage/Shared/"

# ── build ──
# v104 (Code Bot): retired, superseded in tools/checks/codebot_v104.py: #for _f in (_cb103_S + "Services/DataService.luau", _cb103_S + "Services/BaseService.luau", _cb103_S + "EarlyRemotes.server.luau"):
# v104 (Code Bot): retired, superseded in tools/checks/codebot_v104.py: #    must_contain(_f, 'SetAttribute("WE_Build", 103)', "CODEBOT v103: WE_Build=103 " + _f.rsplit("/", 1)[-1])
# v104 (Code Bot): retired, superseded in tools/checks/codebot_v104.py: #must_contain(_cb103_S + "Services/DataService.luau", "WE_Build=103", "CODEBOT v103: DataService profile-loaded log says WE_Build=103")

# ── JOB 13 wired (owner-only) + cash stack keeps both CashBoost and Engagement ──
must_contain(_cb103_SH + "Configs/EngagementConfig.luau", "function EngagementConfig.EventAt(now: number): (any?, number, any?)", "CODEBOT v103: EngagementConfig.EventAt")
# claude-bud BOARDS: retired, superseded in tools/checks/claude_bud_boards.py (the notice boards replaced the single board): #must_contain(_cb103_S + "Services/EngagementService.luau", "DataStoreService:GetOrderedDataStore(b.Store):SetAsync(tostring(player.UserId), v)", "CODEBOT v103: EngagementService writes OrderedDataStores")
must_contain(_cb103_CL + "Modules/EngagementClient.luau", 'pcall((HudLayout :: any).RegisterTopStack, "EventBanner", label, 45)', "CODEBOT v103: event banner in HUD top stack")
must_contain(_cb103_S + "Bootstrap.server.luau", 'safeInit("EngagementService"', "CODEBOT v103: EngagementService init")
must_contain(_cb103_CL + "Bootstrap.client.luau", 'safeInit("EngagementClient"', "CODEBOT v103: EngagementClient init")
must_contain(_cb103_S + "Services/EconomyService.luau", "\t\tmult *= EconomyService.CashBoostMult(profile)\n", "CODEBOT v103: v102 CashBoost still in the cash stack")
must_contain(_cb103_S + "Services/EconomyService.luau", "mult *= (ES :: any).CashMult(player)", "CODEBOT v103: Double Cash events still in the cash stack")
must_contain(_cb103_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v103: WE_Building untouched")
must_not_contain(_cb103_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v103: PreferMesh stays OFF")
