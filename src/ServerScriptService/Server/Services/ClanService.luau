--!strict
--[[
	Clan roster — DataStore-backed records (name, owner, members) with in-memory cache.
	Graceful fallback when DataStore unavailable (Studio without API services):
	session-only roster + profile.ClanId still works for the session.
	TerritoryService stamps runtime.ClanId from profile.ClanId on capture.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
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
	Members: { [string]: boolean }, -- keyed by tostring(userId) for DataStore JSON safety
	CreatedUnix: number,
}

local CLAN_STORE_NAME = "WarEmpire_Clans_v1"
local INDEX_KEY = "_clan_index_v1"

local DataService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

local clans: { [string]: ClanRecord } = {}
local nextClanSerial = 1
local clanStore: DataStore? = nil
local dataStoreAvailable = false
local nameIndex: { [string]: string } = {} -- lower(name|tag) -> clanId (session + loaded)

local function getClanStore(): DataStore?
	if clanStore then
		return clanStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CLAN_STORE_NAME)
	end)
	if ok then
		clanStore = result
		dataStoreAvailable = true
		return clanStore
	end
	dataStoreAvailable = false
	warn("[ClanService] DataStore unavailable (Studio without API services): session-only clans.", result)
	return nil
end

local function memberKey(userId: number): string
	return tostring(userId)
end

local function memberCount(clan: ClanRecord): number
	local n = 0
	for _ in pairs(clan.Members) do
		n += 1
	end
	return n
end

local function normalizeMembers(raw: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for k, v in pairs(raw) do
		if v == true then
			out[tostring(k)] = true
		end
	end
	return out
end

local function decodeClan(data: any): ClanRecord?
	if typeof(data) ~= "table" or typeof(data.Id) ~= "string" then
		return nil
	end
	if typeof(data.Name) ~= "string" or typeof(data.Tag) ~= "string" then
		return nil
	end
	local leader = tonumber(data.LeaderUserId)
	if not leader then
		return nil
	end
	return {
		Id = data.Id,
		Name = data.Name,
		Tag = data.Tag,
		LeaderUserId = leader,
		Members = normalizeMembers(data.Members),
		CreatedUnix = tonumber(data.CreatedUnix) or os.time(),
	}
end

local function encodeClan(clan: ClanRecord): { [string]: any }
	return {
		Id = clan.Id,
		Name = clan.Name,
		Tag = clan.Tag,
		LeaderUserId = clan.LeaderUserId,
		Members = clan.Members,
		CreatedUnix = clan.CreatedUnix,
	}
end

local function indexKeys(clan: ClanRecord)
	nameIndex["n:" .. string.lower(clan.Name)] = clan.Id
	nameIndex["t:" .. string.upper(clan.Tag)] = clan.Id
end

local function clearIndexKeys(clan: ClanRecord)
	local nKey = "n:" .. string.lower(clan.Name)
	local tKey = "t:" .. string.upper(clan.Tag)
	if nameIndex[nKey] == clan.Id then
		nameIndex[nKey] = nil
	end
	if nameIndex[tKey] == clan.Id then
		nameIndex[tKey] = nil
	end
end

local function persistClan(clan: ClanRecord): boolean
	local store = getClanStore()
	if not store then
		return false
	end
	local ok, err = pcall(function()
		store:SetAsync(clan.Id, encodeClan(clan))
	end)
	if not ok then
		warn("[ClanService] persistClan failed:", clan.Id, err)
		return false
	end
	-- Best-effort index update (list of ids)
	pcall(function()
		store:UpdateAsync(INDEX_KEY, function(old)
			local list = if typeof(old) == "table" then old else {}
			local found = false
			for _, id in ipairs(list) do
				if id == clan.Id then
					found = true
					break
				end
			end
			if not found then
				table.insert(list, clan.Id)
			end
			return list
		end)
	end)
	return true
end

local function deleteClanPersist(clanId: string)
	local store = getClanStore()
	if not store then
		return
	end
	pcall(function()
		store:RemoveAsync(clanId)
	end)
	pcall(function()
		store:UpdateAsync(INDEX_KEY, function(old)
			if typeof(old) ~= "table" then
				return {}
			end
			local nextList = {}
			for _, id in ipairs(old) do
				if id ~= clanId then
					table.insert(nextList, id)
				end
			end
			return nextList
		end)
	end)
end

local function loadClanFromStore(clanId: string): ClanRecord?
	local store = getClanStore()
	if not store then
		return nil
	end
	local ok, data = pcall(function()
		return store:GetAsync(clanId)
	end)
	if not ok then
		warn("[ClanService] GetAsync failed:", clanId, data)
		return nil
	end
	local clan = decodeClan(data)
	if clan then
		clans[clan.Id] = clan
		indexKeys(clan)
	end
	return clan
end

local function ensureClanLoaded(clanId: string): ClanRecord?
	local existing = clans[clanId]
	if existing then
		return existing
	end
	return loadClanFromStore(clanId)
end

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

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local clanId = profile.ClanId
	local clan = if clanId then ensureClanLoaded(clanId) else nil
	local remote = RemoteSetup.Get(Constants.RemoteNames.ClanStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		ClanId = clanId,
		Name = if clan then clan.Name else nil,
		Tag = if clan then clan.Tag else nil,
		LeaderUserId = if clan then clan.LeaderUserId else nil,
		MemberCount = if clan then memberCount(clan) else 0,
		Persisted = dataStoreAvailable,
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
	return ensureClanLoaded(clanId)
end

function ClanService.IsDataStoreAvailable(): boolean
	return dataStoreAvailable
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

	-- Session uniqueness
	if nameIndex["n:" .. string.lower(cleanName)] or nameIndex["t:" .. string.upper(cleanTag)] then
		return false, "NameOrTagTaken"
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
		Members = { [memberKey(leader.UserId)] = true },
		CreatedUnix = os.time(),
	}
	clans[clanId] = record
	indexKeys(record)
	persistClan(record)

	profile.ClanId = clanId
	DataService.MarkDirty(leader)
	pushState(leader)

	if NotificationService then
		local suffix = if dataStoreAvailable then "" else " (session-only — enable API Services)"
		NotificationService.Notify(leader, "Clan created: [" .. cleanTag .. "] " .. cleanName .. suffix, "Success")
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("CLAN_CREATE", leader.UserId, {
			clanId = clanId,
			name = cleanName,
			persisted = dataStoreAvailable,
		})
	end
	return true, nil
end

function ClanService.JoinClan(player: Player, clanId: string): (boolean, string?)
	if typeof(clanId) ~= "string" or clanId == "" then
		return false, "InvalidClanId"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.ClanId then
		return false, "AlreadyInClan"
	end
	local clan = ensureClanLoaded(clanId)
	if not clan then
		return false, "ClanNotFound"
	end
	if memberCount(clan) >= ClanConfig.MaxMembers then
		return false, "ClanFull"
	end
	clan.Members[memberKey(player.UserId)] = true
	persistClan(clan)
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
	local clan = ensureClanLoaded(clanId)
	profile.ClanId = nil
	DataService.MarkDirty(player)
	if clan then
		clan.Members[memberKey(player.UserId)] = nil
		if clan.LeaderUserId == player.UserId then
			local newLeader: number? = nil
			for uidStr in pairs(clan.Members) do
				newLeader = tonumber(uidStr)
				break
			end
			if newLeader then
				clan.LeaderUserId = newLeader
				persistClan(clan)
			else
				clearIndexKeys(clan)
				clans[clanId] = nil
				deleteClanPersist(clanId)
			end
		else
			persistClan(clan)
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

	getClanStore() -- probe availability once at boot

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
		if typeof(profile.ClanId) == "string" and profile.ClanId ~= "" then
			local existing = ensureClanLoaded(profile.ClanId)
			if existing then
				existing.Members[memberKey(player.UserId)] = true
				-- Soft-heal membership if they were missing from roster (e.g. crash mid-join)
				persistClan(existing)
			else
				-- Soft rehydrate stub so territory ClanId stamp still works this session
				local stub: ClanRecord = {
					Id = profile.ClanId,
					Name = "Clan " .. string.sub(profile.ClanId, -4),
					Tag = "CLAN",
					LeaderUserId = player.UserId,
					Members = { [memberKey(player.UserId)] = true },
					CreatedUnix = os.time(),
				}
				clans[profile.ClanId] = stub
				indexKeys(stub)
				if dataStoreAvailable then
					persistClan(stub)
				end
			end
		end
		pushState(player)
	end)

	-- Keep member online flag in session; do not remove from persisted roster on leave server
	Players.PlayerRemoving:Connect(function(_player)
		-- Membership persists across sessions via DataStore / profile.ClanId
	end)
end

return ClanService
