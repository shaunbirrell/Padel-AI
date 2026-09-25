--!strict
--[[
	OpsGarrison — the NPC ledger and each job site's guards (W3 step 2 Phase B, lane O; spec §4, contract §4.3).
	SERVER ONLY. Every NPC goes through lane N's CombatService API (called with nil checks and pcall):
	  SpawnNPC(type, homeCFrame, { GroupId = siteId, NoRespawn = true, Home, Leash, Stance, ProvokeRadius, Static })
	  OnNPCDeath(fn) / DespawnNPC(id) / ProvokeGroup(groupId) / CalmGroup(groupId) / NPCCounts()
	CombatService keeps the hard cap (CombatConfig.MaxActiveNPCs 18 regular, +SpecialOverCap for special types); the
	NPC line-of-sight and hit-chance code is untouched (combat fairness), and nothing here aims or fires.

	Ledger (Npc.*): Budget 18 regular slots for all sites. A site reserves its Need when it wakes (standing posts +
	reinforcements present on this build, or the wave cap for uplinks / the holdout). A site whose NPCs are all special
	types (CombatConfig.SpecialNPCTypes) may use the EventReserve 4 only when the regular budget is short. Fewer than
	MinGarrison free slots -> the site is Quiet. Before the cutover the legacy field / bank NPCs still stand, so the
	free count is also capped by what CombatService would accept (NPCCounts, when lane N has landed).

	Without lane N (no OnNPCDeath / DespawnNPC / ProvokeGroup / CalmGroup) a 2-argument SpawnNPC respawns its NPCs
	for ever, so every site that needs NPCs stays Off (OpsSites asks CoreReady()).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)

local N = OpsConfig.Npc

local OpsGarrison = {}

local CombatService: any = nil
local onDeath: ((any, any) -> ())? = nil -- (rt, info) -> OpsService
local npcSite: { [string]: any } = {} -- npc id -> site runtime record
local used = 0 -- regular ledger slots reserved by awake sites
local usedEvent = 0 -- EventReserve slots reserved by awake special-type sites
local deathConn: (() -> ())? = nil

function OpsGarrison.Init(deps: { [string]: any }, deathFn: (any, any) -> ())
	CombatService = deps.CombatService
	onDeath = deathFn
	if deathConn == nil and CombatService and CombatService.OnNPCDeath then
		local ok, disc = pcall(CombatService.OnNPCDeath, function(info: any)
			if typeof(info) ~= "table" or typeof(info.Id) ~= "string" then
				return
			end
			local rt = npcSite[info.Id]
			if rt == nil then
				return
			end
			npcSite[info.Id] = nil
			local e = rt.Npcs[info.Id]
			rt.Npcs[info.Id] = nil
			if e ~= nil then
				rt.NpcCount -= 1
				rt.Killed += 1
				if e.Row ~= nil and rt.RowNpc[e.Row] == info.Id then
					rt.RowNpc[e.Row] = nil
				end
				if e.Row ~= nil then
					rt.RowDeadAt = rt.RowDeadAt or {}
					rt.RowDeadAt[e.Row] = os.clock()
				end
			end
			if onDeath then
				onDeath(rt, info)
			end
		end)
		if ok and typeof(disc) == "function" then
			deathConn = disc
		end
	end
end

-- lane N's API is in (without it grouped, no-respawn NPCs are impossible)
function OpsGarrison.CoreReady(): boolean
	local cs = CombatService
	return cs ~= nil
		and typeof(cs.SpawnNPC) == "function"
		and typeof(cs.OnNPCDeath) == "function"
		and typeof(cs.DespawnNPC) == "function"
		and typeof(cs.ProvokeGroup) == "function"
		and typeof(cs.CalmGroup) == "function"
end

-- the NPC type to spawn for a garrison row (nil = missing: the site is off). CampCommander falls back until lane N
function OpsGarrison.TypeFor(typeId: string): string?
	local types: any = CombatConfig.NPCTypes
	if types[typeId] ~= nil then
		return typeId
	end
	if typeId == N.CommanderType and types[N.CommanderFallback] ~= nil then
		return N.CommanderFallback
	end
	return nil
end

function OpsGarrison.IsSpecial(typeId: string): boolean
	local list: any = (CombatConfig :: any).SpecialNPCTypes
	if typeof(list) ~= "table" then
		list = { "BankGuard", "OilRigGuard", "FortGuard" } -- today's hard-coded list (CombatService.SpawnNPC)
	end
	return table.find(list, typeId) ~= nil
end

-- the standing-surface point of a garrison row (anchor or config At); nil = not built on this quality
function OpsGarrison.RowCFrame(rt: any, row: OpsConfig.GarrisonPost): CFrame?
	if row.At ~= nil then
		local at = row.At
		return CFrame.new(at.X, at.Y, at.Z) * CFrame.Angles(0, math.rad(at.Yaw), 0)
	end
	local a = row.Post and rt.Anchors[row.Post]
	return if a then a.CFrame else nil
end

--[[ Slots this site needs when it wakes: standing + reinforcement rows present on this build; sites with waves
	need the wave cap (Npc.WaveMaxAlive), which also covers their standing posts. ]]
function OpsGarrison.Need(rt: any): number
	local def: OpsConfig.SiteDef = rt.Def
	local n = 0
	for _, row in ipairs(def.Garrison) do
		if OpsGarrison.RowCFrame(rt, row) ~= nil then
			n += 1
		end
	end
	if def.Waves ~= nil and #def.Waves > 0 then
		n = math.max(n, N.WaveMaxAlive)
	end
	return n
end

local function allSpecial(rt: any): boolean
	local def: OpsConfig.SiteDef = rt.Def
	if #def.Garrison == 0 then
		return false
	end
	for _, row in ipairs(def.Garrison) do
		if not OpsGarrison.IsSpecial(OpsGarrison.TypeFor(row.Type) or row.Type) then
			return false
		end
	end
	return def.Waves == nil
end

local function opsAlive(): number
	local n = 0
	for _ in pairs(npcSite) do
		n += 1
	end
	return n
end

-- regular slots free right now (the ledger, and what CombatService would still accept)
function OpsGarrison.Free(): number
	local free = N.Budget - used
	local cs = CombatService
	if cs and typeof(cs.NPCCounts) == "function" then
		local ok, c = pcall(cs.NPCCounts)
		if ok and typeof(c) == "table" and typeof(c.Total) == "number" then
			local others = math.max(0, c.Total - opsAlive())
			local cap = tonumber((CombatConfig :: any).MaxActiveNPCs) or N.Budget
			free = math.min(free, cap - others - used)
		end
	end
	return math.max(0, free)
end

function OpsGarrison.Ledger(): (number, number)
	return used, usedEvent
end

--[[ Reserve this site's slots. Returns false (nothing reserved) when fewer than MinGarrison could be had: Quiet. ]]
function OpsGarrison.Reserve(rt: any): boolean
	if rt.Alloc > 0 then
		return true
	end
	local need = OpsGarrison.Need(rt)
	if need <= 0 then
		return true
	end
	local free = OpsGarrison.Free()
	local reg = math.min(need, free)
	local ev = 0
	if reg < need and allSpecial(rt) then
		ev = math.min(need - reg, math.max(0, N.EventReserve - usedEvent))
	end
	if reg + ev < math.min(need, N.MinGarrison) then
		return false
	end
	used += reg
	usedEvent += ev
	rt.Alloc = reg + ev
	rt.AllocEvent = ev
	return true
end

function OpsGarrison.Release(rt: any)
	used = math.max(0, used - (rt.Alloc - rt.AllocEvent))
	usedEvent = math.max(0, usedEvent - rt.AllocEvent)
	rt.Alloc = 0
	rt.AllocEvent = 0
end

-- a clear point for a Probe anchor / wave point (Npc.ProbeClear, searched out to Npc.ProbeSearch); nil = none
function OpsGarrison.ClearPoint(p: Vector3, ignore: { Instance }?): Vector3?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local function clear(q: Vector3): boolean
		local box = Vector3.new(N.ProbeClear * 2 + 2, 5, N.ProbeClear * 2 + 2)
		local ok, parts = pcall(function()
			return Workspace:GetPartBoundsInBox(CFrame.new(q + Vector3.new(0, 2.6, 0)), box, params)
		end)
		if not ok or typeof(parts) ~= "table" then
			return true
		end
		for _, part in ipairs(parts :: { any }) do
			if part:IsA("BasePart") and part.CanCollide and part.Anchored then
				return false
			end
		end
		return true
	end
	if clear(p) then
		return p
	end
	local step = 2
	local r = step
	while r <= N.ProbeSearch do
		for i = 0, 7 do
			local a = i * math.pi / 4
			local q = p + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if clear(q) then
				return q
			end
		end
		r += step
	end
	return nil
end

-- the nearest standing post of the site to p (Probe / wave fallback)
function OpsGarrison.NearestPost(rt: any, p: Vector3, roles: { string }?): CFrame?
	local best: CFrame? = nil
	local bestD = math.huge
	local function consider(cf: CFrame?)
		if cf then
			local d = (cf.Position - p).Magnitude
			if d < bestD then
				best, bestD = cf, d
			end
		end
	end
	if roles then
		for _, role in ipairs(roles) do
			local a = rt.Anchors[role]
			consider(if a then a.CFrame else nil)
		end
	else
		for _, row in ipairs((rt.Def :: OpsConfig.SiteDef).Garrison) do
			if row.When == nil or row.When == "Open" then
				consider(OpsGarrison.RowCFrame(rt, row))
			end
		end
	end
	return best
end

local function spawnOne(rt: any, typeId: string, home: CFrame, opts: { [string]: any }, rowIdx: number?, extra: boolean): boolean
	local cs = CombatService
	if cs == nil or typeof(cs.SpawnNPC) ~= "function" then
		return false
	end
	local tid = OpsGarrison.TypeFor(typeId)
	if tid == nil then
		return false
	end
	local at = home + Vector3.new(0, N.RootLift, 0)
	opts.GroupId = rt.Id
	opts.NoRespawn = true
	opts.Home = at
	local ok, rec = pcall(cs.SpawnNPC, tid, at, opts)
	if not ok then
		warn("[Ops] SpawnNPC failed at " .. rt.Id .. ": " .. tostring(rec))
		return false
	end
	if typeof(rec) ~= "table" or typeof(rec.Id) ~= "string" then
		return false
	end
	npcSite[rec.Id] = rt
	rt.Npcs[rec.Id] = { Rec = rec, Row = rowIdx, Extra = extra, Home = at }
	rt.NpcCount += 1
	rt.Spawned += 1
	if rowIdx ~= nil then
		rt.RowNpc[rowIdx] = rec.Id
	end
	return true
end

-- room for one more NPC at this site (its reservation)
function OpsGarrison.HasRoom(rt: any): boolean
	return rt.NpcCount + rt.Pending < rt.Alloc
end

local function optsFor(rt: any, row: OpsConfig.GarrisonPost): { [string]: any }
	local def: OpsConfig.SiteDef = rt.Def
	local stance = if row.Static then "Post" else row.Stance
	local o: { [string]: any } = { Stance = stance, Leash = row.Leash, Static = row.Static }
	if stance == "Passive" then
		o.ProvokeRadius = def.ProvokeRadius or N.DefaultProvokeRadius
	end
	return o
end

--[[ Spawn the garrison rows whose When matches (nil / "Open" = the standing garrison), staggered
	SpawnStaggerSeconds apart, within the site's reservation. Rows that already have a live NPC are skipped. Probe
	anchors are clearance-tested once; no clear point -> the nearest standing post. `playersClear(p)` (optional):
	only spawn a row when it returns true (the Open top-up rule). `done()` runs after the last spawn. ]]
function OpsGarrison.SpawnRows(rt: any, when: string?, playersClear: ((Vector3) -> boolean)?, done: (() -> ())?)
	local def: OpsConfig.SiteDef = rt.Def
	local want = when or "Open"
	local batch: { { Idx: number, Row: OpsConfig.GarrisonPost, CF: CFrame } } = {}
	-- the Open top-up (playersClear given) never brings a killed guard back sooner than the respawn delay: a player
	-- outside TopUpClearRadius must not farm NPC kill rewards faster than CombatConfig.NPCRespawnSeconds
	local deadAt: { [number]: number } = rt.RowDeadAt or {}
	local delay = math.max(N.TopUpDelaySeconds or 0, tonumber((CombatConfig :: any).NPCRespawnSeconds) or 0)
	local nowC = os.clock()
	for i, row in ipairs(def.Garrison) do
		local rowWhen = row.When or "Open"
		local tooSoon = playersClear ~= nil and deadAt[i] ~= nil and nowC - deadAt[i] < delay
		if rowWhen == want and rt.RowNpc[i] == nil and not tooSoon then
			local cf = OpsGarrison.RowCFrame(rt, row)
			if cf ~= nil and (playersClear == nil or playersClear(cf.Position)) then
				local a = row.Post and rt.Anchors[row.Post]
				if a and a.Probe then
					local q = OpsGarrison.ClearPoint(cf.Position)
					if q then
						cf = CFrame.new(q) * CFrame.Angles(0, math.rad(a.Yaw), 0)
					else
						cf = OpsGarrison.NearestPost(rt, cf.Position) or cf
					end
				end
				table.insert(batch, { Idx = i, Row = row, CF = cf })
			end
		end
	end
	local n = 0
	for _, b in ipairs(batch) do
		if not OpsGarrison.HasRoom(rt) then
			break
		end
		rt.Pending += 1
		local gen = rt.Gen
		local extra = want ~= "Open"
		task.delay(n * N.SpawnStaggerSeconds, function()
			if rt.Gen ~= gen then
				return -- a Sleep reset Pending and cancelled this spawn: never count down a later generation
			end
			rt.Pending = math.max(0, rt.Pending - 1)
			if rt.Live and rt.Alloc > 0 and rt.RowNpc[b.Idx] == nil then
				spawnOne(rt, b.Row.Type, b.CF, optsFor(rt, b.Row), b.Idx, extra)
			end
			if rt.Pending == 0 and done then
				done()
			end
		end)
		n += 1
	end
	if n == 0 and done then
		done()
	end
end

--[[ One wave NPC group at the wave ring (uplinks / holdout): all of `types` or nothing (the next wave waits while
	it would exceed Npc.WaveMaxAlive or the reservation). Aggressive, leash ring + 20 from its wave point. ]]
function OpsGarrison.SpawnWave(rt: any, types: { string }, centre: Vector3, ring: number, waveNo: number): boolean
	local cap = math.min(N.WaveMaxAlive, rt.Alloc)
	if rt.NpcCount + rt.Pending + #types > cap then
		return false
	end
	local def: OpsConfig.SiteDef = rt.Def
	for i, typeId in ipairs(types) do
		local a = ((waveNo - 1) * 2 + (i - 1)) * math.pi / 2 -- the 4 compass points, rotated per wave
		local p = centre + Vector3.new(math.sin(a) * ring, 0, -math.cos(a) * ring)
		local q = OpsGarrison.ClearPoint(p)
		local cf: CFrame
		if q then
			cf = CFrame.lookAt(q, Vector3.new(centre.X, q.Y, centre.Z))
		else
			cf = OpsGarrison.NearestPost(rt, p, def.WavePosts) or CFrame.new(centre)
		end
		rt.Pending += 1
		local gen = rt.Gen
		task.delay((i - 1) * N.SpawnStaggerSeconds, function()
			if rt.Gen ~= gen then
				return -- cancelled by a Sleep (see SpawnRows)
			end
			rt.Pending = math.max(0, rt.Pending - 1)
			if rt.Live and rt.Alloc > 0 then
				spawnOne(rt, typeId, cf, { Stance = "Aggressive", Leash = ring + 20 }, nil, true)
			end
		end)
	end
	return true
end

function OpsGarrison.Despawn(rt: any, id: string)
	npcSite[id] = nil
	if rt.Npcs[id] ~= nil then
		local e = rt.Npcs[id]
		rt.Npcs[id] = nil
		rt.NpcCount -= 1
		if e.Row ~= nil and rt.RowNpc[e.Row] == id then
			rt.RowNpc[e.Row] = nil
		end
	end
	if CombatService and typeof(CombatService.DespawnNPC) == "function" then
		pcall(CombatService.DespawnNPC, id)
	end
end

-- reinforcements and wave NPCs go at the end of a run (the standing garrison stays and walks home)
function OpsGarrison.DespawnExtras(rt: any)
	local ids: { string } = {}
	for id, e in pairs(rt.Npcs) do
		if e.Extra then
			table.insert(ids, id)
		end
	end
	for _, id in ipairs(ids) do
		OpsGarrison.Despawn(rt, id)
	end
end

-- sleep: every NPC of the site despawns (no pay) and its slots go back to the ledger
function OpsGarrison.Sleep(rt: any)
	rt.Gen += 1 -- cancels staggered spawns still pending
	rt.Pending = 0
	local ids: { string } = {}
	for id in pairs(rt.Npcs) do
		table.insert(ids, id)
	end
	for _, id in ipairs(ids) do
		OpsGarrison.Despawn(rt, id)
	end
	OpsGarrison.Release(rt)
end

function OpsGarrison.Provoke(rt: any)
	if CombatService and typeof(CombatService.ProvokeGroup) == "function" then
		pcall(CombatService.ProvokeGroup, rt.Id)
	end
end

function OpsGarrison.Calm(rt: any)
	if CombatService and typeof(CombatService.CalmGroup) == "function" then
		pcall(CombatService.CalmGroup, rt.Id)
	end
end

-- any live guard of the site hurt (health below max): the provoke test for checkpoints / camps / rigs
function OpsGarrison.AnyHurt(rt: any): boolean
	for _, e in pairs(rt.Npcs) do
		local rec = e.Rec
		local hum = rec and rec.Humanoid
		if hum and hum.Parent and hum.Health < hum.MaxHealth - 0.01 then
			return true
		end
	end
	return false
end

-- homes of the live standing guards (the on-foot proximity provoke test)
function OpsGarrison.Homes(rt: any, out: { Vector3 }): { Vector3 }
	table.clear(out)
	for _, e in pairs(rt.Npcs) do
		if not e.Extra then
			table.insert(out, e.Home.Position)
		end
	end
	return out
end

function OpsGarrison.SiteOf(npcId: string): any
	return npcSite[npcId]
end

function OpsGarrison.AliveTotal(): number
	return opsAlive()
end

return OpsGarrison
