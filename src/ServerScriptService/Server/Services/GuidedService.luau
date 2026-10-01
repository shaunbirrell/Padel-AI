--!strict
--[[
	claude-bud JOB 41 part A (2026-09-30): THE GUIDED FIRST 3-4 MINUTES (TutorialConfig.Guided, owner-first).
	TutorialService plays the steps (OrderVersion 4 = TutorialConfig.GuidedSteps) and calls the hooks below; this service
	only adds what the old tutorial did not have. It never moves a player or a soldier (no teleport / PivotTo) and it
	never writes Humanoid health: the camp NPCs are ordinary CombatService NPCs and die to real shots.

	  * Wants(player, profile): a NEW player (tutorial not done, Command Center not bought, no building, first join <
	    Guided.NewPlayerSeconds) or a Guided save still mid-chain, while Guided is live for him.
	  * RECRUIT: when the recruit step opens, a one-time top-up (reason "onboarding") covers EXACTLY the gap to
	    Guided.RecruitCount soldiers (with the $10,000 start + the $1,500 payout - the $1,500 Command Center it is 0).
	  * FIRST FIGHT: a 2-Recruit training camp at HIS Home Outpost (Starter_P<plot>): CombatService.SpawnNPC with a
	    TargetFilter = only him (they shoot nobody else), leashed to the ring, 2 sandbag posts. Capture is blocked while
	    they live (Blocking, read by TerritoryService). Both dead -> CampDone, TutorialService.Notify "CampCleared".
	    A death of his / a rejoin re-spawns them at full health, at most Camp.MaxCampSpawns times; after that the step
	    completes with a friendly line (never a soft-lock). Skip clears them at once.
	  * REWARD: GuidedRewardCash once (profile.Guided.RewardDone), FeaturePush "GuidedReward" (banner + confetti) and
	    "StarterPayout" (the coin burst), then TutorialService.Notify "GuidedReward" -> the Barracks goal.
	  * FUNNEL: a separate Roblox funnel "FirstMinutes" (one session per profile: Guided.SessionId), each step once,
	    plus the custom events GuidedStepSeconds / GuidedSkipped / GuidedStuck (AnalyticsConfig.Roblox.Custom).

	claude-bud JOB 48 (2026-10-01): THE HOOK (TutorialConfig.Guided.Hook, owner-first; OFF == the v4 chain above). A
	player it is live for plays OrderVersion 5 (OrderFor):
	  * REWARD + Hook.RewardSoldiers free soldiers (SoldierService.GrantFree: the normal recruit state, within the cap).
	  * RAID A RIVAL BASE (step RaidRival): when it opens, RivalService.Candidates (the JOB 38 verdict, ArmySendRules)
	    says whether any rival may be raided now. Yes: the raid goal (FeaturePush "GuidedGoal" {Goal = "Raid"}: the
	    TARGETS card is outlined); a SEND accepted -> RaidSent (ArmyCommand), a SEND / ATM raid that loots -> RaidWon
	    (ArmyPlan / MoneyCollectorService) -> TutorialService.Notify "RaidWon". No: the FALLBACK goal (clear
	    Hook.FallbackKills hostile NPCs: CombatService.OnNPCDeath with him as the killer) -> "GoalFallbackWon"; after
	    Hook.FallbackMaxSeconds -> "GoalFallbackDone" (the chain moves on). Re-checked every Hook.RecheckSeconds.
	  * FAST RAID: a raid won within Hook.FastRaidSeconds of the reward pays Hook.FastRaidBonus once (reason
	    "onboarding"); the countdown is only pushed while that bonus is > 0 (no fake timer).
	  * FUNNEL steps 12-16 (Hook.FunnelSteps) after the unchanged 1-11, once each per profile; the custom events
	    SessionMilestone { sec } (once each per session) and FtueTimeToFight (seconds from spawn to the first kill).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local SoldierConfig = require(Shared.Configs.SoldierConfig)

local GuidedService = {}

local G: any = TutorialConfig.Guided
local deps: { [string]: any } = {}

type Camp = { PlotId: number, Ids: { string }, Alive: { [string]: boolean }, Folder: Instance?, Token: number }
local camps: { [number]: Camp } = {} -- userId -> the live camp
local stepAt: { [number]: { Id: string, At: number } } = {} -- userId -> the open step (stuck timer)
local spawnAt: { [number]: number } = {} -- userId -> clock of this session's first spawn (step seconds)
local campSeq = 0

GuidedService._clock = os.clock -- tests replace these
GuidedService._unix = os.time
GuidedService._delay = function(s: number, fn: (...any) -> (), ...: any)
	task.delay(s, fn, ...)
end

-- ── helpers ────────────────────────────────────────────────────────────────────────────────────────────────────
local function rec(profile: any): any
	local g = profile.Guided
	if typeof(g) ~= "table" then
		g = {}
		profile.Guided = g
	end
	if typeof(g.Funnel) ~= "table" then
		g.Funnel = {}
	end
	return g
end

local function dirty(player: Player)
	if deps.DataService then
		pcall(deps.DataService.MarkDirty, player)
	end
end

local function push(player: Player, kind: string, data: any)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, kind, data)
	end
end

local function notify(player: Player, text: string, kind: string?)
	local N = deps.NotificationService
	if N and N.Notify then
		pcall(N.Notify, player, text, kind or "Info", 5)
	end
end

local function isGuided(profile: any): boolean
	return profile ~= nil and TutorialConfig.IsGuidedVersion(profile.TutorialOrderVersion)
end

-- claude-bud JOB 48: a Hook (OrderVersion 5) profile
local H: any = G.Hook
local function isHook(profile: any): boolean
	return profile ~= nil and typeof(H) == "table" and tonumber(profile.TutorialOrderVersion) == H.OrderVersion
end

-- the Guided order this player plays: 5 while the Hook is live for him, else 4
function GuidedService.OrderFor(player: Player): number
	if TutorialConfig.HookLiveFor(player.UserId) then
		return H.OrderVersion
	end
	return G.OrderVersion
end

-- Code Bot v163: an owner / admin test-mode replay (TutorialService.ReplayGuided): no cash, no funnel / analytics
local function isReplay(profile: any): boolean
	return typeof(profile) == "table" and typeof(profile.GuidedReplay) == "table"
end
GuidedService.IsReplay = isReplay

local function anyBuilding(profile: any): boolean
	if typeof(profile.BaseUpgrades) ~= "table" then
		return false
	end
	for _, lvl in pairs(profile.BaseUpgrades) do
		if (tonumber(lvl) or 0) >= 1 then
			return true
		end
	end
	return false
end

-- a NEW player (or a Guided save mid-chain) the switch is live for
function GuidedService.Wants(player: Player, profile: any): boolean
	if profile == nil or profile.TutorialComplete == true or not TutorialConfig.GuidedLiveFor(player.UserId) then
		return false
	end
	if isGuided(profile) then
		return true
	end
	local first = tonumber(profile.FirstJoinUnix) or 0
	return not anyBuilding(profile)
		and (tonumber(profile.TutorialStep) or 1) <= 2
		and first > 0
		and GuidedService._unix() - first <= G.NewPlayerSeconds
end

-- ── funnel ─────────────────────────────────────────────────────────────────────────────────────────────────────
function GuidedService.FunnelIndex(name: string): number?
	local i = table.find(G.Funnel.Steps, name)
	if i == nil and typeof(H) == "table" then
		-- claude-bud JOB 48: steps 12.. after the live 1-11 (the fallback win is logged at the RaidWon index)
		local j = table.find(H.FunnelSteps, if name == H.FallbackWonName then "RaidWon" else name)
		if j then
			i = #G.Funnel.Steps + j
		end
	end
	return i
end

function GuidedService.Funnel(player: Player, profile: any, name: string)
	if not isGuided(profile) then
		return
	end
	local idx = GuidedService.FunnelIndex(name)
	if idx and idx > #G.Funnel.Steps and not isHook(profile) then
		return -- the Hook's steps only for a Hook profile (OFF == the v4 funnel)
	end
	local g = rec(profile)
	local key = if typeof(H) == "table" and name == H.FallbackWonName then "RaidWon" else name -- one index, logged once
	if idx == nil or g.Funnel[key] then
		return
	end
	g.Funnel[key] = true
	if isReplay(profile) then
		return -- Code Bot v163: a test-mode replay never reaches the FirstMinutes funnel
	end
	if typeof(g.SessionId) ~= "string" then
		g.SessionId = HttpService:GenerateGUID(false)
	end
	dirty(player)
	local A = deps.AnalyticsService
	local secs = math.floor((GuidedService._clock() - (spawnAt[player.UserId] or GuidedService._clock())) * 10 + 0.5) / 10
	if A and A.GuidedFunnel then
		pcall(A.GuidedFunnel, player, g.SessionId, idx, name, secs)
	end
	if A and A.Log then
		pcall(A.Log, "GUIDED_STEP", player.UserId, { step = name, seconds = secs })
	end
end

local FUNNEL_OF_STEP = {
	CommandCenter = "FirstBuild",
	Income = "Collected",
	RecruitSoldiers = "Recruited",
	Outpost = "Captured",
	Reward = "Reward",
	Barracks = "NextBuilding",
}

-- ── the camp ───────────────────────────────────────────────────────────────────────────────────────────────────
local function starterDef(plotId: number): any?
	local T: any = TerritoryConfig
	local list = T.Territories
	return if typeof(list) == "table" then list[T.Starter.IdPrefix .. tostring(plotId)] else nil
end

local function groundAt(x: number, z: number, fallbackY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	params.FilterDescendantsInstances = ex
	local hit = Workspace:Raycast(Vector3.new(x, fallbackY + 80, z), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else fallbackY
end

function GuidedService.ClearCamp(player: Player)
	local c = camps[player.UserId]
	if c == nil then
		return
	end
	camps[player.UserId] = nil
	local CS = deps.CombatService
	for _, id in ipairs(c.Ids) do
		if CS and CS.DespawnNPC then
			pcall(CS.DespawnNPC, id)
		end
	end
	if c.Folder then
		(c.Folder :: Instance):Destroy()
	end
end

local function finishCamp(player: Player, profile: any, auto: boolean)
	GuidedService.ClearCamp(player)
	local g = rec(profile)
	if g.CampDone == true then
		return
	end
	g.CampDone = true
	g.SoldiersAtCamp = tonumber(profile.Soldiers) or 0 -- claude-bud JOB 48: ArmyGrew counts from here
	dirty(player)
	if auto then
		notify(player, G.CampSkipText, "Info")
	end
	local TS = deps.TutorialService
	if TS and TS.Notify then
		pcall(TS.Notify, player, "CampCleared")
	end
end

function GuidedService.SpawnCamp(player: Player, profile: any): boolean
	if not isGuided(profile) or camps[player.UserId] then
		return false
	end
	local g = rec(profile)
	if g.CampDone == true then
		return false
	end
	local plotId = tonumber(profile.BasePlotId)
	local def = plotId and starterDef(plotId :: number)
	local CS = deps.CombatService
	if def == nil or CS == nil or CS.SpawnNPC == nil then
		return false
	end
	g.CampSpawns = (tonumber(g.CampSpawns) or 0) + 1
	dirty(player)
	if g.CampSpawns > G.Camp.MaxCampSpawns then
		finishCamp(player, profile, true) -- never a soft-lock
		return false
	end
	campSeq += 1
	local c: Camp = { PlotId = plotId :: number, Ids = {}, Alive = {}, Folder = nil, Token = campSeq }
	camps[player.UserId] = c
	local folder = Instance.new("Folder")
	folder.Name = "WE_GuidedCamp_" .. tostring(player.UserId)
	folder.Parent = Workspace
	c.Folder = folder
	local centre: Vector3 = def.Position
	local look = Vector3.new(centre.X, 0, centre.Z)
	for i, typeId in ipairs(G.Camp.Npc) do
		local post = G.Camp.Posts[i] or G.Camp.Posts[1]
		local x, z = centre.X + post.X, centre.Z + post.Z
		local y = groundAt(x, z, centre.Y)
		-- the sandbag post (one plain part, removed with the camp)
		local bag = Instance.new("Part")
		bag.Name = "GuidedSandbag"
		bag.Anchored = true
		bag.CanTouch = false
		bag.CastShadow = false
		bag.Material = Enum.Material.Sand
		bag.Color = G.Camp.SandbagColor
		bag.Size = Vector3.new(5, 2.2, 1.6)
		bag.CFrame = CFrame.lookAt(Vector3.new(x, y + 1.1, z), Vector3.new(look.X, y + 1.1, look.Z)) * CFrame.new(0, 0, -2.2)
		bag.Parent = folder
		local cf = CFrame.lookAt(Vector3.new(x, y + 3, z), Vector3.new(look.X, y + 3, look.Z))
		local target = player
		local ok, r = pcall(CS.SpawnNPC, typeId, cf, {
			GroupId = "Guided." .. tostring(player.UserId),
			NoRespawn = true,
			Home = cf,
			Leash = (tonumber(def.Radius) or 20) + 15,
			OverCap = true,
			-- the one hostility rule stays CombatService's: this only narrows WHO they may pick (him alone)
			TargetFilter = function(p: Player): boolean
				return p == target
			end,
		})
		if ok and r and typeof(r.Id) == "string" then
			table.insert(c.Ids, r.Id)
			c.Alive[r.Id] = true
		end
	end
	if #c.Ids == 0 then
		GuidedService.ClearCamp(player)
		return false
	end
	GuidedService.Funnel(player, profile, "FightStarted")
	push(player, "Hint", { Kind = "Attack", Text = TutorialConfig.FirstMinutes.AttackHintText, Seconds = TutorialConfig.FirstMinutes.AttackHintSeconds })
	return true
end

-- TerritoryService: capture of this Home Outpost waits while its camp stands
function GuidedService.Blocking(territoryId: any): boolean
	if typeof(territoryId) ~= "string" then
		return false
	end
	for _, c in pairs(camps) do
		if TerritoryConfig.Starter.IdPrefix .. tostring(c.PlotId) == territoryId then
			for _, alive in pairs(c.Alive) do
				if alive then
					return true
				end
			end
		end
	end
	return false
end

-- claude-bud JOB 48: the fallback goal counts hostile NPCs HE kills (never the Guided camp); set below
local fallbackKill: (info: any) -> () = function(_info: any) end

-- CombatService.OnNPCDeath
function GuidedService.OnNPCDeath(info: any)
	if typeof(info) == "table" and (typeof(info.GroupId) ~= "string" or string.sub(info.GroupId, 1, 7) ~= "Guided.") then
		fallbackKill(info)
	end
	if typeof(info) ~= "table" or typeof(info.GroupId) ~= "string" or string.sub(info.GroupId, 1, 7) ~= "Guided." then
		return
	end
	local uid = tonumber(string.sub(info.GroupId, 8))
	local c = uid and camps[uid :: number]
	if c == nil or not c.Alive[info.Id] then
		return
	end
	c.Alive[info.Id] = false
	local player = Players:GetPlayerByUserId(uid :: number)
	local profile = player and deps.DataService and deps.DataService.GetProfile(player)
	if player == nil or profile == nil then
		return
	end
	GuidedService.Funnel(player, profile, "FirstKill")
	local gk = rec(profile)
	if isHook(profile) and gk.TimeToFight == nil and not isReplay(profile) then
		-- claude-bud JOB 48: FtueTimeToFight = seconds from this session's spawn to the first camp kill, once per profile
		gk.TimeToFight = math.floor((GuidedService._clock() - (spawnAt[player.UserId] or GuidedService._clock())) + 0.5)
		dirty(player)
		local A = deps.AnalyticsService
		if A and A.Log then
			pcall(A.Log, "FTUE_TIME_TO_FIGHT", player.UserId, { seconds = gk.TimeToFight })
		end
	end
	for _, alive in pairs(c.Alive) do
		if alive then
			return
		end
	end
	finishCamp(player, profile, false)
end

-- his death mid-fight: the camp comes back at full health when he respawns (MaxCampSpawns caps it)
local function onDied(player: Player)
	local c = camps[player.UserId]
	if c == nil then
		return
	end
	GuidedService.ClearCamp(player)
	GuidedService._delay(6, function()
		local profile = player.Parent and deps.DataService and deps.DataService.GetProfile(player)
		local cur = profile and stepAt[player.UserId]
		if profile and cur and cur.Id == "FirstFight" then
			GuidedService.SpawnCamp(player, profile)
		end
	end)
end

-- ── the recruit top-up and the reward ──────────────────────────────────────────────────────────────────────────
function GuidedService.RecruitGap(cash: number): number
	local need = (tonumber(G.RecruitCount) or 3) * (tonumber(SoldierConfig.RecruitCostCash) or 500)
	return math.clamp(math.ceil(need - cash), 0, math.max(0, tonumber(G.GuidedRecruitCashMax) or 0))
end

local function recruitTopUp(player: Player, profile: any)
	local g = rec(profile)
	if g.RecruitTopUp ~= nil then
		return
	end
	local gap = if isReplay(profile) then 0 else GuidedService.RecruitGap(tonumber(profile.Cash) or 0) -- v163: no cash in a replay
	g.RecruitTopUp = gap
	dirty(player)
	local E = deps.EconomyService
	if gap > 0 and E and E.AddCash then
		pcall(E.AddCash, player, gap, "onboarding")
	end
end

local function reward(player: Player, profile: any)
	local g = rec(profile)
	if g.RewardDone ~= true then
		g.RewardDone = true
		dirty(player)
		local cash = if isReplay(profile) then 0 else math.max(0, math.floor(tonumber(G.GuidedRewardCash) or 0)) -- v163: banner only in a replay
		local E = deps.EconomyService
		if cash > 0 and E and E.AddCash then
			pcall(E.AddCash, player, cash, "onboarding")
		end
		push(player, "GuidedReward", { Title = G.RewardText, Sub = G.RewardSub })
		if cash > 0 then
			push(player, "StarterPayout", { Cash = cash, Text = G.RewardText })
		end
		-- claude-bud JOB 48: the army grows at the reward (free soldiers, the normal recruit state, within the cap)
		local n = if isHook(profile) and not isReplay(profile) then math.max(0, math.floor(tonumber(H.RewardSoldiers) or 0)) else 0
		local SS = deps.SoldierService
		if n > 0 and SS and SS.GrantFree then
			local before = tonumber(profile.Soldiers) or 0
			pcall(SS.GrantFree, player, n, "onboarding")
			local after = tonumber(profile.Soldiers) or 0
			g.RewardSoldiers = { Before = before, After = after }
			print(string.format("[GUIDED] %s reward soldiers %d -> %d (asked %d, within the cap)", player.Name, before, after, n))
		end
		if isHook(profile) then
			g.RewardAt = GuidedService._unix()
		end
	end
	local TS = deps.TutorialService
	if TS and TS.Notify then
		GuidedService._delay(3, function()
			if player.Parent then
				pcall(TS.Notify, player, "GuidedReward")
			end
		end)
	end
end

-- ── claude-bud JOB 48: RAID A RIVAL BASE (or the fallback) ──────────────────────────────────────────────────────
local function notifyTS(player: Player, ev: string)
	local TS = deps.TutorialService
	if TS and TS.Notify then
		pcall(TS.Notify, player, ev)
	end
end

local function rivalsAllowed(player: Player): number
	local RS = deps.RivalService
	if RS == nil then
		local ok, m = pcall(function(): any
			return (require :: any)(script.Parent.RivalService) -- dynamic: keeps RivalService out of this module's type graph
		end)
		RS = if ok then m else nil
	end
	if RS == nil or RS.Candidates == nil then
		return 0
	end
	local ok, rows = pcall(RS.Candidates, player)
	return if ok and typeof(rows) == "table" then #rows else 0
end

local function goalOpen(player: Player): boolean
	local cur = stepAt[player.UserId]
	return cur ~= nil and cur.Id == "RaidRival"
end

-- the goal text the tutorial chip shows for RaidRival (TutorialService's push reads it): nil = the step's own copy
function GuidedService.GoalText(profile: any): (string?, string?)
	local g = if typeof(profile) == "table" then profile.Guided else nil
	if isHook(profile) and typeof(g) == "table" and g.GoalMode == "Fallback" then
		return H.FallbackTitle, H.FallbackHint
	end
	return nil, nil
end

local function setGoal(player: Player, profile: any, mode: string)
	local g = rec(profile)
	if g.GoalMode == mode then
		return
	end
	g.GoalMode = mode
	dirty(player)
	local left = nil
	if mode == "Raid" and (tonumber(H.FastRaidBonus) or 0) > 0 and g.FastRaidPaid ~= true and typeof(g.RewardAt) == "number" then
		left = math.max(0, (tonumber(H.FastRaidSeconds) or 0) - (GuidedService._unix() - g.RewardAt))
	end
	push(player, "GuidedGoal", { Goal = mode, FastRaidLeft = left, Bonus = if left then H.FastRaidBonus else nil })
	local TS = deps.TutorialService
	if TS and TS.Push then
		pcall(TS.Push, player)
	end
	if mode == "Raid" then
		GuidedService.Funnel(player, profile, "GoalRaidShown")
	else
		local A = deps.AnalyticsService
		if A and A.Log and not isReplay(profile) then
			pcall(A.Log, "GOAL_FALLBACK", player.UserId, { reason = "no_rival" })
		end
		print(string.format("[GUIDED] %s raid goal -> FALLBACK (no rival may be raided now)", player.Name))
	end
end

local function openGoal(player: Player, profile: any)
	local g = rec(profile)
	if typeof(g.RewardAt) ~= "number" then
		g.RewardAt = GuidedService._unix()
	end
	g.FallbackKills = tonumber(g.FallbackKills) or 0
	g.GoalMode = nil
	local mark = stepAt[player.UserId]
	local function decide()
		if stepAt[player.UserId] ~= mark or not player.Parent then
			return
		end
		local P = deps.ArmyPlan
		if P == nil then
			local okP, m = pcall(function(): any
				return require(script.Parent.Parent.Modules.ArmyPlan)
			end)
			P = if okP then m else nil
		end
		local sending = if P and P.Status then P.Status(player.UserId) else nil
		if rivalsAllowed(player) > 0 then
			setGoal(player, profile, "Raid")
		elseif not (typeof(sending) == "table" and sending.Kind == "Send") then
			setGoal(player, profile, "Fallback") -- a SEND already marching keeps the raid goal until it ends
		end
		GuidedService._delay(math.max(5, tonumber(H.RecheckSeconds) or 15), decide)
	end
	decide()
	GuidedService._delay(math.max(30, tonumber(H.FallbackMaxSeconds) or 180), function()
		if stepAt[player.UserId] == mark and player.Parent and rec(profile).GoalMode == "Fallback" then
			print(string.format("[GUIDED] %s fallback goal timed out -> next goal (never a soft-lock)", player.Name))
			notifyTS(player, "GoalFallbackDone")
		end
	end)
end

fallbackKill = function(info: any)
	local killer = info.Killer
	if killer == nil then
		return
	end
	local player = killer :: Player
	if not goalOpen(player) then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if not isHook(profile) then
		return
	end
	local g = rec(profile)
	if g.GoalMode ~= "Fallback" then
		return
	end
	g.FallbackKills = (tonumber(g.FallbackKills) or 0) + 1
	dirty(player)
	if g.FallbackKills >= math.max(1, tonumber(H.FallbackKills) or 2) then
		GuidedService.Funnel(player, profile, H.FallbackWonName)
		notifyTS(player, "GoalFallbackWon")
	end
end

-- ArmyCommand: a SEND to a base was accepted (the JOB 38 verdict passed)
function GuidedService.OnRaidSent(player: Player)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if isHook(profile) and goalOpen(player) then
		GuidedService.Funnel(player, profile, "RaidSent")
	end
end

-- ArmyPlan (a SEND looted) / MoneyCollectorService (an in-person ATM raid moved cash): the raid goal is won
function GuidedService.OnRaidWon(player: Player)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if not isHook(profile) or not goalOpen(player) then
		return
	end
	local g = rec(profile)
	GuidedService.Funnel(player, profile, "RaidWon")
	local bonus = math.max(0, math.floor(tonumber(H.FastRaidBonus) or 0))
	local inTime = typeof(g.RewardAt) == "number" and GuidedService._unix() - g.RewardAt <= (tonumber(H.FastRaidSeconds) or 0)
	if bonus > 0 and inTime and g.FastRaidPaid ~= true and not isReplay(profile) then
		g.FastRaidPaid = true
		dirty(player)
		local E = deps.EconomyService
		if E and E.AddCash then
			pcall(E.AddCash, player, bonus, "onboarding")
		end
		push(player, "StarterPayout", { Cash = bonus, Text = H.FastRaidText })
	end
	notifyTS(player, "RaidWon")
end

-- SoldierService.OnArmyChanged: the army count went up after the fight -> ArmyGrew (once)
function GuidedService.OnArmyChanged(player: Player)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if not isHook(profile) then
		return
	end
	local g = rec(profile)
	if g.CampDone == true and (tonumber(profile.Soldiers) or 0) > (tonumber(g.SoldiersAtCamp) or math.huge) then
		GuidedService.Funnel(player, profile, "ArmyGrew")
	end
end

-- SessionMilestone { sec }: once each per session at Hook.Milestones play seconds (Hook live for him)
local function milestones(player: Player)
	if typeof(H) ~= "table" or not TutorialConfig.HookLiveFor(player.UserId) then
		return
	end
	for _, sec in ipairs(H.Milestones or {}) do
		GuidedService._delay(sec, function()
			if player.Parent then
				local A = deps.AnalyticsService
				if A and A.Log then
					pcall(A.Log, "SESSION_MILESTONE", player.UserId, { sec = sec })
				end
			end
		end)
	end
end
GuidedService._Milestones = milestones

-- ── TutorialService hooks ──────────────────────────────────────────────────────────────────────────────────────
local function openStep(player: Player, profile: any, def: any)
	local uid = player.UserId
	local id = if def then def.Id else nil
	if id == nil then
		stepAt[uid] = nil
		return
	end
	local mark = { Id = id :: string, At = GuidedService._clock() }
	stepAt[uid] = mark
	GuidedService._delay(G.StuckSeconds, function()
		if stepAt[uid] == mark and player.Parent and not isReplay(profile) then
			local A = deps.AnalyticsService
			if A and A.Log then
				pcall(A.Log, "GUIDED_STUCK", uid, { step = id })
			end
		end
	end)
	if id == "RecruitSoldiers" then
		recruitTopUp(player, profile)
	elseif id == "FirstFight" then
		GuidedService.SpawnCamp(player, profile)
	elseif id == "Reward" then
		reward(player, profile)
	elseif id == "RaidRival" and isHook(profile) then
		openGoal(player, profile)
	end
end

function GuidedService.OnStep(player: Player, profile: any, def: any, complete: boolean)
	if not isGuided(profile) then
		return
	end
	if complete then
		stepAt[player.UserId] = nil
		GuidedService.ClearCamp(player)
		return
	end
	openStep(player, profile, def)
end

function GuidedService.OnStepDone(player: Player, profile: any, def: any)
	if not isGuided(profile) or def == nil then
		return
	end
	local f = FUNNEL_OF_STEP[def.Id]
	if f then
		GuidedService.Funnel(player, profile, f)
	end
	if def.Id == "RaidRival" and isHook(profile) then
		GuidedService.Funnel(player, profile, "NextGoal") -- claude-bud JOB 48: the goal after the raid is up
		push(player, "GuidedGoal", { Goal = nil })
	end
end

function GuidedService.OnResume(player: Player, profile: any, def: any)
	if not isGuided(profile) then
		return
	end
	if spawnAt[player.UserId] == nil then
		spawnAt[player.UserId] = GuidedService._clock()
	end
	GuidedService.Funnel(player, profile, "Spawned")
	openStep(player, profile, def)
end

function GuidedService.OnSkip(player: Player, profile: any, def: any)
	GuidedService.ClearCamp(player)
	stepAt[player.UserId] = nil
	if not isGuided(profile) or isReplay(profile) then
		return
	end
	local A = deps.AnalyticsService
	if A and A.Log then
		pcall(A.Log, "GUIDED_SKIPPED", player.UserId, { step = if def then def.Id else "?" })
	end
end

function GuidedService._Camp(player: Player): Camp?
	return camps[player.UserId]
end

function GuidedService.Init(d: { [string]: any })
	deps = d
	if G == nil or G.Enabled ~= true then
		print("[WAR EMPIRE] GuidedService: off (TutorialConfig.Guided.Enabled = false)")
		return
	end
	local CS = deps.CombatService
	if CS and CS.OnNPCDeath then
		CS.OnNPCDeath(GuidedService.OnNPCDeath)
	end
	local SS = deps.SoldierService -- claude-bud JOB 48: ArmyGrew
	if SS and SS.OnArmyChanged then
		SS.OnArmyChanged(GuidedService.OnArmyChanged)
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char: Model)
			local hum = char:WaitForChild("Humanoid", 10)
			if hum and hum:IsA("Humanoid") then
				(hum :: Humanoid).Died:Connect(function()
					onDied(player)
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerAdded:Connect(milestones) -- claude-bud JOB 48: SessionMilestone
	for _, p in ipairs(Players:GetPlayers()) do
		milestones(p)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		GuidedService.ClearCamp(player)
		stepAt[player.UserId] = nil
		spawnAt[player.UserId] = nil
	end)
	print(string.format("[WAR EMPIRE] GuidedService Init (OwnerFirst=%s)", tostring(G.OwnerFirst)))
end

return GuidedService
