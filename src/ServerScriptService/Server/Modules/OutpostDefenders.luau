--!strict
--[[
	claude-bud JOB 24 §6: NPC defenders at every capturable outpost (Shared/Configs/OutpostDefenderConfig; read its
	header for the rules). Server only. The defenders are ordinary CombatService NPCs (SpawnNPC with a GroupId
	"Outpost.<id>", NoRespawn: this module brings them back), so damage, line of sight, hit chance, kill rewards, the army
	targeting them and their shooting back are all CombatService's, unchanged.

	deps (Start): CombatService, EngagementService?, NotificationService?,
	  Territories: () -> { { Id: string, Def: any, Held: boolean } }   (Held = a player / clan holds it now)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local C: any = require(Shared.Configs.OutpostDefenderConfig)

local OutpostDefenders = {}
OutpostDefenders.Stats = { Spawned = 0, Slept = 0, Killed = 0, Refused = 0 }

type Site = {
	Id: string,
	Recs: { any },
	Awake: boolean,
	ClearedAt: number?, -- all dead (killed) at this os.clock(): back RespawnSeconds later
	EmptySince: number?, -- nobody within SleepStuds since this os.clock()
	HeldBefore: boolean,
}

local deps: { [string]: any } = {}
local sites: { [string]: Site } = {}
local started = false
local blockedNoteAt: { [number]: number } = {}

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function alive(site: Site): number
	local n = 0
	for _, rec in ipairs(site.Recs) do
		if rec.Alive and rec.Model and rec.Model.Parent then
			n += 1
		end
	end
	return n
end

local function total(): number
	local n = 0
	for _, s in pairs(sites) do
		n += alive(s)
	end
	return n
end

-- the NPC types for a territory: Easy / Medium by StipendCash, Hard = its own GuardNPCType x GuardCount
function OutpostDefenders.TypesFor(def: any): { string }
	if typeof(def.Tier) == "string" and C.Tiers[def.Tier] then
		return C.Tiers[def.Tier] -- (a JOB 24 §7 area: its own tier)
	end
	local stipend = tonumber(def.StipendCash) or 0
	if stipend >= C.HardFromStipend then
		if typeof(def.GuardNPCType) == "string" then
			local out = {}
			for _ = 1, math.max(1, math.floor(tonumber(def.GuardCount) or 4)) do
				table.insert(out, def.GuardNPCType)
			end
			return out
		end
		return C.Tiers.Hard
	elseif stipend >= C.MediumFromStipend then
		return C.Tiers.Medium
	end
	return C.Tiers.Easy
end

function OutpostDefenders.TierFor(def: any): string
	if typeof(def.Tier) == "string" then
		return def.Tier
	end
	local stipend = tonumber(def.StipendCash) or 0
	return if stipend >= C.HardFromStipend then "Hard" elseif stipend >= C.MediumFromStipend then "Medium" else "Easy"
end

-- the posts: a ring round the capture point (oil rigs: a small ring on the deck), facing out
function OutpostDefenders.Posts(def: any, n: number): { CFrame }
	local c: Vector3 = def.Position
	local r = if def.IsOilRig then C.RigRingStuds else (tonumber(def.Radius) or 50) * C.RingFraction
	local out = {}
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2 + 0.4
		local p = Vector3.new(c.X + math.cos(a) * r, c.Y + 3, c.Z + math.sin(a) * r)
		table.insert(out, CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))))
	end
	return out
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function wake(site: Site, def: any)
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = chars
	local cs = deps.CombatService
	if cs == nil or cs.SpawnNPC == nil then
		return
	end
	local types = OutpostDefenders.TypesFor(def)
	local posts = OutpostDefenders.Posts(def, #types)
	table.clear(site.Recs)
	for i, typeId in ipairs(types) do
		if total() >= C.MaxTotal then
			OutpostDefenders.Stats.Refused += 1
			break
		end
		local cf = posts[i]
		if not def.IsOilRig then
			-- stand on the real ground (terrain / a dune / a slab), never inside it or in the air
			local from = cf.Position + Vector3.new(0, 60, 0)
			local hit = workspace:Raycast(from, Vector3.new(0, -160, 0), groundParams)
			if hit then
				cf = CFrame.new(hit.Position + Vector3.new(0, 3, 0)) * cf.Rotation
			end
		end
		local ok, rec = pcall(cs.SpawnNPC, typeId, cf, {
			GroupId = "Outpost." .. site.Id,
			NoRespawn = true,
			Home = cf,
			Leash = (tonumber(def.Radius) or 50) + C.LeashExtraStuds,
			OverCap = true,
		})
		if ok and rec then
			rec.Model:SetAttribute("WE_OutpostDefender", site.Id)
			table.insert(site.Recs, rec)
			OutpostDefenders.Stats.Spawned += 1
		else
			OutpostDefenders.Stats.Refused += 1
		end
	end
	site.Awake = #site.Recs > 0
end

local function sleep(site: Site)
	local cs = deps.CombatService
	for _, rec in ipairs(site.Recs) do
		if rec.Alive and cs and cs.DespawnNPC then
			pcall(cs.DespawnNPC, rec.Id)
		end
	end
	table.clear(site.Recs)
	site.Awake = false
	OutpostDefenders.Stats.Slept += 1
end

-- true while this outpost still has a living defender (TerritoryService: nobody captures it yet)
function OutpostDefenders.Blocking(territoryId: string): boolean
	if C.Enabled ~= true then
		return false
	end
	local site = sites[territoryId]
	return site ~= nil and site.Awake and alive(site) > 0
end

-- a player standing in a blocked zone is told why the bar does not move (once per BlockedNoteSeconds)
function OutpostDefenders.NoteBlocked(player: Player)
	local ns = deps.NotificationService
	local now = os.clock()
	if ns == nil or now - (blockedNoteAt[player.UserId] or -math.huge) < C.BlockedNoteSeconds then
		return
	end
	blockedNoteAt[player.UserId] = now
	pcall(ns.Notify, player, C.BlockedText, "Warn")
end

local function anyPlayerWithin(pos: Vector3, studs: number): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and flatDist(root.Position, pos) <= studs then
			return true
		end
	end
	return false
end

local function step()
	local list = deps.Territories and deps.Territories() or {}
	-- JOB 24 §7: the named enemy areas (never held: nothing to capture there)
	for _, a in ipairs(C.Areas or {}) do
		table.insert(list, { Id = "Area_" .. a.Id, Def = a, Held = false })
	end
	local now = os.clock()
	for _, t in ipairs(list) do
		local def = t.Def
		local site = sites[t.Id]
		if site == nil then
			site = { Id = t.Id, Recs = {}, Awake = false, ClearedAt = nil, EmptySince = nil, HeldBefore = t.Held }
			sites[t.Id] = site
		end
		if t.Held then
			-- a player / clan holds it: the defenders leave; they come back RespawnSeconds after it is neutral again
			if site.Awake then
				sleep(site)
			end
			site.HeldBefore = true
			site.ClearedAt = now
		else
			if site.HeldBefore then
				site.HeldBefore = false
				site.ClearedAt = now
			end
			local pos: Vector3 = def.Position
			if site.Awake then
				if alive(site) == 0 then
					site.Awake = false
					site.ClearedAt = now -- cleared by the players: back after RespawnSeconds
					table.clear(site.Recs)
				elseif anyPlayerWithin(pos, C.SleepStuds) then
					site.EmptySince = nil
				else
					site.EmptySince = site.EmptySince or now
					if now - (site.EmptySince :: number) >= C.SleepAfterSeconds then
						sleep(site)
						site.EmptySince = nil
					end
				end
			elseif (site.ClearedAt == nil or now - site.ClearedAt >= C.RespawnSeconds) and anyPlayerWithin(pos, C.WakeStuds) then
				wake(site, def)
			end
		end
	end
end

function OutpostDefenders.Start(d: { [string]: any })
	deps = d
	if started or C.Enabled ~= true then
		return
	end
	started = true
	local cs = deps.CombatService
	if cs and cs.OnNPCDeath then
		cs.OnNPCDeath(function(info: any)
			local g = info and info.GroupId
			if typeof(g) ~= "string" or string.sub(g, 1, 8) ~= "Outpost." then
				return
			end
			OutpostDefenders.Stats.Killed += 1
			local es = deps.EngagementService
			if info.Killer and es and es.NoteDefenderKill then
				pcall(es.NoteDefenderKill, info.Killer)
			end
		end)
	end
	task.spawn(function()
		task.wait(5)
		while true do
			local ok, err = pcall(step :: any)
			if not ok then
				warn("[OutpostDefenders] step error: " .. tostring(err))
			end
			task.wait(C.CheckSeconds)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		blockedNoteAt[p.UserId] = nil
	end)
	print("[WAR EMPIRE] OutpostDefenders started (max " .. tostring(C.MaxTotal) .. ")")
end

return OutpostDefenders
