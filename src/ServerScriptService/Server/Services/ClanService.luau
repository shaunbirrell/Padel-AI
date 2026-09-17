--!strict
--[[
	Clan scaffolding — session roster + profile.ClanId persistence.
	TerritoryService stamps runtime.ClanId from profile.ClanId on capture.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ClanConfig = require(Shared.Configs.ClanConfig)

local ClanService = {}

export type ClanRecord = {
	Id: string,
	Name: string,
	Tag: string,
	LeaderUserId: number,
	Members: { [number]: boolean },
	CreatedUnix: number,
}

local DataService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

-- Session-authoritative clan table (not DataStore yet — reversible; ClanId on profile persists)
local clans: { [string]: ClanRecord } = {}
local nextClanSerial = 1

local function sanitizeName(name: string): string?
	if typeof(name) ~= "string" then
		return nil
	end
	local trimmed = string.gsub(name, "^%s*(.-)%s*$", "%1")
	trimmed = string.gsub(trimmed, "[^%w%s%-%_]", "")
	if #trimmed < ClanConfig.MinNameLength or #trimmed > ClanConfig.MaxNameLength then
		return nil
	end
	return trimmed
end

local function sanitizeTag(tag: string): string?
	if typeof(tag) ~= "string" then
		return nil
	end
	local trimmed = string.upper(string.gsub(tag, "%s+", ""))
	trimmed = string.gsub(trimmed, "[^%w]", "")
	if #trimmed < ClanConfig.MinTagLength or #trimmed > ClanConfig.MaxTagLength then
		return nil
	end
	return trimmed
end

local function memberCount(clan: ClanRecord): number
	local n = 0
	for _ in pairs(clan.Members) do
		n += 1
	end
	return n
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local clanId = profile.ClanId
	local clan = if clanId then clans[clanId] else nil
	local remote = RemoteSetup.Get(Constants.RemoteNames.ClanStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		ClanId = clanId,
		Name = if clan then clan.Name else nil,
		Tag = if clan then clan.Tag else nil,
		LeaderUserId = if clan then clan.LeaderUserId else nil,
		MemberCount = if clan then memberCount(clan) else 0,
	})
end

function ClanService.GetClanId(player: Player): string?
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end
	return profile.ClanId
end

function ClanService.GetClan(clanId: string): ClanRecord?
	return clans[clanId]
end

function ClanService.CreateClan(leader: Player, name: string, tag: string?): (boolean, string?)
	local profile = DataService.GetProfile(leader)
	if not profile then
		return false, "NoProfile"
	end
	if profile.ClanId then
		return false, "AlreadyInClan"
	end
	local cleanName = sanitizeName(name)
	if not cleanName then
		return false, "InvalidName"
	end
	local cleanTag = sanitizeTag(tag or string.sub(cleanName, 1, ClanConfig.MaxTagLength))
	if not cleanTag then
		return false, "InvalidTag"
	end
	for _, clan in pairs(clans) do
		if string.lower(clan.Name) == string.lower(cleanName) or clan.Tag == cleanTag then
			return false, "NameOrTagTaken"
		end
	end

	local clanId = string.format("clan_%d_%d", leader.UserId, nextClanSerial)
	nextClanSerial += 1
	local record: ClanRecord = {
		Id = clanId,
		Name = cleanName,
		Tag = cleanTag,
		LeaderUserId = leader.UserId,
		Members = { [leader.UserId] = true },
		CreatedUnix = os.time(),
	}
	clans[clanId] = record
	profile.ClanId = clanId
	DataService.MarkDirty(leader)
	pushState(leader)

	if NotificationService then
		NotificationService.Notify(leader, "Clan created: [" .. cleanTag .. "] " .. cleanName, "Success")
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("CLAN_CREATE", leader.UserId, { clanId = clanId, name = cleanName })
	end
	return true, nil
end

function ClanService.JoinClan(player: Player, clanId: string): (boolean, string?)
	if typeof(clanId) ~= "string" then
		return false, "InvalidClanId"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.ClanId then
		return false, "AlreadyInClan"
	end
	local clan = clans[clanId]
	if not clan then
		return false, "ClanNotFound"
	end
	if memberCount(clan) >= ClanConfig.MaxMembers then
		return false, "ClanFull"
	end
	clan.Members[player.UserId] = true
	profile.ClanId = clanId
	DataService.MarkDirty(player)
	pushState(player)
	if NotificationService then
		NotificationService.Notify(player, "Joined clan [" .. clan.Tag .. "] " .. clan.Name, "Success")
	end
	return true, nil
end

function ClanService.LeaveClan(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local clanId = profile.ClanId
	if not clanId then
		return false, "NotInClan"
	end
	local clan = clans[clanId]
	profile.ClanId = nil
	DataService.MarkDirty(player)
	if clan then
		clan.Members[player.UserId] = nil
		if clan.LeaderUserId == player.UserId then
			-- Promote another member or dissolve
			local newLeader: number? = nil
			for userId in pairs(clan.Members) do
				newLeader = userId
				break
			end
			if newLeader then
				clan.LeaderUserId = newLeader
			else
				clans[clanId] = nil
			end
		end
	end
	pushState(player)
	if NotificationService then
		NotificationService.Notify(player, "Left clan.", "Info")
	end
	return true, nil
end

function ClanService.Push(player: Player)
	pushState(player)
end

function ClanService.Init(deps: { [string]: any })
	DataService = deps.DataService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	local createRemote = RemoteSetup.Get(Constants.RemoteNames.RequestCreateClan) :: RemoteEvent
	createRemote.OnServerEvent:Connect(function(player: Player, name: any, tag: any)
		if not RateLimitService.Allow(player, "clan_create", 1, 2) then
			return
		end
		if typeof(name) ~= "string" then
			return
		end
		local ok, err = ClanService.CreateClan(player, name, if typeof(tag) == "string" then tag else nil)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot create clan: " .. tostring(err), "Warn")
		end
	end)

	local joinRemote = RemoteSetup.Get(Constants.RemoteNames.RequestJoinClan) :: RemoteEvent
	joinRemote.OnServerEvent:Connect(function(player: Player, clanId: any)
		if not RateLimitService.Allow(player, "clan_join", 2, 3) then
			return
		end
		local ok, err = ClanService.JoinClan(player, clanId)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot join clan: " .. tostring(err), "Warn")
		end
	end)

	local leaveRemote = RemoteSetup.Get(Constants.RemoteNames.RequestLeaveClan) :: RemoteEvent
	leaveRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "clan_leave", 1, 2) then
			return
		end
		ClanService.LeaveClan(player)
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		-- Re-attach to session clan table if ClanId set (roster empty after server restart — expected)
		if typeof(profile.ClanId) == "string" and profile.ClanId ~= "" then
			local existing = clans[profile.ClanId]
			if existing then
				existing.Members[player.UserId] = true
			else
				-- Soft rehydrate stub clan so territory ClanId stamp still works this session
				clans[profile.ClanId] = {
					Id = profile.ClanId,
					Name = "Clan " .. string.sub(profile.ClanId, -4),
					Tag = "CLAN",
					LeaderUserId = player.UserId,
					Members = { [player.UserId] = true },
					CreatedUnix = os.time(),
				}
			end
		end
		pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local profile = DataService.GetProfile(player)
		if profile and profile.ClanId then
			local clan = clans[profile.ClanId]
			if clan then
				clan.Members[player.UserId] = nil
			end
		end
	end)
end

return ClanService
