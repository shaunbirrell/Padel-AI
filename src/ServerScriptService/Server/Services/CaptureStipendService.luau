--!strict
--[[
	Periodic cash stipend for owned territories / coastal oil.
	v71 (HUD v70 spec §4.2): silent by default (TerritoryConfig.CaptureStipend.NotifyOnPayout = false) — the cash
	pill counts up; the old "Capture stipend +$N" Reward line came every 90 s for as long as you held a zone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local CaptureStipendService = {}

local DataService: any = nil
local EconomyService: any = nil
local TerritoryService: any = nil
local NotificationService: any = nil
local AnalyticsService: any = nil

local function stipendForDef(def: any): number
	local cfg = TerritoryConfig.CaptureStipend
	if typeof(def.StipendCash) == "number" then
		return def.StipendCash
	end
	if def.IsOilRig then
		return cfg.OilRigCash or 14000
	end
	if def.IsFortress then
		return cfg.FortressCash or 10000
	end
	return cfg.DefaultCash or 4000
end

local function payoutPlayer(player: Player)
	if not TerritoryService or not TerritoryService.GetRuntime then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local total = 0
	local count = 0
	local oilCount = 0
	local ot = TerritoryConfig.OwnerTypes
	for id, def in pairs(TerritoryConfig.Territories) do
		local rt = TerritoryService.GetRuntime(id)
		if rt then
			local owns = (rt.OwnerType == ot.Player and rt.OwnerUserId == player.UserId)
				or (rt.OwnerType == ot.Clan and profile.ClanId ~= nil and rt.ClanId == profile.ClanId)
			if owns then
				total += stipendForDef(def)
				count += 1
				if def.IsOilRig then
					oilCount += 1
				end
			end
		end
	end
	if total <= 0 then
		return
	end
	EconomyService.AddCash(player, total, "capture_stipend")
	if TerritoryConfig.CaptureStipend.NotifyOnPayout and NotificationService then
		local oilHint = if oilCount > 0 then string.format(" (%d oil)", oilCount) else ""
		NotificationService.Notify(
			player,
			string.format("Capture stipend +$%d from %d zones%s", total, count, oilHint),
			"Reward"
		)
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.CAPTURE_STIPEND, player.UserId, {
			cash = total,
			zones = count,
			oil = oilCount,
		})
	end
end

function CaptureStipendService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	TerritoryService = deps.TerritoryService
	NotificationService = deps.NotificationService
	AnalyticsService = deps.AnalyticsService

	local tickSec = (TerritoryConfig.CaptureStipend and TerritoryConfig.CaptureStipend.TickSeconds) or 90
	task.spawn(function()
		while true do
			task.wait(tickSec)
			for _, player in ipairs(Players:GetPlayers()) do
				pcall(payoutPlayer, player)
			end
		end
	end)
end

return CaptureStipendService
