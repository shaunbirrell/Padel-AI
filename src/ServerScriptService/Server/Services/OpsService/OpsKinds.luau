--!strict
--[[
	OpsKinds — the stage machine of every job kind (W3 step 2 Phase B, lane O; spec §5, activities §3, contract §2.3).
	SERVER ONLY. A site walks OpsConfig.Sites[i].Stages in order; each stage id has one rule:

	  Breach / Start  prompt at At: the job goes Active (lockdown, group provoked); Breach opens the runtime door and
	                  spawns the When = "Breach" rows (the bank's R1 / R2)
	  Crack           ring R at At for Seconds: progress while an eligible participant stands in it on foot, not hit
	                  within Zones.UnderFireSeconds; a non-ally with no ally of the starter freezes it (not the bank:
	                  NoContest). Spawns the When = "Crack" rows (the Armory heavy); Sparks on the bank vault.
	  Grab            prompt at At: one bag per eligible player (present PresentSeconds since the start, not carrying,
	                  not on cooldown), MaxBags per run; the player's cooldown starts at the grab (saved)
	  Carry           OpsCargo carries it home; pay on delivery
	  Alarm           checkpoints: on provoke a prompt "Cut alarm" and a Seconds timer; not cut -> the When = "Alarm"
	                  rows (R1 / R2, clearance-probed) spawn
	  Clear           every NPC this site spawned is dead
	  Take / Open     the completing prompt (checkpoint booth, camp chest); a Cache's Open pays the opener at once
	  Hack / Hold     prompt, then a ring R for Seconds with waves (Npc.WaveMaxAlive); Hack decays while empty
	                  (Decay) and fails at 0; Hold fails after EmptyFail empty seconds
	  Plant           prompts on At / AtAny; min(Need, anchors present) charges within Window of the first
	  Fuse            Seconds, then Damage within DamageR of each charge (CombatService.ApplyRadiusDamage)
	  Recover         prompt: the carried box (the Crash)

	Pay (OpsRewards) at completion: Checkpoint = the taker + clan allies present; Uplink / Holdout = the starter's
	team present (share / seconds); Camp / Siege / Rig / Sabotage = every participant present PresentSeconds within
	PresentR of the site; Cache = the opener; carry kinds pay on delivery. Nobody on cooldown is paid; the paid
	player's cooldown starts (saved). Rivals keep their per-kill NPC cash only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)

local Z = OpsConfig.Zones
local N = OpsConfig.Npc
local R = OpsConfig.Rewards
local TOAST = OpsConfig.Text.Toast

local OpsKinds = {}

local ctx: any = nil

function OpsKinds.Init(context: any)
	ctx = context
end

-- kinds whose zone presence and holds need the player ON FOOT (activities §2.2)
local ON_FOOT: { [string]: boolean } = { Vault = true, VaultLite = true, Cache = true, Uplink = true, Holdout = true }
-- kinds that go Active when their garrison is provoked (not by a prompt)
local PROVOKE_KINDS: { [string]: boolean } = { Checkpoint = true, Camp = true, Rig = true, Siege = true }
-- first-stage ids that show a prompt while the site is Open
local IDLE_PROMPT: { [string]: boolean } = { Breach = true, Start = true, Hack = true, Hold = true, Plant = true, Recover = true, Open = true }

function OpsKinds.OnFootKind(kind: string): boolean
	return ON_FOOT[kind] == true
end

local function def(rt: any): OpsConfig.SiteDef
	return rt.Def
end

local function stageOf(rt: any): OpsConfig.StageDef?
	return def(rt).Stages[rt.StageIdx]
end

function OpsKinds.PresentNeed(d: OpsConfig.SiteDef): number
	return d.PresentSeconds or Z.PresentSeconds
end

local function fmtClock(sec: number): string
	sec = math.max(0, math.ceil(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
OpsKinds.FmtClock = fmtClock

-- the anchor roles of a stage (At, or the AtAny anchors present)
local function stageRoles(rt: any, st: OpsConfig.StageDef): { string }
	local out: { string } = {}
	if st.AtAny ~= nil then
		for _, r in ipairs(st.AtAny) do
			if rt.Anchors[r] ~= nil then
				table.insert(out, r)
			end
		end
	elseif st.At ~= nil and rt.Anchors[st.At] ~= nil then
		table.insert(out, st.At)
	end
	return out
end

local function promptKey(st: OpsConfig.StageDef, role: string): string
	return st.Id .. ":" .. role
end

-- the prompts of one stage (a rotating cache shows only its live anchor; planted pumps show none)
local function showPrompts(rt: any, st: OpsConfig.StageDef)
	if st.Prompt == nil then
		return
	end
	local d = def(rt)
	for _, role in ipairs(stageRoles(rt, st)) do
		local live = d.Rotate == nil or role == rt.RotateRole
		if live and not rt.Planted[role] then
			ctx.Sites.Prompt(rt, promptKey(st, role), role, st)
		end
	end
end

local function dropStagePrompts(rt: any, st: OpsConfig.StageDef)
	for _, role in ipairs(stageRoles(rt, st)) do
		ctx.Sites.DropPrompt(rt, promptKey(st, role))
	end
end

--[[ Back to the first stage (a fresh run). Prompts of an idle first stage appear only while the site is Open. ]]
function OpsKinds.Reset(rt: any)
	ctx.Sites.DropPrompts(rt)
	rt.StageIdx = 1
	rt.StageAt = os.clock()
	rt.Progress = 0
	rt.Parts = {}
	rt.Blocked = {}
	rt.Starter = nil
	rt.Planted = {}
	rt.PlantCount = 0
	rt.Planter = nil
	rt.WindowUntil = nil
	rt.BagsTaken = 0
	rt.AlarmUntil = nil
	rt.AlarmCut = false
	rt.FuseUntil = nil
	rt.WaveIdx = 1
	rt.Ringing = false
	rt.EmptyFor = 0
	rt.LockUntil = nil
	rt.ActiveAt = nil
	rt.Provoke = {}
	rt.Killed = 0
	rt.Contested = false
	rt.StarterClan = nil
	OpsKinds.Idle(rt)
end

--[[ An ally of the run's starter: the starter, or a member of the starter's clan as it was when the run started (read
	once at activation: a starter who leaves mid-run must not turn their own clan-mates into "enemies" who freeze the
	ring and lose the pay). No starter (a provoked site): everyone is on the same side. ]]
local function starterAlly(rt: any, p: Player): boolean
	local s: Player? = rt.Starter
	if s == nil or s == p then
		return true
	end
	local clan: string? = rt.StarterClan
	return clan ~= nil and ctx.Zones.ClanOf(p) == clan
end

function OpsKinds.Idle(rt: any)
	if rt.State ~= "Open" then
		return
	end
	local st = def(rt).Stages[1]
	if st ~= nil and IDLE_PROMPT[st.Id] then
		showPrompts(rt, st)
	end
end

-- the job goes Active (a start prompt, or the garrison provoked)
local function activate(rt: any, player: Player?)
	if rt.State == "Active" then
		return
	end
	local d = def(rt)
	local nowC = os.clock()
	rt.ActiveAt = nowC
	rt.Starter = player
	rt.StarterClan = if player then ctx.Zones.ClanOf(player) else nil
	rt.Parts = {}
	rt.Blocked = {}
	if d.Lockdown ~= nil then
		rt.LockUntil = nowC + d.Lockdown
	end
	ctx.SetState(rt, "Active")
	ctx.Garrison.Provoke(rt)
	ctx.Sites.Smoke(rt, true)
	if player then
		ctx.EndNovice(player)
	end
	ctx.Rewards.Log(ctx.Events.OPS_START, if player then player.UserId else nil, { site = rt.Id })
	if d.Kind == "Vault" then
		ctx.RaidStarted(rt, player)
	end
end
OpsKinds.Activate = activate

local enter: (rt: any) -> ()
local complete: (rt: any, player: Player?) -> ()

local function nextStage(rt: any)
	local st = stageOf(rt)
	if st then
		dropStagePrompts(rt, st)
	end
	rt.StageIdx += 1
	enter(rt)
end

enter = function(rt: any)
	local st = stageOf(rt)
	local nowC = os.clock()
	rt.StageAt = nowC
	rt.Progress = 0
	rt.EmptyFor = 0
	if st == nil or st.Id == "Carry" then
		if st == nil then
			complete(rt, nil)
		end
		return
	end
	local id = st.Id
	if id == "Crack" then
		ctx.Garrison.SpawnRows(rt, "Crack")
		ctx.Sites.Sparks(rt, true, st.At)
	elseif id == "Alarm" then
		rt.AlarmUntil = nowC + (st.Seconds or 12)
		showPrompts(rt, st)
	elseif id == "Fuse" then
		rt.FuseUntil = nowC + (st.Seconds or 8)
	elseif id == "Hack" or id == "Hold" then
		if rt.State == "Active" then
			rt.Ringing = true
		else
			showPrompts(rt, st)
		end
	else
		showPrompts(rt, st)
	end
	ctx.MarkSite(rt)
end

--[[ Pay each player in `payees` (unique) who is alive, loaded and not on this site's cooldown; start their cooldown.
	Returns how many were paid. ]]
local function payAll(rt: any, payees: { Player }): number
	local d = def(rt)
	local nowU = os.time()
	local paid = 0
	for _, p in ipairs(payees) do
		local profile = ctx.Profile(p)
		local s = ctx.Zones.Get(p)
		if profile ~= nil and s.Alive and ctx.Rewards.CdLeft(profile, d.Id, nowU) <= 0 then
			local cash, xp = ctx.Rewards.Quote(profile, d, nowU)
			if ctx.Rewards.Grant(p, d, cash, xp, false) then
				ctx.Rewards.SetCd(p, profile, d, nowU)
				paid += 1
				local line = if d.Kind == "Checkpoint"
					then string.format(TOAST.CheckpointTaken, ctx.Rewards.FormatCash(cash))
					else string.format(TOAST.Paid, d.Title, ctx.Rewards.FormatCash(cash))
				ctx.Notify(p, line, "Reward")
				ctx.MarkPlayerSite(p, d.Id)
			end
		end
	end
	return paid
end

-- players present long enough (optionally: only those `ally(p)` accepts; uplinks by ring share)
local function eligible(rt: any, ally: ((Player) -> boolean)?): { Player }
	local d = def(rt)
	local out: { Player } = {}
	local need = OpsKinds.PresentNeed(d)
	local elapsed = if rt.ActiveAt then os.clock() - rt.ActiveAt else 0
	for uid, part in pairs(rt.Parts) do
		local p = Players:GetPlayerByUserId(uid)
		if p and p.Parent then
			local ok
			if d.PresentShare ~= nil then
				local ringT = os.clock() - (rt.RingAt or rt.ActiveAt or os.clock())
				ok = ringT > 0 and part.In / ringT >= d.PresentShare
			else
				ok = part.T >= math.min(need, math.max(0, elapsed - 0.01))
			end
			if ok and (ally == nil or ally(p)) then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function endRun(rt: any, success: boolean, taker: Player?)
	local d = def(rt)
	local row = R.Rows[d.Pay]
	ctx.Sites.DropPrompts(rt)
	rt.Ringing = false
	ctx.Sites.Sparks(rt, false)
	ctx.Sites.Smoke(rt, false)
	ctx.Garrison.DespawnExtras(rt)
	ctx.Garrison.Calm(rt)
	if rt.NpcCount == 0 and rt.Pending == 0 and rt.Alloc > 0 then
		ctx.Garrison.Sleep(rt) -- nobody left standing: the slots go back to the ledger while the site cools
	end
	if rt.Door ~= nil then
		rt.DoorClose = true -- closes once nobody stands in the site (nobody is ever shut in)
	end
	rt.LastEnd = os.clock()
	ctx.Rewards.Log(if success then ctx.Events.OPS_DONE else ctx.Events.OPS_FAIL, if taker then taker.UserId else nil, { site = rt.Id, bags = rt.BagsTaken })
	if d.Kind == "Vault" and not success and (rt.BagsTaken or 0) == 0 then
		for uid in pairs(rt.Parts) do
			local p = Players:GetPlayerByUserId(uid)
			if p then
				ctx.Notify(p, TOAST.Sealed, "Info")
			end
		end
	end
	rt.Parts = {}
	if success and d.Kind == "Checkpoint" then
		ctx.Garrison.Sleep(rt) -- every guard is down: the slots go back to the ledger while Held
		rt.HeldBy = if taker then taker.UserId else nil
		rt.HeldColor = if taker then ctx.ColorOf(taker) else nil
		ctx.Sites.HeldSign(rt, rt.HeldColor)
		ctx.SetState(rt, "Held", ctx.Rewards.Seconds(d.HeldSeconds or 600))
		return
	end
	local cd = if success then row.SiteCd else row.FailCd
	cd = ctx.Rewards.Seconds(cd)
	if cd > 0 then
		ctx.SetState(rt, "Cooling", cd)
	else
		ctx.SetState(rt, if rt.Alloc > 0 or rt.Need == 0 then "Open" else "Dormant")
		OpsKinds.Reset(rt)
	end
end
OpsKinds.End = endRun

complete = function(rt: any, player: Player?)
	local d = def(rt)
	local payees: { Player }
	if d.Kind == "Checkpoint" then
		payees = eligible(rt, if player then function(p: Player): boolean
			return ctx.Zones.Allies(player, p)
		end else nil)
		if player and table.find(payees, player) == nil then
			table.insert(payees, player) -- the taker held the booth: always present
		end
	elseif d.Kind == "Uplink" or d.Kind == "Holdout" then
		payees = if rt.Starter then eligible(rt, function(p: Player): boolean
			return starterAlly(rt, p)
		end) else {}
	else
		payees = eligible(rt, nil)
	end
	payAll(rt, payees)
	endRun(rt, true, player)
end

-- a Cache opens at once for the opener (no NPCs, no run)
local function openCache(rt: any, player: Player)
	local d = def(rt)
	local profile = ctx.Profile(player)
	if profile == nil then
		return
	end
	payAll(rt, { player })
	ctx.Rewards.Log(ctx.Events.OPS_DONE, player.UserId, { site = rt.Id })
	if d.Rotate ~= nil and #d.Rotate > 1 then
		local idx = (table.find(d.Rotate, rt.RotateRole) or 1) % #d.Rotate + 1
		for _ = 1, #d.Rotate do
			if rt.Anchors[d.Rotate[idx]] ~= nil then
				break
			end
			idx = idx % #d.Rotate + 1
		end
		ctx.Sites.DropPrompts(rt)
		rt.RotateRole = d.Rotate[idx]
		rt.Target = rt.Anchors[rt.RotateRole]
		rt.Moved = true
		OpsKinds.Idle(rt)
	end
	ctx.MarkSite(rt)
end

local function grab(rt: any, st: OpsConfig.StageDef, player: Player)
	local d = def(rt)
	if (rt.BagsTaken or 0) >= (st.MaxBags or 1) then
		return
	end
	local part = rt.Parts[player.UserId]
	if part == nil or part.T < OpsKinds.PresentNeed(d) then
		ctx.Notify(player, TOAST.NeedShare, "Info")
		return
	end
	if ctx.Cargo.Carrying(player) ~= nil then
		ctx.Notify(player, TOAST.HandsFull, "Info")
		return
	end
	if not ctx.Cargo.CanAdd() then
		ctx.Notify(player, TOAST.BagsFull, "Info")
		return
	end
	local profile = ctx.Profile(player)
	local nowU = os.time()
	local cash, xp = ctx.Rewards.Quote(profile, d, nowU)
	local bag = ctx.Cargo.Grab(player, d, cash, xp)
	if bag == nil then
		return
	end
	ctx.Rewards.SetCd(player, profile, d, nowU)
	ctx.EndNovice(player)
	ctx.MarkPlayerSite(player, d.Id)
	rt.BagsTaken = (rt.BagsTaken or 0) + 1
	if rt.BagsTaken >= (st.MaxBags or 1) then
		endRun(rt, true, player)
	end
end

local function recover(rt: any, player: Player)
	local d = def(rt)
	if ctx.Cargo.Carrying(player) ~= nil then
		ctx.Notify(player, TOAST.HandsFull, "Info")
		return
	end
	if not ctx.Cargo.CanAdd() then
		ctx.Notify(player, TOAST.BagsFull, "Info")
		return
	end
	activate(rt, player)
	local profile = ctx.Profile(player)
	local nowU = os.time()
	local cash, xp = ctx.Rewards.Quote(profile, d, nowU)
	if ctx.Cargo.Grab(player, d, cash, xp) == nil then
		return
	end
	ctx.Rewards.SetCd(player, profile, d, nowU)
	ctx.MarkPlayerSite(player, d.Id)
	rt.BagsTaken = 1
	endRun(rt, true, player)
end

local function plant(rt: any, st: OpsConfig.StageDef, role: string, player: Player)
	if rt.Planted[role] then
		return
	end
	rt.Planted[role] = true
	rt.PlantCount += 1
	ctx.Sites.DropPrompt(rt, promptKey(st, role))
	if rt.State ~= "Active" then
		activate(rt, player)
	else
		ctx.EndNovice(player)
	end
	if rt.WindowUntil == nil and st.Window ~= nil then
		rt.WindowUntil = os.clock() + st.Window
	end
	if rt.Planter == nil then
		rt.Planter = player
	end
	local need = math.min(st.Need or 1, math.max(1, #stageRoles(rt, st)))
	ctx.MarkSite(rt)
	if rt.PlantCount >= need then
		nextStage(rt)
	end
end

--[[ A prompt on this site fired and OpsService re-checked it (rate limit, profile, alive, distance, on foot,
	stage, cooldown, teleport lock). ]]
function OpsKinds.OnPrompt(rt: any, st: OpsConfig.StageDef, role: string, player: Player)
	local id = st.Id
	local d = def(rt)
	if id == "Breach" or id == "Start" then
		activate(rt, player)
		if id == "Breach" then
			ctx.Sites.SetDoor(rt, true)
			rt.DoorClose = false
			ctx.Garrison.SpawnRows(rt, "Breach")
		end
		nextStage(rt)
	elseif id == "Alarm" then
		rt.AlarmCut = true
		ctx.EndNovice(player)
		nextStage(rt)
	elseif id == "Take" then
		ctx.EndNovice(player)
		complete(rt, player)
	elseif id == "Open" then
		if d.Kind == "Cache" then
			openCache(rt, player)
		else
			complete(rt, player)
		end
	elseif id == "Grab" then
		grab(rt, st, player)
	elseif id == "Hack" or id == "Hold" then
		activate(rt, player)
		dropStagePrompts(rt, st)
		rt.Ringing = true
		rt.RingAt = os.clock()
		rt.StageAt = rt.RingAt
		rt.Progress = 0
		rt.EmptyFor = 0
		rt.WaveIdx = 1
		ctx.MarkSite(rt)
	elseif id == "Plant" then
		plant(rt, st, role, player)
	elseif id == "Recover" then
		recover(rt, player)
	end
end

-- which stage prompts may fire now (the "stage is valid" re-check)
function OpsKinds.PromptValid(rt: any, st: OpsConfig.StageDef): boolean
	local cur = stageOf(rt)
	if cur == nil or cur.Id ~= st.Id then
		return false
	end
	if IDLE_PROMPT[st.Id] and rt.StageIdx == 1 and rt.State == "Open" then
		return true
	end
	if st.Id == "Plant" and rt.State == "Active" then
		return true
	end
	return rt.State == "Active"
end

-- ── the 4 Hz tick of an Active site ─────────────────────────────────────────────────────────────────────────────
local function ringCentre(rt: any, st: OpsConfig.StageDef): (Vector3?, number)
	local a = st.At and rt.Anchors[st.At]
	if a == nil then
		return nil, 0
	end
	return a.Position, st.R or a.R or 8
end

-- who is in a ring: eligible allies of the starter / eligible others / per-player block reasons
local function ringScan(rt: any, centre: Vector3, r: number, nowC: number, dt: number, underFire: boolean): (number, number, number)
	local d = def(rt)
	local onFoot = ON_FOOT[d.Kind] == true
	local team, others, any = 0, 0, 0
	table.clear(rt.Blocked)
	for _, p in ipairs(ctx.PlayerList) do
		local s = ctx.Zones.Get(p)
		if s.Alive and s.Pos and ctx.Zones.Within(s.Pos, centre, r, d.AllowSeated) then
			local why: string? = nil
			if ctx.Zones.Locked(p, nowC) then
				continue -- a teleport-locked player neither helps nor contests
			end
			if onFoot and s.Seated and not d.AllowSeated then
				why = "Vehicle"
			elseif underFire and ctx.Zones.UnderFire(p, nowC) then
				why = "UnderFire"
			end
			if why ~= nil then
				rt.Blocked[p.UserId] = why
			else
				any += 1
				local ally = starterAlly(rt, p)
				if ally then
					team += 1
				else
					others += 1
				end
				local part = rt.Parts[p.UserId]
				if part then
					part.In += dt
				end
			end
		end
	end
	return team, others, any
end

local function tickCrack(rt: any, st: OpsConfig.StageDef, dt: number, nowC: number)
	local centre, r = ringCentre(rt, st)
	if centre == nil then
		return
	end
	local d = def(rt)
	local team, others, any = ringScan(rt, centre, r, nowC, dt, true)
	local go
	if d.NoContest or not Z.ContestFreeze then
		go = any > 0
	else
		go = team > 0
		if team == 0 and others > 0 then
			for _, p in ipairs(ctx.PlayerList) do
				local s = ctx.Zones.Get(p)
				if s.Pos and rt.Blocked[p.UserId] == nil and ctx.Zones.Within(s.Pos, centre, r) then
					rt.Blocked[p.UserId] = "Enemy"
				end
			end
		end
	end
	rt.Contested = team == 0 and others > 0
	if go then
		rt.Progress = math.min(1, rt.Progress + dt / math.max(1, st.Seconds or 30))
	end
	if rt.Progress >= 1 then
		ctx.Sites.Sparks(rt, false)
		nextStage(rt)
	end
end

local function tickRing(rt: any, st: OpsConfig.StageDef, dt: number, nowC: number)
	local centre, r = ringCentre(rt, st)
	if centre == nil then
		return
	end
	local d = def(rt)
	local team, others = ringScan(rt, centre, r, nowC, dt, false)
	local frozen = Z.ContestFreeze and team == 0 and others > 0
	rt.Contested = frozen
	if frozen then
		for _, p in ipairs(ctx.PlayerList) do
			local s = ctx.Zones.Get(p)
			if s.Pos and rt.Blocked[p.UserId] == nil and ctx.Zones.Within(s.Pos, centre, r) then
				rt.Blocked[p.UserId] = "Enemy"
			end
		end
	end
	local seconds = math.max(1, st.Seconds or 60)
	if team > 0 then
		rt.Progress = math.min(1, rt.Progress + dt / seconds)
		rt.EmptyFor = 0
	else
		rt.EmptyFor += dt
		if st.Id == "Hack" and not frozen then
			rt.Progress = math.max(0, rt.Progress - (st.Decay or 0) * dt)
		end
	end
	-- waves on the wave ring (the next wave waits while it would pass Npc.WaveMaxAlive)
	local waves = d.Waves
	if waves ~= nil then
		local elapsed = nowC - (rt.RingAt or nowC)
		local ringR = if d.Kind == "Holdout" then N.HoldoutWaveRing else N.WaveRing
		while rt.WaveIdx <= #waves and elapsed >= waves[rt.WaveIdx].At do
			if ctx.Garrison.SpawnWave(rt, waves[rt.WaveIdx].Types, centre, ringR, rt.WaveIdx) then
				rt.WaveIdx += 1
			else
				break
			end
		end
	end
	if rt.Progress >= 1 then
		complete(rt, rt.Starter)
		return
	end
	local failAfter = st.EmptyFail or 10
	if st.Id == "Hack" then
		if rt.Progress <= 0 and rt.EmptyFor >= failAfter then
			endRun(rt, false, nil)
		end
	elseif rt.EmptyFor >= failAfter then
		endRun(rt, false, nil)
	end
end

local function blast(rt: any, st: OpsConfig.StageDef)
	local d = def(rt)
	local roles: { string } = {}
	for role in pairs(rt.Planted) do
		table.insert(roles, role)
	end
	table.sort(roles)
	local attacker: Player? = rt.Planter
	if attacker and attacker.Parent == nil then
		attacker = nil
	end
	for _, role in ipairs(roles) do
		local a = rt.Anchors[role]
		if a then
			ctx.Blast(attacker, a.Position + Vector3.new(0, 2, 0), st.DamageR or 12, st.Damage or 40)
			if d.Kind == "Sabotage" then
				ctx.Sites.PumpSmoke(rt, role)
			end
		end
	end
end

--[[ Participation: every player within PresentR of the site's zone points while it is Active (alive, not locked,
	on foot for on-foot kinds; seated counts at AllowSeated sites). ]]
local function accrue(rt: any, dt: number, nowC: number)
	local d = def(rt)
	local r = d.PresentR or Z.PresentR
	local onFoot = ON_FOOT[d.Kind] == true
	for _, p in ipairs(ctx.PlayerList) do
		local s = ctx.Zones.Get(p)
		if s.Alive and s.Pos and not ctx.Zones.Locked(p, nowC) and not (onFoot and s.Seated and not d.AllowSeated) then
			if ctx.Zones.NearAny(s.Pos, rt.Points, r, d.AllowSeated) then
				local part = rt.Parts[p.UserId]
				if part == nil then
					part = { T = 0, In = 0 }
					rt.Parts[p.UserId] = part
				end
				part.T += dt
			end
		end
	end
end

-- the Open-state provoke test (checkpoints, camps, rigs, forts): a guard hurt or down, or an on-foot player within
-- ProvokeRadius of a guard's home for CombatConfig.NPCStance.ProvokeHoldSeconds
local homesScratch: { Vector3 } = {}
local function provoked(rt: any, dt: number): boolean
	if rt.Killed > 0 or ctx.Garrison.AnyHurt(rt) then
		return true
	end
	local d = def(rt)
	local radius = d.ProvokeRadius or N.DefaultProvokeRadius
	local stance: any = (CombatConfig :: any).NPCStance
	local hold = if typeof(stance) == "table" and typeof(stance.ProvokeHoldSeconds) == "number" then stance.ProvokeHoldSeconds else 2
	local homes = ctx.Garrison.Homes(rt, homesScratch)
	if #homes == 0 then
		return false
	end
	local hit = false
	for _, p in ipairs(ctx.PlayerList) do
		local s = ctx.Zones.Get(p)
		local uid = p.UserId
		if s.Alive and s.Pos and not s.Seated and ctx.Zones.NearAny(s.Pos, homes, radius) then
			rt.Provoke[uid] = (rt.Provoke[uid] or 0) + dt
			if rt.Provoke[uid] >= hold then
				hit = true
			end
		else
			rt.Provoke[uid] = nil
		end
	end
	return hit
end

function OpsKinds.Tick(rt: any, dt: number, nowC: number)
	local d = def(rt)
	if rt.State == "Open" then
		if PROVOKE_KINDS[d.Kind] and rt.Alloc > 0 and rt.Pending == 0 and provoked(rt, dt) then
			local first = d.Stages[1]
			activate(rt, nil)
			if first ~= nil and not IDLE_PROMPT[first.Id] then
				enter(rt)
			end
		end
		return
	end
	if rt.State ~= "Active" then
		return
	end
	accrue(rt, dt, nowC)
	if rt.LockUntil ~= nil and nowC >= rt.LockUntil then
		endRun(rt, (rt.BagsTaken or 0) > 0, nil)
		return
	end
	local st = stageOf(rt)
	if st == nil then
		return
	end
	local id = st.Id
	if id == "Crack" then
		tickCrack(rt, st, dt, nowC)
	elseif id == "Alarm" then
		if rt.AlarmUntil ~= nil and nowC >= rt.AlarmUntil then
			rt.AlarmUntil = nil
			ctx.Garrison.SpawnRows(rt, "Alarm")
			nextStage(rt)
		end
	elseif id == "Clear" then
		if rt.Pending == 0 and rt.NpcCount == 0 then
			nextStage(rt)
		end
	elseif id == "Fuse" then
		if rt.FuseUntil ~= nil and nowC >= rt.FuseUntil then
			rt.FuseUntil = nil
			blast(rt, st)
			nextStage(rt)
		end
	elseif id == "Plant" then
		if rt.WindowUntil ~= nil and nowC >= rt.WindowUntil then
			endRun(rt, false, nil)
		end
	elseif (id == "Hack" or id == "Hold") and rt.Ringing then
		tickRing(rt, st, dt, nowC)
	end
end

-- OpsProgressPayload for one player at an Active site (nil = nothing to show)
function OpsKinds.Progress(rt: any, player: Player, nowC: number): OpsConfig.OpsProgressPayload?
	local st = stageOf(rt)
	if st == nil or rt.State ~= "Active" then
		return nil
	end
	local d = def(rt)
	local out: OpsConfig.OpsProgressPayload = { Site = rt.Id, Stage = st.Id, Guards = rt.NpcCount }
	local id = st.Id
	if id == "Crack" or ((id == "Hack" or id == "Hold") and rt.Ringing) then
		out.Frac = math.floor(rt.Progress * 1000 + 0.5) / 1000
		out.Blocked = rt.Blocked[player.UserId]
		if out.Blocked == nil and ON_FOOT[d.Kind] then
			local s = ctx.Zones.Get(player)
			local c, r = ringCentre(rt, st)
			if s.Seated and s.Pos and c and ctx.Zones.Within(s.Pos, c, r) and not d.AllowSeated then
				out.Blocked = "Vehicle"
			end
		end
	end
	if id == "Alarm" and rt.AlarmUntil then
		out.Left = math.max(0, math.ceil(rt.AlarmUntil - nowC))
	elseif id == "Fuse" and rt.FuseUntil then
		out.Left = math.max(0, math.ceil(rt.FuseUntil - nowC))
	elseif rt.LockUntil then
		out.Left = math.max(0, math.ceil(rt.LockUntil - nowC))
	end
	if d.Waves ~= nil and rt.Ringing then
		out.Wave = math.min(#d.Waves, math.max(1, rt.WaveIdx - 1))
		out.Waves = #d.Waves
	end
	if id == "Grab" then
		local profile = ctx.Profile(player)
		if profile and ctx.Rewards.CdLeft(profile, d.Id, os.time()) > 0 then
			out.Blocked = "Cooldown"
		end
	end
	return out
end

return OpsKinds
