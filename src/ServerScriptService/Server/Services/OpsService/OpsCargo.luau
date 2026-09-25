--!strict
--[[
	OpsCargo — carried bags and boxes (W3 step 2 Phase B, lane O; contract §4.3, activities §2.4). SERVER ONLY.

	* One carried item per player: 1 welded part (Cargo.BagSize, Fabric, Massless, CanCollide / CanQuery / CanTouch
	  false) on the back, and one stud-scaled WorldLabel "BAG" / "BOX" over the head (red, MaxDistance
	  Ui.LabelMaxDistance, never drawn on top of walls). Its value was fixed on the SERVER when it was grabbed.
	* Deadline Cargo.DeadlineSeconds ("Bag lost" after). Vehicles may carry it (Cargo.AllowVehicles).
	* On death (CombatService.OnPlayerDeath) it drops: 1 anchored, CanCollide-false part with a "Pick up bag" prompt
	  (hold Cargo.PickupHold, distance Cargo.PickupDist) for Cargo.DropLifetimeSeconds. The 4th drop (MaxHandoffs 3)
	  destroys it. A picker who is not the grabber gets Cargo.PickerMult of the value and a fresh deadline; picking
	  up never sets the picker's cooldown.
	* Delivered only inside the carrier's OWN plot square (|dx|, |dz| <= PlotSize / 2 + DeliveryPad); no plot ->
	  within Cargo.FallbackRadius of Cargo.FallbackHome. Leaving the game destroys it. Bags are never saved.
	* At most Cargo.MaxBagsInWorld carried + dropped across all sites (the 512-stud circle budget, spec §3).
	* Carriers are revealed to non-allies on OpsPing every Remote.PingSeconds, never while the carrier is a novice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotFrame = require(Shared.Util.PlotFrame)
local WorldLabel = require(Shared.Util.WorldLabel)

local C = OpsConfig.Cargo

local OpsCargo = {}

export type Bag = {
	Id: number,
	Site: string,
	Kind: string,
	Value: number, -- the grabber's pay, fixed at grab time (server)
	XP: number,
	Grabber: number, -- UserId
	Carrier: Player?,
	Drops: number,
	Deadline: number, -- os.clock
	Part: BasePart?,
	Label: BillboardGui?,
	Prompt: ProximityPrompt?,
	DroppedAt: number?, -- os.clock
	DropPos: Vector3?,
	LastCarrier: number,
	LastPos: Vector3?, -- the carrier's last live position (the fallback drop point)
	PingedMove: boolean,
	NextPing: number,
}

local bags: { Bag } = {}
local byCarrier: { [number]: Bag } = {}
local serial = 0
local ctx: any = nil
local folder: Folder? = nil

local RED = Color3.fromRGB(230, 70, 60)

function OpsCargo.Init(context: any)
	ctx = context
end

function OpsCargo.Count(): number
	return #bags
end

function OpsCargo.CanAdd(): boolean
	return #bags < C.MaxBagsInWorld
end

function OpsCargo.Carrying(player: Player): Bag?
	return byCarrier[player.UserId]
end

function OpsCargo.All(): { Bag }
	return bags
end

local function dropFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local existing = Workspace:FindFirstChild("WE_OpsBags")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local nf = Instance.new("Folder")
	nf.Name = "WE_OpsBags"
	nf.Parent = Workspace
	folder = nf
	return nf
end

local function clearVisual(b: Bag)
	if b.Prompt then
		b.Prompt:Destroy()
		b.Prompt = nil
	end
	if b.Label then
		b.Label:Destroy()
		b.Label = nil
	end
	if b.Part then
		b.Part:Destroy()
		b.Part = nil
	end
end

local function makePart(): Part
	local p = Instance.new("Part")
	p.Name = "WE_OpsBag"
	p.Size = C.BagSize
	p.Material = Enum.Material.Fabric
	p.Color = Color3.fromRGB(70, 62, 48)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	return p
end

local function labelText(b: Bag): string
	local kind = OpsConfig.Kinds[b.Kind]
	return (kind and kind.CarryLabel) or "BAG"
end

-- the carried part on the character's back + the head label
local function attach(b: Bag, player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and root and root:IsA("BasePart")) then
		return false
	end
	local p = makePart()
	p.CFrame = root.CFrame * CFrame.new(0, 0.2, 0.5 + C.BagSize.Z * 0.5)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = char
	b.Part = p
	b.Label = WorldLabel.Create(p, labelText(b), {
		Name = "WE_OpsBagLabel",
		Color = RED,
		Offset = Vector3.new(0, 3.2, 0),
		MaxDistance = OpsConfig.Ui.LabelMaxDistance,
	})
	return true
end

local function remove(b: Bag)
	clearVisual(b)
	local i = table.find(bags, b)
	if i then
		table.remove(bags, i)
	end
	if b.Carrier then
		byCarrier[b.Carrier.UserId] = nil
		b.Carrier = nil
	end
end

--[[ A new bag on `player` (the grab). Returns nil when the world already holds MaxBagsInWorld bags, the player
	already carries one, or has no character. ]]
function OpsCargo.Grab(player: Player, site: OpsConfig.SiteDef, value: number, xp: number): Bag?
	if not OpsCargo.CanAdd() or byCarrier[player.UserId] ~= nil then
		return nil
	end
	serial += 1
	local b: Bag = {
		Id = serial,
		Site = site.Id,
		Kind = site.Kind,
		Value = value,
		XP = xp,
		Grabber = player.UserId,
		Carrier = player,
		Drops = 0,
		Deadline = os.clock() + C.DeadlineSeconds, -- a carry time, never Studio-scaled
		Part = nil,
		Label = nil,
		Prompt = nil,
		DroppedAt = nil,
		DropPos = nil,
		LastCarrier = player.UserId,
		LastPos = nil,
		PingedMove = false,
		NextPing = os.clock() + OpsConfig.Remote.PingSeconds,
	}
	if not attach(b, player) then
		return nil
	end
	table.insert(bags, b)
	byCarrier[player.UserId] = b
	ctx.Rewards.Log(ctx.Events.BAG_GRAB, player.UserId, { site = site.Id, value = value })
	ctx.MarkAllBags()
	return b
end

-- what `player` would be paid for this bag
function OpsCargo.ValueFor(b: Bag, player: Player): number
	if player.UserId == b.Grabber then
		return b.Value
	end
	return math.floor(b.Value * C.PickerMult + 0.5)
end

local function dropAt(b: Bag, pos: Vector3)
	local carrier = b.Carrier
	if carrier then
		byCarrier[carrier.UserId] = nil
		b.LastCarrier = carrier.UserId
		b.Carrier = nil
	end
	clearVisual(b)
	b.Drops += 1
	if b.Drops > C.MaxHandoffs then
		remove(b)
		ctx.MarkAllBags()
		return
	end
	local p = makePart()
	p.Anchored = true
	p.CanQuery = true -- the prompt's part; still no collision
	p.CFrame = CFrame.new(pos.X, math.max(pos.Y - 2, 1.5), pos.Z) -- the root stands ~3 above the ground
	p.Parent = dropFolder()
	b.Part = p
	b.DroppedAt = os.clock()
	b.DropPos = p.Position
	b.Label = WorldLabel.Create(p, labelText(b), {
		Name = "WE_OpsBagLabel",
		Color = RED,
		Offset = Vector3.new(0, 2, 0),
		MaxDistance = OpsConfig.Ui.LabelMaxDistance,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WE_OpsPrompt"
	prompt.ActionText = OpsConfig.Text.Prompts.PickUpBag
	local site = OpsConfig.Get(b.Site)
	prompt.ObjectText = if site then site.Name else ""
	prompt.HoldDuration = C.PickupHold
	prompt.MaxActivationDistance = C.PickupDist
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	b.Prompt = prompt
	local bagRef = b
	prompt.Triggered:Connect(function(player: Player)
		ctx.OnBagPrompt(bagRef, player)
	end)
	ctx.Rewards.Log(ctx.Events.BAG_DROP, b.LastCarrier, { site = b.Site, drops = b.Drops })
	ctx.MarkAllBags()
end

-- a teleport or a new character while carrying: the bag drops at the carrier's previous position
function OpsCargo.DropFor(player: Player, pos: Vector3)
	local b = byCarrier[player.UserId]
	if b ~= nil then
		dropAt(b, pos)
	end
end

-- the carrier died: the bag drops where the root was
function OpsCargo.OnDeath(player: Player)
	local b = byCarrier[player.UserId]
	if b == nil then
		return
	end
	local pos: Vector3? = nil
	local s = ctx.Zones.Get(player)
	if s and s.Pos then
		pos = s.Pos
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pos = root.Position
	end
	if pos == nil then
		remove(b)
		ctx.MarkAllBags()
		return
	end
	dropAt(b, pos)
end

--[[ A validated pickup (OpsService re-checked rate limit, alive, distance, on foot, not carrying, not locked). ]]
function OpsCargo.PickUp(b: Bag, player: Player): boolean
	if b.Carrier ~= nil or b.Part == nil or table.find(bags, b) == nil or byCarrier[player.UserId] ~= nil then
		return false
	end
	clearVisual(b)
	b.Carrier = player
	b.DroppedAt = nil
	b.DropPos = nil
	b.Deadline = os.clock() + C.DeadlineSeconds
	b.LastCarrier = player.UserId
	if not attach(b, player) then
		remove(b)
		ctx.MarkAllBags()
		return false
	end
	byCarrier[player.UserId] = b
	ctx.Rewards.Log(ctx.Events.BAG_PICKUP, player.UserId, { site = b.Site, picked = player.UserId ~= b.Grabber })
	ctx.MarkAllBags()
	return true
end

-- the carrier left the game: the bag is gone (never saved)
function OpsCargo.OnLeave(player: Player)
	local b = byCarrier[player.UserId]
	if b then
		remove(b)
		ctx.MarkAllBags()
	end
end

-- the player's delivery square: own plot (position, half size) or the fallback point (radius)
function OpsCargo.HomeOf(player: Player): (Vector3, number, boolean)
	local plotId = ctx.PlotOf(player)
	if plotId ~= nil then
		local pos = PlotFrame.PlotPosition(plotId)
		if pos then
			return pos, BaseConfig.PlotSize.X * 0.5 + C.DeliveryPad, true
		end
	end
	return Vector3.new(C.FallbackHome.X, 0, C.FallbackHome.Z), C.FallbackRadius, false
end

-- OpsStatePayload.Home: own plot centre moved HomeTowardGate toward the front gate, else FallbackHome
function OpsCargo.HomePoint(player: Player): { X: number, Z: number }
	local plotId = ctx.PlotOf(player)
	if plotId ~= nil then
		local ok, p = pcall(PlotFrame.LocalToWorld, plotId, 0, C.HomeTowardGate)
		if ok and typeof(p) == "Vector3" then
			return { X = math.floor(p.X + 0.5), Z = math.floor(p.Z + 0.5) }
		end
	end
	return { X = C.FallbackHome.X, Z = C.FallbackHome.Z }
end

local function inHome(player: Player, pos: Vector3): boolean
	local centre, half, square = OpsCargo.HomeOf(player)
	local dx, dz = math.abs(pos.X - centre.X), math.abs(pos.Z - centre.Z)
	if square then
		return dx <= half and dz <= half
	end
	return dx * dx + dz * dz <= half * half
end

local function novice(player: Player): boolean
	local profile = ctx.Profile(player)
	if profile == nil then
		return true
	end
	local first = tonumber(profile.FirstJoinUnix)
	if first ~= nil and os.time() - first < C.NoviceSeconds then
		return true
	end
	if profile.NoviceShieldDone == false then
		return true
	end
	return false
end
OpsCargo.IsNovice = novice

--[[ 4 Hz: deliveries, deadlines, dropped-bag lifetimes, carrier pings. ]]
function OpsCargo.Tick(nowC: number)
	local i = 1
	while i <= #bags do
		local b = bags[i]
		local carrier = b.Carrier
		local gone = false
		if carrier then
			if carrier.Parent == nil then
				remove(b)
				ctx.MarkAllBags()
				gone = true
			elseif nowC >= b.Deadline then
				remove(b)
				ctx.Notify(carrier, OpsConfig.Text.Toast.BagLost, "Warn")
				ctx.Rewards.Log(ctx.Events.BAG_DROP, carrier.UserId, { site = b.Site, lost = true })
				ctx.MarkAllBags()
				gone = true
			else
				local s = ctx.Zones.Get(carrier)
				if not s.Alive or b.Part == nil or b.Part.Parent == nil then
					-- a death or a lost character the death event missed: the bag drops where the carrier last was
					-- (never re-attached to a new character: a reset is not a free trip home)
					if b.LastPos ~= nil then
						dropAt(b, b.LastPos)
					else
						remove(b)
						ctx.MarkAllBags()
					end
					gone = true
				elseif s.Pos then
					b.LastPos = s.Pos
				end
				if not gone and s.Pos and not ctx.Zones.Locked(carrier, nowC) and inHome(carrier, s.Pos) then
					remove(b)
					ctx.Deliver(carrier, b)
					ctx.MarkAllBags()
					gone = true
				end
				if not gone and nowC >= b.NextPing then
					b.NextPing = nowC + OpsConfig.Remote.PingSeconds
					if not novice(carrier) then
						ctx.Ping(carrier, b)
					end
				end
			end
		elseif b.DroppedAt ~= nil and nowC - b.DroppedAt >= C.DropLifetimeSeconds then
			remove(b)
			ctx.MarkAllBags()
			gone = true
		end
		if not gone then
			i += 1
		end
	end
end

-- OpsStatePayload.Carrying for this player (nil = not carrying)
function OpsCargo.CarrySnap(player: Player, nowC: number): OpsConfig.OpsCarrySnap?
	local b = byCarrier[player.UserId]
	if b == nil then
		return nil
	end
	return {
		Site = b.Site,
		Kind = b.Kind,
		Value = OpsCargo.ValueFor(b, player),
		Left = math.max(0, math.ceil(b.Deadline - nowC)),
		Picked = player.UserId ~= b.Grabber,
	}
end

-- OpsStatePayload.Bags: dropped bags anyone may pick up
function OpsCargo.BagSnaps(nowC: number): { OpsConfig.OpsBagSnap }
	local out: { OpsConfig.OpsBagSnap } = {}
	for _, b in ipairs(bags) do
		local p = b.DropPos
		if b.Carrier == nil and p ~= nil and b.DroppedAt ~= nil then
			table.insert(out, {
				U = b.LastCarrier,
				X = math.floor(p.X + 0.5),
				Z = math.floor(p.Z + 0.5),
				Age = math.floor(nowC - b.DroppedAt),
				Site = b.Site,
			})
		end
	end
	return out
end

function OpsCargo.Clear()
	for _, b in ipairs(table.clone(bags)) do
		remove(b)
	end
end

return OpsCargo
