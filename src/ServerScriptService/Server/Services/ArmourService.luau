--!strict
--[[
	claude-bud JOB 26: personal armour (Shared/Configs/ArmourConfig; read its header). Server-authoritative:
	  * RequestBuyArmour(tier): the NEXT tier only, its Command Center level reached, inside his own plot (InBaseOnly),
	    Cash through ResearchService.Purchase (the one research Cash path). Paid and saved as the PersonalArmour research level (ResearchService.Purchase; kept after death and rebirth).
	  * On every character (and after a purchase): Humanoid.MaxHealth = PlayerMaxHealth / (1 - Reduction) (capped at
	    MaxReduction), the bonus shown by the HUD as a blue bar (player attributes WE_ArmourTier / WE_ArmourBaseHP /
	    WE_ArmourPct). Bonus max health reduces damage from EVERY source the same way, whatever code path hurts him.
	  * Look: WE_Armour parts (vest, helmet from HelmetFromTier) welded to the character: massless, no collide / query /
	    touch. RequestArmourLook(off) hides the look (profile.Settings.HideArmourLook); the stats stay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ArmourConfig = require(Shared.Configs.ArmourConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local ArmourService = {}

local DataService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local ResearchService: any = nil

local function baseHp(): number
	return tonumber(CombatConfig.PlayerMaxHealth) or 100
end

-- the owned tier = the PersonalArmour research level (paid and saved by ResearchService; kept through rebirth)
local function tierOf(player: Player): number
	local rs = ResearchService
	local ok, lv = pcall(function()
		return if rs and rs.GetLevel then rs.GetLevel(player, "PersonalArmour") else 0
	end)
	return math.clamp(if ok then math.floor(tonumber(lv) or 0) else 0, 0, #ArmourConfig.Tiers)
end

function ArmourService.ReductionFor(tier: number): number
	local def = ArmourConfig.Tiers[tier]
	return if def then math.clamp(def.Reduction, 0, ArmourConfig.MaxReduction) else 0
end

-- MaxHealth for a tier: PlayerMaxHealth / (1 - reduction) (the same damage then takes that share less of his health)
function ArmourService.MaxHealthFor(tier: number): number
	return math.floor(baseHp() / (1 - ArmourService.ReductionFor(tier)) + 0.5)
end

local function lookOff(profile: any): boolean
	return typeof(profile.Settings) == "table" and profile.Settings.HideArmourLook == true
end

local function part(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

local function weldTo(p: BasePart, to: BasePart, offset: CFrame)
	p.CFrame = to.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
end

-- the vest (+ helmet) on the character; rebuilt only when the tier or the setting changes
local function dressLook(char: Model, tier: number, hide: boolean)
	local old = char:FindFirstChild("WE_Armour")
	local key = string.format("%d|%s", tier, tostring(hide))
	if old and old:GetAttribute("Key") == key then
		return
	end
	if old then
		old:Destroy()
	end
	if hide or tier <= 0 then
		return
	end
	local def = ArmourConfig.Tiers[tier]
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local head = char:FindFirstChild("Head")
	if def == nil or torso == nil or not torso:IsA("BasePart") then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "WE_Armour"
	folder:SetAttribute("Key", key)
	local ts = torso.Size
	local vest = part("Vest", Vector3.new(ts.X * 1.08, ts.Y * 0.9, ts.Z * 1.35), def.Color)
	weldTo(vest, torso, CFrame.new(0, -ts.Y * 0.02, 0))
	vest.Parent = folder
	-- the plate on the chest (a lighter rim so the tier reads at a glance)
	local plate = part("Plate", Vector3.new(ts.X * 0.7, ts.Y * 0.5, 0.12), def.Color:Lerp(Color3.new(1, 1, 1), 0.12))
	weldTo(plate, torso, CFrame.new(0, ts.Y * 0.05, -(ts.Z * 0.68 + 0.02)))
	plate.Parent = folder
	if tier >= ArmourConfig.HelmetFromTier and head and head:IsA("BasePart") then
		local hs = head.Size
		local helmet = part("Helmet", Vector3.new(hs.Y * 1.25, hs.Y * 0.6, hs.Y * 1.25), def.Color)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = helmet
		weldTo(helmet, head, CFrame.new(0, hs.Y * 0.3, 0))
		helmet.Parent = folder
	end
	folder.Parent = char
end

function ArmourService.Apply(player: Player)
	if ArmourConfig.Enabled ~= true then
		return
	end
	local profile = DataService and DataService.GetProfile(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if profile == nil or char == nil or hum == nil or hum.Health <= 0 then
		return
	end
	local tier = tierOf(player)
	-- claude-bud JOB 36: Double HP (WE_PerkDoubleHP, server-set by ShopOverhaulService from pass ownership) doubles the base
	local hpMult = if player:GetAttribute("WE_PerkDoubleHP") == true then (require(Shared.Configs.ShopOverhaulConfig) :: any).DoubleHP.Mult else 1
	local mx = math.floor(ArmourService.MaxHealthFor(tier) * hpMult + 0.5)
	-- claude-bud JOB 39: Combat Medicine (+10 max HP a level) on the BASE, before Double HP and armour; the effective HP
	-- is hard-capped at EndgameConfig.Hospital.MaxEffectiveHp (0 bonus while the Hospital part is not live = unchanged)
	local okM, EGS = pcall(function(): any
		return require(script.Parent.EndgameService)
	end)
	local med = if okM and EGS and EGS.MedicineBonus then EGS.MedicineBonus(player) else 0
	if med > 0 then
		local b = baseHp()
		mx = math.min(math.floor(mx * (b + med) / b + 0.5), (require(Shared.Configs.EndgameConfig) :: any).Hospital.MaxEffectiveHp)
	end
	if hum.MaxHealth ~= mx then
		local ratio = if hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
		hum.MaxHealth = mx
		hum.Health = math.max(1, math.floor(mx * ratio + 0.5))
	end
	player:SetAttribute("WE_ArmourTier", tier)
	player:SetAttribute("WE_ArmourBaseHP", math.floor(baseHp() * hpMult + 0.5)) -- JOB 36: the doubled base is not armour
	player:SetAttribute("WE_ArmourPct", math.floor(ArmourService.ReductionFor(tier) * 100 + 0.5))
	player:SetAttribute("WE_ArmourLookOff", if lookOff(profile) then true else nil)
	dressLook(char, tier, lookOff(profile))
end

local function inOwnPlot(player: Player, profile: any): boolean
	local plotId = tonumber(profile.BasePlotId)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = if plotId then PlotFrame.PlotPosition(plotId) else nil
	if pos == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	local loc = PlotFrame.PlotCFrame(pos):PointToObjectSpace(root.Position)
	local half = (BaseConfig :: any).PlotSize * 0.5
	return math.abs(loc.X) <= half.X + 10 and math.abs(loc.Z) <= half.Z + 10
end

local function notify(player: Player, text: string, kind: string)
	if NotificationService then
		pcall(NotificationService.Notify, player, text, kind)
	end
end

function ArmourService.Buy(player: Player, tier: any): (boolean, string?)
	if ArmourConfig.Enabled ~= true then
		return false, "Off"
	end
	local profile = DataService and DataService.GetProfile(player)
	if profile == nil or typeof(tier) ~= "number" or tier ~= math.floor(tier) then
		return false, "Bad"
	end
	local def = ArmourConfig.Tiers[tier]
	if def == nil or tier ~= tierOf(player) + 1 then
		return false, "Order"
	end
	local cc = tonumber(typeof(profile.BaseUpgrades) == "table" and profile.BaseUpgrades.CommandCenter or 0) or 0
	if cc < def.NeedCommandCenter then
		return false, "NeedCC"
	end
	if ArmourConfig.InBaseOnly and not inOwnPlot(player, profile) then
		return false, "NotInBase"
	end
	-- the Cash path is the one research purchase (PersonalArmour, ServiceOnly): the price, spend, save and purchase XP
	local rs = ResearchService
	if rs == nil or rs.PurchaseViaService == nil then
		return false, "Off"
	end
	local ok, err = rs.PurchaseViaService(player, "PersonalArmour")
	if not ok then
		return false, if err == "InsufficientCash" then "Cash" else tostring(err)
	end
	ArmourService.Apply(player)
	notify(player, string.format("ARMOUR EQUIPPED - you take %d%% less damage.", math.floor(ArmourService.ReductionFor(tier) * 100 + 0.5)), "Reward")
	return true, nil
end

local REFUSAL: { [string]: string } = {
	Order = "Buy the armour tiers in order.",
	NeedCC = "Upgrade your Command Center first.",
	NotInBase = "Buy armour inside your base.",
	Cash = "Not enough cash.",
}

function ArmourService.Init(deps: { [string]: any })
	DataService = deps.DataService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	ResearchService = deps.ResearchService
	if ArmourConfig.Enabled ~= true then
		return
	end
	local buy = RemoteSetup.Get(Constants.RemoteNames.RequestBuyArmour) :: RemoteEvent
	buy.OnServerEvent:Connect(function(player: Player, tier: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestBuyArmour", tier) then -- claude-bud JOB 15 gate
			return
		end
		if RateLimitService and not RateLimitService.Allow(player, "buy_armour", 1, 3) then
			return
		end
		local ok, why = ArmourService.Buy(player, tier)
		if not ok and why and REFUSAL[why] then
			notify(player, REFUSAL[why], "Warn")
		end
	end)
	local look = RemoteSetup.Get(Constants.RemoteNames.RequestArmourLook) :: RemoteEvent
	look.OnServerEvent:Connect(function(player: Player, off: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestArmourLook", off) then -- claude-bud JOB 15 gate
			return
		end
		if typeof(off) ~= "boolean" or (RateLimitService and not RateLimitService.Allow(player, "armour_look", 1, 3)) then
			return
		end
		local profile = DataService.GetProfile(player)
		if profile == nil then
			return
		end
		if typeof(profile.Settings) ~= "table" then
			profile.Settings = {}
		end
		profile.Settings.HideArmourLook = off
		DataService.MarkDirty(player)
		ArmourService.Apply(player)
	end)
	local function onCharacter(player: Player)
		-- after CombatService sets PlayerMaxHealth for the new life (it runs on the same signal)
		task.delay(0.5, function()
			for _ = 1, 20 do
				if DataService.GetProfile(player) then
					ArmourService.Apply(player)
					return
				end
				task.wait(1)
			end
		end)
	end
	local function onPlayer(p: Player)
		p.CharacterAdded:Connect(function()
			onCharacter(p)
		end)
		if p.Character then
			onCharacter(p)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
end

return ArmourService
