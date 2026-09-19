--!strict
--[[
	Assigns a nation color on join / first spawn for captured flag tinting.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local NationColorConfig = require(Shared.Configs.NationColorConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local NationColorService = {}

local DataService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local NotificationService: any = nil

local colorByUserId: { [number]: Color3 } = {}
local idByUserId: { [number]: string } = {}

local function findDef(id: string)
	for _, def in ipairs(NationColorConfig.Colors) do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function pickForUser(userId: number): string
	local roster = NationColorConfig.Colors
	if #roster == 0 then
		return "Crimson"
	end
	-- Stable-ish assignment from userId so rejoins match without profile
	local idx = (math.abs(userId) % #roster) + 1
	return roster[idx].Id
end

local function push(player: Player, colorId: string)
	local def = findDef(colorId)
	local color = if def then def.Color else Color3.fromRGB(200, 45, 55)
	colorByUserId[player.UserId] = color
	idByUserId[player.UserId] = colorId
	local remote = RemoteSetup.Get(Constants.RemoteNames.NationColorUpdate) :: RemoteEvent
	remote:FireClient(player, {
		NationColorId = colorId,
		DisplayName = if def then def.DisplayName else colorId,
		Color = { R = color.R, G = color.G, B = color.B },
	})
end

function NationColorService.GetColor(userId: number): Color3?
	return colorByUserId[userId]
end

function NationColorService.GetColorId(userId: number): string?
	return idByUserId[userId]
end

function NationColorService.EnsureAssigned(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local id = profile.NationColorId
	if typeof(id) ~= "string" or not findDef(id) then
		id = pickForUser(player.UserId)
		profile.NationColorId = id
		DataService.MarkDirty(player)
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.NATION_COLOR_ASSIGN, player.UserId, { color = id })
		end
		if NotificationService then
			local def = findDef(id)
			NotificationService.Notify(
				player,
				"Nation color: " .. (if def then def.DisplayName else id),
				"Info"
			)
		end
	end
	push(player, id :: string)
end

function NationColorService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	NotificationService = deps.NotificationService

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		NationColorService.EnsureAssigned(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		colorByUserId[player.UserId] = nil
		idByUserId[player.UserId] = nil
	end)
end

return NationColorService
