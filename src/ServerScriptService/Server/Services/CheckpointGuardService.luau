--!strict
--[[
	claude-bud JOB 37 (2026-09-30): guards at the real road checkpoints (CheckpointGuardConfig). Server only.
	  * Sites: every detailed checkpoint booth (WorldKits Detail.Checkpoint tags it WE_CheckpointSite; its Attachments
	    WE_GuardPost1..5 are the posts, the one with WE_Static is the tower deck). Found once a CheckSeconds tick through
	    CollectionService (no tree scans), never assumed to exist.
	  * Wake / sleep: a live player within WakeStuds wakes the group (CombatService.SpawnNPC: GroupId "CP.<id>",
	    NoRespawn, Home = the post, Leash = SiteRadius + LeashExtra, Static for the tower, TargetFilter = live players
	    only); nobody live within SleepStuds puts it back to sleep (despawned: no NPC slot used).
	  * Combat is CombatService's / CombatNPC's (line of sight, hit chance, real shots, protections, caps). This service
	    never sets Health, never calls TakeDamage and never picks a hit.
	  * Kills: CombatService pays each guard's reward (NPC type). OnNPCDeath here counts contributors (the killer, his
	    army's kills included, and every player whose own hit is on the guard's LastHitBy within AssistSeconds).
	  * Cleared: the last guard down pays each live contributor Cleared.XP + ClearedCash once per cycle, not within
	    PlayerCooldownSeconds of his last one; toast "Checkpoint cleared +$X +Y XP"; MissionService TrackProgress
	    "Checkpoint" 1; analytics checkpoint_cleared. The group comes back RespawnSeconds later, only near a live player
	    and never while a player stands within SpawnClearStuds of a post.
	  * Map / mission: MapList(player) (hostile / cleared + countdown, live players only) and GoTargets() (checkpoints
	    with guards up or asleep and ready) for MissionService's "Checkpoint" GO.
  * codebot_v142 keep-out: a booth within CheckpointGuardConfig.KeepOutStuds of a base plot (pad edge), a player spawn
    (each plot PlayerSpawn lies on its pad; the Emergency / Neutral spawn at 0, 0) or a vehicle spawn pad (WorldConfig.Spawns.Garage gate pads + pools)
    never gets guards (logged once). The shared protection rule: the TargetFilter also refuses a player under the
    spawn / novice shield (CombatService.IsSpawnInvulnerable / IsNoviceShielded), on top of CombatNPC's own
    InvulnerableUntil hit skip.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CheckpointGuardConfig = require(Shared.Configs.CheckpointGuardConfig)

local CheckpointGuardService = {}

local G = CheckpointGuardConfig
local SITE_TAG = "WE_CheckpointSite"

export type Site = {
	Id: string,
	Booth: BasePart,
	Center: Vector3,
	Posts: { CFrame },
	Static: { boolean },
	Recs: { any },
	Awake: boolean,
	ClearedAt: number?,
	Cycle: number,
	Contrib: { [number]: number }, -- UserId -> os.clock() of his last hit / kill this cycle
	PaidCycle: { [number]: number }, -- UserId -> the cycle he was paid for
}

local deps: { [string]: any } = {}
local sites: { [string]: Site } = {}
local keptOut: { [string]: string } = {} -- site id -> reason (never guarded)
-- keep-out zones: { Kind, X, Z, Half } (Half > 0 = an axis-aligned square of that half size, else a point)
export type KeepZone = { Name: string, X: number, Z: number, Half: number }
local keepZones: { KeepZone } = {}
local lastPaid: { [number]: number } = {} -- UserId -> os.clock() of his last cleared bonus (any checkpoint)
local clock: () -> number = os.clock

local function live(uid: number): boolean
	return CheckpointGuardConfig.LiveFor(uid)
end

local function rootOf(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- a site from a tagged booth (nil when its posts are missing)
function CheckpointGuardService.SiteFromBooth(booth: BasePart): Site?
	local posts, static = {}, {}
	for i = 1, G.MaxGuards do
		local a = booth:FindFirstChild("WE_GuardPost" .. i)
		if a and a:IsA("Attachment") then
			local w = a.WorldCFrame
			-- stand on the post facing the booth's front (arrivals come from its -Z)
			local look = booth.CFrame.LookVector
			table.insert(posts, CFrame.lookAt(w.Position + Vector3.new(0, 3, 0), w.Position + Vector3.new(0, 3, 0) + look))
			table.insert(static, a:GetAttribute("WE_Static") == true)
		end
	end
	if #posts == 0 then
		return nil
	end
	local p = booth.Position
	return {
		Id = string.format("CP_%d_%d", math.floor(p.X + 0.5), math.floor(p.Z + 0.5)),
		Booth = booth,
		Center = p,
		Posts = posts,
		Static = static,
		Recs = {},
		Awake = false,
		ClearedAt = nil,
		Cycle = 1,
		Contrib = {},
		PaidCycle = {},
	}
end

-- codebot_v142: the first keep-out zone within KeepOutStuds of pos (flat), or nil
function CheckpointGuardService.KeepOutHit(pos: Vector3, zones: { KeepZone }, studs: number?): (string?, number?)
	local limit = studs or G.KeepOutStuds or 130
	for _, z in ipairs(zones) do
		local dx = math.max(math.abs(pos.X - z.X) - math.max(z.Half, 0), 0)
		local dz = math.max(math.abs(pos.Z - z.Z) - math.max(z.Half, 0), 0)
		local d = math.sqrt(dx * dx + dz * dz)
		if d < limit then
			return z.Name, d
		end
	end
	return nil, nil
end

-- the keep-out zones from the configs: plot pads, plot spawns, emergency spawn, vehicle spawn pads (server boot)
function CheckpointGuardService.BuildKeepZones(): { KeepZone }
	local out: { KeepZone } = {}
	local ok, err = pcall(function()
		local Configs = Shared:WaitForChild("Configs")
		local BaseConfig = require(Configs:WaitForChild("BaseConfig")) :: any
		local WorldConfig = require(Configs:WaitForChild("WorldConfig")) :: any
		local PlotFrame = require(Shared:WaitForChild("Util"):WaitForChild("PlotFrame")) :: any
		local half = (BaseConfig.PlotSize and BaseConfig.PlotSize.X or 320) / 2
		local plots = BaseConfig.PlotPositions or {}
		for i, pos in ipairs(plots) do
			table.insert(out, { Name = "Plot" .. i, X = pos.X, Z = pos.Z, Half = half })
		end
		local garage = WorldConfig.Spawns and WorldConfig.Spawns.Garage or {}
		for _, pad in ipairs(garage) do
			if typeof(pad.PlotId) == "number" and plots[pad.PlotId] then
				local w = PlotFrame.PlotCFrame(plots[pad.PlotId]):PointToWorldSpace(Vector3.new(pad.LocalX or 0, 0, pad.LocalZ or 0))
				table.insert(out, { Name = tostring(pad.Id), X = w.X, Z = w.Z, Half = 0 })
			elseif typeof(pad.X) == "number" and typeof(pad.Z) == "number" then
				table.insert(out, { Name = tostring(pad.Id), X = pad.X, Z = pad.Z, Half = 0 })
			end
		end
	end)
	if not ok then
		warn("[CheckpointGuardService] keep-out configs: " .. tostring(err))
	end
	-- the Emergency / Neutral spawn (Bootstrap / MapSetup, both at 0, 0); each plot's PlayerSpawn lies on its pad
	table.insert(out, { Name = "EmergencySpawn", X = 0, Z = 0, Half = 0 })
	return out
end

local function discover()
	for _, inst in ipairs(CollectionService:GetTagged(SITE_TAG)) do
		if inst:IsA("BasePart") and inst.Parent ~= nil then
			local s = CheckpointGuardService.SiteFromBooth(inst)
			if s and sites[s.Id] == nil and keptOut[s.Id] == nil then
				local hit, d = CheckpointGuardService.KeepOutHit(s.Center, keepZones)
				if hit then
					keptOut[s.Id] = hit
					print(string.format("[CheckpointGuardService] %s: no guards (%.0f studs from %s < %d keep-out)", s.Id, d or 0, hit, G.KeepOutStuds or 130))
				else
					sites[s.Id] = s
				end
			end
		end
	end
end

local function aliveCount(s: Site): number
	local n = 0
	for _, rec in ipairs(s.Recs) do
		if rec.Alive then
			n += 1
		end
	end
	return n
end

-- codebot_v142: the shared protection rule (spawn shield + novice shield): guards never target such a player
function CheckpointGuardService.Protected(p: Player): boolean
	local cs = deps.CombatService
	if cs == nil then
		return false
	end
	for _, fn in ipairs({ "IsSpawnInvulnerable", "IsNoviceShielded" }) do
		local f = cs[fn]
		if typeof(f) == "function" then
			local ok, v = pcall(f, p)
			if ok and v == true then
				return true
			end
		end
	end
	return false
end

local function spawnGroup(s: Site)
	local cs = deps.CombatService
	if cs == nil or cs.SpawnNPC == nil then
		return
	end
	for i, cf in ipairs(s.Posts) do
		local ok, rec = pcall(cs.SpawnNPC, G.NpcType, cf, {
			GroupId = "CP." .. s.Id,
			NoRespawn = true,
			Home = cf,
			Leash = G.SiteRadius + G.LeashExtra,
			Static = s.Static[i] == true,
			TargetFilter = function(p: Player): boolean
				return live(p.UserId) and not CheckpointGuardService.Protected(p)
			end,
		})
		if ok and rec then
			pcall(function()
				rec.Model:SetAttribute("WE_CheckpointGuard", s.Id)
			end)
			table.insert(s.Recs, rec)
		end
	end
	s.Awake = #s.Recs > 0
end

local function sleep(s: Site)
	local cs = deps.CombatService
	for _, rec in ipairs(s.Recs) do
		if rec.Alive and cs and cs.DespawnNPC then
			pcall(cs.DespawnNPC, rec.Id)
		end
	end
	table.clear(s.Recs)
	s.Awake = false
end

-- is any player standing on a post? (a respawn never lands on top of a player)
local function postsBlocked(s: Site, roots: { Vector3 }): boolean
	for _, cf in ipairs(s.Posts) do
		for _, r in ipairs(roots) do
			if (cf.Position - r).Magnitude <= G.SpawnClearStuds + 3 then
				return true
			end
		end
	end
	return false
end

-- one decision step for a site (tests call it with plain positions)
function CheckpointGuardService.Step(s: Site, liveRoots: { Vector3 }, allRoots: { Vector3 }, now: number): string
	local near = math.huge
	for _, r in ipairs(liveRoots) do
		near = math.min(near, flat(r, s.Center))
	end
	if s.Awake then
		if near > G.SleepStuds then
			sleep(s)
			return "sleep"
		end
		return "awake"
	end
	local ready = s.ClearedAt == nil or now - (s.ClearedAt :: number) >= G.RespawnSeconds
	if near <= G.WakeStuds and ready then
		if postsBlocked(s, allRoots) then
			return "blocked"
		end
		if s.ClearedAt ~= nil then
			s.Cycle += 1
			s.ClearedAt = nil
			table.clear(s.Contrib)
		end
		spawnGroup(s)
		return if s.Awake then "wake" else "nospawn"
	end
	return "asleep"
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function isPrivate(): boolean
	local ok, v = pcall(function()
		return (game :: any).PrivateServerOwnerId
	end)
	return ok and typeof(v) == "number" and v ~= 0
end

-- pay the cleared bonus to each live contributor (once per cycle, cooldown); returns the players paid
function CheckpointGuardService.PayCleared(s: Site, now: number): { Player }
	local paid: { Player } = {}
	for uid, at in pairs(s.Contrib) do
		local p = Players:GetPlayerByUserId(uid)
		if p and live(uid) and now - at <= G.AssistSeconds and s.PaidCycle[uid] ~= s.Cycle
			and (lastPaid[uid] == nil or now - lastPaid[uid] >= G.PlayerCooldownSeconds) then
			s.PaidCycle[uid] = s.Cycle
			lastPaid[uid] = now
			local perMin = 0
			local ms = deps.MonetizationService
			local profile = deps.DataService and deps.DataService.GetProfile(p)
			if ms and ms.PassivePerMin and profile then
				local ok, v = pcall(ms.PassivePerMin, p, profile)
				perMin = if ok and typeof(v) == "number" then v else 0
			end
			local cash = CheckpointGuardConfig.ClearedCash(perMin, isPrivate())
			local xp = if isPrivate() then math.floor(G.Cleared.XP * G.Cleared.PrivateMult) else G.Cleared.XP
			if deps.EconomyService then
				pcall(deps.EconomyService.AddCash, p, cash, "checkpoint")
			end
			if deps.XPService then
				pcall(deps.XPService.AddXP, p, xp, "checkpoint")
			end
			if deps.NotificationService then
				pcall(deps.NotificationService.Notify, p, string.format("Checkpoint cleared +$%s +%d XP", commas(cash), xp), "Reward", 5)
			end
			if deps.MissionService and deps.MissionService.TrackProgress then
				pcall(deps.MissionService.TrackProgress, p, "Checkpoint", 1)
			end
			if deps.AnalyticsService then
				pcall(deps.AnalyticsService.Log, "checkpoint_cleared", uid, { site = s.Id, cash = cash, xp = xp })
			end
			table.insert(paid, p)
		end
	end
	return paid
end

local function onDeath(info: any)
	local g = if typeof(info) == "table" then info.GroupId else nil
	if typeof(g) ~= "string" or string.sub(g, 1, 3) ~= "CP." then
		return
	end
	local s = sites[string.sub(g, 4)]
	if s == nil then
		return
	end
	local now = clock()
	local killer = info.Killer
	if typeof(killer) == "Instance" and killer:IsA("Player") then
		s.Contrib[killer.UserId] = now -- his own kill or his army's (ByUnit)
		pcall(function() -- claude-bud JOB 39: the Intel Office's "kill checkpoint guards" contract
			(require(script.Parent.EndgameService) :: any).NoteContract(killer, "CheckpointGuard", 1)
		end)
		if deps.AnalyticsService then
			pcall(deps.AnalyticsService.Log, "checkpoint_guard_kill", killer.UserId, { site = s.Id, byUnit = info.ByUnit == true })
		end
	end
	for _, rec in ipairs(s.Recs) do
		if rec.Id == info.Id and typeof(rec.LastHitBy) == "table" then
			for uid, at in pairs(rec.LastHitBy) do
				if typeof(uid) == "number" and typeof(at) == "number" then
					s.Contrib[uid] = math.max(s.Contrib[uid] or 0, at)
				end
			end
		end
	end
	local alive = 0
	for _, rec in ipairs(s.Recs) do
		if rec.Alive and rec.Id ~= info.Id then
			alive += 1
		end
	end
	if alive == 0 and s.Awake then
		s.Awake = false
		s.ClearedAt = now
		table.clear(s.Recs)
		CheckpointGuardService.PayCleared(s, now)
	end
end

-- the world map rows for this player (nil when not live): hostile while guards are up / ready, cleared + seconds left
function CheckpointGuardService.MapList(player: Player): { any }?
	if not live(player.UserId) then
		return nil
	end
	local out = {}
	local now = clock()
	for _, s in pairs(sites) do
		local left = if s.ClearedAt then math.max(0, math.ceil(G.RespawnSeconds - (now - (s.ClearedAt :: number)))) else 0
		table.insert(out, { X = math.floor(s.Center.X), Z = math.floor(s.Center.Z), Up = left <= 0, T = left })
	end
	return out
end

-- MissionService "Checkpoint" GO: every checkpoint whose guards are up or ready to wake
function CheckpointGuardService.GoTargets(): { { X: number, Y: number, Z: number } }
	local out = {}
	local now = clock()
	for _, s in pairs(sites) do
		if s.ClearedAt == nil or now - (s.ClearedAt :: number) >= G.RespawnSeconds then
			table.insert(out, { X = math.floor(s.Center.X * 10) / 10, Y = math.floor(s.Center.Y * 10) / 10, Z = math.floor(s.Center.Z * 10) / 10 })
		end
	end
	return out
end

-- test hooks
function CheckpointGuardService._Sites(): { [string]: Site }
	return sites
end
function CheckpointGuardService._SetClock(fn: () -> number)
	clock = fn
end
function CheckpointGuardService._OnDeath(info: any)
	onDeath(info)
end
function CheckpointGuardService._Reset()
	table.clear(sites)
	table.clear(lastPaid)
	table.clear(keptOut)
end
function CheckpointGuardService._SetKeepZones(z: { KeepZone })
	keepZones = z
end
function CheckpointGuardService._KeptOut(): { [string]: string }
	return keptOut
end

function CheckpointGuardService.Init(d: { [string]: any })
	deps = d
	if CheckpointGuardConfig.Live.Enabled ~= true then
		return
	end
	local cs = d.CombatService
	if cs and cs.OnNPCDeath then
		cs.OnNPCDeath(onDeath)
	end
	task.spawn(function()
		keepZones = CheckpointGuardService.BuildKeepZones()
		while true do
			task.wait(G.CheckSeconds)
			local ok, err = pcall(function()
				discover()
				local liveRoots, allRoots = {}, {}
				for _, p in ipairs(Players:GetPlayers()) do
					local r = rootOf(p)
					if r then
						table.insert(allRoots, r.Position)
						if live(p.UserId) then
							table.insert(liveRoots, r.Position)
						end
					end
				end
				local now = clock()
				for id, s in pairs(sites) do
					if s.Booth.Parent == nil then
						sleep(s)
						sites[id] = nil
					else
						if s.Awake and aliveCount(s) == 0 then
							s.Awake = false -- despawned elsewhere (no death event): wake again later
							table.clear(s.Recs)
						end
						CheckpointGuardService.Step(s, liveRoots, allRoots, now)
					end
				end
			end)
			if not ok then
				warn("[CheckpointGuardService] " .. tostring(err))
			end
		end
	end)
	print("[WAR EMPIRE] CheckpointGuardService Init")
end

return CheckpointGuardService
