--!strict
--[[ claude-bud JOB 53: the Defence upgrades you can SEE.

	EndgameConfig.Defence levels (profile.Endgame.Defence.{Plating, Guns, Gate, Vault}, saved) used to change numbers
	only. This module dresses the base defences by VISUAL TIER (EndgameConfig.DefenceVisualTier: L1-3 = 1, L4-6 = 2,
	L7-9 = 3, L10 = 4):
	  * Plating -> armour plates round each turret nest (side plates -> front shield -> dark steel -> gold-edged ring)
	  * Guns    -> ammo crates + a shell rack beside each nest (more and heavier with the tier)
	  * Gate    -> steel bands / corner plates / a top beam on the gate leaves, plus the leaves' colour by tier
	  * Vault   -> plating round the plot's money collector (corner brackets -> side plates -> cage -> armour cap)
	and shows the gate's DAMAGE STATE (EndgameConfig.GateDamageStage: >60 % clean, <=60 % scorched + dents, <=30 %
	plates sag + smoke, breached = the reinforcement is gone).

	Rules: plain Parts only, Anchored, CanCollide / CanQuery / CanTouch false (they never block a shot, a raycast or a
	walk), no Neon, no lights, CastShadow false on small bits, at most DefenceVisuals.MaxParts per piece. Everything
	is parented inside the plot's WE_GateDefense folder (GateDefenseService.syncPlotNow), so every SyncPlot / rejoin /
	restart rebuilds it from the SAVED levels and nothing is left behind. OFF (EndgameConfig.DefenceVisualsLive) =
	nothing is built. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndgameConfig: any = require(Shared.Configs.EndgameConfig)

local DefenceVisuals = {}

local M = Enum.Material
local C = {
	Steel = Color3.fromRGB(92, 96, 100),
	SteelDark = Color3.fromRGB(46, 49, 54),
	Olive = Color3.fromRGB(78, 86, 58),
	Crate = Color3.fromRGB(104, 84, 52),
	Brass = Color3.fromRGB(176, 140, 64),
	Gold = Color3.fromRGB(200, 160, 60),
	Hazard = Color3.fromRGB(210, 170, 40),
	Scorch = Color3.fromRGB(34, 30, 28),
}
-- the gate leaf colour / material per Gate tier (0 = the old look, which setGateBarrierOpen restores)
type Look = { Color: Color3, Mat: Enum.Material }
local LEAF: { [number]: Look } = {
	[0] = { Color = Color3.fromRGB(55, 58, 62), Mat = M.Metal },
	[1] = { Color = Color3.fromRGB(70, 74, 78), Mat = M.Metal },
	[2] = { Color = Color3.fromRGB(62, 66, 70), Mat = M.DiamondPlate },
	[3] = { Color = Color3.fromRGB(44, 47, 52), Mat = M.DiamondPlate },
	[4] = { Color = Color3.fromRGB(34, 36, 40), Mat = M.DiamondPlate },
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 6
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function group(parent: Instance, name: string, track: string, tier: number): Model
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("WE_DefenceTrack", track)
	m:SetAttribute("WE_DefenceTier", tier)
	m.Parent = parent
	return m
end

-- ── turrets ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- Plating: armour round the nest at `at` (the gun's base CFrame; its -Z faces out). Static: the gun turns inside it.
function DefenceVisuals.TurretPlating(at: CFrame, tier: number, parent: Instance): Model?
	if tier < 1 then
		return nil
	end
	local m = group(parent, "DefVis_Plating", "Plating", tier)
	local col = if tier >= 3 then C.SteelDark else C.Steel
	local mat = if tier >= 2 then M.DiamondPlate else M.Metal
	local h = 1.6 + 0.3 * tier
	for _, sx in ipairs({ -1, 1 }) do -- T1: two side plates
		part(m, "SidePlate", Vector3.new(0.35, h, 2.6), at * CFrame.new(2.5 * sx, h / 2, 0) * CFrame.Angles(0, math.rad(12 * sx), 0), col, mat)
	end
	if tier >= 2 then -- T2: a front shield with a sight slit
		part(m, "FrontShieldL", Vector3.new(1.5, h, 0.35), at * CFrame.new(-1.3, h / 2, -2.4), col, mat)
		part(m, "FrontShieldR", Vector3.new(1.5, h, 0.35), at * CFrame.new(1.3, h / 2, -2.4), col, mat)
	end
	if tier >= 3 then -- T3: rear plates + a hazard band (a dark steel ring)
		part(m, "RearPlate", Vector3.new(3.6, h * 0.7, 0.35), at * CFrame.new(0, h * 0.35, 2.4), col, mat)
		part(m, "HazardBand", Vector3.new(5.2, 0.25, 0.4), at * CFrame.new(0, h - 0.15, -2.4), C.Hazard, M.SmoothPlastic)
	end
	if tier >= 4 then -- T4: gold-edged caps on every plate
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "GoldCap", Vector3.new(0.45, 0.2, 2.7), at * CFrame.new(2.5 * sx, h + 0.1, 0) * CFrame.Angles(0, math.rad(12 * sx), 0), C.Gold, M.Metal)
		end
		part(m, "GoldCapFront", Vector3.new(4.2, 0.2, 0.45), at * CFrame.new(0, h + 0.1, -2.4), C.Gold, M.Metal)
	end
	return m
end

-- Guns: ammo beside the nest (crates, then a shell rack, then a heavy ammo box with brass rounds on top)
function DefenceVisuals.TurretGuns(at: CFrame, tier: number, parent: Instance): Model?
	if tier < 1 then
		return nil
	end
	local m = group(parent, "DefVis_Guns", "Guns", tier)
	part(m, "AmmoCrate1", Vector3.new(1.4, 0.9, 1), at * CFrame.new(3.6, 0.45, 1.2), C.Olive, M.Wood)
	if tier >= 2 then
		part(m, "AmmoCrate2", Vector3.new(1.4, 0.9, 1), at * CFrame.new(3.6, 1.35, 1.2), C.Olive, M.Wood)
		part(m, "ShellRack", Vector3.new(0.3, 1.4, 1.8), at * CFrame.new(-3.7, 0.7, 1), C.SteelDark, M.Metal)
	end
	if tier >= 3 then
		part(m, "HeavyAmmoBox", Vector3.new(1.8, 1, 1.2), at * CFrame.new(-3.6, 0.5, 2.6), C.Crate, M.Wood)
		part(m, "Rounds", Vector3.new(1.5, 0.3, 0.9), at * CFrame.new(-3.6, 1.15, 2.6), C.Brass, M.Metal)
	end
	if tier >= 4 then
		part(m, "BeltFeed", Vector3.new(0.5, 0.25, 2.2), at * CFrame.new(1.9, 1.1, 1.4), C.Brass, M.Metal)
		part(m, "StencilBand", Vector3.new(1.45, 0.2, 1.05), at * CFrame.new(3.6, 1.9, 1.2), C.Hazard, M.SmoothPlastic)
	end
	return m
end

-- ── the gate ────────────────────────────────────────────────────────────────────────────────────────────────────
-- the reinforcement on both leaves (+ the leaves' tier colour, saved as attributes so setGateBarrierOpen restores it)
function DefenceVisuals.Gate(leaves: { BasePart }, tier: number, parent: Instance): Model?
	local look = LEAF[math.clamp(tier, 0, 4)]
	for _, leaf in ipairs(leaves) do
		if tier >= 1 then
			leaf.Color = look.Color
			leaf.Material = look.Mat
			leaf:SetAttribute("WE_DefColor", look.Color)
			leaf:SetAttribute("WE_DefMaterial", look.Mat.Name)
		end
	end
	if tier < 1 or #leaves == 0 then
		return nil
	end
	local m = group(parent, "DefVis_Gate", "Gate", tier)
	for i, leaf in ipairs(leaves) do
		local s = leaf.Size
		local cf = leaf.CFrame
		local face = s.Z / 2 + 0.12
		for _, fz in ipairs({ -1, 1 }) do -- both faces (inside / outside)
			-- T1: two horizontal steel bands
			for _, fy in ipairs({ -0.3, 0.3 }) do
				part(m, "Band", Vector3.new(s.X * 0.96, 0.45, 0.22), cf * CFrame.new(0, s.Y * fy, face * fz), C.SteelDark, M.Metal)
			end
			if tier >= 2 and fz == 1 then -- T2: corner plates (outside face)
				for _, fx in ipairs({ -1, 1 }) do
					part(m, "CornerPlate", Vector3.new(0.9, 0.9, 0.2), cf * CFrame.new(fx * (s.X / 2 - 0.5), s.Y / 2 - 0.5, face * fz), C.Steel, M.Metal)
				end
			end
		end
		if tier >= 3 then -- T3: a diagonal brace (outside)
			local len = math.sqrt(s.X ^ 2 + s.Y ^ 2) * 0.85
			part(m, "Brace", Vector3.new(0.35, len, 0.2), cf * CFrame.new(0, 0, face) * CFrame.Angles(0, 0, math.atan2(s.X, s.Y) * (if i == 1 then 1 else -1)), C.SteelDark, M.Metal)
		end
		-- the damage-state dents (hidden until the stage asks; DefenceVisuals.GateDamage)
		part(m, "Dent1_" .. i, Vector3.new(s.X * 0.4, s.Y * 0.25, 0.15), cf * CFrame.new(s.X * 0.15, -s.Y * 0.1, -face), C.Scorch, M.Slate).Transparency = 1
		part(m, "Dent2_" .. i, Vector3.new(s.X * 0.5, s.Y * 0.3, 0.15), cf * CFrame.new(-s.X * 0.1, s.Y * 0.2, -face), C.Scorch, M.Slate).Transparency = 1
	end
	if tier >= 4 and #leaves >= 2 then -- T4: one top beam across both leaves with a gold edge
		local a, b = leaves[1], leaves[2]
		local mid = a.CFrame.Rotation + (a.Position + b.Position) / 2
		local w = (a.Position - b.Position).Magnitude + a.Size.X
		part(m, "TopBeam", Vector3.new(w, 0.8, a.Size.Z + 0.6), mid * CFrame.new(0, a.Size.Y / 2 + 0.4, 0), C.SteelDark, M.DiamondPlate)
		part(m, "TopBeamGold", Vector3.new(w, 0.18, a.Size.Z + 0.7), mid * CFrame.new(0, a.Size.Y / 2 + 0.85, 0), C.Gold, M.Metal)
	end
	return m
end

--[[ The gate's damage state (called from GateDefenseService.updateGateBillboard, the one funnel every damage / regen /
	rebuild / breach goes through). Stage = EndgameConfig.GateDamageStage(frac, breached): 0 clean, 1 dents + scorched
	(<= 60 %), 2 + sagging bands + smoke (<= 30 %), 3 breached (the reinforcement is hidden, smoke). Only a stage CHANGE
	touches anything (WE_GateDmgStage on leaf 1). Works with no tier visuals too (the smoke + the leaf scorch). ]]
function DefenceVisuals.GateDamage(leaves: { BasePart }, frac: number, breached: boolean): number?
	local first: BasePart? = leaves[1]
	if first == nil or first.Parent == nil then
		return nil
	end
	local stage = EndgameConfig.GateDamageStage(frac, breached)
	if first:GetAttribute("WE_GateDmgStage") == stage then
		return stage
	end
	first:SetAttribute("WE_GateDmgStage", stage)
	local vis = first.Parent:FindFirstChild("DefVis_Gate")
	if vis then
		for _, p in ipairs(vis:GetChildren()) do
			if p:IsA("BasePart") then
				local dent = string.sub(p.Name, 1, 4) == "Dent"
				if dent then
					local n = tonumber(string.sub(p.Name, 5, 5)) or 1
					p.Transparency = if stage >= 3 then 1 elseif stage >= n then 0 else 1
				else
					p.Transparency = if stage >= 3 then 1 else 0
					local sag = p:GetAttribute("WE_SagFrom")
					if stage == 2 and p.Name == "Band" and sag == nil then
						p:SetAttribute("WE_SagFrom", p.CFrame)
						p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(7))
					elseif stage ~= 2 and typeof(sag) == "CFrame" then
						p.CFrame = sag
						p:SetAttribute("WE_SagFrom", nil)
					end
				end
			end
		end
	end
	-- the smoke (one capped emitter on leaf 1)
	local smoke = first:FindFirstChild("WE_GateSmoke")
	if stage >= 2 and smoke == nil then
		local e = Instance.new("ParticleEmitter")
		e.Name = "WE_GateSmoke"
		e.Rate = tonumber(EndgameConfig.DefenceVisuals.SmokeRate) or 4
		e.Lifetime = NumberRange.new(1.6, 2.4)
		e.Speed = NumberRange.new(1.5, 3)
		e.SpreadAngle = Vector2.new(20, 20)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(60, 58, 56))
		e.LightEmission = 0
		e.Parent = first
	elseif stage < 2 and smoke then
		smoke:Destroy()
	end
	-- the leaves' scorch at stage 1-2 (the breached look is setGateBarrierOpen's)
	if stage <= 2 then
		for _, leaf in ipairs(leaves) do
			local base = leaf:GetAttribute("WE_DefColor")
			local c: Color3 = if typeof(base) == "Color3" then base else LEAF[0].Color
			leaf.Color = if stage >= 1 then c:Lerp(C.Scorch, if stage == 1 then 0.35 else 0.6) else c
		end
	end
	return stage
end

-- ── the vault (the plot's money collector) ───────────────────────────────────────────────────────────────────────
function DefenceVisuals.Vault(collector: Instance?, tier: number, parent: Instance): Model?
	if tier < 1 or collector == nil then
		return nil
	end
	local cf: CFrame, size: Vector3
	if collector:IsA("BasePart") then
		cf, size = collector.CFrame, collector.Size
	elseif collector:IsA("Model") then
		cf, size = collector:GetBoundingBox()
	else
		local body = collector:FindFirstChild("CollectorBody")
		if body == nil or not body:IsA("BasePart") then
			return nil
		end
		cf, size = body.CFrame, body.Size
	end
	local m = group(parent, "DefVis_Vault", "Vault", tier)
	local hx, hz, hy = size.X / 2 + 0.25, size.Z / 2 + 0.25, size.Y / 2
	local col = if tier >= 3 then C.SteelDark else C.Steel
	for _, sx in ipairs({ -1, 1 }) do -- T1: four corner brackets
		for _, sz in ipairs({ -1, 1 }) do
			part(m, "Bracket", Vector3.new(0.4, size.Y * 0.9, 0.4), cf * CFrame.new(hx * sx, 0, hz * sz), col, M.Metal)
		end
	end
	if tier >= 2 then -- T2: side plates
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "SidePlate", Vector3.new(0.2, size.Y * 0.6, size.Z * 0.8), cf * CFrame.new(hx * sx, -hy * 0.2, 0), col, M.DiamondPlate)
		end
	end
	if tier >= 3 then -- T3: a top cage frame
		part(m, "CageFront", Vector3.new(size.X + 0.6, 0.3, 0.3), cf * CFrame.new(0, hy + 0.15, -hz), C.SteelDark, M.Metal)
		part(m, "CageBack", Vector3.new(size.X + 0.6, 0.3, 0.3), cf * CFrame.new(0, hy + 0.15, hz), C.SteelDark, M.Metal)
	end
	if tier >= 4 then -- T4: an armour cap with a gold edge
		part(m, "ArmourCap", Vector3.new(size.X + 0.7, 0.35, size.Z + 0.7), cf * CFrame.new(0, hy + 0.45, 0), C.SteelDark, M.DiamondPlate)
		part(m, "CapGold", Vector3.new(size.X + 0.8, 0.12, size.Z + 0.8), cf * CFrame.new(0, hy + 0.68, 0), C.Gold, M.Metal)
	end
	return m
end

--[[ Apply every track for one plot (GateDefenseService.syncPlotNow, after the turrets + gate exist). levels = the
	owner's saved Defence levels (EndgameService.DefenceLevelFor: 0 while Defence is not live). Returns the parts
	added (the budget test). ]]
function DefenceVisuals.Apply(ownerUserId: number, levels: { [string]: number }, gunBases: { CFrame }, leaves: { BasePart }, collector: Instance?, parent: Instance): number
	if not EndgameConfig.DefenceVisualsLive(ownerUserId) then
		return 0
	end
	local before = #parent:GetDescendants()
	local tierOf = EndgameConfig.DefenceVisualTier
	local pT, gT = tierOf(levels.Plating or 0), tierOf(levels.Guns or 0)
	for _, at in ipairs(gunBases) do
		DefenceVisuals.TurretPlating(at, pT, parent)
		DefenceVisuals.TurretGuns(at, gT, parent)
	end
	DefenceVisuals.Gate(leaves, tierOf(levels.Gate or 0), parent)
	DefenceVisuals.Vault(collector, tierOf(levels.Vault or 0), parent)
	return #parent:GetDescendants() - before
end

return DefenceVisuals
