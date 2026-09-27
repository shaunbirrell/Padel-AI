--!strict
--[[
	Empire Bank raid — stand on vault to loot Cash; per-player cooldown.
	Bank guards are living CombatService NPCs (MoveTo + shoot), not static MapSetup props.
	Pushes HoldProgress / UnderFire / InVault / Blocked to clients for BankRaidController HUD.

	v71 (task #20, bank retune): "under fire" = hit within BankRaidConfig.UnderFireSeconds (was: health below 95 %,
	which froze the hold forever for anyone the guards had ever scratched — no health regen reaches 95 % inside the
	respawn window). The vault label is one stud-scaled WorldLabel, never AlwaysOnTop, MaxDistance <= 40 (HUD v70
	spec §5).

	W3 step 2, lane F "bank findable" (spec w3s2 §6 Phase A; server decides everything, the client only draws):
	- Guards spawn on FIXED posts: the "Town.Bank" npc anchors G1..Gn (ActivityAnchors, stamped on BankPlaza by
	  MapSetup once lane BK lands), else BankRaidConfig.GuardPosts (P0 posts clear of today's building).
	- On foot only: a seated raider (Humanoid.SeatPart) gets Blocked = "Vehicle", no progress and no pay.
	- The cooldown lives on the profile (profile.Raid.BankCooldownUntil, os.time seconds): sanitised here on load
	  (junk → removed, longer than one cooldown → clamped), so it survives a rejoin. No ProfileSchema edit: Migrate
	  keeps unknown Raid keys. A player whose profile has not loaded yet cannot loot (GetProfile is nil).
	- Label: "Empire Bank" + "OPEN · rob the vault" / "RAID ON" (everyone; attribute WE_BankState = open / raid).
	  "CLOSED 4m" is drawn by BankRaidController on the cooling player's own client only.
	- The EMPIRE BANK sign is painted (WorldKits.Sign, inside the world sign budget) only when BankSign has none.
	- Reward toast "Bank job +$23,456" (commas), MissionService.TrackProgress(player, "Heist", 1), and a one-time
	  first-visit tip (profile.Raid.BankSeen) within BankRaidConfig.FirstVisitRadius.

	Owner phone test 2026-09-27 ("the bank guards respawn super fast, never a chance to rob"), BankRaidConfig.GuardRespawn:
	- The guards are spawned with SpawnNPC opts { NoRespawn = true } (their fight is unchanged: Aggressive, no leash, no
	  group), so CombatService no longer brings each one back 18 s after its own death. This service keeps one slot per
	  post and brings the dead ones back as a GROUP: DelaySeconds after the LAST bank-guard death (a payout brings it
	  forward to AfterRaidSeconds after it; each guard at most MaxDownSeconds after its own death), never while a vault
	  hold is running (at most RaidDeferMaxSeconds past due),
	  never sooner than CombatService's own respawn time after a guard's death (no faster kill farm), only on a post no
	  living player is near (ClearRadius) or can see (SightRadius, a ray from the eye), and ForceAfterSeconds past due
	  anyway (never within MinSpawnStuds of a player; an occupied post uses the nearest clear spot), so a camper or an
	  AFK farmer on the vault still meets the guards before the 5 min cooldown ends. The post test (a few raycasts per
	  dead guard and player) runs at most once per CheckSeconds, and only while guards are due.
	- GuardRespawn.Enabled = false: the old per-guard respawn exactly (2-argument SpawnNPC).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local BankRaidService = {}

local EconomyService: any = nil
local NotificationService: any = nil
local AnalyticsService: any = nil
local RemoteSetup: any = nil
local CombatService: any = nil
local DataService: any = nil
local MissionService: any = nil

local vaultPart: BasePart? = nil
local holdProgress: { [number]: number } = {}
-- only when no DataService is wired (headless drivers); live servers keep the cooldown on the profile
local sessionCooldown: { [number]: number } = {}
local inVaultNow: { [number]: boolean } = {}
local underFireNow: { [number]: boolean } = {}
local blockedNow: { [number]: string } = {}
local lastPushedProgress: { [number]: number } = {}
local firstVisitDone: { [number]: boolean } = {}
local guardsSpawned = false
local vaultLabel: BillboardGui? = nil
local lastRaiding: boolean? = nil
local signTried = false
-- under fire = a health drop seen within UnderFireSeconds (sampled on the 4 Hz tick; regen never counts)
local lastHealth: { [number]: number } = {}
local hurtAt: { [number]: number } = {}

-- guard roster (BankRaidConfig.GuardRespawn): one slot per post, os.clock() times
type GuardSlot = {
	Post: CFrame,
	Rec: any?, -- the living CombatService NPC record; nil = dead (DeadAt set) or never spawned (DeadAt nil: no delay)
	DeadAt: number?,
}
local slots: { GuardSlot } = {}
local lastGuardDeathAt: number? = nil -- every bank-guard death restarts the group clock
local lastRaidEndAt: number? = nil -- the latest payout
local nextRespawnCheckAt = 0
local sightParams: RaycastParams? = nil
local GUARD_OPTS = { NoRespawn = true } -- SpawnNPC copies its opts; today's fight otherwise (Aggressive, no leash / group)
local SIGHT_IGNORE_FOLDERS = { "WarEmpireNPCs", "WarEmpireSquads" }
local RING_STEPS = 8

local function groupRespawnOn(): boolean
	local gr = BankRaidConfig.GuardRespawn
	return gr ~= nil and gr.Enabled == true
end

local LABEL = BankRaidConfig.Label
local TEXT = BankRaidConfig.Text
local SIGN = BankRaidConfig.Sign

-- Server modules used lazily (a missing or broken module only means the fallback path)
local function serverModule(name: string): any
	local parent = script.Parent and script.Parent.Parent
	local modules = parent and parent:FindFirstChild("Modules")
	local m = modules and modules:FindFirstChild(name)
	if not (m and m:IsA("ModuleScript")) then
		return nil
	end
	local ok, mod = pcall(require, m)
	return if ok then mod else nil
end

local function formatCash(n: number): string
	local s = string.format("%d", math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function findVault(): BasePart?
	if vaultPart and vaultPart.Parent then
		return vaultPart
	end
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BankVault)) do
		if inst:IsA("BasePart") then
			vaultPart = inst
			return inst
		end
	end
	return nil
end

-- ── profile: Raid.BankCooldownUntil / Raid.BankSeen (no schema edit; Migrate keeps unknown Raid keys) ──────────
local function raidTable(profile: any): { [string]: any }?
	local raid = profile.Raid
	if typeof(raid) ~= "table" then
		return nil
	end
	return raid
end

local function profileOf(player: Player): any
	if DataService == nil then
		return nil
	end
	return DataService.GetProfile(player)
end

-- os.time() until which this player cannot loot; nil = profile not loaded yet (not eligible)
local function cooldownUntil(player: Player): number?
	if DataService == nil then
		return sessionCooldown[player.UserId] or 0
	end
	local profile = profileOf(player)
	if profile == nil then
		return nil
	end
	local raid = raidTable(profile)
	local v = raid and raid.BankCooldownUntil
	if typeof(v) ~= "number" or v ~= v then
		return 0
	end
	return v
end

local function setCooldown(player: Player, untilT: number)
	if DataService == nil then
		sessionCooldown[player.UserId] = untilT
		return
	end
	local profile = profileOf(player)
	if profile == nil then
		return
	end
	local raid = raidTable(profile)
	if raid == nil then
		-- same defaults as ProfileSchema / MoneyCollectorService.raidOf (Migrate always leaves a table here)
		local fresh: { [string]: any } = { ShieldUntil = 0, StrikeCooldownUntil = 0, DefensesDownUntil = 0 }
		profile.Raid = fresh
		raid = fresh
	end
	if raid ~= nil then
		raid.BankCooldownUntil = untilT
	end
	DataService.MarkDirty(player)
end

--[[ Local sanitiser for the saved cooldown (spec w3s2 §6 lane F): not a finite number or <= 0 → removed; longer
	than one cooldown from now (junk or a clock jump) → clamped to now + CooldownSeconds; whole seconds. Returns the
	clean value (nil when absent) and whether it changed. Pure: exported for the headless tests. ]]
function BankRaidService.SanitizeCooldown(value: any, nowUnix: number): (number?, boolean)
	if value == nil then
		return nil, false
	end
	if typeof(value) ~= "number" or value ~= value or value <= 0 then
		return nil, true
	end
	local cap = nowUnix + math.max(0, BankRaidConfig.CooldownSeconds or 300)
	local clean = math.floor(math.min(value, cap))
	return clean, clean ~= value
end

local function sanitizeProfile(player: Player, profile: any)
	local raid = raidTable(profile)
	if raid == nil then
		return
	end
	local changed = false
	local cd, cdChanged = BankRaidService.SanitizeCooldown(raid.BankCooldownUntil, os.time())
	if cdChanged then
		raid.BankCooldownUntil = cd
		changed = true
	end
	local seen = raid.BankSeen
	if seen ~= nil and typeof(seen) ~= "boolean" then
		raid.BankSeen = nil
		changed = true
	end
	if changed and DataService then
		DataService.MarkDirty(player)
	end
end

-- ── world: vault label, EMPIRE BANK sign ────────────────────────────────────────────────────────────────────
local function ensureVaultBillboard(vault: BasePart)
	local existing = vault:FindFirstChild(LABEL.Name)
	if existing and existing:IsA("BillboardGui") and existing:FindFirstChild("Title") then
		vaultLabel = existing
		return
	end
	if existing then
		existing:Destroy()
	end
	-- spec §5 "Bank vault labels ×2 → keep only BankRaidService's": MapSetup's "EMPIRE BANK · Stand to RAID cash"
	-- card ("Label") sits on the same vault at the same height, so the two drew on top of each other. Its how-to
	-- line now lives in this label's state line ("OPEN · rob the vault").
	local legacy = vault:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") then
		legacy:Destroy()
	end
	-- stud-scaled, plain outlined text, MaxDistance <= 40, never through walls (spec §5 "Bank vault labels")
	local bb = WorldLabel.Create(vault, LABEL.Title, {
		Name = LABEL.Name,
		Color = LABEL.Color,
		Sub = LABEL.OpenSub,
		SubColor = LABEL.OpenColor,
		Offset = Vector3.new(0, LABEL.HeightStuds, 0),
		MaxDistance = LABEL.MaxDistance,
	})
	bb:SetAttribute(LABEL.StateAttribute, "open")
	vaultLabel = bb
	lastRaiding = false
end

local FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}

-- the face of `part` whose world normal points most along `dir` (the street side of the sign)
local function faceToward(part: BasePart, dir: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, face in ipairs(FACES) do
		local n = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
		local d = n:Dot(dir)
		if d > bestDot then
			best, bestDot = face, d
		end
	end
	return best
end

-- the bank's own folder (MapSetup's "EmpireBank" = BankId), however deep the vault sits in it
local function bankFolderOf(vault: BasePart): Instance?
	local cur = vault.Parent
	while cur ~= nil and not cur:IsA("Workspace") do
		if cur.Name == BankRaidConfig.BankId then
			return cur
		end
		cur = cur.Parent
	end
	local parent = vault.Parent
	return if parent ~= nil and not parent:IsA("Workspace") then parent else nil -- never search all of Workspace
end

-- EMPIRE BANK on the bank's sign part, only when it has no SurfaceGui yet (idempotent once lane BK paints it)
local function ensureBankSign(vault: BasePart)
	if signTried then
		return
	end
	local folder = bankFolderOf(vault)
	-- a 17-part folder; searched at most a few times (Init, the 4 Hz tick until the 2 s deferred pass)
	local sign = folder and folder:FindFirstChild(SIGN.PartName, true)
	if not (sign and sign:IsA("BasePart")) then
		return -- not built yet (retried on the next tick); nothing to paint on
	end
	signTried = true
	if sign:FindFirstChildWhichIsA("SurfaceGui") then
		return
	end
	local WorldKits = serverModule("WorldKits")
	if WorldKits == nil or WorldKits.Sign == nil then
		warn("[WAR EMPIRE] BankRaidService: WorldKits.Sign missing; EMPIRE BANK sign not painted")
		return
	end
	local ok, gui = pcall(WorldKits.Sign, sign, faceToward(sign, SIGN.Facing), SIGN.Text)
	if not ok or gui == nil then
		warn("[WAR EMPIRE] BankRaidService: EMPIRE BANK sign not painted (" .. tostring(if ok then "world sign budget" else gui) .. ")")
	end
end

local function refreshBillboardHint()
	local bb = vaultLabel
	if not bb or not bb.Parent then
		return
	end
	-- One public line; the per-player hold / cooldown stays on the raider's HUD (BankRaidController), and the
	-- "CLOSED 4m" line is drawn by that player's own client over this one.
	local anyRaiding = false
	for uid, inv in pairs(inVaultNow) do
		if inv and (holdProgress[uid] or 0) > 0 then
			anyRaiding = true
			break
		end
	end
	if anyRaiding == lastRaiding then
		return
	end
	lastRaiding = anyRaiding
	-- attribute first: a client drawing its own CLOSED line reads the public state back from it
	bb:SetAttribute(LABEL.StateAttribute, if anyRaiding then "raid" else "open")
	WorldLabel.SetText(
		bb,
		LABEL.Title,
		if anyRaiding then LABEL.RaidingSub else LABEL.OpenSub,
		if anyRaiding then LABEL.RaidingColor else LABEL.OpenColor
	)
end

-- ── guards on fixed posts ───────────────────────────────────────────────────────────────────────────────────
--[[ Root CFrames for the bank guards: the "Town.Bank" npc anchors whose role is G<n> (sorted by id), else the
	BankRaidConfig.GuardPosts fallback (at most GuardCount). Pure apart from the anchor read: exported for tests. ]]
function BankRaidService.GuardPosts(): ({ CFrame }, string)
	local lift = BankRaidConfig.GuardRootLift or 3
	local out: { CFrame } = {}
	local ActivityAnchors = serverModule("ActivityAnchors")
	if ActivityAnchors and ActivityAnchors.List then
		local ok, list = pcall(ActivityAnchors.List, BankRaidConfig.AnchorSite, "npc")
		if ok and typeof(list) == "table" then
			for _, a in ipairs(list) do
				if typeof(a.Role) == "string" and string.match(a.Role, BankRaidConfig.GuardRolePattern) and typeof(a.CFrame) == "CFrame" then
					table.insert(out, a.CFrame + Vector3.new(0, lift, 0))
				end
			end
		end
	end
	if #out > 0 then
		return out, "anchors"
	end
	local limit = BankRaidConfig.GuardCount or #BankRaidConfig.GuardPosts
	for i, p in ipairs(BankRaidConfig.GuardPosts) do
		if i > limit then
			break
		end
		local cf = CFrame.new(p.X, p.Y + lift, p.Z) * CFrame.Angles(0, math.rad(p.Yaw or 180), 0)
		table.insert(out, cf)
	end
	return out, "config"
end

local function spawnBankGuards()
	if guardsSpawned then
		return
	end
	if not CombatService or not CombatService.SpawnNPC then
		warn("[WAR EMPIRE] BankRaidService: CombatService.SpawnNPC missing")
		return
	end
	guardsSpawned = true

	local posts, source = BankRaidService.GuardPosts()
	local typeId = BankRaidConfig.GuardNPCType or "BankGuard"
	local group = groupRespawnOn()
	local spawned = 0
	for _, cf in ipairs(posts) do
		-- group respawn: this service brings the guard back (NoRespawn); off: CombatService's own per-guard respawn
		local rec = if group then CombatService.SpawnNPC(typeId, cf, GUARD_OPTS) else CombatService.SpawnNPC(typeId, cf)
		if group then
			table.insert(slots, { Post = cf, Rec = rec, DeadAt = nil })
			if rec then
				rec.Model:SetAttribute("WE_BankPost", #slots) -- which post (tests / the Studio explorer)
			end
		end
		if rec then
			spawned += 1
		end
	end
	print(string.format("[WAR EMPIRE] BankRaidService: spawned %d %s combat NPCs at bank (%d fixed posts from %s; %s)", spawned, typeId, #posts, source,
		if group then "group respawn" else "per-guard respawn"))
	if spawned == 0 then
		warn("[WAR EMPIRE] BankRaidService: ZERO BankGuards — will retry once in 3s")
		guardsSpawned = false
		table.clear(slots)
		task.delay(3, function()
			if not guardsSpawned then
				spawnBankGuards()
			end
		end)
	end
end

-- ── group respawn (BankRaidConfig.GuardRespawn) ────────────────────────────────────────────────────────────
-- CombatService's own respawn time for the guard type (NPCTypes[type].RespawnSeconds, else NPCRespawnSeconds): the
-- floor, so no guard is ever back sooner after its own death than before the group respawn (no faster kill farm)
local function guardFloorSeconds(): number
	local def: any = CombatConfig.NPCTypes[BankRaidConfig.GuardNPCType or "BankGuard"]
	local t = if def then tonumber(def.RespawnSeconds) else nil
	if t and t > 0 then
		return t
	end
	return tonumber(CombatConfig.NPCRespawnSeconds) or 18
end

--[[ os.clock() when the dead guards are due back as a group: the last bank-guard death + DelaySeconds, or a later
	payout + AfterRaidSeconds if that is sooner (each guard: at most MaxDownSeconds after its own death, see
	slotDueAt). nil while no guard has died (or the group respawn is off). For tests too. ]]
function BankRaidService.GuardsDueAt(): number?
	local last = lastGuardDeathAt
	local gr = BankRaidConfig.GuardRespawn
	if last == nil or gr == nil then
		return nil
	end
	local due = last + gr.DelaySeconds
	local raidEnd = lastRaidEndAt
	if raidEnd ~= nil and raidEnd >= last then
		due = math.min(due, raidEnd + gr.AfterRaidSeconds)
	end
	return due
end

-- the roster for tests / the Studio console: per post, alive or when its death was seen (os.clock())
function BankRaidService.GuardRoster(): { { Post: CFrame, Alive: boolean, DeadAt: number? } }
	local out = {}
	for _, slot in ipairs(slots) do
		table.insert(out, { Post = slot.Post, Alive = slot.Rec ~= nil, DeadAt = slot.DeadAt })
	end
	return out
end

type Viewer = { Root: Vector3, Eye: Vector3 }

-- living players (root, eye) + what a sight ray ignores: every character, a seated player's vehicle, NPCs, squads
local function livingViewers(): ({ Viewer }, { Instance })
	local list: { Viewer } = {}
	local ignore: { Instance } = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if char then
			table.insert(ignore, char)
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 then
				table.insert(list, { Root = hrp.Position, Eye = hrp.Position + Vector3.new(0, 1.5, 0) })
				local seat = hum.SeatPart
				local vehicle = if seat then seat:FindFirstAncestorOfClass("Model") else nil
				if vehicle and vehicle ~= char then
					table.insert(ignore, vehicle)
				end
			end
		end
	end
	for _, name in ipairs(SIGHT_IGNORE_FOLDERS) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	return list, ignore
end

local function clearRay(from: Vector3, to: Vector3, params: RaycastParams): boolean
	local d = to - from
	if d.Magnitude < 1e-3 then
		return true
	end
	return Workspace:Raycast(from, d, params) == nil
end

-- no living player within ClearRadius of the post, and none within SightRadius who can see its torso or head
local function postIsFree(p: Vector3, viewers: { Viewer }, params: RaycastParams): boolean
	local gr = BankRaidConfig.GuardRespawn
	local head = p + Vector3.new(0, 1.5, 0)
	for _, v in ipairs(viewers) do
		local d = (v.Root - p).Magnitude
		if d < gr.ClearRadius then
			return false
		end
		if d <= gr.SightRadius and (clearRay(v.Eye, p, params) or clearRay(v.Eye, head, params)) then
			return false
		end
	end
	return true
end

local function farFromAll(p: Vector3, viewers: { Viewer }, minD: number): boolean
	for _, v in ipairs(viewers) do
		if (v.Root - p).Magnitude < minD then
			return false
		end
	end
	return true
end

--[[ A forced spawn for a post a player stands on: the nearest spot MinSpawnStuds .. MinSpawnStuds + 6 from the post
	that is MinSpawnStuds from every player, reachable in a straight line from the post (nothing collidable at knee or
	chest height: the same room, never inside a wall) and has a floor under it. nil = none (tried again next check). ]]
local function displacedSpot(post: CFrame, viewers: { Viewer }, params: RaycastParams): CFrame?
	local gr = BankRaidConfig.GuardRespawn
	local p = post.Position
	local lift = BankRaidConfig.GuardRootLift or 3
	local knee, chest = Vector3.new(0, -1.2, 0), Vector3.new(0, 0.5, 0)
	for r = gr.MinSpawnStuds, gr.MinSpawnStuds + 6, 3 do
		for i = 0, RING_STEPS - 1 do
			local a = i * (2 * math.pi / RING_STEPS)
			local q = p + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if farFromAll(q, viewers, gr.MinSpawnStuds) and clearRay(p + knee, q + knee, params) and clearRay(p + chest, q + chest, params) then
				local floor = Workspace:Raycast(q, Vector3.new(0, -(lift + 2), 0), params)
				if floor then
					return CFrame.new(floor.Position + Vector3.new(0, lift, 0)) * (post - post.Position)
				end
			end
		end
	end
	return nil
end

-- someone's vault hold is running (the previous tick's state)
local function raidRunning(): boolean
	for uid, prog in pairs(holdProgress) do
		if prog > 0 and inVaultNow[uid] == true then
			return true
		end
	end
	return false
end

--[[ The 4 Hz step: note the deaths, then (at most once per CheckSeconds, only while guards are due) bring back the
	dead guards whose post is free, or any blocked one ForceAfterSeconds past due. ]]
local function stepGuards(nowC: number)
	if #slots == 0 or not groupRespawnOn() then
		return
	end
	local anyDown = false
	for _, slot in ipairs(slots) do
		local rec = slot.Rec
		if rec ~= nil and not (rec.Alive == true and rec.Humanoid.Health > 0 and rec.Model.Parent ~= nil) then
			slot.Rec = nil
			slot.DeadAt = nowC
			lastGuardDeathAt = nowC
		end
		if slot.Rec == nil then
			anyDown = true
		end
	end
	if not anyDown or nowC < nextRespawnCheckAt then
		return
	end
	local gr = BankRaidConfig.GuardRespawn
	nextRespawnCheckAt = nowC + gr.CheckSeconds
	local due = BankRaidService.GuardsDueAt() or -math.huge
	local floorS = guardFloorSeconds()
	local robbing = raidRunning()
	local vs: { Viewer } = {}
	local prepared = false -- the players and the ray filter, read once per check and only when a guard is due
	local params = sightParams or RaycastParams.new()
	sightParams = params
	local typeId = BankRaidConfig.GuardNPCType or "BankGuard"
	for i, slot in ipairs(slots) do
		local deadAt = slot.DeadAt
		-- the group due, capped at MaxDownSeconds after this guard's own death, never before the CombatService floor
		local slotDue = if deadAt then math.max(math.min(due, deadAt + gr.MaxDownSeconds), deadAt + floorS) else due
		-- a robbery in progress: nobody walks in on it (at most RaidDeferMaxSeconds past due)
		if slot.Rec == nil and nowC >= slotDue and not (robbing and nowC < slotDue + gr.RaidDeferMaxSeconds) then
			if not prepared then
				prepared = true
				local ignore: { Instance }
				vs, ignore = livingViewers()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = ignore
				params.IgnoreWater = true
				params.RespectCanCollide = true
			end
			local cf: CFrame? = nil
			if postIsFree(slot.Post.Position, vs, params) then
				cf = slot.Post
			elseif nowC >= slotDue + gr.ForceAfterSeconds then
				cf = if farFromAll(slot.Post.Position, vs, gr.MinSpawnStuds) then slot.Post else displacedSpot(slot.Post, vs, params)
			end
			if cf then
				local rec = CombatService.SpawnNPC(typeId, cf, GUARD_OPTS)
				if rec then -- nil: the NPC cap is full; tried again next check
					slot.Rec = rec
					slot.DeadAt = nil
					rec.Model:SetAttribute("WE_BankPost", i)
				end
			end
		end
	end
end

-- ── HUD payload ────────────────────────────────────────────────────────────────────────────────────────────
local function pushState(player: Player, opts: { InVault: boolean?, UnderFire: boolean? }?)
	if not RemoteSetup then
		return
	end
	local now = os.time()
	local untilT = cooldownUntil(player) or 0
	local remaining = math.max(0, untilT - now)
	local need = BankRaidConfig.RaidHoldSeconds or 8
	local prog = holdProgress[player.UserId] or 0
	local inVault = if opts and opts.InVault ~= nil then opts.InVault else (inVaultNow[player.UserId] == true)
	local underFire = if opts and opts.UnderFire ~= nil then opts.UnderFire else (underFireNow[player.UserId] == true)
	local remote = RemoteSetup.Get(Constants.RemoteNames.BankRaidStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		BankId = BankRaidConfig.BankId,
		DisplayName = BankRaidConfig.DisplayName,
		Enabled = BankRaidConfig.Enabled == true,
		CooldownRemaining = remaining,
		RaidHoldSeconds = need,
		HoldNeed = need,
		HoldProgress = prog,
		InVault = inVault,
		UnderFire = underFire,
		Blocked = if inVault then blockedNow[player.UserId] else nil,
		CashHintMin = BankRaidConfig.CashMin,
		CashHintMax = BankRaidConfig.CashMax,
	})
	lastPushedProgress[player.UserId] = prog
end

local function completeRaid(player: Player)
	local cashMin = BankRaidConfig.CashMin or 15000
	local cashMax = BankRaidConfig.CashMax or 35000
	local cash = math.random(cashMin, cashMax)
	holdProgress[player.UserId] = nil
	inVaultNow[player.UserId] = false
	underFireNow[player.UserId] = false
	blockedNow[player.UserId] = nil
	-- "bank_raid" is exempt from the cash multipliers (MonetizationConfig.CashMultExemptReasons): the toast is exact
	if EconomyService.AddCash(player, cash, "bank_raid") ~= true then
		pushState(player, { InVault = false, UnderFire = false })
		return -- no profile: nothing paid, so no cooldown either
	end
	lastRaidEndAt = os.clock() -- GuardRespawn.AfterRaidSeconds: the bank refills after a payout
	local cd = BankRaidConfig.CooldownSeconds or 300
	setCooldown(player, os.time() + cd)
	if BankRaidConfig.NotifyOnRaid and NotificationService then
		NotificationService.Notify(player, string.format(TEXT.Reward, formatCash(cash)), "Reward")
	end
	if MissionService and MissionService.TrackProgress then
		local ok, err = pcall(MissionService.TrackProgress, player, "Heist", 1)
		if not ok then
			warn("[WAR EMPIRE] BankRaidService: TrackProgress Heist failed: " .. tostring(err))
		end
	end
	if AnalyticsService then
		local ev = (AnalyticsConfig.Events and AnalyticsConfig.Events.BANK_RAID) or "BANK_RAID"
		AnalyticsService.Log(ev, player.UserId, { cash = cash })
	end
	pushState(player, { InVault = false, UnderFire = false })
end

-- health drops since the last tick → "hit just now" (a respawn or regen raises health and never counts)
local function sampleHurt(uid: number, hum: Humanoid, nowC: number)
	local hp = hum.Health
	local prev = lastHealth[uid]
	if prev ~= nil and hp < prev - 0.01 then
		hurtAt[uid] = nowC
	end
	lastHealth[uid] = hp
end

local function isUnderFire(player: Player, nowC: number): boolean
	local char = player.Character
	if not char then
		return true
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return true
	end
	return nowC - (hurtAt[player.UserId] or -math.huge) < (BankRaidConfig.UnderFireSeconds or 2)
end

-- one-time tip the first time this player comes near the bank (saved; never while being shot at)
local function maybeFirstVisit(player: Player, rootPos: Vector3, nowC: number)
	local uid = player.UserId
	if firstVisitDone[uid] or not NotificationService then
		return
	end
	local center = BankRaidConfig.Position
	local dx, dz = rootPos.X - center.X, rootPos.Z - center.Z
	local r = BankRaidConfig.FirstVisitRadius or 150
	if dx * dx + dz * dz > r * r then
		return
	end
	local profile = profileOf(player)
	if DataService ~= nil and profile == nil then
		return -- not loaded yet: ask again on a later tick
	end
	local raid = if profile ~= nil then raidTable(profile) else nil
	if raid ~= nil and raid.BankSeen == true then
		firstVisitDone[uid] = true
		return
	end
	if nowC - (hurtAt[uid] or -math.huge) < (BankRaidConfig.FirstVisitSkipIfHitSeconds or 5) then
		return
	end
	firstVisitDone[uid] = true
	if raid ~= nil then
		raid.BankSeen = true
		DataService.MarkDirty(player)
	end
	NotificationService.Notify(player, TEXT.FirstVisit, "Info")
end

function BankRaidService.Push(player: Player)
	pushState(player)
end

function BankRaidService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	AnalyticsService = deps.AnalyticsService
	RemoteSetup = deps.RemoteSetup
	CombatService = deps.CombatService
	DataService = deps.DataService
	MissionService = deps.MissionService

	if not BankRaidConfig.Enabled then
		return
	end

	-- the sign first, while the world sign budget still has the bank's slot (MapDressing paints the POI boards a
	-- frame later); retried from the tick if the bank is not built yet
	do
		local vault = findVault()
		if vault then
			ensureBankSign(vault)
		end
	end

	task.defer(function()
		task.wait(2)
		local vault = findVault()
		if vault then
			ensureVaultBillboard(vault)
			ensureBankSign(vault)
			signTried = true -- one more try at most: a bank without a BankSign part has nothing to paint
		end
		spawnBankGuards()
	end)

	if DataService and DataService.OnProfileLoaded then
		-- the saved cooldown reaches the HUD (and the client's CLOSED line) as soon as the save is in
		DataService.OnProfileLoaded(function(player: Player, profile: any)
			sanitizeProfile(player, profile)
			if player.Parent then
				pushState(player)
			end
		end)
	end

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.25 then
			return
		end
		local step = accum
		accum = 0
		stepGuards(os.clock()) -- before the vault lookup: the guards come back even if the vault is missing

		local vault = findVault()
		if not vault then
			return
		end
		if not (vaultLabel and vaultLabel.Parent) then
			ensureVaultBillboard(vault)
		end
		if not signTried then
			ensureBankSign(vault)
		end
		local radius = BankRaidConfig.VaultRadius or 12
		local need = BankRaidConfig.RaidHoldSeconds or 8
		local nowUnix = os.time()
		local nowC = os.clock()
		local pos = vault.Position
		local nearby: { [number]: boolean } = {}
		local toPush: { Player } = {}

		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local untilT = cooldownUntil(player) -- nil: profile not loaded → not eligible (treated as away)
			local onCooldown = untilT ~= nil and untilT > nowUnix
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local inside = false
			local fired = false

			if hum then
				sampleHurt(uid, hum, nowC)
			end
			if hrp and hum and hum.Health > 0 then
				inside = untilT ~= nil and (hrp.Position - pos).Magnitude <= radius
				maybeFirstVisit(player, hrp.Position, nowC)
			end

			if inside and not onCooldown and hum and hum.SeatPart ~= nil then
				-- on foot only: a vehicle parked on the vault never loots (progress frozen, "LEAVE VEHICLE")
				nearby[uid] = true
				inVaultNow[uid] = true
				underFireNow[uid] = false
				blockedNow[uid] = "Vehicle"
				table.insert(toPush, player)
			elseif inside and not onCooldown then
				nearby[uid] = true
				blockedNow[uid] = nil
				fired = isUnderFire(player, nowC)
				underFireNow[uid] = fired
				inVaultNow[uid] = true
				if not fired then
					local prog = (holdProgress[uid] or 0) + step
					holdProgress[uid] = prog
					if prog >= need then
						completeRaid(player)
						-- completeRaid already pushed
					else
						table.insert(toPush, player)
					end
				else
					-- Under fire: progress frozen but HUD must show the block
					table.insert(toPush, player)
				end
			elseif inside and onCooldown then
				-- Standing on vault while cooling down — still show cooldown HUD
				inVaultNow[uid] = true
				underFireNow[uid] = false
				blockedNow[uid] = nil
				nearby[uid] = true
				table.insert(toPush, player)
			else
				local wasIn = inVaultNow[uid] == true
				local hadProg = (holdProgress[uid] or 0) > 0
				blockedNow[uid] = nil
				if wasIn or hadProg then
					-- Left vault / progress reset — push once so client hides bar
					inVaultNow[uid] = false
					underFireNow[uid] = false
					holdProgress[uid] = nil
					table.insert(toPush, player)
				else
					inVaultNow[uid] = false
					underFireNow[uid] = false
				end
			end
		end

		for uid in pairs(holdProgress) do
			if not nearby[uid] then
				holdProgress[uid] = nil
			end
		end

		for _, player in ipairs(toPush) do
			pushState(player)
		end

		refreshBillboardHint()
	end)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			pushState(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		holdProgress[uid] = nil
		inVaultNow[uid] = nil
		underFireNow[uid] = nil
		blockedNow[uid] = nil
		lastPushedProgress[uid] = nil
		lastHealth[uid] = nil
		hurtAt[uid] = nil
		firstVisitDone[uid] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			pushState(player)
		end)
	end

	print("[WAR EMPIRE] BankRaidService ready (fixed-post BankGuards, on-foot hold, saved cooldown)")
end

return BankRaidService
