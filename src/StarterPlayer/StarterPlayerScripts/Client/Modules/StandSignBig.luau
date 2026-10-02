--!strict
--[[ Code Bot board-text (Shaun, phone: "the writing on the upgrade / pass boards is far too small"). The Supply Depot
	purchase-stand signs (Server/Modules/PurchaseStands.BuildSign: a SurfaceGui "WE_PremiumBillboard" on the stand's
	purchase part, adorned to the "SignPanel" part) re-laid out on THIS client for a viewer the big layout is live for
	(MonetizationConfig.BigSignLiveFor: NEW-OWNER-FIRST). Display only, client-local:
	  * the panel grows to PremiumPads.BigSign W x H studs UPWARD (bottom edge and posts stay put, so the hologram and
	    pad under it are untouched; W <= Depot.Step - 5 so neighbours never overlap);
	  * Shared/Util/StandSignLayout.Big: big bold name, ONE short effect line from MonetizationConfig.EffectFor (the same
	    config the Shop reads), a big price / OWNED pill (ShopController keeps writing "✓ OWNED" into the same Price
	    label), every label TextScaled with a UITextSizeConstraint floor, no wrap, truncation as the last guard.
	Only stands with a PadSlot (the Supply Depot row); the Golden Pump stand at the pumps is left exactly as it is.
	Cost: CollectionService added-signal + one OfferKey attribute signal per stand. No loop, no Heartbeat. ]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local StandSignLayout = require(Shared.Util.StandSignLayout)

local StandSignBig = {}

local TAG = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"
local ATTR_DONE = "WE_BigSign"

local FONTS: { [string]: Enum.Font } = {
	GothamBlack = Enum.Font.GothamBlack,
	GothamBold = Enum.Font.GothamBold,
}

local function place(obj: GuiObject, b: any)
	obj.Position = UDim2.fromOffset(b.X, b.Y)
	obj.Size = UDim2.fromOffset(b.W, b.H)
end

local function styleText(t: Instance?, b: any, color: Color3?)
	if not (t and t:IsA("TextLabel")) then
		return
	end
	place(t, b)
	t.Font = FONTS[b.Font] or Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextWrapped = false
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.TextXAlignment = if b.Align == "Left" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	if color then
		t.TextColor3 = color
	end
	local c = t:FindFirstChildOfClass("UITextSizeConstraint")
	if c == nil then
		c = Instance.new("UITextSizeConstraint")
		c.Parent = t
	end
	(c :: UITextSizeConstraint).MaxTextSize = b.Max;
	(c :: UITextSizeConstraint).MinTextSize = b.Min
end

-- the effect line for the stand's current offer (the server may retarget the Speed stand: OfferKind / OfferKey)
local function effectFor(top: BasePart): string?
	local kind, key = top:GetAttribute("OfferKind"), top:GetAttribute("OfferKey")
	if typeof(key) ~= "string" then
		return nil
	end
	local section: any = if kind == "GamePass" then MonetizationConfig.GamePasses else MonetizationConfig.DevProducts
	local def = if typeof(section) == "table" then section[key] else nil
	return (MonetizationConfig :: any).EffectFor(def, Players.LocalPlayer.UserId)
end

local function resizePanel(sg: SurfaceGui, B: any)
	local panel = sg.Adornee
	if not (panel and panel:IsA("BasePart")) or panel:GetAttribute(ATTR_DONE) == true then
		return
	end
	local old = panel.Size
	local dh = B.H - old.Y
	-- grow upward: the bottom edge stays where it was (posts + hologram untouched)
	panel.Size = Vector3.new(B.W, B.H, old.Z)
	panel.CFrame = panel.CFrame * CFrame.new(0, dh / 2, 0)
	panel:SetAttribute(ATTR_DONE, true)
end

function StandSignBig.Apply(top: Instance)
	if not top:IsA("BasePart") or top:GetAttribute("WE_Stand") ~= true or top:GetAttribute("PadSlot") == nil then
		return
	end
	local sg = top:FindFirstChild("WE_PremiumBillboard")
	if not (sg and sg:IsA("SurfaceGui")) then
		return
	end
	local B: any = (MonetizationConfig.PremiumPads :: any).BigSign
	local L = StandSignLayout.Big(B.W, B.H, B.PixelsPerStud)
	resizePanel(sg, B)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = B.PixelsPerStud
	local disc = sg:FindFirstChild("IconDisc")
	if disc and disc:IsA("Frame") then
		place(disc, L.Icon)
		styleText(disc:FindFirstChild("Icon"), L.IconGlyph, nil)
	end
	styleText(sg:FindFirstChild("Title"), L.Title, Color3.fromRGB(255, 250, 235))
	local benefit = sg:FindFirstChild("Benefit")
	styleText(benefit, L.Effect, Color3.fromRGB(255, 226, 120)) -- warm yellow on the dark panel: strong contrast
	local eff = effectFor(top)
	if eff and benefit and benefit:IsA("TextLabel") then
		benefit.Text = eff
	end
	local chip = sg:FindFirstChild("PriceChip")
	if chip and chip:IsA("Frame") then
		chip.AnchorPoint = Vector2.new(0, 0)
		place(chip, L.Chip)
		styleText(chip:FindFirstChild("Price"), L.Price, nil)
	end
end

function StandSignBig.Start()
	local lp = Players.LocalPlayer
	if not (MonetizationConfig :: any).BigSignLiveFor(lp.UserId) then
		return
	end
	local function hook(inst: Instance)
		if not inst:IsA("BasePart") then
			return
		end
		task.defer(function()
			pcall(StandSignBig.Apply, inst)
		end)
		-- the server's Retarget writes the new offer's texts: re-apply after them
		inst:GetAttributeChangedSignal("OfferKey"):Connect(function()
			task.defer(function()
				pcall(StandSignBig.Apply, inst)
			end)
		end)
		local sg = inst:FindFirstChild("WE_PremiumBillboard")
		if sg == nil then
			-- the sign is parented after the tag on some paths: one ChildAdded wait, no polling
			local conn: RBXScriptConnection? = nil
			conn = inst.ChildAdded:Connect(function(c: Instance)
				if c.Name == "WE_PremiumBillboard" then
					if conn then
						conn:Disconnect()
					end
					task.defer(function()
						pcall(StandSignBig.Apply, inst)
					end)
				end
			end)
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(hook)
end

return StandSignBig
