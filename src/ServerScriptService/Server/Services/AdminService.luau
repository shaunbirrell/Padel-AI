--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local AdminConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AdminConfig)
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local AdminService = {}

local EconomyService: any = nil
local XPService: any = nil
local DataService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil

function AdminService.IsAdmin(player: Player): boolean
	for _, id in ipairs(AdminConfig.UserIds) do
		if id == player.UserId then
			return true
		end
	end
	return false
end

function AdminService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	DataService = deps.DataService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService

	local RemoteSetup = deps.RemoteSetup
	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestAdminCommand) :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, command: any, arg1: any, arg2: any)
		if not RateLimitService.Allow(player, "admin", 2, 4) then
			return
		end
		if not AdminService.IsAdmin(player) then
			warn("[AdminService] Unauthorized admin attempt:", player.UserId)
			return
		end
		if not RemoteGuard.IsCommandString(command) then
			return
		end
		-- Admin still requires a loaded profile for mutating commands
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end

		local cmd = string.lower(command :: string)
		local ADMIN_GRANT_MAX = 1_000_000_000
		AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = cmd })

		if cmd == "givecash" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt then
				EconomyService.AddCash(player, amt, "admin")
			end
		elseif cmd == "givegold" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt then
				EconomyService.AddGold(player, amt, "admin")
			end
		elseif cmd == "givexp" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt then
				XPService.AddXP(player, amt, "admin")
			end
		elseif cmd == "setlevel" then
			local lvl = RemoteGuard.ClampPositiveInt(arg1, 1000)
			if lvl then
				XPService.SetLevel(player, lvl)
			end
		elseif cmd == "unlockall" then
			local profile = DataService.GetProfile(player)
			if profile then
				local VehicleConfig = require(ReplicatedStorage.Shared.Configs.VehicleConfig)
				local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
				for id in pairs(VehicleConfig.Vehicles) do
					profile.Vehicles[id] = true
				end
				for id in pairs(WeaponConfig.Weapons) do
					profile.Weapons[id] = true
				end
				DataService.MarkDirty(player)
			end
		elseif cmd == "resetbase" then
			local profile = DataService.GetProfile(player)
			if profile then
				for id in pairs(profile.BaseUpgrades) do
					profile.BaseUpgrades[id] = 0
				end
				DataService.MarkDirty(player)
				if deps.BaseService then
					deps.BaseService.PushState(player)
					if deps.BaseService.RefreshAllVisuals then
						deps.BaseService.RefreshAllVisuals(player)
					end
				end
			end
		elseif cmd == "wipeprofile" then
			-- Delete DataStore key, clear memory (so PlayerRemoving cannot re-save), kick to rejoin fresh
			local userId = player.UserId
			local okWipe, wipeErr = DataService.RemovePersistedProfile(userId)
			if not okWipe then
				warn("[AdminService] wipeprofile RemoveAsync failed:", wipeErr)
			end
			DataService.ClearInMemoryProfile(userId)
			pcall(function()
				local SessionLock = require(script.Parent.Parent.Modules.SessionLock)
				SessionLock.Release(userId)
			end)
			player:Kick("Progress wiped — please rejoin")
			return
		elseif cmd == "resettutorial" then
			if deps.TutorialService and deps.TutorialService.Reset then
				deps.TutorialService.Reset(player)
			end
		elseif cmd == "prestige" or cmd == "forceprestige" then
			if deps.PrestigeService and deps.PrestigeService.DoPrestige then
				-- force: temporarily ignore level gate via SetLevel first if needed
				if cmd == "forceprestige" and deps.XPService then
					local PrestigeConfig = require(ReplicatedStorage.Shared.Configs.PrestigeConfig)
					deps.XPService.SetLevel(player, PrestigeConfig.MinLevelToPrestige)
				end
				local ok, err = deps.PrestigeService.DoPrestige(player)
				if deps.NotificationService then
					deps.NotificationService.Notify(player, if ok then "Prestige OK" else ("Prestige failed: " .. tostring(err)), if ok then "Success" else "Warn")
				end
			end
		elseif cmd == "createclan" and RemoteGuard.IsIdString(arg1, 32) then
			if deps.ClanService and deps.ClanService.CreateClan then
				local tagArg = if RemoteGuard.IsIdString(arg2, 8) then arg2 :: string else nil
				local ok, err = deps.ClanService.CreateClan(player, arg1 :: string, tagArg)
				if not ok and deps.NotificationService then
					deps.NotificationService.Notify(player, "Clan create failed: " .. tostring(err), "Warn")
				end
			end
		elseif cmd == "joinclan" and RemoteGuard.IsIdString(arg1) then
			if deps.ClanService then
				deps.ClanService.JoinClan(player, arg1 :: string)
			end
		elseif cmd == "leaveclan" then
			if deps.ClanService then
				deps.ClanService.LeaveClan(player)
			end
		elseif cmd == "bpxp" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt and deps.BattlePassService and deps.BattlePassService.AddXP then
				deps.BattlePassService.AddXP(player, amt, "admin")
			end
		elseif cmd == "grantpremium" then
			if deps.BattlePassService and deps.BattlePassService.SetPremium then
				deps.BattlePassService.SetPremium(player, true)
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Battle Pass Premium granted", "Success")
				end
			end
		elseif cmd == "grantpass" and RemoteGuard.IsKeyString(arg1) then
			-- Studio mock GamePass ownership (Ids may still be 0)
			if deps.MonetizationService and deps.MonetizationService.SetMockGamePassOwned then
				deps.MonetizationService.SetMockGamePassOwned(player, arg1 :: string, true)
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Mock GamePass owned: " .. arg1, "Success")
				end
			end
		elseif cmd == "endseason" then
			if deps.SeasonService and deps.SeasonService.EndSeason then
				deps.SeasonService.EndSeason("admin:" .. tostring(player.UserId))
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Season ended (admin)", "Info")
				end
			end
		elseif cmd == "resumeseason" then
			if deps.SeasonService and deps.SeasonService.ClearEndOverride then
				deps.SeasonService.ClearEndOverride("admin:" .. tostring(player.UserId))
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Season resumed (admin)", "Success")
				end
			end
		elseif cmd == "resetmap" then
			-- Studio: destroy WarEmpireSetup and rebuild via MapSetup
			if not RunService:IsStudio() then
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "resetmap is Studio-only", "Warn")
				end
				return
			end
			local existing = Workspace:FindFirstChild("WarEmpireSetup")
			if existing then
				existing:Destroy()
			end
			local voidFb = Workspace:FindFirstChild("WE_VoidFallback")
			if voidFb then
				voidFb:Destroy()
			end
			local MapSetup = require(script.Parent.Parent.Modules.MapSetup)
			local ok, err = pcall(function()
				MapSetup.Run()
			end)
			if not ok then
				warn("[WAR EMPIRE] resetmap MapSetup failed: " .. tostring(err))
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "MapSetup failed — check Output", "Error")
				end
				return
			end
			if deps.NotificationService then
				deps.NotificationService.Notify(player, "Map regenerated (MapSetup)", "Success")
			end
		end
	end)
end

return AdminService
