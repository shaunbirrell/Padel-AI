--!strict
--[[
	claude-bud JOB 31 (2026-09-30): garrisons and activities at the new sites (SiteActivityConfig, WorldSitesConfig,
	Modules/WorldSites). Server-authoritative:
	  * a player starts an activity (RequestSiteActivity "start" <id>);
	  * the server spawns that player's own NPC group (GroupId "Act.<UserId>") or hides the cache crate;
	  * kills come from CombatService.OnNPCDeath (Info.Killer);
	  * zones and the sniper perch are checked against the server's character;
	  * the reward is paid once (EconomyService.AddCash "activity", XPService, AddGold);
	  * a per-player cooldown follows every finish.
	State for the Missions panel's ACTIVITIES rows goes out on FeaturePush "Activities": on request, on start / finish,
	and at <= 1 Hz while one runs.
	Garrisons ("Garrison.<Site>") wake for players the switch is live for and use normal NPC slots.
	Nothing here runs per frame; one 1 s loop while any activity runs, one 2 s garrison loop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SiteActivityConfig = require(Shared.Configs.SiteActivityConfig)
local WorldSitesConfig = require(Shared.Configs.WorldSitesConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)

local SiteActivityService = {}

local deps: { [string]: any } = {}
local WorldSites: any = nil

type Run = {
	Def: SiteActivityConfig.ActivityDef,
	Site: any,
	StartedAt: number,
	Npcs: { [string]: boolean },
	NpcLeft: number,
	Kills: number,
	Wave: number,
	Hold: number,
	OutFor: number,
	Cache: BasePart?,
	Phase: string,
}

local running: { [number]: Run } = {}
local cooldownUntil: { [number]: { [string]: number } } = {}
local lastPush: { [number]: number } = {}

type Garrison = { Recs: { any }, Awake: boolean, ClearedAt: number? }
local garrisons: { [string]: Garrison } = {}

local rng = Random.new()

local function live(userId: number): boolean
	return WorldSitesConfig.Enabled == true and RetentionConfig.Live(SiteActivityConfig, userId)
end

local function defById(id: string): SiteActivityConfig.ActivityDef?
	for _, d in ipairs(SiteActivityConfig.Activities) do
		if d.Id == id then
			return d
		end
	end
	return nil
end

local function root(player: Player): BasePart?
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if hum == nil or hum.Health <= 0 or r == nil or not r:IsA("BasePart") then
		return nil
	end
	return r
end

local function flatDist(a: Vector3, x: number, z: number): number
	local dx, dz = a.X - x, a.Z - z
	return math.sqrt(dx * dx + dz * dz)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function groundCF(x: number, z: number, faceX: number?, faceZ: number?): CFrame
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = chars
	local hit = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), groundParams)
	local y = (if hit then hit.Position.Y else 0.5) + 3
	if faceX and faceZ and (faceX ~= x or faceZ ~= z) then
		return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(faceX, y, faceZ))
	end
	return CFrame.new(x, y, z)
end

local function spawnNpc(typeId: string, cf: CFrame, group: string, opts: { [string]: any }?): any
	local cs = deps.CombatService
	if cs == nil or cs.SpawnNPC == nil then
		return nil
	end
	local o: { [string]: any } = { GroupId = group, NoRespawn = true, Home = cf }
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	local ok, rec = pcall(cs.SpawnNPC, typeId, cf, o)
	return if ok then rec else nil
end

local function despawn(id: string)
	local cs = deps.CombatService
	if cs and cs.DespawnNPC then
		pcall(cs.DespawnNPC, id)
	end
end

local function notify(player: Player, text: string, kind: string?)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function log(player: Player, ev: string, props: { [string]: any })
	local a = deps.AnalyticsService
	if a and a.Log then
		pcall(a.Log, ev, player.UserId, props)
	end
end

-- ── state for the Missions panel ─────────────────────────────────────────────────────────────────────────────────
local function progressText(run: Run): string
	local d = run.Def
	if d.Kind == "ClearCamp" then
		return string.format("Soldiers left: %d", run.NpcLeft)
	elseif d.Kind == "Depot" then
		return if run.Phase == "Hold" then string.format("Hold the depot %d/%d", math.floor(run.Hold), d.HoldSeconds or 30) else string.format("Guards left: %d", run.NpcLeft)
	elseif d.Kind == "Convoy" then
		return string.format("Wave %d/%d · enemies %d", run.Wave, d.Waves or 3, run.NpcLeft)
	elseif d.Kind == "Cache" then
		return "Search " .. tostring(run.Site.Name)
	elseif d.Kind == "Sniper" then
		return string.format("Targets %d/%d from the deck", run.Kills, d.Targets or 5)
	end
	return ""
end

local function payload(player: Player): { [string]: any }
	local uid = player.UserId
	local list = {}
	local now = os.clock()
	local cds = cooldownUntil[uid] or {}
	local run = running[uid]
	for _, d in ipairs(SiteActivityConfig.Activities) do
		local site = WorldSites and WorldSites.Get(d.Site)
		if site == nil then
			continue
		end
		local row: { [string]: any } = {
			Id = d.Id,
			Title = d.Title,
			Desc = d.Desc,
			Cash = d.Cash,
			XP = d.XP,
			Short = d.Short,
			X = site.X,
			Y = site.Y,
			Z = site.Z,
			State = "Ready",
		}
		if run and run.Def.Id == d.Id then
			row.State = "Active"
			row.Left = math.max(0, math.ceil(d.Seconds - (now - run.StartedAt)))
			row.Progress = progressText(run)
			local s = run.Site
			row.X, row.Y, row.Z = s.X, s.Y, s.Z
			if d.Kind == "Sniper" and s.Tower then
				local p = (s.Tower :: CFrame).Position
				row.X, row.Y, row.Z = p.X, p.Y, p.Z
			end
		elseif (cds[d.Id] or 0) > now then
			row.State = "Cooldown"
			row.Left = math.ceil(cds[d.Id] - now)
		elseif run then
			row.State = "Busy" -- another activity runs
		end
		table.insert(list, row)
	end
	return { List = list }
end

local function push(player: Player)
	if not live(player.UserId) then
		return
	end
	lastPush[player.UserId] = os.clock()
	local ev = deps.RemoteSetup and deps.RemoteSetup.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "Activities", payload(player))
	end
end

-- ── finish ───────────────────────────────────────────────────────────────────────────────────────────────────────
local function finish(player: Player, ok: boolean, reason: string?)
	local uid = player.UserId
	local run = running[uid]
	if run == nil then
		return
	end
	running[uid] = nil
	for id in pairs(run.Npcs) do
		despawn(id)
	end
	if run.Cache then
		run.Cache:Destroy()
	end
	local d = run.Def
	cooldownUntil[uid] = cooldownUntil[uid] or {}
	cooldownUntil[uid][d.Id] = os.clock() + d.Cooldown
	if player.Parent == nil then
		return
	end
	if ok then
		local es = deps.EconomyService
		if es and es.AddCash then
			pcall(es.AddCash, player, d.Cash, "activity")
		end
		if (d.Gold or 0) > 0 and es and es.AddGold then
			pcall(es.AddGold, player, d.Gold, "activity")
		end
		local xs = deps.XPService
		if xs and xs.AddXP and d.XP > 0 then
			pcall(xs.AddXP, player, d.XP, "activity")
		end
		notify(player, string.format("%s done! +$%d", d.Title, d.Cash), "Reward")
	else
		notify(player, string.format("%s failed: %s", d.Title, reason or "time up"), "Warn")
	end
	log(player, "ACTIVITY_DONE", { activity = d.Id, ok = ok, seconds = math.floor(os.clock() - run.StartedAt) })
	push(player)
end

-- ── start ────────────────────────────────────────────────────────────────────────────────────────────────────────
local function ring(site: any, n: number, radius: number): { CFrame }
	local out = {}
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, n do
		local a = a0 + (i - 1) * (math.pi * 2 / n)
		table.insert(out, groundCF(site.X + radius * math.cos(a), site.Z + radius * math.sin(a), site.X, site.Z))
	end
	return out
end

local function spawnGroup(player: Player, run: Run, types: { string }, posts: { CFrame }, opts: { [string]: any }?): boolean
	local group = "Act." .. tostring(player.UserId)
	for i, t in ipairs(types) do
		local rec = spawnNpc(t, posts[((i - 1) % #posts) + 1], group, opts)
		if rec == nil then
			return false
		end
		run.Npcs[rec.Id] = true
		run.NpcLeft += 1
	end
	return true
end

local function spawnWave(player: Player, run: Run)
	local d = run.Def
	local site = run.Site
	local a = rng:NextNumber(0, math.pi * 2)
	local dist = site.R + 50
	local cx, cz = site.X + dist * math.cos(a), site.Z + dist * math.sin(a)
	local posts = {}
	for i = 1, #(d.Npc or {}) do
		table.insert(posts, groundCF(cx + (i - 2) * 6, cz + (i % 2) * 5, site.X, site.Z))
	end
	run.Wave += 1
	-- a wave that cannot spawn (the NPC cap) is skipped, never a failure
	spawnGroup(player, run, d.Npc or {}, posts, { Leash = site.R + 90 })
end

local function hideCache(player: Player, run: Run)
	local site = run.Site
	local C = SiteActivityConfig.Cache
	local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(6, C.HideStuds)
	local cf = groundCF(site.X + r * math.cos(a), site.Z + r * math.sin(a))
	local crate = Instance.new("Part")
	crate.Name = "WE_SupplyCache"
	crate.Size = Vector3.new(2.4, 1.8, 1.8)
	crate.CFrame = cf - Vector3.new(0, 2.1, 0)
	crate.Anchored = true
	crate.CanCollide = true
	crate.Material = Enum.Material.WoodPlanks
	crate.Color = Color3.fromRGB(96, 104, 58)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Supply cache"
	prompt.HoldDuration = C.HoldSeconds
	prompt.MaxActivationDistance = C.PromptStuds
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate
	local owner = player.UserId
	prompt.Triggered:Connect(function(who: Player)
		local run2 = running[owner]
		-- only the player who started it; the server re-checks the distance
		if who.UserId ~= owner or run2 == nil or run2.Cache ~= crate then
			return
		end
		local r0 = root(who)
		if r0 == nil or (r0.Position - crate.Position).Magnitude > C.PromptStuds + 4 then
			return
		end
		finish(who, true)
	end)
	local folder = Workspace:FindFirstChild("WorldFill") or Workspace
	crate.Parent = folder
	run.Cache = crate
end

local function sniperTargets(player: Player, run: Run, n: number)
	local site = run.Site
	local tower: CFrame? = site.Tower
	if tower == nil then
		return
	end
	local S = SiteActivityConfig.Sniper
	local base = tower.Position
	local look = tower.LookVector
	local heading = math.atan2(look.Z, look.X)
	for i = 1, n do
		local a = heading + rng:NextNumber(-0.9, 0.9)
		local r = rng:NextNumber(S.MinStuds, S.MaxStuds)
		local cf = groundCF(base.X + r * math.cos(a), base.Z + r * math.sin(a), base.X, base.Z)
		spawnGroup(player, run, { (run.Def.Npc or { "Infantry" })[1] }, { cf }, { Static = true, Stance = "Post" })
	end
end

local function start(player: Player, id: string): (boolean, string?)
	local uid = player.UserId
	if not live(uid) then
		return false, "Off"
	end
	if running[uid] then
		return false, "Busy"
	end
	local d = defById(id)
	if d == nil then
		return false, "Unknown"
	end
	local cds = cooldownUntil[uid]
	if cds and (cds[d.Id] or 0) > os.clock() then
		return false, "Cooldown"
	end
	if root(player) == nil then
		return false, "NoCharacter"
	end
	local siteId = d.Site
	if d.Sites and #d.Sites > 0 then
		siteId = d.Sites[rng:NextInteger(1, #d.Sites)]
	end
	local site = WorldSites and WorldSites.Get(siteId)
	if site == nil then
		return false, "NoSite"
	end
	local run: Run = { Def = d, Site = site, StartedAt = os.clock(), Npcs = {}, NpcLeft = 0, Kills = 0, Wave = 0, Hold = 0, OutFor = 0, Cache = nil, Phase = "Fight" }
	running[uid] = run
	local ok = true
	if d.Kind == "ClearCamp" or d.Kind == "Depot" then
		ok = spawnGroup(player, run, d.Npc or {}, ring(site, #(d.Npc or {}), site.R * 0.45), { Leash = site.R + 25 })
	elseif d.Kind == "Convoy" then
		spawnWave(player, run)
		ok = run.NpcLeft > 0
	elseif d.Kind == "Cache" then
		hideCache(player, run)
	elseif d.Kind == "Sniper" then
		sniperTargets(player, run, d.Targets or 5)
		ok = run.NpcLeft > 0 and site.Tower ~= nil
	end
	if not ok then
		-- the NPC cap is full (or no perch): undo without a cooldown
		running[uid] = nil
		for nid in pairs(run.Npcs) do
			despawn(nid)
		end
		if run.Cache then
			run.Cache:Destroy()
		end
		return false, "AreaBusy"
	end
	log(player, "ACTIVITY_START", { activity = d.Id })
	notify(player, d.Title .. ": " .. d.Desc, "Info")
	push(player)
	return true, nil
end

-- ── NPC deaths ───────────────────────────────────────────────────────────────────────────────────────────────────
local function onDeath(info: any)
	local g = if typeof(info) == "table" then info.GroupId else nil
	if typeof(g) ~= "string" then
		return
	end
	if string.sub(g, 1, 4) == "Act." then
		local uid = tonumber(string.sub(g, 5))
		local run = uid and running[uid]
		if run == nil or not run.Npcs[info.Id] then
			return
		end
		run.Npcs[info.Id] = nil
		run.NpcLeft = math.max(0, run.NpcLeft - 1)
		local player = Players:GetPlayerByUserId(uid :: number)
		if run.Def.Kind == "Sniper" and player then
			local killer = info.Killer
			local tower: CFrame? = run.Site.Tower
			local r = root(player)
			local onPerch = r ~= nil and tower ~= nil and flatDist(r.Position, tower.X, tower.Z) <= SiteActivityConfig.Sniper.PerchStuds and r.Position.Y >= tower.Y - 1
			if killer == player and onPerch then
				run.Kills += 1
			else
				sniperTargets(player, run, 1) -- not from the deck: a new target stands up
			end
		end
		if player then
			push(player)
		end
	elseif string.sub(g, 1, 9) == "Garrison." then
		local gs = garrisons[string.sub(g, 10)]
		if gs then
			local alive = 0
			for _, rec in ipairs(gs.Recs) do
				if rec.Alive and rec.Id ~= info.Id then
					alive += 1
				end
			end
			if alive == 0 then
				gs.Awake = false
				gs.ClearedAt = os.clock()
				table.clear(gs.Recs)
				local k = info.Killer -- claude-bud JOB 39: the Intel Office's "clear a site garrison" contract
				if typeof(k) == "Instance" and k:IsA("Player") then
					pcall(function()
						(require(script.Parent.EndgameService) :: any).NoteContract(k, "Garrison", 1)
					end)
				end
			end
		end
	end
end

-- ── the 1 s activity loop ────────────────────────────────────────────────────────────────────────────────────────
local function tick(dt: number)
	local pad = SiteActivityConfig.ZonePadStuds
	for uid, run in pairs(running) do
		local player = Players:GetPlayerByUserId(uid)
		if player == nil then
			running[uid] = nil
			for id in pairs(run.Npcs) do
				despawn(id)
			end
			if run.Cache then
				run.Cache:Destroy()
			end
			continue
		end
		local d = run.Def
		if os.clock() - run.StartedAt > d.Seconds then
			finish(player, false, "time up")
			continue
		end
		local r = root(player)
		local inZone = r ~= nil and flatDist(r.Position, run.Site.X, run.Site.Z) <= run.Site.R + pad
		if d.Kind == "ClearCamp" then
			if run.NpcLeft == 0 then
				finish(player, true)
				continue
			end
		elseif d.Kind == "Depot" then
			if run.NpcLeft == 0 then
				run.Phase = "Hold"
				if inZone then
					run.Hold += dt
				end
				if run.Hold >= (d.HoldSeconds or 30) then
					finish(player, true)
					continue
				end
			end
		elseif d.Kind == "Convoy" then
			local gap = d.WaveGap or 30
			if run.Wave < (d.Waves or 3) and os.clock() - run.StartedAt >= run.Wave * gap then
				spawnWave(player, run)
			end
			if inZone then
				run.OutFor = 0
			else
				run.OutFor += dt
				if run.OutFor > 8 then
					finish(player, false, "left the checkpoint")
					continue
				end
			end
			if run.Wave >= (d.Waves or 3) and run.NpcLeft == 0 then
				finish(player, true)
				continue
			end
		elseif d.Kind == "Sniper" then
			if run.Kills >= (d.Targets or 5) then
				finish(player, true)
				continue
			end
		end
		if os.clock() - (lastPush[uid] or 0) >= SiteActivityConfig.PushSeconds then
			push(player)
		end
	end
end

-- ── garrisons ────────────────────────────────────────────────────────────────────────────────────────────────────
local function garrisonTick()
	local G = SiteActivityConfig.Garrisons
	if G.Enabled ~= true or WorldSites == nil then
		return
	end
	local roots = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = if live(p.UserId) then root(p) else nil
		if r then
			table.insert(roots, r.Position)
		end
	end
	for siteId, types in pairs(G.Sites) do
		local site = WorldSites.Get(siteId)
		if site == nil then
			continue
		end
		local gs = garrisons[siteId]
		if gs == nil then
			gs = { Recs = {}, Awake = false, ClearedAt = nil }
			garrisons[siteId] = gs
		end
		local near, far = math.huge, math.huge
		for _, pos in ipairs(roots) do
			local dd = flatDist(pos, site.X, site.Z)
			near = math.min(near, dd)
			far = math.min(far, dd)
		end
		if not gs.Awake and near <= G.WakeStuds and (gs.ClearedAt == nil or os.clock() - gs.ClearedAt >= G.RespawnSeconds) then
			local posts = ring(site, #types, site.R * 0.4)
			for i, t in ipairs(types) do
				local rec = spawnNpc(t, posts[i], "Garrison." .. siteId, { Leash = site.R + 20 })
				if rec then
					rec.Model:SetAttribute("WE_SiteGarrison", siteId)
					table.insert(gs.Recs, rec)
				end
			end
			gs.Awake = #gs.Recs > 0
		elseif gs.Awake and far > G.SleepStuds then
			for _, rec in ipairs(gs.Recs) do
				if rec.Alive then
					despawn(rec.Id)
				end
			end
			table.clear(gs.Recs)
			gs.Awake = false
		end
	end
end

-- tests only: one activity-loop step of dt seconds (tools/sim/run_sites_test.py)
SiteActivityService._Tick = function(dt: number)
	tick(dt)
end

function SiteActivityService.Running(player: Player): string?
	local run = running[player.UserId]
	return if run then run.Def.Id else nil
end

function SiteActivityService.Init(d: { [string]: any })
	deps = d
	local okW, mod = pcall(function(): any
		return require(script.Parent.Parent.Modules.WorldSites)
	end)
	WorldSites = if okW then mod else nil
	if SiteActivityConfig.Enabled ~= true then
		return
	end
	local cs = d.CombatService
	if cs and cs.OnNPCDeath then
		cs.OnNPCDeath(onDeath)
	end
	local remote = d.RemoteSetup.Get(Constants.RemoteNames.RequestSiteActivity) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, action: any, id: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestSiteActivity", action, id) then
			return
		end
		if d.RateLimitService and not d.RateLimitService.Allow(player, "site_activity", 2, 4) then
			return
		end
		if not live(player.UserId) then
			return
		end
		if action == "list" then
			push(player)
		elseif action == "start" and typeof(id) == "string" then
			local ok, why = start(player, id)
			if not ok then
				local copy = ({ Busy = "Finish your current activity first", Cooldown = "Not ready yet", AreaBusy = "The battlefield is full right now; try again soon", NoSite = "That site is not on this map" } :: { [string]: string })[why or ""]
				if copy then
					notify(player, copy, "Warn")
				end
				push(player)
			end
		elseif action == "quit" then
			finish(player, false, "quit")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if next(running) ~= nil then
				pcall(tick, 1)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(math.max(1, SiteActivityConfig.Garrisons.CheckSeconds))
			pcall(garrisonTick)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		local run = running[p.UserId]
		if run then
			running[p.UserId] = nil
			for id in pairs(run.Npcs) do
				despawn(id)
			end
			if run.Cache then
				run.Cache:Destroy()
			end
		end
		cooldownUntil[p.UserId] = nil
		lastPush[p.UserId] = nil
	end)
	print("[WAR EMPIRE] SiteActivityService Init: activities=" .. #SiteActivityConfig.Activities)
end

return SiteActivityService
