--!strict
--[[
	Periodic Supply Drops — crates spawn on map; stand near to claim Cash.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SupplyDropConfig = require(Shared.Configs.SupplyDropConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

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

local function pickSpawnPosition(): Vector3
	local pads = CollectionService:GetTagged(Constants.Tags.EventSpawn)
	local candidates: { Vector3 } = {}
	for _, inst in ipairs(pads) do
		if inst:IsA("BasePart") then
			table.insert(candidates, inst.Position + Vector3.new(0, 3, 0))
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
		local pos = Vector3.new(math.cos(angle) * dist, 3, math.sin(angle) * dist)
		local ok = true
		for _, rec in pairs(active) do
			if (rec.Part.Position - pos).Magnitude < 40 then
				ok = false
				break
			end
		end
		if ok then
			return pos
		end
	end
	return Vector3.new(150, 3, 150)
end

local function destroyDrop(id: string)
	local rec = active[id]
	if not rec then
		return
	end
	active[id] = nil
	if rec.Part and rec.Part.Parent then
		rec.Part:Destroy()
	end
end

local function spawnDrop()
	if not SupplyDropConfig.Enabled then
		return
	end
	local count = 0
	for _ in pairs(active) do
		count += 1
	end
	if count >= (SupplyDropConfig.MaxActive or 3) then
		return
	end

	nextId += 1
	local id = "drop_" .. tostring(nextId)
	local pos = pickSpawnPosition()
	local cashMin = SupplyDropConfig.CashMin or 2500
	local cashMax = SupplyDropConfig.CashMax or 12000
	local cash = math.random(cashMin, cashMax)

	local parent = ensureFolder()
	local crate = Instance.new("Part")
	crate.Name = "SupplyCrate_" .. id
	crate.Size = SupplyDropConfig.CrateSize or Vector3.new(5, 4, 5)
	crate.Position = pos
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

	-- Visual kits v2: straps + lid + neon ring
	local function decor(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.Material = mat
		p.Color = color
		if shape then
			p.Shape = shape
		end
		p.CFrame = crate.CFrame * offset
		p.Parent = crate
		return p
	end
	decor("StrapX", Vector3.new(crate.Size.X + 0.2, 0.35, 0.35), CFrame.new(0, 0.2, 0), Color3.fromRGB(40, 40, 42), Enum.Material.Metal, nil)
	decor("StrapZ", Vector3.new(0.35, 0.35, crate.Size.Z + 0.2), CFrame.new(0, 0.2, 0), Color3.fromRGB(40, 40, 42), Enum.Material.Metal, nil)
	decor("Lid", Vector3.new(crate.Size.X * 0.92, 0.4, crate.Size.Z * 0.92), CFrame.new(0, crate.Size.Y * 0.5 + 0.1, 0), Color3.fromRGB(180, 140, 50), Enum.Material.Metal, nil)
	decor("Ring", Vector3.new(crate.Size.X + 1.5, 0.25, crate.Size.Z + 1.5), CFrame.new(0, -crate.Size.Y * 0.45, 0), Color3.fromRGB(255, 200, 80), Enum.Material.Neon, nil)

	local tip = Instance.new("Part")
	tip.Name = "Beacon"
	tip.Size = Vector3.new(1.4, 1.4, 1.4)
	tip.Shape = Enum.PartType.Ball
	tip.Anchored = true
	tip.CanCollide = false
	tip.Material = Enum.Material.Neon
	tip.Color = SupplyDropConfig.BeaconColor or Color3.fromRGB(255, 200, 80)
	tip.CFrame = crate.CFrame * CFrame.new(0, 4, 0)
	tip.Parent = crate

	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(200, 40)
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500
	bb.Parent = crate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(12, 14, 16)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.Text = string.format("SUPPLY DROP · Stand to claim ~$%d", cash)
	label.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local ttl = SupplyDropConfig.LifetimeSeconds or 75
		pcall(function()
		local vas = require(script.Parent.VisualAssetService)
		if vas and vas.TryAttachCashCrateVisual then
			vas.TryAttachCashCrateVisual(crate)
		end
	end)

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
		NotificationService.Notify(player, string.format("Supply Drop +$%d", rec.ClaimCash), "Reward")
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
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (hrp.Position - pos).Magnitude
				if d <= radius then
					nearby[player.UserId] = true
					local prog = (rec.ClaimProgress[player.UserId] or 0) + dt
					rec.ClaimProgress[player.UserId] = prog
					if prog >= holdNeed then
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

function SupplyDropService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	AnalyticsService = deps.AnalyticsService

	if not SupplyDropConfig.Enabled then
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
