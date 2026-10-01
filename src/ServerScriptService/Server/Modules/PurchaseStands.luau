--!strict
--[[
	claude-bud JOB 19 (2026-09-29, owner: "the Robux purchase pads look terrible"): a proper purchase stand for every
	base Robux offer (MonetizationConfig.PremiumPads.Stand / .Depot). Built by MapSetup (the ATM offers, grouped in the
	plot's "Supply Depot" corner under one sign) and PlotOilPumpService (the Golden Pump stand by the pumps).
	  * A raised hexagonal steel plinth (3 boxes at 0 / 60 / 120 degrees) with a gold trim ring, a steel top.
	  * The top is THE purchase part: WE_PremiumPad tag + OfferKind / OfferKey / PlotId / OwnedIfAny / PadSlot (exactly
	    what the old flat pad carried), WE_Stand = true, and a ProximityPrompt "Buy - R$ X". PremiumPadService listens
	    to that prompt ONLY for stands: stepping on a stand never buys (no Touched, no standing check). The purchase path
	    is unchanged: PremiumPadService.tryPrompt -> PromptPremiumPad -> the client's PromptPurchase / ProcessReceipt.
	  * A slowly spinning glowing hologram (client spins it) and, Code Bot v175, ONE physical sign over the plinth (a
	    SurfaceGui panel: icon, name, one benefit line, a gold Robux price pill; price from MonetizationConfig /
	    LivePrices, never typed here). Was a floating BillboardGui + an icon billboard (they overlapped side by side).
	  * A soft Neon ring on the floor (the client pulses it; low quality: still).
	  * OWNED (client, ShopController): green ring + tint, a check badge in the chip, the prompt hidden.
	No shadows; one PointLight per stand (Shadows off). Anchored; only the plinth collides.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local LivePrices = require(Shared.Util.LivePrices) -- Code Bot v156: the real Roblox price / name

local PurchaseStands = {}

local TAG = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"
local ROBUX = utf8.char(0xE002) -- the Robux icon glyph in Roblox fonts

export type StandOpts = {
	Kind: string, -- "GamePass" | "DevProduct"
	Key: string,
	PlotId: number,
	Label: string?, -- display name (else the config DisplayName)
	Benefit: string?, -- one short line (else the config Description)
	Color: Color3,
	Icon: string?, -- the hologram glyph
	OwnedIfAny: string?, -- comma list (PremiumPads slot)
	PadSlot: string?,
	FaceDir: Vector3?, -- Code Bot v175: the direction the sign's readable face looks (world, flattened); nil = the stand's front (-Z)
}

-- price + name + benefit, from MonetizationConfig only
function PurchaseStands.OfferInfo(kind: string, key: string, userId: number?): (number, string, string)
	local def: any = if kind == "GamePass" then (MonetizationConfig.GamePasses :: any)[key] else (MonetizationConfig.DevProducts :: any)[key]
	-- Code Bot v156: the real Roblox price and product name (config only as the fallback)
	local price = if typeof(def) == "table" then LivePrices.Price(kind, key) else 0
	local name = if typeof(def) == "table" then LivePrices.Name(kind, key) else key
	local desc = (MonetizationConfig :: any).DescFor(def, userId) or "" -- claude-bud JOB 40: speed text from the helper
	return price, name, desc
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = font
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.4
	t.Text = text
	t.Parent = parent
	return t
end

--[[ Code Bot v175 (Shaun 2026-10-01, phone: "2x Cash overlaps Auto Collect, the descriptions are cut off"). Root cause:
	every stand drew its name / benefit / price on a camera-facing BillboardGui 7 x 3.6 studs wide floating ~7.6 studs up
	(plus a 2.6-stud icon billboard on the hologram). Billboards always turn to the camera, so from any angle off the
	row's normal the three stands' boards (12 studs apart) slide over each other, and the benefit line had 24 % of a
	3.6-stud board, TextScaled, so long lines shrank to nothing. Now each stand carries ONE physical sign: a dark
	military panel (SignW x SignH studs, never wider than the row step minus a gap, so neighbours can never overlap at any
	angle or distance: they are solid parts in one plane) on two slim posts over the plinth, with a SurfaceGui
	(PixelsPerStud, MaxDistance = LabelMaxDistance): gold edge, the icon disc, the NAME in bold, one description line,
	the price in a gold Robux pill, and OWNED (the Shop client turns the pill green "✓ OWNED" and the edge green).
	Nothing collides (CanCollide / CanQuery / CanTouch false); the purchase part, prompt and attributes are unchanged. ]]
local function gl(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, color: Color3, font: Enum.Font, maxSize: number, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = font
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	t.TextWrapped = false
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.ZIndex = 3
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.MinTextSize = 14
	c.Parent = t
	t.Parent = parent
	return t
end

-- the sign's numbers (pure; the check reads them): panel size, the gap to the next stand, its centre height
function PurchaseStands.SignLayout(): { W: number, H: number, Lift: number, PostX: number, Px: number, CanvasW: number, CanvasH: number }
	local S: any = MonetizationConfig.PremiumPads.Stand
	local W, H = S.SignW or 6.4, S.SignH or 3.4
	local px = S.SignPixelsPerStud or 60
	return { W = W, H = H, Lift = S.Height + S.HoloLift + 1.6 + H / 2, PostX = W / 2 - 0.45, Px = px, CanvasW = W * px, CanvasH = H * px }
end

function PurchaseStands.BuildSign(m: Instance, top: BasePart, base: CFrame, o: StandOpts, name: string, benefit: string, price: number)
	local S: any = MonetizationConfig.PremiumPads.Stand
	local L = PurchaseStands.SignLayout()
	local face = o.FaceDir or base.LookVector
	face = Vector3.new(face.X, 0, face.Z)
	if face.Magnitude < 1e-3 then
		face = Vector3.new(0, 0, -1)
	end
	face = face.Unit
	local centre = base.Position + Vector3.new(0, L.Lift, 0)
	local cf = CFrame.lookAt(centre, centre + face) -- Front face (the SurfaceGui) looks along `face`
	local panel = part("SignPanel", Vector3.new(L.W, L.H, 0.25), cf, S.SignBack or Color3.fromRGB(26, 30, 26), Enum.Material.Metal, false, m)
	panel.CanQuery = false
	for _, x in ipairs({ -L.PostX, L.PostX }) do
		local postH = L.Lift - L.H / 2 - S.Height + 0.1
		local post = part("SignPost", Vector3.new(0.22, postH, 0.22), cf * CFrame.new(x, -L.H / 2 - postH / 2 + 0.05, 0.2), S.Gold, Enum.Material.Metal, false, m)
		post.CanQuery = false
	end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WE_PremiumBillboard" -- the Shop client's OWNED look and Retarget find it by this name (as before)
	sg.Face = Enum.NormalId.Front
	sg.Adornee = panel
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = L.Px
	sg.MaxDistance = S.LabelMaxDistance
	sg.LightInfluence = 0
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.ResetOnSpawn = false
	local CW, CH = L.CanvasW, L.CanvasH
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = S.SignBack or Color3.fromRGB(26, 30, 26)
	card.BorderSizePixel = 0
	card.ZIndex = 1
	card.Parent = sg
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 16)
	cc.Parent = card
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = S.Gold
	edge.Thickness = 6
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = card
	-- the icon disc (the stand's colour), top-left
	local disc = Instance.new("Frame")
	disc.Name = "IconDisc"
	disc.Position = UDim2.fromOffset(14, 14)
	disc.Size = UDim2.fromOffset(78, 78)
	disc.BackgroundColor3 = o.Color
	disc.BorderSizePixel = 0
	disc.ZIndex = 2
	disc.Parent = sg
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(0.5, 0)
	dc.Parent = disc
	local ds = Instance.new("UIStroke")
	ds.Color = Color3.fromRGB(20, 20, 18)
	ds.Thickness = 3
	ds.Parent = disc
	local icon = gl(disc, "Icon", o.Icon or "★", 8, 8, 62, 62, Color3.new(1, 1, 1), Enum.Font.GothamBlack, 52, Enum.TextXAlignment.Center)
	icon.TextStrokeTransparency = 0.5
	-- the NAME (bold) beside the icon, the one description line under both, the gold Robux pill at the bottom
	gl(sg, "Title", name, 104, 12, CW - 118, 80, Color3.fromRGB(248, 242, 226), Enum.Font.GothamBlack, 58)
	gl(sg, "Benefit", benefit, 16, 98, CW - 32, 34, Color3.fromRGB(206, 212, 200), Enum.Font.GothamMedium, 28, Enum.TextXAlignment.Center)
	local chip = Instance.new("Frame")
	chip.Name = "PriceChip"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.fromOffset(CW / 2, 138)
	chip.Size = UDim2.fromOffset(math.floor(CW * 0.62), CH - 138 - 12)
	chip.BackgroundColor3 = S.Gold
	chip.BorderSizePixel = 0
	chip.ZIndex = 2
	chip.Parent = sg
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0.5, 0)
	pc.Parent = chip
	local pr = gl(chip, "Price", ROBUX .. " " .. tostring(price), 10, 4, math.floor(CW * 0.62) - 20, CH - 138 - 20, Color3.fromRGB(34, 26, 8), Enum.Font.GothamBlack, 44, Enum.TextXAlignment.Center)
	pr.TextStrokeTransparency = 1
	sg.Parent = top
	return panel
end

--[[ One stand at `base` (world CFrame on the floor; its -Z = the stand's front). Returns the purchase part (the top). ]]
function PurchaseStands.Build(parent: Instance, base: CFrame, o: StandOpts): BasePart
	local S: any = MonetizationConfig.PremiumPads.Stand
	local price, cfgName, cfgDesc = PurchaseStands.OfferInfo(o.Kind, o.Key)
	local name = o.Label or cfgName
	local benefit = o.Benefit or cfgDesc
	local m = Instance.new("Model")
	m.Name = "PurchaseStand_" .. o.Key
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local R, H = S.Radius, S.Height
	-- hexagonal plinth: 3 boxes (side R, width sqrt(3) R) turned 0 / 60 / 120 degrees
	for k = 0, 2 do
		part("Plinth", Vector3.new(R, H, R * math.sqrt(3)), base * CFrame.new(0, H / 2, 0) * CFrame.Angles(0, math.rad(60 * k), 0), S.Steel, Enum.Material.DiamondPlate, true, m)
	end
	-- gold trim ring round the top edge
	part("GoldTrim", Vector3.new(0.3, 2 * R + 0.7, 2 * R + 0.7), base * CFrame.new(0, H - 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), S.Gold, Enum.Material.Metal, false, m, Enum.PartType.Cylinder)
	-- the purchase part: the steel top
	local top = part("PremiumPad_" .. o.Key, Vector3.new(0.2, 2 * R, 2 * R), base * CFrame.new(0, H + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), S.Top, Enum.Material.Metal, true, m, Enum.PartType.Cylinder)
	top:SetAttribute("PlotId", o.PlotId)
	top:SetAttribute("OfferKind", o.Kind)
	top:SetAttribute("OfferKey", o.Key)
	if o.OwnedIfAny then
		top:SetAttribute("OwnedIfAny", o.OwnedIfAny)
	end
	if o.PadSlot then
		top:SetAttribute("PadSlot", o.PadSlot)
	end
	top:SetAttribute("WE_Stand", true)
	top:SetAttribute("WE_StandColor", o.Color)
	-- the soft floor ring (the client pulses it)
	local ring = part("FloorRing", Vector3.new(0.1, 2 * R + 3, 2 * R + 3), base * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), o.Color, Enum.Material.Neon, false, m, Enum.PartType.Cylinder)
	ring.Transparency = S.RingTransparency
	-- the hologram (the client spins it) + its icon
	local holo = part("Hologram", Vector3.new(S.HoloSize, S.HoloSize, S.HoloSize), base * CFrame.new(0, H + S.HoloLift, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), o.Color, Enum.Material.Neon, false, m)
	holo.Transparency = S.HoloTransparency
	local light = Instance.new("PointLight")
	light.Color = o.Color
	light.Brightness = S.LightBrightness
	light.Range = S.LightRange
	light.Shadows = false
	light.Parent = holo
	PurchaseStands.BuildSign(m, top, base, o, name, benefit, price)
	-- the ONLY purchase trigger
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "WE_BuyPrompt"
	pp.ActionText = "Buy - " .. ROBUX .. " " .. tostring(price)
	pp.ObjectText = name
	pp.HoldDuration = S.HoldSeconds
	pp.MaxActivationDistance = S.PromptDistance
	pp.RequiresLineOfSight = false
	pp.Parent = top

	CollectionService:AddTag(top, TAG)
	m.Parent = parent
	return top
end

--[[ The depot sign behind the stand row (a 2-post board, one SurfaceGui, MaxDistance 60). ]]
--[[ claude-bud JOB 36: point an existing stand at another offer (the base Speed stand sells Speed Boost while the shop
	overhaul is live for the plot's owner). Updates what PremiumPadService reads at trigger time (OfferKind / OfferKey)
	and what the stand shows (title, benefit, price chip, prompt), all from MonetizationConfig. ]]
function PurchaseStands.Retarget(top: BasePart, kind: string, key: string)
	local price, name, benefit = PurchaseStands.OfferInfo(kind, key)
	top:SetAttribute("OfferKind", kind)
	top:SetAttribute("OfferKey", key)
	local bb = top:FindFirstChild("WE_PremiumBillboard")
	if bb then
		local t = bb:FindFirstChild("Title")
		if t and t:IsA("TextLabel") then
			t.Text = name
		end
		local b = bb:FindFirstChild("Benefit")
		if b and b:IsA("TextLabel") then
			b.Text = benefit
		end
		local chip = bb:FindFirstChild("PriceChip")
		local p = chip and chip:FindFirstChild("Price")
		if p and p:IsA("TextLabel") then
			p.Text = ROBUX .. " " .. tostring(price)
		end
	end
	local pp = top:FindFirstChild("WE_BuyPrompt")
	if pp and pp:IsA("ProximityPrompt") then
		pp.ActionText = "Buy - " .. ROBUX .. " " .. tostring(price)
		pp.ObjectText = name
	end
end

-- Code Bot v175: lift = the board's centre height (default 6, as before); the Supply Depot raises it over the stand signs
function PurchaseStands.Sign(parent: Instance, cf: CFrame, text: string, lift: number?)
	local S: any = MonetizationConfig.PremiumPads.Stand
	local y = lift or 6
	local m = Instance.new("Model")
	m.Name = "SupplyDepotSign"
	for _, x in ipairs({ -6, 6 }) do
		part("SignPost", Vector3.new(0.6, y + 1, 0.6), cf * CFrame.new(x, (y + 1) / 2, 0.3), S.Steel, Enum.Material.Metal, false, m)
	end
	local board = part("SignBoard", Vector3.new(14, 2.6, 0.4), cf * CFrame.new(0, y, 0), S.Steel, Enum.Material.Metal, false, m)
	part("SignGold", Vector3.new(14.4, 0.3, 0.5), cf * CFrame.new(0, y + 1.4, 0), S.Gold, Enum.Material.Metal, false, m)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.MaxDistance = 60
	sg.LightInfluence = 0
	sg.CanvasSize = Vector2.new(560, 104)
	sg.Parent = board
	label(sg, "Text", text, UDim2.fromScale(0.03, 0.08), UDim2.fromScale(0.94, 0.84), S.Gold, Enum.Font.GothamBlack)
	m.Parent = parent
end

return PurchaseStands
