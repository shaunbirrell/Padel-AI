--!strict
--[[
	Periodic Supply Drops — crates spawn on map; stand near to claim Cash.

	v71 (HUD v70 spec §5, roadmap §1.6): the crate stands ON THE GROUND under its anchor (a downward ray from the
	WE_EventSpawn anchor or scatter point; anchors may be invisible and float), and its label is one stud-scaled
	WorldLabel "Supply Drop" / "$8,500" (MaxDistance <= 40, never AlwaysOnTop).

	W3 step 2, lane F (spec w3s2 §3): a crate is exactly 2 parts (the crate + its lid). The glowing ring, the beacon
	ball, both straps and the catalog crate overlay (a model of unknown part count) are gone, and SupplyDropConfig
	caps it at MaxActive 2 / LifetimeSeconds 120, so the busiest 512-stud circle stays <= 500 with the bank's
	transients. Nothing here is Neon. The reward toast formats the cash with commas.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local SupplyDropConfig = require(Shared.Configs.SupplyDropConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local WorldLabel = require(Shared.Util.WorldLabel)
local Remotes = require(Shared.Remotes) -- claude-bud JOB 4.1: FeaturePush (airdrop marker)
local TweenService = game:GetService("TweenService")

local SupplyDropService = {}

local EconomyService: any = nil
local NotificationService: any = nil
local AnalyticsService: any = nil

type DropRec = {
	Id: string,
	Part: BasePart,
	ClaimCash: number,
	ExpiresAt: number,
	ClaimProgress: { [number]: number }, -- userId -> hold seconds
	Airdrop: boolean?, -- claude-bud JOB 4.1: a parachute airdrop (claimable only by players it is live for)
	Landed: boolean?, -- airdrop: false while it falls (no claims)
}

local active: { [string]: DropRec } = {}
local folder: Folder? = nil
local nextId = 0

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local root = Workspace:FindFirstChild("WarEmpireSetup")
	local parent = if root then root else Workspace
	local existing = parent:FindFirstChild("SupplyDrops")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "SupplyDrops"
	f.Parent = parent
	folder = f
	return f
end

local function formatCash(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Ground under `pos`: a downward ray that skips the anchor itself, the crates, characters and non-collidable
-- decor. nil when nothing solid is below within `depth` studs.
local function groundBelow(pos: Vector3, ignore: { Instance }, depth: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	table.insert(list, ensureFolder())
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(pos, Vector3.new(0, -depth, 0), params)
	return if hit then hit.Position.Y else nil
end

-- Where the crate's BOTTOM goes: the ground under an event anchor (or a scatter point), not the anchor's centre.
local function pickSpawnPosition(): Vector3
	local pads = CollectionService:GetTagged(Constants.Tags.EventSpawn)
	local candidates: { Vector3 } = {}
	for _, inst in ipairs(pads) do
		if inst:IsA("BasePart") then
			local top = inst.Position + Vector3.new(0, inst.Size.Y * 0.5, 0)
			-- a visible solid pad IS the ground (the ray lands on its top); an invisible anchor is skipped, and a
			-- non-collidable one is skipped by RespectCanCollide
			local ignore: { Instance } = if inst.Transparency >= 0.99 then { inst } else {}
			local gy = groundBelow(top + Vector3.new(0, 1, 0), ignore, 80)
			table.insert(candidates, Vector3.new(top.X, gy or top.Y, top.Z))
		end
	end
	-- Avoid stacking on occupied pads
	local free: { Vector3 } = {}
	for _, pos in ipairs(candidates) do
		local blocked = false
		for _, rec in pairs(active) do
			if (rec.Part.Position - pos).Magnitude < 25 then
				blocked = true
				break
			end
		end
		if not blocked then
			table.insert(free, pos)
		end
	end
	if #free > 0 then
		return free[math.random(1, #free)]
	end
	-- Scatter fallback on open ground
	local r = SupplyDropConfig.ScatterRadius or 900
	local minR = SupplyDropConfig.ScatterMinDistanceFromOrigin or 120
	for _ = 1, 12 do
		local angle = math.random() * math.pi * 2
		local dist = minR + math.random() * (r - minR)
		local pos = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local ok = true
		for _, rec in pairs(active) do
			if (rec.Part.Position - pos).Magnitude < 40 then
				ok = false
				break
			end
		end
		if ok then
			local gy = groundBelow(pos + Vector3.new(0, 60, 0), {}, 200)
			return Vector3.new(pos.X, gy or 1, pos.Z)
		end
	end
	return Vector3.new(150, 1, 150)
end

-- claude-bud JOB 4.1: the airdrop marker, only to players the airdrop is live for
local function pushAirdrop(data: { [string]: any })
	local ev = Remotes.TryGetEvent(Constants.RemoteNames.FeaturePush)
	if ev == nil then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if SupplyDropConfig.AirdropLiveFor(p.UserId) then
			ev:FireClient(p, "Airdrop", data)
		end
	end
end

local function destroyDrop(id: string)
	local rec = active[id]
	if not rec then
		return
	end
	active[id] = nil
	if rec.Airdrop then
		pushAirdrop({ Show = false })
	end
	if rec.Part and rec.Part.Parent then
		rec.Part:Destroy()
	end
end

local function spawnDrop()
	if not SupplyDropConfig.Enabled then
		return
	end
	local count = 0
	for _, r in pairs(active) do
		if not r.Airdrop then -- claude-bud: the airdrop never takes a crate slot
			count += 1
		end
	end
	if count >= (SupplyDropConfig.MaxActive or 2) then
		return
	end

	nextId += 1
	local id = "drop_" .. tostring(nextId)
	local ground = pickSpawnPosition()
	local cashMin = SupplyDropConfig.CashMin or 2500
	local cashMax = SupplyDropConfig.CashMax or 12000
	local cash = math.random(cashMin, cashMax)

	local parent = ensureFolder()
	local crate = Instance.new("Part")
	crate.Name = "SupplyCrate_" .. id
	crate.Size = SupplyDropConfig.CrateSize or Vector3.new(5, 4, 5)
	crate.Position = ground + Vector3.new(0, crate.Size.Y * 0.5, 0) -- bottom face on the ground
	crate.Anchored = true
	crate.CanCollide = true
	crate.Color = SupplyDropConfig.CrateColor or Color3.fromRGB(210, 160, 55)
	crate.Material = Enum.Material.Metal
	crate.TopSurface = Enum.SurfaceType.Smooth
	crate.BottomSurface = Enum.SurfaceType.Smooth
	crate.Parent = parent
	crate:SetAttribute("SupplyDropId", id)
	crate:SetAttribute("ClaimCash", cash)
	CollectionService:AddTag(crate, Constants.Tags.SupplyDrop)

	-- The one decor part: a darker lid (2 parts per crate; no ring, beacon, straps or catalog overlay: spec w3s2 §3)
	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(crate.Size.X * 0.92, 0.4, crate.Size.Z * 0.92)
	lid.Anchored = true
	lid.CanCollide = false
	lid.CanQuery = false
	lid.CanTouch = false
	lid.CastShadow = false
	lid.Material = Enum.Material.Metal
	lid.Color = SupplyDropConfig.LidColor or Color3.fromRGB(180, 140, 50)
	lid.TopSurface = Enum.SurfaceType.Smooth
	lid.BottomSurface = Enum.SurfaceType.Smooth
	lid.CFrame = crate.CFrame * CFrame.new(0, crate.Size.Y * 0.5 + 0.1, 0)
	lid.Parent = crate

	local bb = WorldLabel.Create(crate, "Supply Drop", {
		Name = "Label",
		Sub = "$" .. formatCash(cash),
		Color = Color3.fromRGB(255, 220, 120),
		SubColor = Color3.fromRGB(110, 255, 90),
		Offset = Vector3.new(0, crate.Size.Y * 0.5 + (SupplyDropConfig.LabelLiftStuds or 3), 0), -- above the lid
		MaxDistance = 40,
	})
	-- v31: never AlwaysOnTop — was covering structure name billboards on approach
	bb.AlwaysOnTop = false

	local ttl = SupplyDropConfig.LifetimeSeconds or 120

	active[id] = {
		Id = id,
		Part = crate,
		ClaimCash = cash,
		ExpiresAt = os.clock() + ttl,
		ClaimProgress = {},
	}
end

local function claim(player: Player, rec: DropRec)
	destroyDrop(rec.Id)
	EconomyService.AddCash(player, rec.ClaimCash, "supply_drop")
	if NotificationService then
		if rec.Airdrop then
			NotificationService.Notify(player, "Airdrop +$" .. formatCash(rec.ClaimCash), "Reward") -- claude-bud JOB 4.1
		else
			NotificationService.Notify(player, "Supply drop +$" .. formatCash(rec.ClaimCash), "Reward")
		end
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.SUPPLY_DROP_CLAIM, player.UserId, {
			cash = rec.ClaimCash,
			dropId = rec.Id,
		})
	end
end

local function tickClaims(dt: number)
	local radius = SupplyDropConfig.ClaimRadius or 10
	local holdNeed = SupplyDropConfig.ClaimHoldSeconds or 2.5
	local now = os.clock()

	-- Expire
	local expired: { string } = {}
	for id, rec in pairs(active) do
		if now >= rec.ExpiresAt or not rec.Part.Parent then
			table.insert(expired, id)
		end
	end
	for _, id in ipairs(expired) do
		destroyDrop(id)
	end

	for _, rec in pairs(active) do
		local pos = rec.Part.Position
		local nearby: { [number]: boolean } = {}
		local airdrop = rec.Airdrop == true
		if airdrop and rec.Landed ~= true then
			continue -- claude-bud: no claims while it falls
		end
		local r2 = if airdrop then (SupplyDropConfig.Airdrop.ClaimRadius or radius) else radius
		local hold2 = if airdrop then (SupplyDropConfig.Airdrop.ClaimHoldSeconds or holdNeed) else holdNeed
		for _, player in ipairs(Players:GetPlayers()) do
			if airdrop and not SupplyDropConfig.AirdropLiveFor(player.UserId) then
				continue -- claude-bud: an owner-only airdrop is claimable only by players it is live for
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (hrp.Position - pos).Magnitude
				if d <= r2 then
					nearby[player.UserId] = true
					local prog = (rec.ClaimProgress[player.UserId] or 0) + dt
					rec.ClaimProgress[player.UserId] = prog
					if prog >= hold2 then
						claim(player, rec)
						break
					end
				end
			end
		end
		-- Decay progress for leavers
		for uid in pairs(rec.ClaimProgress) do
			if not nearby[uid] then
				rec.ClaimProgress[uid] = nil
			end
		end
	end
end

--[[ claude-bud JOB 4.1: one parachute airdrop (SupplyDropConfig.Airdrop). Server-built, 3 parts while it falls: the
	anchored crate is tweened down; the lid and canopy are welded to it (unanchored) and follow. The canopy goes on
	landing. Returns false when one is already active or nobody it is live for is here. ]]
local function spawnAirdrop(): boolean
	local A = SupplyDropConfig.Airdrop
	for _, r in pairs(active) do
		if r.Airdrop then
			return false
		end
	end
	local anyone = false
	for _, p in ipairs(Players:GetPlayers()) do
		if SupplyDropConfig.AirdropLiveFor(p.UserId) then
			anyone = true
			break
		end
	end
	if not anyone then
		return false
	end
	nextId += 1
	local id = "airdrop_" .. tostring(nextId)
	local ground = pickSpawnPosition()
	local cash = math.random(A.CashMin, A.CashMax)
	local size = SupplyDropConfig.CrateSize or Vector3.new(5, 4, 5)
	local landed = CFrame.new(ground + Vector3.new(0, size.Y * 0.5, 0))
	local crate = Instance.new("Part")
	crate.Name = "Airdrop_" .. id
	crate.Size = size
	crate.CFrame = landed + Vector3.new(0, A.DropHeight, 0)
	crate.Anchored = true
	crate.CanCollide = true
	crate.Color = SupplyDropConfig.CrateColor or Color3.fromRGB(210, 160, 55)
	crate.Material = Enum.Material.Metal
	crate.TopSurface = Enum.SurfaceType.Smooth
	crate.BottomSurface = Enum.SurfaceType.Smooth
	crate:SetAttribute("SupplyDropId", id)
	crate:SetAttribute("ClaimCash", cash)
	crate:SetAttribute("WE_Airdrop", true)
	local function welded(name: string, psize: Vector3, offset: CFrame, color: Color3, mat: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = psize
		p.CFrame = crate.CFrame * offset
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Color = color
		p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local w = Instance.new("WeldConstraint")
		w.Part0 = crate
		w.Part1 = p
		w.Parent = p
		p.Parent = crate
		return p
	end
	welded("Lid", Vector3.new(size.X * 0.92, 0.4, size.Z * 0.92), CFrame.new(0, size.Y * 0.5 + 0.1, 0), SupplyDropConfig.LidColor or Color3.fromRGB(180, 140, 50), Enum.Material.Metal)
	local canopy = welded("Canopy", Vector3.new(14, 2, 14), CFrame.new(0, size.Y * 0.5 + 12, 0), A.CanopyColor, Enum.Material.Fabric)
	crate.Parent = ensureFolder()
	CollectionService:AddTag(crate, Constants.Tags.SupplyDrop)
	local rec: DropRec = {
		Id = id,
		Part = crate,
		ClaimCash = cash,
		ExpiresAt = os.clock() + A.FallSeconds + A.LifetimeSeconds,
		ClaimProgress = {},
		Airdrop = true,
		Landed = false,
	}
	active[id] = rec
	pushAirdrop({ Show = true, X = ground.X, Y = ground.Y, Z = ground.Z, Cash = cash })
	if NotificationService then
		for _, p in ipairs(Players:GetPlayers()) do
			if SupplyDropConfig.AirdropLiveFor(p.UserId) then
				NotificationService.Notify(p, "Airdrop incoming! $" .. formatCash(cash), "Info")
			end
		end
	end
	local tw = TweenService:Create(crate, TweenInfo.new(A.FallSeconds, Enum.EasingStyle.Linear), { CFrame = landed })
	tw.Completed:Connect(function()
		if canopy.Parent then
			canopy:Destroy()
		end
		if active[id] == rec then
			rec.Landed = true
			local bb = WorldLabel.Create(crate, "Airdrop", {
				Name = "Label",
				Sub = "$" .. formatCash(cash),
				Color = Color3.fromRGB(255, 220, 120),
				SubColor = Color3.fromRGB(110, 255, 90),
				Offset = Vector3.new(0, size.Y * 0.5 + (SupplyDropConfig.LabelLiftStuds or 3), 0),
				MaxDistance = 40,
			})
			bb.AlwaysOnTop = false -- the objective marker is the one AlwaysOnTop cue
		end
	end)
	tw:Play()
	return true
end

function SupplyDropService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	AnalyticsService = deps.AnalyticsService

	-- claude-bud JOB 4.1: the airdrop loop (a no-op tick while nobody it is live for is in the server)
	task.spawn(function()
		task.wait(SupplyDropConfig.Airdrop.FirstDelaySeconds)
		while true do
			local okA, spawned = pcall(spawnAirdrop)
			if not okA then
				warn("[SupplyDropService] airdrop failed:", spawned)
			end
			-- the full interval after a drop; a short re-check while nobody it is live for is here
			task.wait(if okA and spawned == true then SupplyDropConfig.Airdrop.IntervalSeconds else 30)
		end
	end)

	if not SupplyDropConfig.Enabled then
		-- claude-bud: the airdrop still needs the claim tick
		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= 0.2 then
				local step = acc
				acc = 0
				tickClaims(step)
			end
		end)
		return
	end

	ensureFolder()

	task.spawn(function()
		task.wait(12) -- let map settle
		spawnDrop()
		local interval = SupplyDropConfig.SpawnIntervalSeconds or 90
		while true do
			task.wait(interval)
			spawnDrop()
		end
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		local step = accum
		accum = 0
		tickClaims(step)
	end)
end

return SupplyDropService
