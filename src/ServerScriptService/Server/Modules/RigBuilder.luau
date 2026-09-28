--!strict
--[[
	R-RIG: an animated R6 soldier figure that costs no more parts than today's Part kit.

	BakeTemplate(model, assetId) turns an inserted Roblox R6 character (the Roblox "Soldier" 187790284) into a rig
	template with NO Humanoid (CLAUDE.md catalog rule):
	  • CharacterMesh → a FileMesh SpecialMesh on its limb; BodyColors → limb colours (a Humanoid-free model ignores both);
	  • keeps Torso, Left/Right Arm, Left/Right Leg, the four limb Motor6D and the hat Handle ("Beret" + its weld);
	  • adds RootJoint (Part0 set at attach) and Neck (Part1 set at attach), AnimationController + Animator;
	  • drops HumanoidRootPart, Head, Humanoid, scripts, the gun, AnimSaves, configs, BodyGyro, BodyColors, CharacterMesh.
	Attach(host, template, look) swaps a host's Part-kit body for a clone of the template, in a sub-model "WE_Rig":
	  • the host keeps its HumanoidRootPart (collision, Humanoid root, aim-assist torso; Transparency 1) and Humanoid,
	    both direct children of the host as today;
	  • the kit "Head" (headshot part, face decal), kit "Helmet" (look.Headwear == "KitHelmet", else the Beret), kit
	    "Rifle" and kit "Pack" MOVE INTO WE_Rig: Head on the Neck, Rifle on the right hand (R6 grip), Pack on the Torso.
	    No code at HEAD looks them up as direct children of an NPC / squad / guard host (BuyPathStatic scan R-RIG-H);
	  • limbs take the kit colours (Vest → Torso, ArmL → arms, LegL → legs), so friend / foe colours do not change;
	  • destroys every other kit part and its WeldConstraint; rig parts are Massless, CanCollide / CanTouch false; arms,
	    legs, Head, Helmet, Pack and the Torso (a RigConfig.Hit.TorsoDepth-deep hit box, same look) keep CanQuery;
	  • host Humanoid: BreakJointsOnDeath false, RequiresNeck = RigConfig.Host.RequiresNeck, RigType per
	    RigConfig.Host.RigType ("Keep" = untouched). Whether a Humanoid reads legs or a Neck inside a sub-model is a
	    Studio check (spec §10), not a stand-in result;
	  • tags the rig "WE_Rig" (clients animate it; the server never plays a track).
	Everything is built before the host is touched: any failure returns false and the Part kit stays as it was.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RigConfig = require(ReplicatedStorage.Shared.Configs.RigConfig)

local RigBuilder = {}

RigBuilder.Tag = RigConfig.Tag
RigBuilder.RigName = "WE_Rig"

local LIMBS = { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local LIMB_JOINTS = { "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }
local BODY_PART_OF: { [string]: string } = {
	Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg",
}
local COLOR_OF: { [string]: string } = {
	Torso = "TorsoColor3", ["Left Arm"] = "LeftArmColor3", ["Right Arm"] = "RightArmColor3",
	["Left Leg"] = "LeftLegColor3", ["Right Leg"] = "RightLegColor3",
}
-- R6 joint frames (standard R6 values; the Soldier file stores the same)
local ROOT_ROT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local NECK_C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local GRIP_C0 = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0) -- R6 RightGrip: tool -Z along the arm
local GRIP_C1 = CFrame.new(0, 0, 0.5) -- the hand holds the kit rifle 0.5 behind its centre (muzzle 1.7 ahead)

export type Look = {
	Headwear: string?, -- "Beret" (the Soldier file's hat) | "KitHelmet" (the host kit's own helmet) | "None"
	KeepRifle: boolean?, -- default true
	StaticHoldDeg: number?, -- anchored hosts: right arm raised this much at rest (RigConfig.Anim.StaticHoldDeg; 0 = arm down)
}

local function findPart(root: Instance, name: string): BasePart?
	local p = root:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function motor(name: string, p0: BasePart?, p1: BasePart?, c0: CFrame, c1: CFrame, parent: Instance): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return m
end

local function cosmetic(p: BasePart, query: boolean)
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = query
	p.Massless = true
	p.CastShadow = false
end

-- Inserted R6 character → a Humanoid-free rig template (unparented), or nil + reason. `model` is consumed.
function RigBuilder.BakeTemplate(model: Model, assetId: number): (Model?, string?)
	local torso = findPart(model, "Torso")
	if torso == nil then
		return nil, "no Torso"
	end
	local rig = Instance.new("Model")
	rig.Name = "WE_Rig_" .. tostring(assetId)
	local rest = torso.CFrame -- the template is stored with Torso at the origin (identity)
	local parts: { [string]: BasePart } = {}
	for _, n in ipairs(LIMBS) do
		local p = findPart(model, n)
		if p == nil then
			return nil, "no " .. n
		end
		parts[n] = p
	end
	-- the file's own limb joints (C0 / C1), read before anything moves
	local frames: { [string]: { CFrame } } = {}
	for _, jn in ipairs(LIMB_JOINTS) do
		local j = model:FindFirstChild(jn, true)
		if j and j:IsA("Motor6D") and j.Part1 and parts[(j.Part1 :: BasePart).Name] then
			frames[jn] = { j.C0, j.C1 }
		end
	end
	local jointsFound = 0
	for _ in pairs(frames) do
		jointsFound += 1
	end
	if jointsFound ~= 4 then
		return nil, string.format("%d of 4 limb joints", jointsFound)
	end
	-- the limbs move into the rig with no joints, welds, decals or old meshes of their own
	for _, p in pairs(parts) do
		for _, c in ipairs(p:GetChildren()) do
			c:Destroy()
		end
		p.Parent = rig
	end
	for _, jn in ipairs(LIMB_JOINTS) do
		local limbName = string.gsub(string.gsub(jn, "Shoulder", "Arm"), "Hip", "Leg")
		motor(jn, parts.Torso, parts[limbName], frames[jn][1], frames[jn][2], parts.Torso)
	end
	-- BodyColors / CharacterMesh do nothing without a Humanoid: bake them onto the parts
	local bc = model:FindFirstChildWhichIsA("BodyColors", true)
	for n, prop in pairs(COLOR_OF) do
		if bc then
			parts[n].Color = (bc :: any)[prop]
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("CharacterMesh") then
			local limbName = BODY_PART_OF[d.BodyPart.Name]
			local limb = if limbName then parts[limbName] else nil
			if limb and d.MeshId > 0 then
				for _, old in ipairs(limb:GetChildren()) do
					if old:IsA("DataModelMesh") or old:IsA("Decal") then
						old:Destroy()
					end
				end
				local sm = Instance.new("SpecialMesh")
				sm.MeshType = Enum.MeshType.FileMesh
				sm.MeshId = "rbxassetid://" .. tostring(d.MeshId)
				if d.BaseTextureId > 0 then
					sm.TextureId = "rbxassetid://" .. tostring(d.BaseTextureId)
				end
				sm.Parent = limb
			end
		end
	end
	-- the hat: its Handle becomes "Beret" (SpecialMesh kept), welded to the head at attach
	local hat = model:FindFirstChildWhichIsA("Accoutrement", true)
	local handle = if hat then hat:FindFirstChild("Handle") else nil
	if handle and handle:IsA("BasePart") then
		local hw = model:FindFirstChild("HeadWeld", true)
		handle.Name = "Beret"
		for _, c in ipairs(handle:GetChildren()) do
			if not c:IsA("DataModelMesh") then
				c:Destroy()
			end
		end
		handle.Parent = rig
		parts.Beret = handle
		local w = Instance.new("Weld")
		w.Name = "HeadwearWeld"
		w.Part0 = nil -- the host head, at attach
		w.Part1 = handle
		if hw and hw:IsA("Weld") then
			w.C0, w.C1 = hw.C0, hw.C1
		else
			w.C0, w.C1 = CFrame.new(0, 0.5, 0), CFrame.new()
		end
		w.Parent = handle
	end
	-- rest pose around Torso at the origin (the engine re-solves the joints anyway once parented)
	for n, p in pairs(parts) do
		p.CFrame = rest:ToObjectSpace(p.CFrame)
		cosmetic(p, n == "Left Arm" or n == "Right Arm" or n == "Left Leg" or n == "Right Leg")
		p.Anchored = true -- template only
	end
	motor("RootJoint", nil, parts.Torso, ROOT_ROT, ROOT_ROT, rig) -- Part0 = host HumanoidRootPart at attach
	motor("Neck", parts.Torso, nil, NECK_C0, NECK_C0 * CFrame.new(0, -1.5, 0), parts.Torso) -- C1 re-fit at attach
	local ac = Instance.new("AnimationController")
	ac.Name = "AnimationController"
	ac.Parent = rig
	local animator = Instance.new("Animator")
	animator.Parent = ac
	rig.PrimaryPart = parts.Torso
	model:Destroy()
	-- the catalog rule: no Humanoid, <= 40 parts (checked again by VisualAssetService)
	return rig, nil
end

-- relink joints by part name inside a fresh clone (never depends on how Clone remaps references)
local function relink(rig: Model)
	local byName: { [string]: BasePart } = {}
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			byName[d.Name] = d
		end
	end
	for _, jn in ipairs(LIMB_JOINTS) do
		local j = rig:FindFirstChild(jn, true)
		if j and j:IsA("Motor6D") then
			j.Part0 = byName.Torso
			local limb = string.gsub(string.gsub(jn, "Shoulder", "Arm"), "Hip", "Leg")
			j.Part1 = byName[limb]
		end
	end
	return byName
end

-- the kit parts a rig keeps; every other BasePart child of the host (except its root) goes
local KEEP_KIT = { Head = true, Helmet = true, Rifle = true, Pack = true }

-- Swaps the host's Part-kit body for a rig clone. Returns true when attached (the kit is then gone), false when
-- nothing changed.
function RigBuilder.Attach(host: Model, template: Model, look: Look?): boolean
	local root = host.PrimaryPart or host:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	if host:FindFirstChild(RigBuilder.RigName) then
		return false -- already rigged
	end
	local lk: Look = look or {}
	local headwear = lk.Headwear or "Beret"
	local kit: { [string]: BasePart? } = {}
	local drop: { BasePart } = {}
	for _, c in ipairs(host:GetChildren()) do
		if c:IsA("BasePart") and c ~= root then
			if KEEP_KIT[c.Name] and kit[c.Name] == nil then
				kit[c.Name] = c
			else
				table.insert(drop, c)
			end
		end
	end
	local colorOf = function(name: string, fallback: Color3): Color3
		for _, c in ipairs(drop) do
			if c.Name == name then
				return c.Color
			end
		end
		return fallback
	end
	local rootColor = root.Color
	local torsoColor = colorOf("Vest", rootColor)
	local armColor = colorOf("ArmL", rootColor)
	local legColor = colorOf("LegL", rootColor)

	-- build off-host first
	local rigOrNil: Model? = template:Clone()
	if rigOrNil == nil then
		return false
	end
	local rig: Model = rigOrNil
	rig.Name = RigBuilder.RigName
	local parts = relink(rig)
	local torso: BasePart? = parts.Torso
	if torso == nil then
		rig:Destroy()
		return false
	end
	local rootJoint = rig:FindFirstChild("RootJoint")
	local neck = rig:FindFirstChild("Neck", true)
	if not (rootJoint and rootJoint:IsA("Motor6D") and neck and neck:IsA("Motor6D")) then
		rig:Destroy()
		return false
	end
	torso.CFrame = root.CFrame -- rest pose: Torso on the root (RootJoint C0 * C1^-1 = identity)
	for _, jn in ipairs(LIMB_JOINTS) do
		local j = rig:FindFirstChild(jn, true)
		if j and j:IsA("Motor6D") and j.Part1 then
			(j.Part1 :: BasePart).CFrame = torso.CFrame * j.C0 * j.C1:Inverse()
		end
	end
	torso.Color = torsoColor
	parts["Left Arm"].Color = armColor
	parts["Right Arm"].Color = armColor
	parts["Left Leg"].Color = legColor
	parts["Right Leg"].Color = legColor
	for _, p in pairs(parts) do
		p.Anchored = false
	end
	rootJoint.Part0 = root

	-- head: the kit head (headshot part + face) on the Neck at its current rest place; else a 1.05 ball
	local head: BasePart? = kit.Head
	if head == nil then
		local h = Instance.new("Part")
		h.Name = "Head"
		h.Shape = Enum.PartType.Ball
		h.Size = Vector3.new(1.05, 1.05, 1.05)
		h.Color = Color3.fromRGB(190, 160, 120)
		h.CFrame = root.CFrame * CFrame.new(0, 1.55, 0)
		head = h
	end
	local headPart = head :: BasePart
	neck.Part1 = headPart
	neck.C1 = headPart.CFrame:Inverse() * (torso.CFrame * neck.C0)

	-- headwear
	local beret = parts.Beret
	if headwear == "KitHelmet" and kit.Helmet then
		if beret then
			beret:Destroy()
		end
	elseif beret then
		local w = beret:FindFirstChild("HeadwearWeld")
		if w and w:IsA("Weld") then
			w.Part0 = headPart
			beret.CFrame = headPart.CFrame * w.C0 * w.C1:Inverse()
		end
		local oldHelmet = kit.Helmet
		if oldHelmet then
			table.insert(drop, oldHelmet)
			kit.Helmet = nil
		end
	end

	-- now change the host: nothing below can fail
	local keptWelds: { [BasePart]: boolean } = {}
	for _, p in pairs(kit) do
		if p then
			keptWelds[p] = true
		end
	end
	for _, d in ipairs(host:GetDescendants()) do
		if d:IsA("WeldConstraint") then
			local p1 = d.Part1
			local p0 = d.Part0
			if (p1 and (keptWelds[p1] or table.find(drop, p1))) or (p0 and (keptWelds[p0] or table.find(drop, p0))) then
				d:Destroy()
			end
		end
	end
	for _, p in ipairs(drop) do
		p:Destroy()
	end
	local function weld(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
		local w = Instance.new("Weld")
		w.Name = name
		w.Part0 = p0
		w.Part1 = p1
		w.C0 = c0
		w.C1 = c1
		w.Parent = p1
	end
	headPart.Parent = rig
	cosmetic(headPart, true) -- the kit head stays the headshot part
	if kit.Helmet and headwear == "KitHelmet" then
		local hm = kit.Helmet
		hm.Parent = rig
		cosmetic(hm, true)
		weld("HeadwearWeld", headPart, hm, headPart.CFrame:Inverse() * hm.CFrame, CFrame.new())
	end
	if kit.Rifle and lk.KeepRifle ~= false then
		local rf = kit.Rifle
		rf.Parent = rig
		cosmetic(rf, false)
		weld("RightGrip", parts["Right Arm"], rf, GRIP_C0, GRIP_C1)
		rf.CFrame = parts["Right Arm"].CFrame * GRIP_C0 * GRIP_C1:Inverse()
	elseif kit.Rifle then
		kit.Rifle:Destroy()
	end
	if kit.Pack then
		local pk = kit.Pack
		pk.Parent = rig
		cosmetic(pk, true)
		weld("PackWeld", torso, pk, torso.CFrame:Inverse() * pk.CFrame, CFrame.new())
	end
	-- hit silhouette (owner R4): the rig Torso is a hit box this deep; its FileMesh ignores the part size (same look)
	local depth = tonumber(RigConfig.Hit.TorsoDepth) or 0
	if depth > 0 then
		torso.Size = Vector3.new(torso.Size.X, torso.Size.Y, depth)
		torso.CanQuery = true
	end
	root.Transparency = 1
	local hum = host:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false -- a dead figure stays in one piece until its builder removes it (0.35 s)
		hum.RequiresNeck = RigConfig.Host.RequiresNeck == true -- the rig Neck can never kill the host (death = Health)
		if RigConfig.Host.RigType == "R15" then
			hum.RigType = Enum.HumanoidRigType.R15 -- Studio fallback: HipHeight absolute, legs never measured
		end
	end
	if root.Anchored then
		rig:SetAttribute("WE_RigStatic", true)
		-- a base statue never loads a track: bake the Hold keyframe (right arm forward) into the shoulder's rest pose
		local rs = torso:FindFirstChild("Right Shoulder")
		if rs and rs:IsA("Motor6D") and (lk.StaticHoldDeg or 0) ~= 0 then
			rs.C0 = rs.C0 * CFrame.Angles(0, 0, math.rad(lk.StaticHoldDeg :: number))
		end
	end
	-- hit routing: attributes the host set on its root (GateDefenseService guards: GateBarrier / GateGuardPart / PlotId)
	-- go onto every rig part a ray can hit, whatever order the host's own DescendantAdded marking runs in
	local rootAttrs = root:GetAttributes()
	if next(rootAttrs) ~= nil then
		for _, d in ipairs(rig:GetDescendants()) do -- one 9-part body, once at spawn
			if d:IsA("BasePart") and d.CanQuery then
				for k, v in pairs(rootAttrs) do
					d:SetAttribute(k, v)
				end
			end
		end
	end
	CollectionService:AddTag(rig, RigBuilder.Tag)
	rig.Parent = host
	return true
end

return RigBuilder
