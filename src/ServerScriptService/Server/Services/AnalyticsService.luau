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
local AnalyticsConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AnalyticsConfig)
local RetentionConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.RetentionConfig) -- claude-bud JOB 29

local AnalyticsService = {}
AnalyticsService.Stats = { Custom = 0, Funnel = 0, Economy = 0, Dropped = 0, Client = 0 }

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
type Pending = { Flow: string, Amount: number, Balance: number, Reason: string }
local pending: { [number]: { [string]: Pending } } = {}

local function txType(reason: string): string
	local types = typeof(RC) == "table" and RC.EconomyTypes or {}
	for prefix, t in pairs(types) do
		if string.sub(reason, 1, #prefix) == prefix then
			return t
		end
	end
	return "Gameplay"
end

local function flush(userId: number)
	local rows = pending[userId]
	pending[userId] = nil
	local player = Players:GetPlayerByUserId(userId)
	local svc = rbx()
	if rows == nil or player == nil or svc == nil then
		return
	end
	for _, r in pairs(rows) do
		local flow = if r.Flow == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
		local ok = pcall(function()
			svc:LogEconomyEvent(player, flow, "Cash", math.floor(r.Amount), math.max(0, math.floor(r.Balance)), txType(r.Reason), string.sub(r.Reason, 1, 50))
		end)
		if ok then
			AnalyticsService.Stats.Economy += 1
		end
	end
end

--[[ One Cash movement (EconomyService): flow "Source" | "Sink", the amount, the balance after it, the reason. Summed per
	player per flow + reason until the next flush. ]]
function AnalyticsService.Economy(player: Player, flow: string, amount: number, balance: number, reason: string?)
	if rbx() == nil or typeof(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return
	end
	local r = reason or "other"
	-- the "upgrade_<id>" style reasons keep their id as the sku; the dictionary key groups by the full reason
	local rows = pending[player.UserId]
	if rows == nil then
		rows = {}
		pending[player.UserId] = rows
	end
	local key = flow .. "|" .. r
	local row = rows[key]
	if row == nil then
		row = { Flow = flow, Amount = 0, Balance = balance, Reason = r }
		rows[key] = row
	end
	row.Amount += amount
	row.Balance = balance
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

--[[ Seconds from this session's join to `step`, once per session (RetentionConfig.Funnel). Analytics only. ]]
function AnalyticsService.Onboard(player: Player, step: string)
	local F: any = (RetentionConfig :: any).Funnel
	if typeof(F) ~= "table" or F.Enabled ~= true or typeof(step) ~= "string" then
		return
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

function AnalyticsService.SetSink(fn: (eventName: string, userId: number?, props: { [string]: any }?) -> ())
	sink = fn
end

function AnalyticsService.Log(eventName: string, userId: number?, props: { [string]: any }?)
	if not AnalyticsConfig.Enabled then
		return
	end
	if sink then
		sink(eventName, userId, props)
		return
	end
	if AnalyticsConfig.LogToOutput or RunService:IsStudio() then
		local propStr = ""
		if props then
			local parts = {}
			for k, v in pairs(props) do
				table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
			end
			propStr = table.concat(parts, ", ")
		end
		print(string.format("[Analytics] %s user=%s %s", eventName, tostring(userId), propStr))
	end
	local player = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if player == nil then
		return
	end
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
	pcall(funnel, player, eventName)
	pcall(custom, player, eventName, props)
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
		task.defer(onboardEnd, p) -- claude-bud JOB 29 (PLAYER_LEAVE normally ends it first; this only cleans up)
	end)
	-- claude-bud JOB 29: the timing zero is the real join (PlayerAdded), before the save loads
	Players.PlayerAdded:Connect(function(p: Player)
		onboardAt[p.UserId] = os.clock()
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
