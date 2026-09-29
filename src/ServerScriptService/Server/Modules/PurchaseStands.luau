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
	  * A slowly spinning glowing hologram (client spins it; icon BillboardGui) and a floating info BillboardGui (name, a
	    short benefit line, a gold price chip with the Robux icon; price read from MonetizationConfig, never typed here).
	  * A soft Neon ring on the floor (the client pulses it; low quality: still).
	  * OWNED (client, ShopController): green ring + tint, a check badge in the chip, the prompt hidden.
	No shadows; one PointLight per stand (Shadows off). Anchored; only the plinth collides.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

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
}

-- price + name + benefit, from MonetizationConfig only
function PurchaseStands.OfferInfo(kind: string, key: string): (number, string, string)
	local def: any = if kind == "GamePass" then (MonetizationConfig.GamePasses :: any)[key] else (MonetizationConfig.DevProducts :: any)[key]
	local price = if typeof(def) == "table" then tonumber(def.RobuxPrice) or 0 else 0
	local name = if typeof(def) == "table" and typeof(def.DisplayName) == "string" then def.DisplayName else key
	local desc = if typeof(def) == "table" and typeof(def.Description) == "string" then def.Description else ""
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
	local icon = Instance.new("BillboardGui")
	icon.Name = "WE_StandIcon"
	icon.Size = UDim2.fromScale(2.6, 2.6)
	icon.MaxDistance = S.LabelMaxDistance
	icon.LightInfluence = 0
	icon.Parent = holo
	label(icon, "Icon", o.Icon or "★", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	-- the info board: name, benefit, gold price chip (the client's OWNED look finds it by name)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_PremiumBillboard"
	bb.Size = UDim2.fromScale(7, 3.6)
	bb.StudsOffsetWorldSpace = Vector3.new(0, H + S.HoloLift + 3.4, 0)
	bb.MaxDistance = S.LabelMaxDistance
	bb.LightInfluence = 0
	bb.Adornee = top
	bb.Parent = top
	label(bb, "Title", name, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.38), Color3.fromRGB(245, 240, 225), Enum.Font.GothamBlack)
	label(bb, "Benefit", benefit, UDim2.fromScale(0, 0.38), UDim2.fromScale(1, 0.24), Color3.fromRGB(210, 214, 220), Enum.Font.GothamMedium)
	local chip = Instance.new("Frame")
	chip.Name = "PriceChip"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.fromScale(0.5, 0.66)
	chip.Size = UDim2.fromScale(0.5, 0.32)
	chip.BackgroundColor3 = S.Gold
	chip.BorderSizePixel = 0
	chip.Parent = bb
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.5, 0)
	cc.Parent = chip
	label(chip, "Price", ROBUX .. " " .. tostring(price), UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.9), Color3.fromRGB(34, 26, 8), Enum.Font.GothamBlack).TextStrokeTransparency = 1
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
function PurchaseStands.Sign(parent: Instance, cf: CFrame, text: string)
	local S: any = MonetizationConfig.PremiumPads.Stand
	local m = Instance.new("Model")
	m.Name = "SupplyDepotSign"
	for _, x in ipairs({ -6, 6 }) do
		part("SignPost", Vector3.new(0.6, 7, 0.6), cf * CFrame.new(x, 3.5, 0.3), S.Steel, Enum.Material.Metal, false, m)
	end
	local board = part("SignBoard", Vector3.new(14, 2.6, 0.4), cf * CFrame.new(0, 6, 0), S.Steel, Enum.Material.Metal, false, m)
	part("SignGold", Vector3.new(14.4, 0.3, 0.5), cf * CFrame.new(0, 7.4, 0), S.Gold, Enum.Material.Metal, false, m)
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
