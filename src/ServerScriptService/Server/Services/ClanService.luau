--!strict
--[[
	Clan roster — DataStore-backed records (name, owner, members) with in-memory cache.
	Graceful fallback when DataStore unavailable (Studio without API services):
	session-only roster + profile.ClanId still works for the session.
	TerritoryService stamps runtime.ClanId from profile.ClanId on capture.

	v70: clan ids are random (clan_<12 hex>) instead of a per-server counter (clan_<leader>_1 repeated in
	every server and overwrote older clans). A new record is written create-only, and a clan whose record
	could not be read is never written back over the real one.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ClanConfig = require(Shared.Configs.ClanConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

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
-- v70: clans whose stored record could not be read (DataStore error). Their in-memory copy is a stub, so it
-- is never written back over the real record; ensureClanLoaded retries the read.
local unsynced: { [string]: number } = {} -- clanId -> os.clock() of the last failed read
local UNSYNCED_RETRY_SECONDS = 30
local NEW_ID_ATTEMPTS = 4
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

local function addToIndex(store: DataStore, clanId: string)
	-- Best-effort index update (list of ids)
	pcall(function()
		store:UpdateAsync(INDEX_KEY, function(old)
			local list = if typeof(old) == "table" then old else {}
			for _, id in ipairs(list) do
				if id == clanId then
					return nil -- already listed: cancel (no write)
				end
			end
			table.insert(list, clanId)
			return list
		end)
	end)
end

--[[ v70: a fresh random id. Twelve hex digits (48 bits) from a GUID: short enough to type into the join /
	declare-war box, and never the same across servers (the old per-server counter was). ]]
local function newClanId(): string
	for _ = 1, 8 do
		local hex = string.gsub(HttpService:GenerateGUID(false), "[^%x]", "")
		local id = "clan_" .. string.lower(string.sub(hex, 1, 12))
		if #id == 17 and clans[id] == nil then
			return id
		end
	end
	-- Unreachable in practice; still unique on this server
	return string.format("clan_%x%x", os.time(), math.random(0, 0xFFFFF))
end

--[[ v70: create-only write. "ok" = written; "exists" = another clan already has this id (nothing written);
	"error" = no store / DataStore failure (the clan stays session-only). ]]
local function persistNewClan(clan: ClanRecord): string
	local store = getClanStore()
	if not store then
		return "error"
	end
	local exists = false
	local ok, err = pcall(function()
		store:UpdateAsync(clan.Id, function(old)
			if old ~= nil then
				exists = true
				return nil -- never overwrite another clan's record (nil cancels the write)
			end
			exists = false
			return encodeClan(clan)
		end)
	end)
	if not ok then
		warn("[ClanService] persistNewClan failed:", clan.Id, err)
		return "error"
	end
	if exists then
		return "exists"
	end
	addToIndex(store, clan.Id)
	return "ok"
end

local function persistClan(clan: ClanRecord): boolean
	if unsynced[clan.Id] then
		return false -- stub from a failed read: writing it would replace the real roster
	end
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
	addToIndex(store, clan.Id)
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

--- Returns (record or nil, readOk). readOk = false means the DataStore read failed (record unknown).
local function loadClanFromStore(clanId: string): (ClanRecord?, boolean)
	local store = getClanStore()
	if not store then
		return nil, false
	end
	local ok, data = pcall(function()
		return store:GetAsync(clanId)
	end)
	if not ok then
		warn("[ClanService] GetAsync failed:", clanId, data)
		return nil, false
	end
	local clan = decodeClan(data)
	if clan then
		clans[clan.Id] = clan
		indexKeys(clan)
	end
	return clan, true
end

local function ensureClanLoaded(clanId: string): ClanRecord?
	local existing = clans[clanId]
	if existing then
		local failedAt = unsynced[clanId]
		if failedAt == nil or os.clock() - failedAt < UNSYNCED_RETRY_SECONDS then
			return existing
		end
		-- v70: retry the read that failed; the real record replaces the stub, keeping this session's members
		local stub = existing
		unsynced[clanId] = os.clock() -- one retry at a time; callers meanwhile get the stub
		local loaded, readOk = loadClanFromStore(clanId)
		if not readOk then
			unsynced[clanId] = os.clock()
			clans[clanId] = stub
			return stub
		end
		unsynced[clanId] = nil
		if loaded then
			local added = false
			for uid in pairs(stub.Members) do
				if not loaded.Members[uid] then
					loaded.Members[uid] = true
					added = true
				end
			end
			if added then
				persistClan(loaded)
			end
			if stub.Name ~= loaded.Name or stub.Tag ~= loaded.Tag then
				clearIndexKeys(stub)
				indexKeys(loaded)
			end
			return loaded
		end
		-- No record exists: keep the stub and store it (create-only)
		persistNewClan(stub)
		return stub
	end
	local clan = loadClanFromStore(clanId)
	return clan
end

local function sanitizeName(name: string): string?
	if typeof(name) ~= "string" then
		return nil
	end
	local trimmed = string.gsub(name, "^%s*(.-)%s*$", "%1")
	trimmed = string.gsub(trimmed, "[^%w%s%-_]", "")
	if #trimmed < ClanConfig.MinNameLength or #trimmed > ClanConfig.MaxNameLength then
		return nil
	end
	return trimmed
end

local function sanitizeTag(tag: string): string?
	if typeof(tag) ~= "string" then
		return nil
	end
	local trimmed = string.upper((string.gsub(tag, "%s+", "")))
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

	local clanId = newClanId()
	local record: ClanRecord = {
		Id = clanId,
		Name = cleanName,
		Tag = cleanTag,
		LeaderUserId = leader.UserId,
		Members = { [memberKey(leader.UserId)] = true },
		CreatedUnix = os.time(),
	}
	-- Registered (and the leader's ClanId set) before the DataStore write yields, so a second create
	-- request meanwhile sees AlreadyInClan / NameOrTagTaken.
	clans[clanId] = record
	indexKeys(record)
	profile.ClanId = clanId
	DataService.MarkDirty(leader)

	-- v70: create-only write; on the (astronomically unlikely) id collision pick a new id and try again
	for _ = 1, NEW_ID_ATTEMPTS do
		if persistNewClan(record) ~= "exists" then
			break
		end
		clans[record.Id] = nil
		clearIndexKeys(record)
		record.Id = newClanId()
		clans[record.Id] = record
		indexKeys(record)
		if profile.ClanId == clanId then -- same table the leave-save writes, even if they left meanwhile
			profile.ClanId = record.Id
			DataService.MarkDirty(leader)
		end
		clanId = record.Id
	end

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
	if not RemoteGuard.IsIdString(clanId) then
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
				if unsynced[clanId] then
					-- v70: only a stub was known here (read failed) — never delete the real record
					unsynced[clanId] = nil
				else
					deleteClanPersist(clanId)
				end
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
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		if not RemoteGuard.IsIdString(name, 32) then
			return
		end
		local tagArg = if RemoteGuard.IsIdString(tag, 8) then tag :: string else nil
		local ok, err = ClanService.CreateClan(player, name :: string, tagArg)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot create clan: " .. tostring(err), "Warn")
		end
	end)

	local joinRemote = RemoteSetup.Get(Constants.RemoteNames.RequestJoinClan) :: RemoteEvent
	joinRemote.OnServerEvent:Connect(function(player: Player, clanId: any)
		if not RateLimitService.Allow(player, "clan_join", 2, 3) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		if not RemoteGuard.IsIdString(clanId) then
			return
		end
		local ok, err = ClanService.JoinClan(player, clanId :: string)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot join clan: " .. tostring(err), "Warn")
		end
	end)

	local leaveRemote = RemoteSetup.Get(Constants.RemoteNames.RequestLeaveClan) :: RemoteEvent
	leaveRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "clan_leave", 1, 2) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		ClanService.LeaveClan(player)
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if typeof(profile.ClanId) == "string" and profile.ClanId ~= "" then
			local clanId: string = profile.ClanId
			local existing: ClanRecord? = clans[clanId]
			local readOk = true
			if not existing then
				existing, readOk = loadClanFromStore(clanId)
			else
				existing = ensureClanLoaded(clanId)
			end
			if existing then
				-- Soft-heal membership if they were missing from roster (e.g. crash mid-join)
				if not existing.Members[memberKey(player.UserId)] then
					existing.Members[memberKey(player.UserId)] = true
					persistClan(existing)
				end
			else
				-- Soft rehydrate stub so territory ClanId stamp still works this session
				local stub: ClanRecord = {
					Id = clanId,
					Name = "Clan " .. string.sub(clanId, -4),
					Tag = "CLAN",
					LeaderUserId = player.UserId,
					Members = { [memberKey(player.UserId)] = true },
					CreatedUnix = os.time(),
				}
				clans[clanId] = stub
				indexKeys(stub)
				if not readOk then
					-- v70: the read failed — the real record may exist. Never write this stub over it.
					if dataStoreAvailable then
						unsynced[clanId] = os.clock()
					end
				elseif dataStoreAvailable then
					persistNewClan(stub) -- create-only: no record exists for this id
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
