--!strict
--[[
	Analytics abstraction. Does not fabricate metrics — only logs events you fire.

	claude-bud JOB 24 §10: the sink is Roblox's AnalyticsService (Creator Hub -> Analytics), AnalyticsConfig.Roblox:
	  * Funnel: the onboarding steps (Roblox.Funnel, in order: join -> cash collect -> first building -> Army -> first
	    attack -> first outpost -> purchase prompt -> purchase) through LogOnboardingFunnelStepEvent, for NEW players
	    only (profile.FirstJoinUnix within FunnelNewPlayerSeconds of their first join), each step once, remembered in
	    profile.AnalyticsFunnel so a rejoin never logs it twice.
	  * Economy: AnalyticsService.Economy (EconomyService AddCash / SpendCash) sums Cash per player per flow + reason and
	    flushes every EconomyFlushSeconds (and on leave) through LogEconomyEvent (the Robux side is MonetizationService's
	    IAP economy event, unchanged).
	  * Custom: the events listed in Roblox.Custom through LogCustomEvent, under a per-minute budget.
	  * The client may report a few UI events (Roblox.ClientEvents: shop / Army opened, tips) on RequestAnalyticsEvent,
	    rate-limited; nothing else from the client is ever logged.
	Studio (or LogToOutput) still prints every event. Every Roblox call is pcall'd: analytics never breaks gameplay.

	claude-bud JOB 29: onboarding steps (RetentionConfig.Funnel). AnalyticsService.Onboard(player, step) records the
	seconds since this session's join, once per step per session:
	  * logged on the SAME funnel above as the event "STEP:<step>" (AnalyticsConfig.Roblox.Funnel lists which row);
	  * sent as the custom event ONBOARD_STEP ("OnboardingSeconds", value = seconds, field = step) for NEW players only
	    (same rule as the funnel; marks made before the save loads wait and are sent once it is known);
	  * printed "[FUNNEL] <step> t=<s>" in Studio for everyone, plus a one-line summary on leave.
	Steps come from:
	  * RetentionService: Joined, CharacterSpawned;
	  * TutorialService: BaseClaimed, Tut_<step Id>, TutorialDone / TutorialSkipped;
	  * this Log (ONBOARD_FROM_EVENT): first cash collect, first purchase, first recruit, first Robux, SessionEnd.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local AnalyticsConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AnalyticsConfig)
local RetentionConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.RetentionConfig) -- claude-bud JOB 29
local AdminConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AdminConfig)

local AnalyticsService = {}
AnalyticsService.Stats = { Custom = 0, Funnel = 0, Economy = 0, Dropped = 0, Client = 0 }

local function isAdminUser(userId: number?): boolean
	if typeof(userId) ~= "number" or (AnalyticsConfig.Privacy and AnalyticsConfig.Privacy.ExcludeAdminUserIds ~= true) then
		return false
	end
	for _, id in ipairs((AdminConfig :: any).UserIds or {}) do
		if tonumber(id) == userId then
			return true
		end
	end
	return false
end

local PII_KEYS: { [string]: boolean } = {
	UserId = true, userId = true, VictimUserId = true, playerName = true, PlayerName = true,
	DisplayName = true, Username = true, username = true, Name = true, IP = true, ip = true,
}
local function safeProps(props: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	if typeof(props) ~= "table" then
		return out
	end
	for key, value in pairs(props) do
		if typeof(key) == "string" and not PII_KEYS[key] then
			local kind = typeof(value)
			if kind == "string" or kind == "number" or kind == "boolean" then
				out[key] = if kind == "string" then string.sub(value, 1, 50) else value
			end
		end
	end
	return out
end

local sink: ((eventName: string, userId: number?, props: { [string]: any }?) -> ())? = nil
local RC: any = (AnalyticsConfig :: any).Roblox

local function rbx(): any?
	if typeof(RC) ~= "table" or RC.Enabled ~= true then
		return nil
	end
	local ok, svc = pcall(function()
		return game:GetService("AnalyticsService")
	end)
	return if ok then svc else nil
end

local function dataService(): any?
	local ok, m = pcall(function()
		return require(script.Parent.DataService) :: any
	end)
	return if ok then m else nil
end

-- ── funnel ─────────────────────────────────────────────────────────────────────────────────────────────────────
local stepOf: { [string]: { Index: number, Name: string } } = {}
if typeof(RC) == "table" and typeof(RC.Funnel) == "table" then
	for i, row in ipairs(RC.Funnel) do
		for _, ev in ipairs(row.Events) do
			if stepOf[ev] == nil then
				stepOf[ev] = { Index = i, Name = row.Step }
			end
		end
	end
end

-- JOB 61: the eight-step first-session funnel. State is saved per player, so rejoining cannot
-- fire a step twice. Event names are server-produced; client input is never accepted as a step.
local primaryStepByEvent: { [string]: string } = {}
local primaryStepIndex: { [string]: number } = {}
local primaryStepName: { [string]: string } = {}
for index, row in ipairs(((AnalyticsConfig :: any).Onboarding and (AnalyticsConfig :: any).Onboarding.Steps) or {}) do
	if typeof(row) == "table" and typeof(row.Name) == "string" then
		primaryStepIndex[row.Name] = index
		primaryStepName[row.Name] = row.Name
		if typeof(row.Event) == "string" then
			primaryStepByEvent[row.Event] = row.Name
		end
	end
end
local primaryPending: { [number]: { string } } = {}

local function onboardingStep(player: Player, name: string)
	if isAdminUser(player.UserId) or ((AnalyticsConfig :: any).Onboarding or {}).Enabled ~= true then
		return
	end
	local index = primaryStepIndex[name]
	if index == nil then
		return
	end
	local ds = dataService()
	local profile = ds and ds.GetProfile and ds.GetProfile(player)
	if profile == nil then
		local q = primaryPending[player.UserId] or {}
		primaryPending[player.UserId] = q
		if not table.find(q, name) then
			table.insert(q, name)
		end
		return
	end
	local maxAge = tonumber(((AnalyticsConfig :: any).Onboarding or {}).MaxFirstSessionSeconds) or 900
	local first = tonumber(profile.FirstJoinUnix) or 0
	local f = (profile :: any).AnalyticsOnboarding
	if typeof(f) ~= "table" then
		if first <= 0 or os.time() - first > maxAge then
			(profile :: any).AnalyticsOnboarding = { Off = true }
			return
		end
		f = { Steps = {}, StartedUnix = first }
		(profile :: any).AnalyticsOnboarding = f
	end
	if f.Off == true then return end
	f.Steps = if typeof(f.Steps) == "table" then f.Steps else {}
	if f.Steps[name] == true then return end
	f.Steps[name] = true
	if ds.MarkDirty then
		pcall(ds.MarkDirty, player)
	end
	local svc = rbx()
	if svc == nil then return end
	local ok = pcall(function()
		svc:LogOnboardingFunnelStepEvent(player, index, primaryStepName[name])
	end)
	if ok then
		AnalyticsService.Stats.Funnel += 1
	end
end

local function flushPrimaryPending(player: Player)
	local q = primaryPending[player.UserId]
	if q == nil then return end
	primaryPending[player.UserId] = nil
	for _, name in ipairs(q) do
		onboardingStep(player, name)
	end
end

local function funnel(player: Player, eventName: string)
	local st = stepOf[eventName]
	local svc = rbx()
	if st == nil or svc == nil then
		return
	end
	local ds = dataService()
	local profile = ds and ds.GetProfile and ds.GetProfile(player)
	if profile == nil then
		return
	end
	local f = profile.AnalyticsFunnel
	if typeof(f) ~= "table" then
		-- only a player who first joined within FunnelNewPlayerSeconds enters the funnel (older saves never do)
		local first = tonumber(profile.FirstJoinUnix) or 0
		if first <= 0 or os.time() - first > (tonumber(RC.FunnelNewPlayerSeconds) or 900) then
			profile.AnalyticsFunnel = { Off = true }
			return
		end
		f = { Steps = {} }
		profile.AnalyticsFunnel = f
	end
	if f.Off == true or typeof(f.Steps) ~= "table" or f.Steps[tostring(st.Index)] then
		return
	end
	f.Steps[tostring(st.Index)] = true
	pcall(ds.MarkDirty, player)
	local ok = pcall(function()
		svc:LogOnboardingFunnelStepEvent(player, st.Index, st.Name)
	end)
	if ok then
		AnalyticsService.Stats.Funnel += 1
	end
end

-- ── custom events (budgeted) ───────────────────────────────────────────────────────────────────────────────────
local budget = { At = 0, N = 0 }
local function budgetOk(): boolean
	local now = os.clock()
	if now - budget.At >= 60 then
		budget.At = now
		budget.N = 0
	end
	local cap = (tonumber(RC.MaxCustomPerMinute) or 100) + (tonumber(RC.PerPlayerPerMinute) or 10) * #Players:GetPlayers()
	if budget.N >= cap then
		AnalyticsService.Stats.Dropped += 1
		return false
	end
	budget.N += 1
	return true
end

local function custom(player: Player, eventName: string, props: { [string]: any }?)
	if isAdminUser(player.UserId) then return end
	props = safeProps(props)
	local map = typeof(RC) == "table" and RC.Custom and RC.Custom[eventName]
	local svc = rbx()
	if not map or svc == nil or not budgetOk() then
		return
	end
	local value = 1
	if map.Value and props and tonumber(props[map.Value]) then
		value = tonumber(props[map.Value]) :: number
	end
	local fields: any = nil
	if map.Field and props and props[map.Field] ~= nil then
		fields = { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = string.sub(tostring(props[map.Field]), 1, 50) }
	end
	-- claude-bud JOB 42: an optional second field (CustomField02), e.g. the time-pack income bucket on RobuxPurchase
	if map.Field2 and props and props[map.Field2] ~= nil then
		fields = fields or {}
		fields[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = string.sub(tostring(props[map.Field2]), 1, 50)
	end
	local ok = pcall(function()
		svc:LogCustomEvent(player, map.Name, value, fields)
	end)
	if ok then
		AnalyticsService.Stats.Custom += 1
	end
end

-- ── session length ─────────────────────────────────────────────────────────────────────────────────────────────
local joinedAt: { [number]: number } = {}
local function bucketOf(minutes: number): string
	if minutes < 2 then
		return "0-2"
	elseif minutes < 5 then
		return "2-5"
	elseif minutes < 15 then
		return "5-15"
	elseif minutes < 30 then
		return "15-30"
	elseif minutes < 60 then
		return "30-60"
	end
	return "60+"
end

-- ── economy (summed, flushed) ──────────────────────────────────────────────────────────────────────────────────
type Pending = { Flow: string, Currency: string, Amount: number, Balance: number, Reason: string, ItemSKU: string, TxType: string }
local pending: { [number]: { [string]: Pending } } = {}

local function startsWith(value: string, prefix: string): boolean
	return string.sub(value, 1, #prefix) == prefix
end

local function economySKU(reason: string, flow: string): string
	local E: any = (AnalyticsConfig :: any).Economy or {}
	local direct = if flow == "Source" then E.SourceSKUs else E.SinkSKUs
	if typeof(direct) == "table" then
		if direct[reason] then return direct[reason] end
		for prefix, sku in pairs(direct) do
			if startsWith(reason, tostring(prefix)) then return tostring(sku) end
		end
	end
	local clean = string.gsub(string.sub(reason, 1, 50), "[^%w_%-%.]", "_")
	return if clean ~= "" then clean else "unspecified"
end

local function txType(reason: string): string
	local types = typeof(RC) == "table" and RC.EconomyTypes or {}
	for prefix, t in pairs(types) do
		if startsWith(reason, tostring(prefix)) then return tostring(t) end
	end
	return "Gameplay"
end

local function enumValue(enumName: string, itemName: string): any
	local ok, value = pcall(function()
		local e = (Enum :: any)[enumName]
		return e and e[itemName]
	end)
	return if ok and value ~= nil then value else itemName
end

local function flush(userId: number)
	local rows = pending[userId]
	pending[userId] = nil
	local player = Players:GetPlayerByUserId(userId)
	local svc = rbx()
	if rows == nil or player == nil or svc == nil or isAdminUser(userId) then return end
	for _, r in pairs(rows) do
		local ok = pcall(function()
			svc:LogEconomyEvent(player, enumValue("AnalyticsEconomyFlowType", r.Flow), r.Currency,
				math.floor(r.Amount), math.max(0, math.floor(r.Balance)),
				 enumValue("AnalyticsEconomyTransactionType", r.TxType), r.ItemSKU)
		end)
		if ok then
			AnalyticsService.Stats.Economy += 1
		end
	end
end

-- One central, batched economy entry point. Callers provide no user/name data: itemSKU is
-- normalized from a server-owned reason and endingBalance is always the post-transaction balance.
function AnalyticsService.Economy(player: Player, flow: string, amount: number, balance: number, reason: string?, currency: string?, itemSKU: string?)
	if isAdminUser(player.UserId) or rbx() == nil or typeof(amount) ~= "number" or amount <= 0 or amount ~= amount then return end
	local r = if typeof(reason) == "string" and reason ~= "" then reason else "unspecified"
	local c = if typeof(currency) == "string" and currency ~= "" then currency else "Cash"
	local sku = if typeof(itemSKU) == "string" and itemSKU ~= "" then string.sub(itemSKU, 1, 50) else economySKU(r, flow)
	local key = flow .. "|" .. c .. "|" .. sku .. "|" .. txType(r)
	local rows = pending[player.UserId] or {}
	pending[player.UserId] = rows
	local row = rows[key]
	if row == nil then
		row = { Flow = flow, Currency = c, Amount = 0, Balance = balance, Reason = r, ItemSKU = sku, TxType = txType(r) }
		rows[key] = row
	end
	row.Amount += amount
	row.Balance = balance
end

function AnalyticsService.EconomyGold(player: Player, flow: string, amount: number, balance: number, reason: string?)
	AnalyticsService.Economy(player, flow, amount, balance, reason, "Gold")
end

-- ── product funnels (server-owned session ids; no client-supplied ids) ─────────────────────────────────────────
local productSessions: { [number]: { Shop: string?, Rebirth: string?, ShopSteps: { [number]: boolean }, RebirthSteps: { [number]: boolean } } } = {}
local function sessionFor(player: Player): any
	local s = productSessions[player.UserId]
	if s == nil then
		s = { ShopSteps = {}, RebirthSteps = {} }
		productSessions[player.UserId] = s
	end
	return s
end
local function newSession(): string
	local ok, id = pcall(HttpService.GenerateGUID, HttpService, false)
	return if ok and typeof(id) == "string" then id else "analytics-session"
end
function AnalyticsService.FunnelStep(player: Player, funnelName: string, stepName: string, sku: string?)
	if isAdminUser(player.UserId) then return end
	local def: any = if funnelName == "Shop" then (AnalyticsConfig :: any).Funnels.Shop else (AnalyticsConfig :: any).Funnels.Rebirth
	if typeof(def) ~= "table" then return end
	local s = sessionFor(player)
	local idKey = if funnelName == "Shop" then "Shop" else "Rebirth"
	local steps = if funnelName == "Shop" then s.ShopSteps else s.RebirthSteps
	local index = table.find(def.Steps, stepName)
	if index == nil then return end
	if index == 1 or s[idKey] == nil then
		s[idKey] = newSession()
	end
	local funnelSessionId = s[idKey] -- server-owned; never accepted from the client
	if steps[index] then return end
	steps[index] = true
	local svc = rbx()
	if svc == nil then return end
	local ok = pcall(function()
		svc:LogFunnelStepEvent(player, def.Name, funnelSessionId, index, stepName)
	end)
	if ok then
		AnalyticsService.Stats.Funnel += 1
	end
	if sku then
		custom(player, if funnelName == "Shop" then "SHOP_ITEM_VIEW" else "REBIRTH_CONFIRMED", { productKey = sku, sku = sku })
	end
end

-- ── onboarding timing (claude-bud JOB 29) ─────────────────────────────────────────────────────────────────────
local ONBOARD_FROM_EVENT: { [string]: string } = {
	CASH_COLLECT = "FirstCash",
	UPGRADE_PURCHASED = "FirstPurchase",
	FIRST_UPGRADE = "FirstPurchase",
	SOLDIER_RECRUIT = "FirstRecruit",
	PURCHASE_RECEIPT = "FirstRobux",
}
local onboardAt: { [number]: number } = {} -- userId -> os.clock() at join (the timing zero)
local onboardMarks: { [number]: { { Step: string, T: number } } } = {}
local onboardSeen: { [number]: { [string]: boolean } } = {}
local onboardNew: { [number]: boolean } = {} -- nil = not decided yet (save not loaded)

local function onboardIsNew(player: Player): boolean?
	local uid = player.UserId
	if onboardNew[uid] ~= nil then
		return onboardNew[uid]
	end
	local ds = dataService()
	local profile = ds and ds.GetProfile and ds.GetProfile(player)
	if profile == nil then
		return nil
	end
	local first = tonumber(profile.FirstJoinUnix) or 0
	local isNew = first > 0 and os.time() - first <= (tonumber(RC and RC.FunnelNewPlayerSeconds) or 900)
	onboardNew[uid] = isNew
	return isNew
end

local function onboardSend(player: Player)
	local marks = onboardMarks[player.UserId]
	if marks == nil or #marks == 0 then
		return
	end
	local isNew = onboardIsNew(player)
	if isNew == nil then
		return -- wait for the save
	end
	onboardMarks[player.UserId] = {}
	if not isNew then
		return
	end
	for _, m in ipairs(marks) do
		pcall(funnel, player, "STEP:" .. m.Step) -- the same Roblox funnel (AnalyticsConfig.Roblox.Funnel), at the real moment
		pcall(custom, player, "ONBOARD_STEP", { step = m.Step, seconds = math.floor(m.T * 10 + 0.5) / 10 })
	end
end

--[[ claude-bud JOB 41: the separate "FirstMinutes" Roblox funnel (TutorialConfig.Guided.Funnel; the onboarding funnel
	above is left as it is). GuidedService logs each step once per profile, with its own funnel session id. ]]
function AnalyticsService.GuidedFunnel(player: Player, sessionId: string, index: number, name: string, seconds: number?)
	if not AnalyticsConfig.Enabled then
		return
	end
	local F: any = (RetentionConfig :: any).Funnel
	if typeof(F) == "table" and F.PrintInStudio == true and RunService:IsStudio() then
		print(string.format("[FUNNEL] FirstMinutes %d %s t=%.1fs user=%d", index, name, tonumber(seconds) or 0, player.UserId))
	end
	local svc = rbx()
	if svc == nil then
		return
	end
	local funnelName = (require(ReplicatedStorage.Shared.Configs.TutorialConfig) :: any).Guided.Funnel.Name
	local ok = pcall(function()
		svc:LogFunnelStepEvent(player, funnelName, sessionId, index, name)
	end)
	if ok then
		AnalyticsService.Stats.Funnel += 1
	end
end

--[[ Seconds from this session's join to `step`, once per session (RetentionConfig.Funnel). Analytics only. ]]
function AnalyticsService.Onboard(player: Player, step: string)
	local F: any = (RetentionConfig :: any).Funnel
	if typeof(F) ~= "table" or F.Enabled ~= true or typeof(step) ~= "string" then
		return
	end
	local primary = ({ Joined = "joined", BaseClaimed = "base_claimed", FirstCash = "first_collect", FirstCollect = "first_collect", FirstPurchase = "first_upgrade", FirstRecruit = "first_recruit", FirstArmyOrder = "first_army_order", FirstRaidOrAttack = "first_raid_or_attack", Reached5Minutes = "reached_5_minutes" } :: any)[step]
	if primary then
		onboardingStep(player, primary)
	end
	local uid = player.UserId
	if onboardAt[uid] == nil then
		onboardAt[uid] = os.clock()
	end
	local seen = onboardSeen[uid]
	if seen == nil then
		seen = {}
		onboardSeen[uid] = seen
	end
	if seen[step] then
		return
	end
	seen[step] = true
	local t = os.clock() - onboardAt[uid]
	local marks = onboardMarks[uid]
	if marks == nil then
		marks = {}
		onboardMarks[uid] = marks
	end
	table.insert(marks, { Step = step, T = t })
	if F.PrintInStudio == true and RunService:IsStudio() then
		print(string.format("[FUNNEL] %s t=%.1fs user=%d", step, t, uid))
	end
	onboardSend(player)
end

local function onboardEnd(player: Player)
	local uid = player.UserId
	if onboardAt[uid] ~= nil then
		pcall(AnalyticsService.Onboard, player, "SessionEnd")
		local F: any = (RetentionConfig :: any).Funnel
		if typeof(F) == "table" and F.PrintInStudio == true and RunService:IsStudio() and onboardSeen[uid] then
			local steps = {}
			for step in pairs(onboardSeen[uid]) do
				table.insert(steps, step)
			end
			table.sort(steps)
			print(string.format("[FUNNEL] session end user=%d steps=%s", uid, table.concat(steps, ",")))
		end
	end
	onboardAt[uid] = nil
	onboardMarks[uid] = nil
	onboardSeen[uid] = nil
	onboardNew[uid] = nil
end

function AnalyticsService.OnboardingStep(player: Player, name: string)
	onboardingStep(player, name)
end

function AnalyticsService.SetSink(fn: (eventName: string, userId: number?, props: { [string]: any }?) -> ())
	sink = fn
end

function AnalyticsService.Log(eventName: string, userId: number?, props: { [string]: any }?)
	if not AnalyticsConfig.Enabled or isAdminUser(userId) then return end
	local clean = safeProps(props)
	if sink then
		sink(eventName, userId, clean)
		return
	end
	if AnalyticsConfig.LogToOutput or RunService:IsStudio() then
		local parts = {}
		for k, v in pairs(clean) do
			table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
		end
		print(string.format("[Analytics] %s user=%s %s", eventName, tostring(userId), table.concat(parts, ", ")))
	end
	local player = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if player == nil then return end
	flushPrimaryPending(player)
	if eventName == "PLAYER_JOIN" then
		joinedAt[player.UserId] = os.clock()
	elseif eventName == "PLAYER_LEAVE" then
		local at = joinedAt[player.UserId]
		joinedAt[player.UserId] = nil
		if at then
			local minutes = math.floor((os.clock() - at) / 60)
			custom(player, "SESSION_END", { minutes = minutes, bucket = bucketOf(minutes) })
		end
		flush(player.UserId)
		onboardEnd(player) -- claude-bud JOB 29
	end
	pcall(custom, player, eventName, clean)
	local primary = primaryStepByEvent[eventName]
	if primary then
		pcall(onboardingStep, player, primary)
	end
	if eventName == "SHOP_OPEN" then pcall(AnalyticsService.FunnelStep, player, "Shop", "open_shop")
	elseif eventName == "SHOP_ITEM_VIEW" then pcall(AnalyticsService.FunnelStep, player, "Shop", "view_item", clean.productKey)
	elseif eventName == "SHOP_PROMPT" then pcall(AnalyticsService.FunnelStep, player, "Shop", "prompt_purchase", clean.productKey)
	elseif eventName == "PURCHASE_RECEIPT" then pcall(AnalyticsService.FunnelStep, player, "Shop", "purchase_complete", clean.productKey)
	elseif eventName == "REBIRTH_AVAILABLE" then pcall(AnalyticsService.FunnelStep, player, "Rebirth", "available")
	elseif eventName == "REBIRTH_OPENED" then pcall(AnalyticsService.FunnelStep, player, "Rebirth", "opened")
	elseif eventName == "REBIRTH_CONFIRMED" then
		pcall(AnalyticsService.FunnelStep, player, "Rebirth", "confirmed")
	end
	local step = ONBOARD_FROM_EVENT[eventName] -- claude-bud JOB 29: onboarding timing
	if step then
		pcall(AnalyticsService.Onboard, player, step)
	elseif eventName == "PLAYER_JOIN" then
		pcall(onboardSend, player) -- the save is loaded now: send the marks made before it
	end
end

local started = false
function AnalyticsService.Init()
	if started then
		return
	end
	started = true
	-- economy flush loop
	task.spawn(function()
		while true do
			task.wait(math.max(10, tonumber(RC and RC.EconomyFlushSeconds) or 60))
			for uid, _ in pairs(pending) do
				pcall(flush, uid)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		pcall(flush, p.UserId)
		joinedAt[p.UserId] = nil
		productSessions[p.UserId] = nil
		primaryPending[p.UserId] = nil
		task.defer(onboardEnd, p) -- claude-bud JOB 29 (PLAYER_LEAVE normally ends it first; this only cleans up)
	end)
	-- claude-bud JOB 29: the timing zero is the real join (PlayerAdded), before the save loads
	Players.PlayerAdded:Connect(function(p: Player)
		onboardAt[p.UserId] = os.clock()
		-- One delayed server task, never Heartbeat/Stepped: the last onboarding step is cheap and once-only.
		task.delay(300, function()
			if p.Parent then
				AnalyticsService.OnboardingStep(p, "reached_5_minutes")
			end
		end)
	end)
	-- a cancelled Robux prompt (analytics only: never a grant, never trusted for anything else)
	pcall(function()
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
			if not isPurchased then
				AnalyticsService.Log("PROMPT_CLOSED", userId, { kind = "product", productId = productId })
			end
		end)
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
			if not wasPurchased and typeof(player) == "Instance" then
				AnalyticsService.Log("PROMPT_CLOSED", player.UserId, { kind = "pass", passId = passId })
			end
		end)
	end)
	-- the client's whitelisted UI events (RequestAnalyticsEvent; RemoteSetup makes it)
	task.spawn(function()
		local okR, RemoteSetup = pcall(function()
			return require(script.Parent.Parent.Modules.RemoteSetup) :: any
		end)
		if not okR then
			return
		end
		local remote: any = nil
		for _ = 1, 60 do
			local ok, r = pcall(RemoteSetup.Get, "RequestAnalyticsEvent")
			if ok and r then
				remote = r
				break
			end
			task.wait(1)
		end
		if remote == nil then
			return
		end
		local window: { [number]: { At: number, N: number } } = {}
		remote.OnServerEvent:Connect(function(player: Player, name: any, tip: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestAnalyticsEvent", name, tip) then -- claude-bud JOB 15 gate: rate ceiling + argument schema
				return
			end
			local map = typeof(RC) == "table" and RC.ClientEvents or {}
			local ev = if typeof(name) == "string" then map[name] else nil
			if ev == nil then
				return
			end
			local now = os.clock()
			local w = window[player.UserId]
			if w == nil or now - w.At >= 60 then
				w = { At = now, N = 0 }
				window[player.UserId] = w
			end
			if w.N >= (tonumber(RC.ClientPerMinute) or 12) then
				return
			end
			w.N += 1
			AnalyticsService.Stats.Client += 1
			-- a tip id is a short config key (BuildingTutorialConfig); anything else is dropped
			local tipId = if typeof(tip) == "string" and #tip <= 32 and string.match(tip, "^[%w_]+$") then tip else nil
			local cprops: { [string]: any } = { tip = tipId }
			if ev == "REBIRTH_OPENED" then
				-- claude-bud JOB 33: the level and this life's minutes come from the server's save, never the client
				local ds = dataService()
				local pr = ds and ds.GetProfile and ds.GetProfile(player)
				if pr then
					cprops.level = tonumber(pr.Level) or 0
					cprops.minutes = math.floor((tonumber(pr.LifePlaySeconds) or 0) / 60)
				end
			end
			AnalyticsService.Log(ev, player.UserId, cprops)
		end)
		Players.PlayerRemoving:Connect(function(p: Player)
			window[p.UserId] = nil
		end)
	end)
end

return AnalyticsService
