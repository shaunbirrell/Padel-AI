--!strict
--[[
	NationService (nations spec section 2 Server, lane B). The file and the deps key keep the legacy name
	NationColorService, because Bootstrap and TerritoryService already use it.

	A nation is the player's OWN cosmetic country (CLAUDE.md nation rule): a flag on their own base and nothing
	else. It is never a gameplay input and never appears in kill, strike, nuke, raid or capture text, and this service
	never names a nation to anyone but the player who picked it. There is no player-list column (a leaderboard):
	lead decision 1 overrides the spec's leaderstat.

	Kept (legacy): GetColor / GetColorId. NationColorId (the 8-colour roster) is assigned SILENTLY on first load
	(the old join toast that named the colour is gone) and never wiped. GetColor returns the chosen nation's banner colour
	while that nation may be shown (NationConfig.Enabled and (art ready or the player is an admin)), else the legacy
	colour, which also stays the colour of "No flag" players.
	New: GetNationId, AdminReset, the RequestSetNation handler, the flags on the owner's base (Modules/NationFlag).

	RequestSetNation (client -> server, Types.NationRequestPayload), checked in this order (spec R17):
	  1. RateLimitService.Allow(player, "RequestSetNation", RequestRate, RequestBurst), else dropped (no reply)
	  2. a table; Action exactly "pick" / "later"; Source exactly "join" / "flagpole" / "settings", else dropped
	  3. pick: Id a string of <= 8 bytes that is NeutralId or passes NationConfig.Get (exact match), else "invalid";
	     the stored id is always NationConfig's own string, never the client's
	  4. no profile yet -> "loading"
	A pick is allowed right now when (pickAllowedAt == 0):
	  * NationId is nil (never picked, or cleared by the load sanitiser), or
	  * NationId is "NEUTRAL" and NationFreeUntil == 0 (No flag does not use up the first pick; lead decision 2), or
	  * now < NationFreeUntil and NationFreeChanges < FreeRepickMax (the free window), or
	  * now >= NationSetAt + ChangeCooldownSeconds (a NationSetAt later than now counts as 0; lead decision 4).
	Otherwise the reply is "cooldown" with NextChangeAt = NationSetAt + ChangeCooldownSeconds. Picking the id you
	already have replies "ok" and writes nothing (lead decision 3). The first REAL country opens the 10-minute free
	window once per profile (NationFreeUntil = now + FreeRepickSeconds only while it is 0).
	later: honoured only while NeedsPick is true, once per session; NationPrompts + 1 (capped 99). No reply.

	Player attributes (replicated; nothing private): WE_NationId, WE_NationNeedsPick, WE_NationFreeUntil and
	WE_NationNextAt (0 exactly when a pick would be accepted right now, else the time it will be). One task.delay per
	player keeps WE_NationNextAt exact when the free window or the cooldown ends (cancelled on leave; no loops).

	The IP-based suggestion (LocalizationService, pcall, 5 s cap) goes only to that player as NationColorUpdate
	.Suggested, only when it is a roster id; it is kept in memory for the session and never stored, logged or set as
	an attribute. Analytics: NATION_PICKER_SHOWN {source}, NATION_PICK {id, source, first}, NATION_LATER {count}.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalizationService = game:GetService("LocalizationService")

local Shared = ReplicatedStorage.Shared -- replicated by Rojo before any server script runs (no unbounded wait)
local Constants = require(Shared.Constants)
local NationColorConfig = require(Shared.Configs.NationColorConfig)
local NationConfig = require(Shared.Configs.NationConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local NationTexture = require(Shared.Util.NationTexture)

local NationFlag = require(script.Parent.Parent.Modules.NationFlag)

local NationColorService = {}

local DataService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local BaseService: any = nil
local TerritoryService: any = nil

local SUGGEST_TIMEOUT = 5 -- s: a later IP-lookup answer is dropped
local MAX_PROMPTS = 99 -- ProfileSchema MAX_NATION_PROMPTS

-- legacy 8-colour roster (banner colour of "No flag" players)
local legacyColorByUserId: { [number]: Color3 } = {}
local legacyIdByUserId: { [number]: string } = {}
-- what GetColor answers (nation colour while it may be shown, else the legacy colour)
local colorByUserId: { [number]: Color3 } = {}
-- session memory (cleared on PlayerRemoving)
local laterUsed: { [number]: boolean } = {}
local suggestion: { [number]: string } = {} -- the IP suggestion: memory only, this session only
local suggestStarted: { [number]: boolean } = {}
local plotByUserId: { [number]: number } = {}
local refreshTimer: { [number]: thread } = {}

local artReady = false

---------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------

local function num(v: any): number
	if typeof(v) == "number" and v == v and v > -math.huge and v < math.huge then
		return v
	end
	return 0
end

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

local function isAdminUser(userId: number): boolean
	return table.find(AdminConfig.UserIds, userId) ~= nil
end

-- May this player's nation be shown at all? Until the flag art is uploaded only admins see the feature
-- (NationConfig.LiveRequiresArt, lead decision 6).
local function shows(userId: number): boolean
	return NationConfig.Enabled and (not NationConfig.LiveRequiresArt or artReady or isAdminUser(userId))
end

-- the saved id as stored: a NationConfig id, NationConfig.NeutralId or nil
local function savedId(profile: any): string?
	local id = profile.NationId
	if id == NationConfig.NeutralId then
		return NationConfig.NeutralId
	end
	local def = NationConfig.Get(id)
	return if def then def.Id else nil
end

--[[ 0 when a pick would be accepted right now, else the os.time() it will be (lead decision 5). ]]
local function pickAllowedAt(profile: any, now: number): number
	local id = savedId(profile)
	if id == nil then
		return 0
	end
	local freeUntil = num(profile.NationFreeUntil)
	if id == NationConfig.NeutralId and freeUntil == 0 then
		return 0 -- No flag before the first real country (lead decision 2)
	end
	if now < freeUntil and num(profile.NationFreeChanges) < NationConfig.FreeRepickMax then
		return 0
	end
	local setAt = num(profile.NationSetAt)
	if setAt > now then
		setAt = 0 -- clock skew / corrupt save (lead decision 4)
	end
	local at = setAt + NationConfig.ChangeCooldownSeconds
	return if now >= at then 0 else at
end

local function needsPick(userId: number, profile: any): boolean
	return NationConfig.Enabled
		and savedId(profile) == nil
		and num(profile.NationPrompts) < NationConfig.MaxJoinPrompts
		and not laterUsed[userId]
end

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function remote(): RemoteEvent
	return RemoteSetup.Get(Constants.RemoteNames.NationColorUpdate) :: RemoteEvent
end

local function log(event: string, userId: number, props: { [string]: any })
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(event, userId, props)
	end
end

---------------------------------------------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------------------------------------------

local function refreshColor(player: Player, profile: any)
	local uid = player.UserId
	local def = NationConfig.Get(profile.NationId)
	if def and shows(uid) then
		colorByUserId[uid] = def.Color
	else
		colorByUserId[uid] = legacyColorByUserId[uid]
	end
end

local scheduleRefresh: (Player, any, number) -> ()

local function refreshAttributes(player: Player, profile: any)
	local uid = player.UserId
	local now = os.time()
	setAttr(player, "WE_NationId", savedId(profile))
	setAttr(player, "WE_NationNeedsPick", needsPick(uid, profile))
	setAttr(player, "WE_NationFreeUntil", num(profile.NationFreeUntil))
	setAttr(player, "WE_NationNextAt", pickAllowedAt(profile, now))
	scheduleRefresh(player, profile, now)
end

-- One timer per player: the next moment WE_NationNextAt changes by itself (the free window closes, or the
-- cooldown ends). Replaced on every refresh, cancelled on leave.
scheduleRefresh = function(player: Player, profile: any, now: number)
	local uid = player.UserId
	local old = refreshTimer[uid]
	if old then
		refreshTimer[uid] = nil
		pcall(task.cancel, old)
	end
	local at = pickAllowedAt(profile, now)
	if at == 0 then
		local freeUntil = num(profile.NationFreeUntil)
		at = if savedId(profile) ~= nil and now < freeUntil then freeUntil else 0
	end
	if at <= now then
		return
	end
	refreshTimer[uid] = task.delay(at - now + 1, function()
		refreshTimer[uid] = nil
		if player.Parent ~= Players then
			return
		end
		local prof = DataService.GetProfile(player)
		if prof then
			refreshAttributes(player, prof)
		end
	end)
end

local function statePayload(player: Player, profile: any, now: number): { [string]: any }
	local uid = player.UserId
	local legacyId = legacyIdByUserId[uid]
	local legacyDef = if legacyId then findDef(legacyId) else nil
	local legacyColor = legacyColorByUserId[uid] or Color3.fromRGB(200, 45, 55)
	local freeUntil = num(profile.NationFreeUntil)
	return {
		NationColorId = legacyId,
		DisplayName = if legacyDef then legacyDef.DisplayName else legacyId,
		Color = { R = legacyColor.R, G = legacyColor.G, B = legacyColor.B },
		NationId = savedId(profile),
		NeedsPick = needsPick(uid, profile),
		FreeUntil = freeUntil,
		FreeChangesLeft = if now < freeUntil then math.max(0, NationConfig.FreeRepickMax - num(profile.NationFreeChanges)) else 0,
		NextChangeAt = pickAllowedAt(profile, now),
	}
end

local function viewFor(player: Player, profile: any?): NationFlag.View
	return {
		OwnerUserId = player.UserId,
		NationId = if profile then savedId(profile) else nil,
		Show = shows(player.UserId),
	}
end

local function applyFlags(player: Player, profile: any?)
	local uid = player.UserId
	local plotId = plotByUserId[uid]
	if plotId == nil and BaseService and BaseService.GetOwnedPlotId then
		local ok, pid = pcall(BaseService.GetOwnedPlotId, player)
		if ok and typeof(pid) == "number" then
			plotId = pid
			plotByUserId[uid] = pid
		end
	end
	if plotId then
		NationFlag.ApplyPlot(plotId, viewFor(player, profile))
	end
end

-- the IP-based suggestion: that player only, this session only, memory only (spec R3 / R4)
local function startSuggestion(player: Player)
	local uid = player.UserId
	if suggestStarted[uid] or not shows(uid) then
		return
	end
	suggestStarted[uid] = true
	task.spawn(function()
		local t0 = os.clock()
		local ok, code = pcall(function(): any
			return LocalizationService:GetCountryRegionForPlayerAsync(player)
		end)
		if not ok or typeof(code) ~= "string" or os.clock() - t0 > SUGGEST_TIMEOUT then
			return
		end
		if player.Parent ~= Players or not suggestStarted[uid] then
			return -- left (or left and came back) meanwhile
		end
		local def = NationConfig.Get(string.upper(code))
		if def == nil then
			return -- only a roster id is ever suggested (Kosovo has no code of its own: nothing is badged)
		end
		suggestion[uid] = def.Id
		local profile = DataService.GetProfile(player)
		remote():FireClient(player, {
			NeedsPick = if profile then needsPick(uid, profile) else nil,
			Suggested = def.Id,
		})
	end)
end

---------------------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------------------

--[[ Territory tint: the nation's banner colour while it may be shown, else the legacy roster colour. ]]
function NationColorService.GetColor(userId: number): Color3?
	return colorByUserId[userId]
end

function NationColorService.GetColorId(userId: number): string?
	return legacyIdByUserId[userId]
end

--[[ The online player's nation id (a NationConfig id or "NEUTRAL"), or nil when never picked or when nations may not
	be shown for them yet (art gate). Cosmetic only: never a gameplay input, never used in combat / raid text. ]]
function NationColorService.GetNationId(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	if not player or not shows(userId) then
		return nil
	end
	local profile = DataService and DataService.GetProfile(player)
	return if profile then savedId(profile) else nil
end

--[[ Load-time setup: the legacy colour (silent), attributes, the state push, the flags, the suggestion. ]]
function NationColorService.EnsureAssigned(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local uid = player.UserId
	local id = profile.NationColorId
	if typeof(id) ~= "string" or not findDef(id) then
		id = pickForUser(uid)
		profile.NationColorId = id
		DataService.MarkDirty(player)
		log(AnalyticsConfig.Events.NATION_COLOR_ASSIGN, uid, { color = id })
	end
	local def = findDef(id :: string)
	legacyIdByUserId[uid] = id :: string
	legacyColorByUserId[uid] = if def then def.Color else Color3.fromRGB(200, 45, 55)
	refreshColor(player, profile)
	refreshAttributes(player, profile)
	local payload = statePayload(player, profile, os.time())
	payload.Suggested = suggestion[uid]
	remote():FireClient(player, payload)
	if payload.NeedsPick and shows(uid) then
		log(AnalyticsConfig.Events.NATION_PICKER_SHOWN, uid, { source = "join" })
	end
	applyFlags(player, profile)
	if NationConfig.Enabled then
		startSuggestion(player)
	end
end

--[[ nationreset (AdminService, admin allowlist only): clears the CALLER's own nation fields, so the join picker
	and the free first pick can be tested again. Returns false while the profile is still loading. ]]
function NationColorService.AdminReset(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	profile.NationId = nil
	profile.NationSetAt = 0
	profile.NationFreeUntil = 0
	profile.NationFreeChanges = 0
	profile.NationPrompts = 0
	DataService.MarkDirty(player)
	laterUsed[player.UserId] = nil
	refreshColor(player, profile)
	refreshAttributes(player, profile)
	local payload = statePayload(player, profile, os.time())
	payload.Suggested = suggestion[player.UserId]
	remote():FireClient(player, payload)
	applyFlags(player, profile)
	return true
end

---------------------------------------------------------------------------------------------------------------
-- RequestSetNation
---------------------------------------------------------------------------------------------------------------

local function reply(player: Player, payload: { [string]: any })
	remote():FireClient(player, payload)
end

local function acceptPick(player: Player, profile: any, id: string, source: string)
	local uid = player.UserId
	local now = os.time()
	if savedId(profile) == id then
		-- already this flag: "ok", nothing written, no toast (lead decision 3)
		local payload = statePayload(player, profile, now)
		payload.Result = "ok"
		reply(player, payload)
		return
	end
	local nextAt = pickAllowedAt(profile, now)
	if nextAt > 0 then
		reply(player, { Result = "cooldown", NextChangeAt = nextAt })
		return
	end
	local first = num(profile.NationSetAt) == 0
	local freeUntil = num(profile.NationFreeUntil)
	if now < freeUntil and not first then
		profile.NationFreeChanges = num(profile.NationFreeChanges) + 1
	end
	profile.NationId = id
	profile.NationSetAt = now
	if id ~= NationConfig.NeutralId and freeUntil == 0 then
		profile.NationFreeUntil = now + NationConfig.FreeRepickSeconds -- once per profile: never reopens
	end
	DataService.MarkDirty(player)
	refreshColor(player, profile)
	refreshAttributes(player, profile)
	applyFlags(player, profile)
	if NationConfig.OutpostFlags and TerritoryService and typeof(TerritoryService.RefreshOwnerFlags) == "function" then
		pcall(TerritoryService.RefreshOwnerFlags, uid)
	end
	log(AnalyticsConfig.Events.NATION_PICK, uid, { id = id, source = source, first = first })
	if shows(uid) and NotificationService and NotificationService.Notify then
		local def = NationConfig.Get(id)
		pcall(NotificationService.Notify, player, if def then "Flag raised: " .. def.Short else "Plain flag raised", "Success")
	end
	local payload = statePayload(player, profile, now)
	payload.Result = "ok"
	reply(player, payload)
end

local function acceptLater(player: Player, profile: any)
	local uid = player.UserId
	if not needsPick(uid, profile) then
		return -- NeedsPick already false (picked, 3 LATERs, or one LATER this session): ignored
	end
	laterUsed[uid] = true
	profile.NationPrompts = math.min(num(profile.NationPrompts) + 1, MAX_PROMPTS)
	DataService.MarkDirty(player)
	refreshAttributes(player, profile)
	log(AnalyticsConfig.Events.NATION_LATER, uid, { count = profile.NationPrompts })
end

local function onRequest(player: Player, payload: any)
	if not RateLimitService.Allow(player, "RequestSetNation", NationConfig.RequestRate, NationConfig.RequestBurst) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local action = payload.Action
	local source = payload.Source
	if action ~= "pick" and action ~= "later" then
		return
	end
	if source ~= "join" and source ~= "flagpole" and source ~= "settings" then
		return
	end
	if action == "later" then
		if source ~= "join" then
			return -- LATER exists only in the join picker
		end
		local profile = DataService.GetProfile(player)
		if profile then
			acceptLater(player, profile)
		end
		return
	end
	local raw = payload.Id
	local id: string? = nil
	if typeof(raw) == "string" and #raw <= 8 then
		if raw == NationConfig.NeutralId then
			id = NationConfig.NeutralId
		else
			local def = NationConfig.Get(raw)
			if def then
				id = def.Id -- NationConfig's own string, never the client's
			end
		end
	end
	if id == nil or not NationConfig.Enabled then
		reply(player, { Result = "invalid" })
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		reply(player, { Result = "loading" })
		return
	end
	acceptPick(player, profile, id :: string, source :: string)
end

---------------------------------------------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------------------------------------------

function NationColorService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	BaseService = deps.BaseService
	TerritoryService = deps.TerritoryService

	artReady = NationTexture.ArtReady()

	local request = RemoteSetup.Get(Constants.RemoteNames.RequestSetNation) :: RemoteEvent
	request.OnServerEvent:Connect(onRequest)

	NationFlag.SetPromptHandler(function(player: Player, _plotId: number)
		if RateLimitService.Allow(player, "NationPickerShown", 0.2, 2) then
			log(AnalyticsConfig.Events.NATION_PICKER_SHOWN, player.UserId, { source = "flagpole" })
		end
	end)

	-- the owner's own base: parade flag + HQ flag (+ the flagpole prompt while the art gate passes)
	if BaseService and BaseService.OnPlotReady then
		BaseService.OnPlotReady(function(player: Player, plotId: number)
			local uid = player.UserId
			local prev = plotByUserId[uid]
			if prev and prev ~= plotId and NationFlag.OwnerOf(prev) == uid then
				NationFlag.ResetPlot(prev)
			end
			for other, pid in pairs(plotByUserId) do
				if other ~= uid and pid == plotId then
					plotByUserId[other] = nil
				end
			end
			plotByUserId[uid] = plotId
			NationFlag.ApplyPlot(plotId, viewFor(player, DataService.GetProfile(player)))
		end)
	end

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		NationColorService.EnsureAssigned(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		local timer = refreshTimer[uid]
		if timer then
			refreshTimer[uid] = nil
			pcall(task.cancel, timer)
		end
		local plotId = plotByUserId[uid]
		if plotId and NationFlag.OwnerOf(plotId) == uid then
			NationFlag.ResetPlot(plotId) -- plain army green again; parts are never destroyed
		end
		plotByUserId[uid] = nil
		colorByUserId[uid] = nil
		legacyColorByUserId[uid] = nil
		legacyIdByUserId[uid] = nil
		laterUsed[uid] = nil
		suggestion[uid] = nil
		suggestStarted[uid] = nil
	end)
end

return NationColorService
