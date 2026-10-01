--!strict
--[[
	claude-bud JOB 15 (2026-09-29): anti-exploit sweep (Server/Modules/RemoteGate). One gate in front of every
	client -> server remote, on top of each handler's own RateLimitService key and checks (those stay as they are).
	  * Rate ceiling per player per remote (Limits, else Default): set ABOVE every handler's own limit, so a real
	    player never meets it; it stops floods before any handler work.
	  * Argument schema (Schemas): each position's allowed types ("string", "string:N" max length, "number" finite,
	    "boolean", "table" (<= MaxTableKeys keys, <= MaxDepth deep, finite numbers, short strings), "Vector3" finite,
	    "any"; "a|b" either; a trailing "?" = may be nil). More arguments than the schema lists = rejected.
	  * A remote the client should never fire (server pushes, unused requests) gets a sink listener: every fire is a
	    bad request.
	  * Bad requests are logged (one line per player per LogSeconds, with counts) and ignored. Only an extreme flood
	    kicks: FloodKick.Rejects rejected requests inside FloodKick.WindowSeconds.
	Modes: players the gate is live for (Rollout) are ENFORCED (rejected requests dropped, flood kick). Everyone else
	gets Others: "observe" = the same checks, logged as "would reject", never dropped or kicked (OFF = the old
	behaviour for play), "off" = nothing at all. Flip Rollout to "all" after reading the observe logs from live.
]]

local SecurityConfig = {
	RemoteGate = {
		Rollout = "observe", -- "all" = enforced for everyone, "observe" = nobody enforced (flip after reading the logs)
		Others = "observe", -- "observe" | "off"
		Default = { Rate = 15, Burst = 30 },
		Limits = {
			GetPlayerState = { Rate = 30, Burst = 60 }, -- the HUD polls it hard during the first 20 s
			RequestFire = { Rate = 30, Burst = 45 }, -- CombatConfig.FireRemoteRate 20 / burst 28
			VehicleDriveInput = { Rate = 30, Burst = 40 }, -- drive stream 15 / s + Hello / Exit
			RequestVehicleFire = { Rate = 20, Burst = 30 }, -- AircraftWeaponConfig 12 / 16, VehicleWeaponConfig 14 / 20
			RequestPremiumWeapon = { Rate = 20, Burst = 30 }, -- VehicleConfig.Premium.MaxRequestHz 14
			RequestPurchaseUpgrade = { Rate = 10, Burst = 20 },
			RequestMapLive = { Rate = 4, Burst = 8 }, -- claude-bud JOB 30: the open map asks 2x a second
		} :: { [string]: { Rate: number, Burst: number } },
		MaxString = 64,
		MaxTableKeys = 16,
		MaxDepth = 2,
		LogSeconds = 10,
		FloodKick = { Rejects = 600, WindowSeconds = 60 }, -- 10 rejected requests / s for a whole minute
		KickMessage = "Connection reset: too many requests.",
	},

	-- client -> server remotes and their arguments (checked against the client's FireServer calls, 2026-09-29)
	Schemas = {
		GetPlayerState = {},
		RequestPurchaseUpgrade = { "table|string" },
		RequestClaimDailyReward = {},
		RequestSpawnVehicle = { "string" },
		RequestPurchaseVehicle = { "string" },
		RequestDespawnVehicle = {},
		RequestEquipWeapon = { "string" },
		RequestPurchaseWeapon = { "string" },
		RequestFire = { "table" },
		RequestReload = {},
		RequestStartMission = { "string" },
		RequestClaimMission = { "string" },
		RequestCaptureTerritory = { "string" },
		RequestAdminCommand = { "string", "string:200|number|boolean?", "string:200|number|boolean?" },
		RequestPurchaseDevProduct = { "string", "string?" },
		RequestPurchaseGamePass = { "string", "string?" },
		RequestSkipTutorial = {},
		RequestPrestige = { "string?" },
		RequestCreateClan = { "string:32", "string:8" },
		RequestJoinClan = { "string" },
		RequestLeaveClan = {},
		RequestClaimBattlePassReward = { "number", "string?" },
		RequestRecruitSoldiers = { "number?" },
		RequestDismissSoldiers = { "number?" },
		RequestSquadOrder = { "string" },
		RequestDeclareClanWar = { "string" },
		RedeemCode = { "string:40" }, -- Code Bot v102: a RemoteFunction (CodesService); RequestRedeemCode is unused now (sink)
		RequestSetNation = { "table" },
		RequestClaimSpinner = {},
		RequestAnalyticsEvent = { "string", "string?" },
		RequestTipSetting = { "boolean" }, -- claude-bud JOB 24 §5
		RequestTipsReplay = {}, -- claude-bud JOB 24 §5
		RequestBuyArmour = { "number" }, -- claude-bud JOB 26
		RequestMapLive = {}, -- claude-bud JOB 30
		RequestSiteActivity = { "string:8", "string:24?" }, -- claude-bud JOB 31
		RequestNuke = { "string:8", "string:40?" }, -- claude-bud JOB 33
		RequestAchievements = {}, -- claude-bud JOB 34
		RequestArmySend = { "number" }, -- claude-bud JOB 38: the plot id only
		RequestArmySendCheck = { "number" }, -- claude-bud JOB 38
		RequestEndgameBuy = { "string:16", "string:32?" }, -- claude-bud JOB 39: kind + id only, never a price
		RequestEndgameState = {}, -- claude-bud JOB 39
		RequestRivalAction = { "string:8", "number?" }, -- claude-bud JOB 41 C: "open" | "send", plot id (telemetry only)
		RequestRecruitPackResult = { "string:8" }, -- claude-bud JOB 41 B: "shown" | "dropped" (checked in the service)
		RequestRatePromptAnswer = { "string:8" }, -- claude-bud JOB 40 D: one answer word (the service checks the enum)
		RequestNotifOptInResult = { "string:12", "string?" }, -- claude-bud JOB 29: accepted / declined / unavailable, "settings"?
		RequestArmourLook = { "boolean" }, -- claude-bud JOB 26 -- claude-bud JOB 24 §10 (AnalyticsConfig.Roblox.ClientEvents only)
		RequestResearch = { "string", "string?" },
		RequestMissileStrike = { "table" },
		VehicleDriveInput = { "table" },
		RequestVehicleFire = { "table" },
		RequestSetDrawn = { "boolean" },
		RequestPlazaAirstrike = {},
		RequestGroupReward = {},
		RequestPremiumWeapon = { "string", "Vector3" },
		RequestBoardSetting = { "boolean" }, -- claude-bud BOARDS
		OfferResult = { "string:32", "string:12", "number?" }, -- Code Bot v153: offer key, shown / dropped / refused, AckId
	} :: { [string]: { string } },
}

function SecurityConfig.GateLiveFor(userId: any): boolean
	local mode = SecurityConfig.RemoteGate.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
	end
	return false
end

return SecurityConfig
