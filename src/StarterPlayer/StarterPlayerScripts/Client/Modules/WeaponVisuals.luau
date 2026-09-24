--!strict
--[[
	WeaponVisuals (W2 CC-3, contracts §5.2): every combat visual and sound on the client. Cosmetic only: the server
	decides every hit (CombatService); nothing here sends anything to the server.
	Numbers: HudConfig.CombatFx (caps, anims, sizes). Sounds: SoundConfig.Weapons / CombatCues via AudioController.
	Guns: WeaponConfig.Visual (Part kit) or, when WeaponConfig.VisualAssetId > 0 and the server's WeaponAssetLoader
	made it, the template ReplicatedStorage.WE_WeaponTemplates["Weapon_<Id>"] (FindFirstChild only, never a wait).
	Adapted from the Roblox Weapons Kit's behaviours (G-a): no kit code, no kit assets.

	API
	  Init()                                     idempotent; binds WeaponFx, tracks WE_GunOut / WE_ShieldUntil
	  SetLocalWeapon(weaponId?, drawn)           builds / clears the local gun, plays / stops the hold animation
	  LocalShot(weaponId, origin, dir, hitPos?, hitInst?, hitNormal?)
	                                             predicted muzzle flash, fire sound, tracer, impact, bullet hole, casing
	  PlayReload(weaponId)                       reload animation + sound (local player)
	  Cue(name)                                  a SoundConfig.CombatCues key at the local character ("Empty", ...)
	  OnHitFeedback(payload)                     hit / kill / headshot sound, damage number, target bar, haptic
	  MuzzleWorldPosition() -> Vector3?          where the local tracers start
	  Stats()                                    live counts (tests); never above the caps

	PHONE BUDGET (HudConfig.CombatFx; touch in brackets)
	  tracers      Beams between pooled Terrain attachments, 0 parts, Tracers.Max 16 [10]
	  impacts      pooled Attachment + ParticleEmitter (Rate 0, Emit only), 0 parts, Impacts.Max 12 [8]
	  explosions   3 [2] pooled Attachment + ParticleEmitters, 0 parts
	  parts        bullet holes 20 [10] + projectile bodies 6 x 3 [4 x 3] + casings 8 [0] <= MaxFxParts 48 [24];
	               pooled, parked far away (never reparented) and DESTROYED after 20 s without use (gone < 25 s)
	  muzzle flash a ParticleEmitter on the gun's Muzzle (no lights)
	  remote guns  other players' drawn guns: the first CoreParts (5) parts, nearest RemoteGuns.Max 6 [3] within 120
	No per-frame work unless a projectile flies (one Heartbeat step over <= 6 bodies); the sweeper runs at 20 Hz only
	while something is live; remote guns and shield bubbles at 2 Hz. Other characters are tracked by signals.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local HapticService = game:GetService("HapticService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local SoundConfig = require(Shared.Configs.SoundConfig)
local CombatFeelConfig = require(Shared.Configs.CombatFeelConfig)
local AudioController = require(script.Parent.AudioController)
local HudLayout = require(script.Parent.HudLayout)
local CameraFx = require(script.Parent.CameraFx)

local WeaponVisuals = {}

local FX = HudConfig.CombatFx
local player = Players.LocalPlayer

local PARK_CF = CFrame.new(0, 10000, 0) -- "moved far away": pooled parts rest here, never reparented
local IDLE_DESTROY_SECONDS = 20 -- a part pool unused this long is destroyed (every FX part gone within 25 s)
local SWEEP_HZ = 20
local SLOW_HZ = 2
local TEMPLATE_FOLDER = "WE_WeaponTemplates"
local GUN_NAME = "WE_Gun"
local BUBBLE_NAME = "WE_ShieldBubble"
local DRAWN_ATTR = CombatFeelConfig.Drawn.Attribute -- "WE_GunOut"
local SHIELD_ATTR = CombatFeelConfig.ShieldAttribute -- "WE_ShieldUntil"
local DMG_ATTR = CombatFeelConfig.DamageNumbersAttribute -- "WE_ShowDamageNumbers"
local FX_POLL_SECONDS = 0.5
local FX_POLL_MAX_SECONDS = 120
local TEX_FLASH = "rbxasset://textures/particles/sparkles_main.dds" -- engine files in every client (shortlist §3.6)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

local initialized = false
local isTouch = false
local rng = Random.new()

-- caps (set by Init from the device)
local TRACER_MAX = 16
local IMPACT_MAX = 12
local IMPACT_EMIT = 8
local BLAST_MAX = 3
local HOLE_MAX = 20
local PROJ_MAX = 6
local PROJ_PARTS = 3
local CASING_MAX = 8
local CASINGS_ON = true
local PART_CAP = 48
local REMOTE_MAX = 6
local DMG_MAX = 4

local function clock(): number
	return os.clock()
end

---------------------------------------------------------------------------------------------------------------
-- Part-kit guns (generic shapes, <= 12 parts each, no real-world silhouettes). Handle space: -Z = barrel
-- (forward), +Y = up; the Handle is the grip. The FIRST FiveParts are the remote "core" LOD.
---------------------------------------------------------------------------------------------------------------

type PartSpec = { N: string, S: Vector3, C: CFrame, Col: Color3, M: Enum.Material?, Cyl: boolean? }
type KitSpec = { Parts: { PartSpec }, Muzzle: Vector3, Eject: Vector3?, Flash: number }

local GUNMETAL = Color3.fromRGB(46, 48, 52)
local DARK = Color3.fromRGB(26, 27, 30)
local OLIVE = Color3.fromRGB(78, 88, 60)
local TAN = Color3.fromRGB(152, 130, 94)
local STEEL = Color3.fromRGB(96, 100, 106)
local GREEN = Color3.fromRGB(62, 78, 52)
local METAL = Enum.Material.Metal
local CYL = CFrame.Angles(0, math.rad(90), 0) -- a Cylinder's axis (X) along the barrel (Z)

local function P(n: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, col: Color3, m: Enum.Material?, rx: number?, cyl: boolean?): PartSpec
	local c = CFrame.new(x, y, z)
	if rx then
		c *= CFrame.Angles(math.rad(rx), 0, 0)
	end
	if cyl then
		c *= CYL
	end
	return { N = n, S = Vector3.new(sx, sy, sz), C = c, Col = col, M = m, Cyl = cyl }
end

local KITS: { [string]: KitSpec } = {
	Rifle = {
		Parts = {
			P("Handle", 0.2, 0.55, 0.28, 0, 0, 0, DARK),
			P("Receiver", 0.28, 0.42, 1.5, 0, 0.42, -0.35, GUNMETAL, METAL),
			P("Barrel", 0.12, 0.12, 1.2, 0, 0.5, -1.7, STEEL, METAL),
			P("Stock", 0.24, 0.4, 0.9, 0, 0.36, 0.85, OLIVE),
			P("Magazine", 0.2, 0.62, 0.3, 0, 0.02, -0.62, DARK, nil, -10),
			P("Handguard", 0.26, 0.26, 0.75, 0, 0.46, -1.35, OLIVE),
			P("Rail", 0.1, 0.12, 0.7, 0, 0.68, -0.4, DARK, METAL),
			P("FrontPost", 0.06, 0.2, 0.06, 0, 0.62, -1.9, DARK, METAL),
		},
		Muzzle = Vector3.new(0, 0.5, -2.32),
		Eject = Vector3.new(0.16, 0.5, -0.3),
		Flash = 0.9,
	},
	Carbine = {
		Parts = {
			P("Handle", 0.2, 0.55, 0.28, 0, 0, 0, DARK),
			P("Receiver", 0.28, 0.44, 1.3, 0, 0.42, -0.3, DARK, METAL),
			P("Barrel", 0.12, 0.12, 0.9, 0, 0.5, -1.4, STEEL, METAL),
			P("Stock", 0.12, 0.34, 0.8, 0, 0.38, 0.72, DARK, METAL),
			P("Magazine", 0.2, 0.66, 0.3, 0, 0.0, -0.55, TAN, nil, -14),
			P("Handguard", 0.3, 0.3, 0.6, 0, 0.46, -1.1, TAN),
			P("ForeGrip", 0.14, 0.4, 0.16, 0, 0.18, -1.15, DARK),
			P("Optic", 0.16, 0.18, 0.36, 0, 0.72, -0.35, DARK, METAL),
			P("ButtPad", 0.2, 0.44, 0.1, 0, 0.36, 1.16, DARK),
		},
		Muzzle = Vector3.new(0, 0.5, -1.88),
		Eject = Vector3.new(0.16, 0.5, -0.25),
		Flash = 0.85,
	},
	SMG = {
		Parts = {
			P("Handle", 0.2, 0.5, 0.26, 0, 0, 0, DARK),
			P("Receiver", 0.26, 0.4, 1.0, 0, 0.38, -0.2, GUNMETAL, METAL),
			P("Barrel", 0.12, 0.12, 0.45, 0, 0.44, -0.9, STEEL, METAL),
			P("Magazine", 0.16, 0.7, 0.22, 0, -0.05, -0.48, DARK),
			P("Stock", 0.1, 0.26, 0.6, 0, 0.36, 0.55, DARK, METAL),
			P("Sight", 0.08, 0.14, 0.3, 0, 0.64, -0.2, DARK, METAL),
			P("ForeGrip", 0.12, 0.3, 0.14, 0, 0.14, -0.62, DARK),
		},
		Muzzle = Vector3.new(0, 0.44, -1.14),
		Eject = Vector3.new(0.14, 0.44, -0.2),
		Flash = 0.7,
	},
	Pistol = {
		Parts = {
			P("Handle", 0.18, 0.5, 0.26, 0, 0, 0.02, DARK, nil, 12),
			P("Slide", 0.2, 0.22, 0.72, 0, 0.34, -0.2, GUNMETAL, METAL),
			P("Barrel", 0.1, 0.1, 0.12, 0, 0.34, -0.6, STEEL, METAL),
			P("Guard", 0.08, 0.1, 0.24, 0, 0.14, -0.22, DARK),
		},
		Muzzle = Vector3.new(0, 0.34, -0.7),
		Eject = Vector3.new(0.12, 0.38, -0.12),
		Flash = 0.55,
	},
	Shotgun = {
		Parts = {
			P("Handle", 0.2, 0.5, 0.28, 0, 0, 0.04, DARK, nil, 18),
			P("Receiver", 0.28, 0.4, 0.9, 0, 0.4, -0.15, GUNMETAL, METAL),
			P("Barrel", 0.14, 0.14, 1.6, 0, 0.52, -1.35, STEEL, METAL),
			P("Stock", 0.24, 0.42, 1.0, 0, 0.32, 0.85, TAN, nil, -6),
			P("Pump", 0.26, 0.24, 0.55, 0, 0.3, -1.05, TAN),
			P("TubeMag", 0.12, 0.12, 1.3, 0, 0.36, -1.25, DARK, METAL),
			P("Bead", 0.05, 0.08, 0.05, 0, 0.63, -2.1, STEEL, METAL),
		},
		Muzzle = Vector3.new(0, 0.52, -2.17),
		Eject = Vector3.new(0.16, 0.45, -0.1),
		Flash = 1.1,
	},
	LongRifle = {
		Parts = {
			P("Handle", 0.2, 0.52, 0.28, 0, 0, 0.05, DARK, nil, 16),
			P("Body", 0.28, 0.36, 1.6, 0, 0.38, -0.3, GREEN),
			P("Barrel", 0.12, 0.12, 1.8, 0, 0.46, -1.95, STEEL, METAL),
			P("Stock", 0.26, 0.46, 1.1, 0, 0.3, 1.0, GREEN),
			P("Scope", 0.9, 0.2, 0.2, 0, 0.78, -0.35, DARK, METAL, nil, true),
			P("MountA", 0.08, 0.16, 0.08, 0, 0.62, -0.62, DARK, METAL),
			P("MountB", 0.08, 0.16, 0.08, 0, 0.62, -0.08, DARK, METAL),
			P("Bolt", 0.2, 0.06, 0.06, 0.2, 0.46, 0.05, STEEL, METAL),
			P("Magazine", 0.18, 0.3, 0.28, 0, 0.12, -0.45, DARK),
		},
		Muzzle = Vector3.new(0, 0.46, -2.88),
		Eject = Vector3.new(0.16, 0.46, 0.0),
		Flash = 1.0,
	},
	Launcher = {
		Parts = {
			P("Handle", 0.2, 0.5, 0.26, 0, 0, 0, DARK),
			P("Tube", 3.2, 0.42, 0.42, 0, 0.5, -0.4, OLIVE, nil, nil, true),
			P("FrontGrip", 0.16, 0.44, 0.18, 0, 0.12, -1.1, DARK),
			P("Sight", 0.1, 0.26, 0.14, -0.26, 0.72, -0.8, DARK, METAL),
			P("RearCone", 0.4, 0.5, 0.5, 0, 0.5, 1.3, DARK, METAL, nil, true),
			P("Pad", 0.3, 0.2, 0.5, 0, 0.26, 0.55, DARK),
		},
		Muzzle = Vector3.new(0, 0.5, -2.05),
		Eject = nil,
		Flash = 1.4,
	},
	Grenade = {
		Parts = {
			P("Handle", 0.42, 0.5, 0.42, 0, 0, 0, GREEN),
			P("Lever", 0.08, 0.36, 0.12, 0.2, 0.12, 0, STEEL, METAL),
			P("Cap", 0.2, 0.12, 0.2, 0, 0.3, 0, STEEL, METAL),
		},
		Muzzle = Vector3.new(0, 0.3, 0),
		Eject = nil,
		Flash = 0,
	},
}

local HOLD_BY_VISUAL: { [string]: string } = { Pistol = "Pistol", Launcher = "Launcher" }

local function visualKey(def: WeaponConfig.WeaponDef?): string
	local v = if def then def.Visual else nil
	if type(v) == "string" and KITS[v] then
		return v
	end
	return "Rifle"
end

local function flashEmitter(parent: Attachment, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Flash"
	e.Texture = TEX_FLASH
	e.Rate = 0
	e.Lifetime = NumberRange.new(math.max(0.02, tonumber(FX.MuzzleFlashSeconds) or 0.05))
	e.Speed = NumberRange.new(0)
	e.Size = NumberSequence.new(size, size * 0.3)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new(Color3.fromRGB(255, 226, 150), Color3.fromRGB(255, 150, 60))
	e.Rotation = NumberRange.new(0, 360)
	e.LockedToPart = true
	e.ZOffset = 0.5
	e.Parent = parent
	return e
end

type GunRig = {
	Model: Model,
	Handle: BasePart,
	Muzzle: Attachment?,
	Eject: Attachment?,
	Flash: ParticleEmitter?,
	WeaponId: string,
	Parts: number,
}

local function prepPart(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
end

local function buildKit(key: string, maxParts: number): (Model, BasePart, Attachment, Attachment?, number, number)
	local spec = KITS[key] or KITS.Rifle
	local model = Instance.new("Model")
	model.Name = GUN_NAME
	local handle: BasePart? = nil
	local n = 0
	for i, ps in ipairs(spec.Parts) do
		if i > maxParts or i > 12 then
			break
		end
		local p = Instance.new("Part")
		p.Name = if i == 1 then "Handle" else ps.N
		if ps.Cyl then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Size = ps.S
		p.Color = ps.Col
		p.Material = ps.M or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		prepPart(p)
		if i == 1 then
			handle = p
			p.CFrame = CFrame.identity
		else
			p.CFrame = ps.C -- Handle space (the Handle sits at the origin until buildGun moves the whole gun)
			local w = Instance.new("Weld")
			w.Name = "WE_KitWeld"
			w.Part0 = handle
			w.Part1 = p
			w.C0 = ps.C
			w.Parent = p
		end
		p.Parent = model
		n += 1
	end
	local h = handle :: BasePart
	model.PrimaryPart = h
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = spec.Muzzle
	muzzle.Parent = h
	local eject: Attachment? = nil
	if spec.Eject then
		local e = Instance.new("Attachment")
		e.Name = "CasingEject"
		e.Position = spec.Eject
		e.Parent = h
		eject = e
	end
	return model, h, muzzle, eject, n, spec.Flash
end

-- the server loader's template (VisualAssetId > 0), else nil
local function buildFromTemplate(weaponId: string, maxParts: number): (Model?, BasePart?, Attachment?, Attachment?, number)
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	local tpl = if folder then folder:FindFirstChild("Weapon_" .. weaponId) else nil
	if not (tpl and tpl:IsA("Model")) then
		return nil, nil, nil, nil, 0
	end
	local model = tpl:Clone()
	model.Name = GUN_NAME
	local handle: BasePart? = nil
	local muzzle: Attachment? = nil
	local eject: Attachment? = nil
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do -- once per build, never per frame
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d.Name == "Handle" then
				handle = d
			end
		elseif d:IsA("Attachment") then
			local nm = string.lower(d.Name)
			if muzzle == nil and (string.find(nm, "muzzle") or string.find(nm, "tip") or string.find(nm, "nozzle")) then
				muzzle = d
			elseif eject == nil and (string.find(nm, "eject") or string.find(nm, "shell")) then
				eject = d
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	if #parts == 0 or #parts > 16 then
		model:Destroy()
		return nil, nil, nil, nil, 0
	end
	local h = handle or model.PrimaryPart or parts[1]
	local kept = 0
	for i, p in ipairs(parts) do
		if i > maxParts and p ~= h then
			p:Destroy() -- remote LOD: the first CoreParts only
		else
			prepPart(p)
			kept += 1
		end
	end
	return model, h, muzzle, eject, kept
end

local function gripOf(character: Model): (BasePart?, CFrame)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then
		return nil, CFrame.identity
	end
	local att = hand:FindFirstChild("RightGripAttachment")
	if att and att:IsA("Attachment") then
		local acf = att.CFrame
		if typeof(acf) == "CFrame" then
			return hand, acf
		end
	end
	return hand, CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
end

-- an attachment's world point (its part's CFrame when WorldPosition is not available, e.g. mid-build)
local function attWorld(att: Attachment?, part: BasePart): Vector3
	if att then
		local wp = att.WorldPosition
		if typeof(wp) == "Vector3" then
			return wp
		end
		return part.CFrame:PointToWorldSpace(att.Position)
	end
	return part.Position
end

local function buildGun(character: Model, weaponId: string, maxParts: number): GunRig?
	local hand, grip = gripOf(character)
	if not hand then
		return nil -- not built / streamed out yet
	end
	local def = WeaponConfig.Weapons[weaponId]
	local model: Model?, handle: BasePart?, muzzle: Attachment?, eject: Attachment?, n: number = nil, nil, nil, nil, 0
	local flashSize = 0.9
	if def and (tonumber(def.VisualAssetId) or 0) > 0 then
		model, handle, muzzle, eject, n = buildFromTemplate(weaponId, maxParts)
	end
	if model == nil then
		local m, h, mz, ej, cnt, fs = buildKit(visualKey(def), maxParts)
		model, handle, muzzle, eject, n, flashSize = m, h, mz, ej, cnt, fs
	end
	local mdl = model :: Model
	local h = handle :: BasePart
	-- HudConfig.CombatFx.Grip: a device-tuning rotation / offset of the gun in the hand (zero = Tool default)
	local adj = CFrame.identity
	local gcfg = (FX :: any).Grip
	if type(gcfg) == "table" then
		local r, o = gcfg.RotationDeg, gcfg.OffsetStuds
		if typeof(r) == "Vector3" then
			adj = CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		end
		if typeof(o) == "Vector3" then
			adj *= CFrame.new(o)
		end
	end
	-- place the whole gun at the grip before welding (no one-frame flash at the world origin)
	local delta = (hand.CFrame * grip * adj) * h.CFrame:Inverse()
	for _, d in ipairs(mdl:GetDescendants()) do -- once per build, never per frame
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	local grip0 = Instance.new("Weld")
	grip0.Name = "WE_GunGrip"
	grip0.Part0 = hand
	grip0.Part1 = h
	grip0.C0 = grip
	grip0.C1 = adj:Inverse() -- Handle = hand * C0 * C1^-1 = hand * grip * adj
	grip0.Parent = h
	local flash: ParticleEmitter? = nil
	if muzzle and flashSize > 0 then
		flash = flashEmitter(muzzle, flashSize)
	end
	mdl.Parent = character
	return { Model = mdl, Handle = h, Muzzle = muzzle, Eject = eject, Flash = flash, WeaponId = weaponId, Parts = n }
end

---------------------------------------------------------------------------------------------------------------
-- FX folder + pools
---------------------------------------------------------------------------------------------------------------

local fxFolder: Folder? = nil

local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "WE_WeaponFx"
	nf.Parent = Workspace
	fxFolder = nf
	return nf
end

local function terrain(): Instance
	return Workspace.Terrain
end

-- tracers: Beams between pooled Terrain attachments (0 parts)
type Tracer = { A0: Attachment, A1: Attachment, Beam: Beam, Token: number, Busy: boolean }
local tracers: { Tracer } = {}
local tracerNext = 0
local tracersLive = 0

local function newTracer(): Tracer
	local a0 = Instance.new("Attachment")
	a0.Name = "WE_TracerA"
	a0.Parent = terrain()
	local a1 = Instance.new("Attachment")
	a1.Name = "WE_TracerB"
	a1.Parent = terrain()
	local b = Instance.new("Beam")
	b.Name = "WE_Tracer"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = 0.09
	b.Width1 = 0.05
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 1
	b.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 190, 90))
	b.Transparency = NumberSequence.new(0.15, 0.55)
	b.Enabled = false
	b.Parent = a0
	return { A0 = a0, A1 = a1, Beam = b, Token = 0, Busy = false }
end

local function hideTracer(t: Tracer, token: number)
	if t.Token == token and t.Busy then
		t.Busy = false
		t.Beam.Enabled = false
		tracersLive -= 1
	end
end

local function showTracer(from: Vector3, to: Vector3)
	if (to - from).Magnitude < 0.5 then
		return
	end
	local t: Tracer
	if #tracers < TRACER_MAX then
		t = newTracer()
		table.insert(tracers, t)
		tracerNext = #tracers
	else
		tracerNext = tracerNext % #tracers + 1
		t = tracers[tracerNext]
	end
	if not t.Busy then
		tracersLive += 1
	end
	t.Busy = true
	t.Token += 1
	t.A0.WorldPosition = from
	t.A1.WorldPosition = to
	t.Beam.Enabled = true
	task.delay(math.max(0.03, tonumber(FX.Tracers.Seconds) or 0.08), hideTracer, t, t.Token)
end

-- impacts: pooled Terrain attachment + 2 emitters (dust / sparks), Emit only
type Impact = { Att: Attachment, Dust: ParticleEmitter, Spark: ParticleEmitter }
local impacts: { Impact } = {}
local impactNext = 0
local impactsFired = 0

local function emitter(parent: Attachment, name: string, tex: string, life: number, speed: number, s0: number, s1: number, c0: Color3, c1: Color3, light: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = tex
	e.Rate = 0
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(45, 45)
	e.Size = NumberSequence.new(s0, s1)
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Color = ColorSequence.new(c0, c1)
	e.LightEmission = light
	e.Acceleration = Vector3.new(0, -12, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function impactAt(pos: Vector3, metal: boolean)
	local im: Impact
	if #impacts < IMPACT_MAX then
		local a = Instance.new("Attachment")
		a.Name = "WE_Impact"
		a.Parent = terrain()
		im = {
			Att = a,
			Dust = emitter(a, "Dust", TEX_SMOKE, 0.5, 6, 0.5, 1.4, Color3.fromRGB(196, 176, 140), Color3.fromRGB(160, 144, 118), 0),
			Spark = emitter(a, "Spark", TEX_SPARK, 0.25, 18, 0.3, 0.05, Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 140, 40), 1),
		}
		table.insert(impacts, im)
		impactNext = #impacts
	else
		impactNext = impactNext % #impacts + 1
		im = impacts[impactNext]
	end
	im.Att.WorldPosition = pos
	if metal then
		im.Spark:Emit(IMPACT_EMIT)
	else
		im.Dust:Emit(math.max(2, math.floor(IMPACT_EMIT * 0.75)))
	end
	impactsFired += 1
end

-- explosions: pooled Terrain attachment + fire / smoke emitters
type Blast = { Att: Attachment, Fire: ParticleEmitter, Smoke: ParticleEmitter }
local blasts: { Blast } = {}
local blastNext = 0

local function explosionAt(pos: Vector3, radius: number)
	local b: Blast
	if #blasts < BLAST_MAX then
		local a = Instance.new("Attachment")
		a.Name = "WE_Blast"
		a.Parent = terrain()
		b = {
			Att = a,
			Fire = emitter(a, "Fire", TEX_FIRE, 0.45, 14, 3, 7, Color3.fromRGB(255, 200, 110), Color3.fromRGB(230, 90, 30), 1),
			Smoke = emitter(a, "Smoke", TEX_SMOKE, 1.4, 8, 3, 9, Color3.fromRGB(90, 84, 76), Color3.fromRGB(60, 56, 52), 0),
		}
		b.Fire.SpreadAngle = Vector2.new(180, 180)
		b.Smoke.SpreadAngle = Vector2.new(180, 180)
		b.Smoke.Acceleration = Vector3.new(0, 3, 0)
		table.insert(blasts, b)
		blastNext = #blasts
	else
		blastNext = blastNext % #blasts + 1
		b = blasts[blastNext]
	end
	local scale = math.clamp(radius / 10, 0.6, 1.6)
	b.Att.WorldPosition = pos
	b.Fire:Emit(math.floor((if isTouch then 6 else 12) * scale))
	b.Smoke:Emit(math.floor((if isTouch then 4 else 8) * scale))
end

-- part pools (bullet holes, projectile bodies, casings): created lazily, parked far away, destroyed when idle
type PooledPart = { Part: BasePart, Until: number, Busy: boolean }
type PartPool = { Name: string, Items: { PooledPart }, Max: number, Next: number, Live: number, LastUse: number }

local holes: PartPool = { Name = "Holes", Items = {}, Max = 0, Next = 0, Live = 0, LastUse = 0 }
local casings: PartPool = { Name = "Casings", Items = {}, Max = 0, Next = 0, Live = 0, LastUse = 0 }

local function fxPartCount(): number
	return #holes.Items + #casings.Items
end

local ensureSweeper: () -> ()
local projPartCount: () -> number

local function acquire(pool: PartPool, make: () -> BasePart): PooledPart?
	local item: PooledPart? = nil
	for _, it in ipairs(pool.Items) do
		if not it.Busy then
			item = it
			break
		end
	end
	if item == nil then
		if #pool.Items < pool.Max and fxPartCount() + projPartCount() < PART_CAP then
			local p = make()
			p.CFrame = PARK_CF
			p.Parent = folder()
			local it: PooledPart = { Part = p, Until = 0, Busy = false }
			table.insert(pool.Items, it)
			item = it
		elseif #pool.Items > 0 then
			pool.Next = pool.Next % #pool.Items + 1 -- all busy: recycle round-robin
			item = pool.Items[pool.Next]
		end
	end
	local it = item
	if it == nil then
		return nil
	end
	if not it.Busy then
		pool.Live += 1
	end
	it.Busy = true
	pool.LastUse = clock()
	ensureSweeper()
	return it
end

local function park(pool: PartPool, it: PooledPart)
	if it.Busy then
		it.Busy = false
		pool.Live -= 1
	end
	it.Part.CFrame = PARK_CF
end

local function destroyPool(pool: PartPool)
	for _, it in ipairs(pool.Items) do
		it.Part:Destroy()
	end
	table.clear(pool.Items)
	pool.Live = 0
	pool.Next = 0
end

local function makeHole(): BasePart
	local p = Instance.new("Part")
	p.Name = "WE_Hole"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.04, 0.28, 0.28)
	p.Color = Color3.fromRGB(30, 27, 24)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function makeCasing(): BasePart
	local p = Instance.new("Part")
	p.Name = "WE_Casing"
	p.Size = Vector3.new(0.08, 0.08, 0.22)
	p.Color = Color3.fromRGB(196, 158, 70)
	p.Material = Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function bulletHole(pos: Vector3, normal: Vector3)
	if HOLE_MAX <= 0 or normal.Magnitude < 0.5 then
		return
	end
	local it = acquire(holes, makeHole)
	if not it then
		return
	end
	local n = normal.Unit
	it.Part.CFrame = CFrame.lookAt(pos + n * 0.02, pos + n * 2) * CYL
	it.Until = clock() + (tonumber(FX.BulletHoles.Seconds) or 4)
end

local function ejectCasing(from: Vector3, right: Vector3)
	if not CASINGS_ON or CASING_MAX <= 0 then
		return
	end
	local it = acquire(casings, makeCasing)
	if not it then
		return
	end
	local p = it.Part
	p.CFrame = CFrame.new(from)
	local land = from + right * (1.1 + rng:NextNumber() * 0.5) + Vector3.new(0, -2.6, 0)
	it.Until = clock() + (tonumber(FX.Casings.Seconds) or 2)
	TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(land) * CFrame.Angles(0, rng:NextNumber() * 6, math.rad(90)),
	}):Play()
end

---------------------------------------------------------------------------------------------------------------
-- projectiles ("L" / "X"): <= PROJ_PARTS parts each (or a Part + SpecialMesh when Projectile.MeshId > 0)
---------------------------------------------------------------------------------------------------------------

type Proj = {
	Parts: { Part },
	Offsets: { CFrame },
	Trail: Trail?,
	Mesh: SpecialMesh?,
	Serial: number,
	O: Vector3,
	V: Vector3,
	G: number,
	T0: number,
	Until: number,
	Live: boolean,
	Shown: number,
}
local projs: { Proj } = {}
local projLive = 0
local projStepConn: RBXScriptConnection? = nil
local projLastUse = 0

projPartCount = function(): number
	local n = 0
	for _, pr in ipairs(projs) do
		n += #pr.Parts
	end
	return n
end

local function newProj(): Proj?
	if projPartCount() + fxPartCount() + PROJ_PARTS > PART_CAP then
		return nil
	end
	local parts: { Part } = {}
	local offsets: { CFrame } = {}
	for i = 1, PROJ_PARTS do
		local p = Instance.new("Part")
		p.Name = "WE_Proj" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = PARK_CF
		p.Parent = folder()
		parts[i] = p
		offsets[i] = CFrame.identity
	end
	local body = parts[1]
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.12, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.12, 0)
	a1.Parent = body
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = 0.3
	tr.LightEmission = 0.6
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(150, 146, 140))
	tr.Transparency = NumberSequence.new(0.2, 1)
	tr.Enabled = false
	tr.Parent = body
	local pr: Proj = {
		Parts = parts,
		Offsets = offsets,
		Trail = tr,
		Mesh = nil,
		Serial = 0,
		O = Vector3.zero,
		V = Vector3.zero,
		G = 0,
		T0 = 0,
		Until = 0,
		Live = false,
		Shown = 0,
	}
	table.insert(projs, pr)
	return pr
end

local function parkProj(pr: Proj)
	if pr.Live then
		pr.Live = false
		projLive -= 1
	end
	local tr = pr.Trail
	if tr then
		tr.Enabled = false
		pcall(function()
			tr:Clear()
		end)
	end
	for _, p in ipairs(pr.Parts) do
		p.CFrame = PARK_CF
	end
end

local function projStep()
	local t = clock()
	for _, pr in ipairs(projs) do
		if pr.Live then
			if t >= pr.Until then
				parkProj(pr)
			else
				local dt = t - pr.T0
				local vel = pr.V + Vector3.new(0, -pr.G * dt, 0)
				local pos = pr.O + pr.V * dt + Vector3.new(0, -0.5 * pr.G * dt * dt, 0)
				local cf = if vel.Magnitude > 0.01 then CFrame.lookAt(pos, pos + vel) else CFrame.new(pos)
				for i = 1, pr.Shown do
					pr.Parts[i].CFrame = cf * pr.Offsets[i]
				end
			end
		end
	end
	if projLive <= 0 then
		local c = projStepConn
		projStepConn = nil
		if c then
			c:Disconnect()
		end
	end
end

local function styleProj(pr: Proj, def: WeaponConfig.WeaponDef?)
	local pd = if def then def.Projectile else nil
	local grenade = def ~= nil and def.Visual == "Grenade"
	local meshId = if pd then tonumber(pd.MeshId) or 0 else 0
	local p1, p2, p3 = pr.Parts[1], pr.Parts[2], pr.Parts[3]
	local mesh = pr.Mesh
	if meshId > 0 then
		if mesh == nil then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.FileMesh
			m.Parent = p1
			mesh = m
			pr.Mesh = m
		end
		local mm = mesh :: SpecialMesh
		mm.MeshId = "rbxassetid://" .. tostring(math.floor(meshId))
		local tex = if pd then tonumber(pd.TextureId) or 0 else 0
		mm.TextureId = if tex > 0 then "rbxassetid://" .. tostring(math.floor(tex)) else ""
		p1.Size = if grenade then Vector3.new(0.5, 0.5, 0.5) else Vector3.new(0.4, 0.4, 1.4)
		pr.Shown = 1
		return
	end
	if mesh then
		mesh:Destroy()
		pr.Mesh = nil
	end
	if grenade then
		p1.Shape = Enum.PartType.Ball
		p1.Size = Vector3.new(0.5, 0.5, 0.5)
		p1.Color = GREEN
		p2.Size = Vector3.new(0.1, 0.3, 0.1)
		p2.Color = STEEL
		pr.Offsets[2] = CFrame.new(0.2, 0.15, 0)
		pr.Shown = 2
	else
		p1.Shape = Enum.PartType.Block
		p1.Size = Vector3.new(0.34, 0.34, 1.3)
		p1.Color = OLIVE
		p2.Shape = Enum.PartType.Ball
		p2.Size = Vector3.new(0.34, 0.34, 0.34)
		p2.Color = DARK
		pr.Offsets[2] = CFrame.new(0, 0, -0.65)
		p3.Size = Vector3.new(0.6, 0.06, 0.3)
		p3.Color = DARK
		pr.Offsets[3] = CFrame.new(0, 0, 0.55)
		pr.Shown = 3
	end
	for i = pr.Shown + 1, #pr.Parts do
		pr.Parts[i].CFrame = PARK_CF
	end
end

local function launch(p: Types.WeaponFxPayload)
	local serial = tonumber(p.I) or 0
	local v = p.V
	if typeof(v) ~= "Vector3" then
		return
	end
	local pr: Proj? = nil
	for _, it in ipairs(projs) do
		if not it.Live then
			pr = it
			break
		end
	end
	if pr == nil then
		if #projs < PROJ_MAX then
			pr = newProj()
		else
			local oldest: Proj? = nil
			for _, it in ipairs(projs) do
				if oldest == nil or it.T0 < (oldest :: Proj).T0 then
					oldest = it
				end
			end
			pr = oldest
		end
	end
	local slot = pr
	if slot == nil then
		return
	end
	if slot.Live then
		parkProj(slot)
	end
	local def = WeaponConfig.Weapons[p.W]
	local pd = if def then def.Projectile else nil
	styleProj(slot, def)
	slot.Serial = serial
	slot.O = p.O
	slot.V = v :: Vector3
	slot.G = Workspace.Gravity * (if pd then tonumber(pd.GravityFactor) or 0 else 0)
	slot.T0 = clock()
	slot.Until = slot.T0 + (tonumber(p.T) or (if pd then pd.MaxSeconds else 2)) + 0.5
	slot.Live = true
	projLive += 1
	projLastUse = clock()
	local cf = CFrame.lookAt(p.O, p.O + (v :: Vector3))
	for i = 1, slot.Shown do
		slot.Parts[i].CFrame = cf * slot.Offsets[i]
	end
	local tr = slot.Trail
	if tr then
		pcall(function()
			tr:Clear()
		end)
		tr.Enabled = true
	end
	if projStepConn == nil then
		projStepConn = RunService.Heartbeat:Connect(projStep)
	end
	ensureSweeper()
end

---------------------------------------------------------------------------------------------------------------
-- sounds / haptics
---------------------------------------------------------------------------------------------------------------

local function play(key: string?, at: any?)
	if type(key) == "string" and key ~= "" then
		AudioController.Play(key, at)
	end
end

local function weaponSound(weaponId: string, field: string): string?
	local w = (SoundConfig.Weapons :: any)[weaponId]
	if type(w) == "table" then
		local k = w[field]
		if type(k) == "string" then
			return k
		end
	end
	return nil
end

local function cueKey(name: string): string?
	local k = (SoundConfig.CombatCues :: any)[name]
	return if type(k) == "string" then k else nil
end

local lastBuzz = -math.huge
local function stopMotor(inputType: EnumItem)
	pcall(function()
		HapticService:SetMotor(inputType :: any, Enum.VibrationMotor.Small, 0)
	end)
end

local function buzz(amount: number)
	local hp = FX.Haptics
	if not isTouch or not hp or hp.Enabled == false or amount <= 0 then
		return
	end
	local t = clock()
	if t - lastBuzz < 0.12 then
		return
	end
	lastBuzz = t
	pcall(function()
		for _, it in ipairs({ Enum.UserInputType.Touch, Enum.UserInputType.Gamepad1 }) do
			if HapticService:IsVibrationSupported(it) and HapticService:IsMotorSupported(it, Enum.VibrationMotor.Small) then
				HapticService:SetMotor(it, Enum.VibrationMotor.Small, math.clamp(amount, 0, 1))
				task.delay(0.08, stopMotor, it)
				return
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- local gun + animations
---------------------------------------------------------------------------------------------------------------

local localGun: GunRig? = nil
local wantWeapon: string? = nil
local wantDrawn = false
local holdTrack: AnimationTrack? = nil
local holdKey: string? = nil
local animCache: { [string]: Animation } = {}
local trackCache: { [Instance]: { [string]: AnimationTrack } } = setmetatable({} :: any, { __mode = "k" })
local buildRetryRunning = false

local function animatorOf(character: Model?): Animator?
	if not character then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local a = hum:FindFirstChildOfClass("Animator")
	if a then
		return a
	end
	return nil
end

local function trackFor(character: Model?, id: number): AnimationTrack?
	if id <= 0 then
		return nil
	end
	local animator = animatorOf(character)
	if not animator then
		return nil
	end
	local key = tostring(math.floor(id))
	local byAnim = trackCache[animator]
	if byAnim == nil then
		byAnim = {}
		trackCache[animator] = byAnim
	end
	local cached = (byAnim :: { [string]: AnimationTrack })[key]
	if cached then
		return cached
	end
	local anim: Animation? = animCache[key]
	if anim == nil then
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. key
		animCache[key] = a
		anim = a
	end
	local ok, track = pcall(function(): AnimationTrack
		return (animator :: Animator):LoadAnimation(anim :: Animation)
	end)
	if ok and track then
		(byAnim :: { [string]: AnimationTrack })[key] = track
		return track
	end
	return nil -- R6 / blocked id: fail quietly
end

local function holdIdFor(weaponId: string?): number
	local def = if weaponId then WeaponConfig.Weapons[weaponId] else nil
	local vk = visualKey(def)
	if vk == "Grenade" then
		return 0
	end
	local hold = FX.Anims and FX.Anims.Hold
	if not hold then
		return 0
	end
	local which = HOLD_BY_VISUAL[vk] or "Rifle"
	return tonumber((hold :: any)[which]) or 0
end

local function stopHold()
	local tr = holdTrack
	holdTrack = nil
	holdKey = nil
	if tr then
		pcall(function()
			tr:Stop(0.15)
		end)
	end
end

local function playHold(weaponId: string)
	local id = holdIdFor(weaponId)
	local key = tostring(id)
	if holdKey == key and holdTrack then
		return
	end
	stopHold()
	if id <= 0 then
		return
	end
	local tr = trackFor(player.Character, id)
	if tr then
		pcall(function()
			tr.Priority = Enum.AnimationPriority.Action
			tr.Looped = true
			tr:Play(0.15)
		end)
		holdTrack = tr
		holdKey = key
	end
end

local function clearLocalGun()
	local g = localGun
	localGun = nil
	if g then
		g.Model:Destroy()
	end
end

local function syncLocalGun(): boolean
	local ch = player.Character
	local id = wantWeapon
	if not wantDrawn or id == nil or ch == nil then
		clearLocalGun()
		stopHold()
		return true
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if hum == nil or hum.Health <= 0 then
		clearLocalGun()
		stopHold()
		return true
	end
	local g = localGun
	if g and g.WeaponId == id and g.Model.Parent == ch then
		playHold(id)
		return true
	end
	clearLocalGun()
	local rig = buildGun(ch, id, 12)
	if rig == nil then
		return false -- hand not there yet: retry
	end
	localGun = rig
	playHold(id)
	return true
end

local function retryBuild()
	if buildRetryRunning then
		return
	end
	buildRetryRunning = true
	task.spawn(function()
		local deadline = clock() + 10
		while clock() < deadline do
			task.wait(0.5)
			if syncLocalGun() then
				break
			end
		end
		buildRetryRunning = false
	end)
end

---------------------------------------------------------------------------------------------------------------
-- other players' guns (WE_GunOut) + spawn-shield bubbles (WE_ShieldUntil): tracked by signals, 2 Hz upkeep
---------------------------------------------------------------------------------------------------------------

type Rec = { Player: Player, Char: Model?, GunOut: string?, Gun: GunRig?, Conns: { RBXScriptConnection }, Dist: number }
local recs: { [Player]: Rec } = {}
local recList: { Rec } = {}
local shielded: { [Model]: boolean } = {}
local slowRunning = false
local remoteGunCount = 0

local function serverNow(): number
	local ok, t = pcall(Workspace.GetServerTimeNow, Workspace)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

local function dropRemoteGun(rec: Rec)
	local g = rec.Gun
	rec.Gun = nil
	if g then
		remoteGunCount -= 1
		g.Model:Destroy()
	end
end

local function refreshBubble(char: Model)
	local untilT = char:GetAttribute(SHIELD_ATTR)
	local on = typeof(untilT) == "number" and untilT > serverNow() and char.Parent ~= nil
	local mine = char:FindFirstChild(BUBBLE_NAME)
	if on then
		local other = char:FindFirstChildOfClass("ForceField")
		if other == nil then
			local ff = Instance.new("ForceField")
			ff.Name = BUBBLE_NAME
			ff.Visible = true
			ff.Parent = char
		end
		shielded[char] = true
	else
		if mine then
			mine:Destroy()
		end
		shielded[char] = nil
	end
end

local ensureSlow: () -> ()

local function slowTick()
	-- shield bubbles (2 Hz): removed on expiry
	for char in pairs(shielded) do
		if char.Parent == nil then
			shielded[char] = nil
		else
			refreshBubble(char)
		end
	end
	-- remote guns: the nearest REMOTE_MAX drawn guns within RemoteGuns.Radius
	local cam = Workspace.CurrentCamera
	local from = if cam then cam.CFrame.Position else nil
	local radius = tonumber(FX.RemoteGuns.Radius) or 120
	local n = 0
	for _, rec in ipairs(recList) do
		rec.Dist = math.huge
		local ch = rec.Char
		if rec.GunOut and ch and ch.Parent and from then
			local root = ch:FindFirstChild("HumanoidRootPart")
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and hum and hum.Health > 0 then
				local d = (root.Position - from).Magnitude
				if d <= radius then
					rec.Dist = d
					n += 1
				end
			end
		end
	end
	-- choose: a rec keeps / gets a gun when fewer than REMOTE_MAX eligible recs are nearer
	for _, rec in ipairs(recList) do
		local keep = false
		if rec.Dist < math.huge then
			local nearer = 0
			for _, other in ipairs(recList) do
				if other ~= rec and other.Dist < rec.Dist then
					nearer += 1
				end
			end
			keep = nearer < REMOTE_MAX
		end
		local g = rec.Gun
		if keep then
			local ch = rec.Char :: Model
			local want = rec.GunOut :: string
			if g == nil or g.WeaponId ~= want or g.Model.Parent ~= ch then
				dropRemoteGun(rec)
				local rig = buildGun(ch, want, tonumber(FX.RemoteGuns.CoreParts) or 5)
				if rig then
					rec.Gun = rig
					remoteGunCount += 1
				end
			end
		elseif g then
			dropRemoteGun(rec)
		end
	end
	if n == 0 and remoteGunCount == 0 and next(shielded) == nil then
		local anyOut = false
		for _, rec in ipairs(recList) do
			if rec.GunOut then
				anyOut = true
				break
			end
		end
		if not anyOut then
			slowRunning = false
		end
	end
end

ensureSlow = function()
	if slowRunning then
		return
	end
	slowRunning = true
	task.spawn(function()
		while slowRunning do
			local ok, err = pcall(slowTick)
			if not ok then
				warn("[WeaponVisuals] slow tick failed:", err)
			end
			if slowRunning then
				task.wait(1 / SLOW_HZ)
			end
		end
	end)
end

local function bindCharacter(rec: Rec, char: Model)
	for _, c in ipairs(rec.Conns) do
		c:Disconnect()
	end
	table.clear(rec.Conns)
	dropRemoteGun(rec)
	rec.Char = char
	local isMe = rec.Player == player
	local function readGun()
		if isMe then
			return -- the local gun is built from SetLocalWeapon (full kit), not from the attribute
		end
		local v = char:GetAttribute(DRAWN_ATTR)
		rec.GunOut = if typeof(v) == "string" and v ~= "" then v else nil
		if rec.GunOut then
			ensureSlow()
		end
	end
	local function readShield()
		refreshBubble(char)
		if shielded[char] then
			ensureSlow()
		end
	end
	table.insert(rec.Conns, char:GetAttributeChangedSignal(DRAWN_ATTR):Connect(readGun))
	table.insert(rec.Conns, char:GetAttributeChangedSignal(SHIELD_ATTR):Connect(readShield))
	readGun()
	readShield()
end

local function trackPlayer(p: Player)
	if recs[p] then
		return
	end
	local rec: Rec = { Player = p, Char = nil, GunOut = nil, Gun = nil, Conns = {}, Dist = math.huge }
	recs[p] = rec
	table.insert(recList, rec)
	p.CharacterAdded:Connect(function(char: Model)
		bindCharacter(rec, char)
	end)
	p.CharacterRemoving:Connect(function(char: Model)
		if rec.Char == char then
			dropRemoteGun(rec)
			rec.GunOut = nil
			shielded[char] = nil
		end
	end)
	if p.Character then
		bindCharacter(rec, p.Character)
	end
end

local function untrackPlayer(p: Player)
	local rec = recs[p]
	if not rec then
		return
	end
	recs[p] = nil
	local i = table.find(recList, rec)
	if i then
		table.remove(recList, i)
	end
	for _, c in ipairs(rec.Conns) do
		c:Disconnect()
	end
	dropRemoteGun(rec)
end

---------------------------------------------------------------------------------------------------------------
-- 2D feedback in WE_Reticle: target bar + damage numbers (real px / HudLayout.Scale() = v under MobileScale)
---------------------------------------------------------------------------------------------------------------

local targetBar: Frame? = nil
local targetName: TextLabel? = nil
local targetFill: Frame? = nil
local targetModel: Instance? = nil
local targetUntil = 0
local targetLastName = ""
type DmgLabel = { Label: TextLabel, Token: number, Busy: boolean, At: number }
local dmgLabels: { DmgLabel } = {}
local dmgLive = 0

local function reticleGui(): ScreenGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local rg = if pg then pg:FindFirstChild("WE_Reticle") else nil
	if rg and rg:IsA("ScreenGui") then
		return rg
	end
	return nil
end

local function vOf(px: number): number
	local s = HudLayout.Scale()
	return math.ceil(px / math.max(0.1, s))
end

local function layoutTargetBar()
	local bar, name, fill = targetBar, targetName, targetFill
	if not (bar and name and fill) then
		return
	end
	local TB = FX.TargetBar
	local nameV = vOf(TB.NamePx)
	local w, h = vOf(TB.Width), math.max(2, vOf(TB.Height))
	bar.Size = UDim2.fromOffset(w, nameV + 4 + h)
	name.Size = UDim2.new(1, 0, 0, nameV + 2)
	name.TextSize = nameV
	local track = fill.Parent :: Frame
	track.Size = UDim2.new(1, 0, 0, h)
end

local function buildTargetBar(): boolean
	if targetBar and targetBar.Parent then
		return true
	end
	local rg = reticleGui()
	if not rg then
		return false
	end
	local bar = Instance.new("Frame")
	bar.Name = "TargetBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0.5, 40)
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Active = false
	bar.Visible = false
	bar.ZIndex = 5
	local name = Instance.new("TextLabel")
	name.Name = "TargetName"
	name.BackgroundTransparency = 1
	name.Font = HudConfig.Fonts.Body
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.35
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = ""
	name.Active = false
	name.ZIndex = 6
	name.Parent = bar
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.fromScale(0, 1)
	track.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	track.BackgroundTransparency = 0.4
	track.BorderSizePixel = 0
	track.Active = false
	track.ZIndex = 6
	track.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 70, 60)
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.ZIndex = 7
	fill.Parent = track
	targetBar, targetName, targetFill = bar, name, fill
	layoutTargetBar()
	bar.Parent = rg
	HudLayout.BindVisibility(bar, { ShowWhen = { "Drawn" }, HideWhen = { "Driving", "Modal", "Dead" } }, function(): boolean
		return targetModel ~= nil and clock() < targetUntil
	end)
	return true
end

local function hpOf(inst: Instance): (number?, number?)
	if inst:IsA("Model") then
		local hum = inst:FindFirstChildOfClass("Humanoid")
		if hum then
			return hum.Health, hum.MaxHealth
		end
	end
	local hp, mx = inst:GetAttribute("WE_HP"), inst:GetAttribute("WE_MaxHP")
	if typeof(hp) == "number" and typeof(mx) == "number" and mx > 0 then
		return hp, mx
	end
	return nil, nil
end

local function refreshTargetBar()
	local bar, fill = targetBar, targetFill
	if not (bar and fill) then
		return
	end
	local m = targetModel
	if m and (m.Parent == nil or clock() >= targetUntil) then
		targetModel = nil
		m = nil
	end
	if m then
		local hp, mx = hpOf(m)
		if hp and mx and mx > 0 then
			local frac = math.clamp(hp / mx, 0, 1)
			fill.Size = UDim2.fromScale(frac, 1)
		end
	end
	HudLayout.RefreshVisibility(bar)
end

local function showTarget(target: Instance?, name: string?)
	if not (target and typeof(target) == "Instance") then
		return
	end
	if not buildTargetBar() then
		return
	end
	targetModel = target
	targetUntil = clock() + (tonumber(FX.TargetBar.Seconds) or 2.5)
	local nm = name
	if not nm or nm == "" then
		local p = Players:GetPlayerFromCharacter(target)
		nm = if p then p.DisplayName else target.Name
	end
	local label = targetName
	if label and nm ~= targetLastName then
		targetLastName = nm :: string
		label.Text = string.upper(nm :: string)
	end
	refreshTargetBar()
	ensureSweeper()
end

local function hideDmg(d: DmgLabel, token: number)
	if d.Token == token and d.Busy then
		d.Busy = false
		d.Label.Visible = false
		dmgLive -= 1
	end
end

local function damageNumber(pos: Vector3, amount: number, kind: string)
	if player:GetAttribute(DMG_ATTR) == false then
		return
	end
	local cam = Workspace.CurrentCamera
	local rg = reticleGui()
	if not cam or not rg or amount <= 0 then
		return
	end
	local sp, onScreen = cam:WorldToViewportPoint(pos)
	if not onScreen or sp.Z <= 0 then
		return
	end
	local vp = cam.ViewportSize
	if vp.X < 2 or vp.Y < 2 then
		return
	end
	local d: DmgLabel
	if #dmgLabels < DMG_MAX then
		local l = Instance.new("TextLabel")
		l.Name = "DamageNumber"
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BackgroundTransparency = 1
		l.Font = HudConfig.Fonts.Display
		l.TextStrokeTransparency = 0.3
		l.Active = false
		l.ZIndex = 9
		l.Visible = false
		l.Parent = rg
		d = { Label = l, Token = 0, Busy = false, At = 0 }
		table.insert(dmgLabels, d)
	else
		-- reuse the oldest (<= DMG_MAX live)
		local oldest = dmgLabels[1]
		for _, it in ipairs(dmgLabels) do
			if not it.Busy then
				oldest = it
				break
			end
			if it.At < oldest.At then
				oldest = it
			end
		end
		d = oldest
	end
	local l = d.Label
	local sz = vOf(tonumber(FX.DamageNumbers.TextPx) or 18)
	l.TextSize = sz
	l.Size = UDim2.fromOffset(sz * 4, sz + 4)
	l.TextColor3 = if kind == "Kill" then Color3.fromRGB(255, 96, 80)
		elseif kind == "Headshot" then Color3.fromRGB(255, 214, 72)
		else Color3.fromRGB(255, 255, 255)
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.3
	l.Text = tostring(math.max(1, math.floor(amount + 0.5)))
	-- beside the hit point (up-right), so the number never sits on the crosshair; rises 24 px
	local x, y = sp.X + 26, sp.Y - 30
	l.Position = UDim2.fromScale(x / vp.X, y / vp.Y)
	l.Visible = true
	if not d.Busy then
		dmgLive += 1
	end
	d.Busy = true
	d.At = clock()
	d.Token += 1
	local secs = tonumber(FX.DamageNumbers.Seconds) or 0.8
	TweenService:Create(l, TweenInfo.new(secs, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(x / vp.X, (y - 24) / vp.Y),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(secs, hideDmg, d, d.Token)
end

---------------------------------------------------------------------------------------------------------------
-- sweeper (20 Hz while anything is live): bullet holes, casings, target bar, idle pool destruction
---------------------------------------------------------------------------------------------------------------

local sweeperRunning = false
local sweepN = 0

local function sweepPool(pool: PartPool, t: number)
	if pool.Live > 0 then
		for _, it in ipairs(pool.Items) do
			if it.Busy and t >= it.Until then
				park(pool, it)
			end
		end
	end
	if pool.Live == 0 and #pool.Items > 0 and t - pool.LastUse >= IDLE_DESTROY_SECONDS then
		destroyPool(pool)
	end
end

local function sweep(): boolean
	local t = clock()
	sweepN += 1
	sweepPool(holes, t)
	sweepPool(casings, t)
	if projLive == 0 and #projs > 0 and t - projLastUse >= IDLE_DESTROY_SECONDS then
		for _, pr in ipairs(projs) do
			for _, p in ipairs(pr.Parts) do
				p:Destroy()
			end
		end
		table.clear(projs)
	end
	if sweepN % 2 == 0 and targetModel ~= nil then
		refreshTargetBar() -- 10 Hz
	end
	local busy = holes.Live > 0 or casings.Live > 0 or projLive > 0 or targetModel ~= nil
	local pending = #holes.Items > 0 or #casings.Items > 0 or #projs > 0
	return busy or pending
end

ensureSweeper = function()
	if sweeperRunning then
		return
	end
	sweeperRunning = true
	task.spawn(function()
		while true do
			task.wait(1 / SWEEP_HZ)
			local ok, more = pcall(sweep)
			if not ok then
				warn("[WeaponVisuals] sweep failed:", more)
			end
			if ok and not more then
				break
			end
		end
		sweeperRunning = false
	end)
end

---------------------------------------------------------------------------------------------------------------
-- shots
---------------------------------------------------------------------------------------------------------------

local function isVehiclePart(inst: Instance?): boolean
	local p = if inst then inst.Parent else nil
	local depth = 0
	while p and p ~= Workspace and depth < 8 do
		if CollectionService:HasTag(p, Constants.Tags.Vehicle) then
			return true
		end
		p = p.Parent
		depth += 1
	end
	return false
end

local function isCharacterPart(inst: Instance?): boolean
	local m = if inst then inst:FindFirstAncestorOfClass("Model") else nil
	return m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil
end

local function camPos(): Vector3?
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

local function jitter(dir: Vector3, deg: number): Vector3
	if deg <= 0 then
		return dir
	end
	local a = math.rad(deg) * 0.5
	local cf = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0)
	return cf.LookVector
end

function WeaponVisuals.MuzzleWorldPosition(): Vector3?
	local g = localGun
	if g and g.Model.Parent then
		return attWorld(g.Muzzle, g.Handle)
	end
	return nil
end

function WeaponVisuals.LocalShot(weaponId: string, origin: Vector3, dir: Vector3, hitPos: Vector3?, hitInst: Instance?, hitNormal: Vector3?)
	local def = WeaponConfig.Weapons[weaponId]
	if not def or typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return
	end
	local g = localGun
	local from = WeaponVisuals.MuzzleWorldPosition() or origin
	if g and g.Flash then
		(g.Flash :: ParticleEmitter):Emit(1)
	end
	play(weaponSound(weaponId, "Fire"), from)
	if def.Projectile ~= nil then
		return -- the body comes from WeaponFx "L" (the server's projectile)
	end
	local range = math.max(1, tonumber(def.Range) or 100)
	local to = hitPos or (origin + dir.Unit * range)
	if def.Tracer ~= false then
		local pellets = math.clamp(tonumber(def.Pellets) or 1, 1, 3)
		if pellets <= 1 then
			showTracer(from, to)
		else
			local d = (to - from)
			local len = d.Magnitude
			for i = 1, pellets do
				local jd = if i == 1 then d.Unit else jitter(d.Unit, tonumber(def.Spread) or 0)
				showTracer(from, from + jd * len)
			end
		end
	end
	if hitPos and hitInst then
		if isVehiclePart(hitInst) then
			impactAt(hitPos, true)
			play(cueKey("ImpactMetal"), hitPos)
		elseif not isCharacterPart(hitInst) then
			impactAt(hitPos, false)
			play(cueKey("ImpactGround"), hitPos)
			if hitNormal and hitInst:IsA("BasePart") and hitInst.Anchored then
				bulletHole(hitPos, hitNormal)
			end
		end
	end
	if g and g.Eject then
		ejectCasing(attWorld(g.Eject, g.Handle), g.Handle.CFrame.RightVector)
	end
end

local function onFx(raw: any)
	if typeof(raw) ~= "table" then
		return
	end
	local p = raw :: Types.WeaponFxPayload
	if typeof(p.O) ~= "Vector3" or typeof(p.P) ~= "Vector3" or type(p.K) ~= "string" or type(p.W) ~= "string" then
		return
	end
	local kind = p.K
	local cp = camPos()
	local cull = tonumber(FX.CullStuds) or 250
	if kind == "L" then
		if cp and (cp - p.O).Magnitude > cull then
			return
		end
		launch(p)
		local shooterL = tonumber(p.S) or 0
		if shooterL ~= player.UserId then
			play(weaponSound(p.W, "Fire"), p.O) -- the shooter already heard his own launch (LocalShot)
		end
		return
	end
	if kind == "X" then
		local id = tonumber(p.I) or 0
		for _, pr in ipairs(projs) do
			if pr.Live and pr.Serial == id then
				parkProj(pr)
			end
		end
		local radius = tonumber(p.D) or 10
		if cp and (cp - p.P).Magnitude > cull then
			return
		end
		explosionAt(p.P, radius)
		play(cueKey("ExplosionSmall"), p.P)
		CameraFx.Blast(p.P, radius)
		return
	end
	-- bullets: the shooter predicts his own
	local shooter = tonumber(p.S) or 0
	if shooter ~= 0 and shooter == player.UserId then
		return
	end
	if cp and (cp - p.O).Magnitude > cull and (cp - p.P).Magnitude > cull then
		return
	end
	local from = p.O
	local rec: Rec? = nil
	if shooter ~= 0 then
		local other = Players:GetPlayerByUserId(shooter)
		rec = if other then recs[other] else nil
	end
	local gun = if rec then rec.Gun else nil
	if gun and gun.Model.Parent then
		from = attWorld(gun.Muzzle, gun.Handle)
		local fl = gun.Flash
		if fl then
			fl:Emit(1)
		end
	end
	local def = WeaponConfig.Weapons[p.W]
	if def == nil or def.Tracer ~= false then
		if def and (tonumber(def.Pellets) or 1) > 1 then
			local d = p.P - from
			local len = d.Magnitude
			if len > 0.5 then
				for i = 1, 3 do
					local jd = if i == 1 then d.Unit else jitter(d.Unit, tonumber(def.Spread) or 0)
					showTracer(from, from + jd * len)
				end
			end
		else
			showTracer(from, p.P)
		end
	end
	play(weaponSound(p.W, "Fire") or weaponSound("NPC", "Fire"), from)
	if kind == "V" then
		impactAt(p.P, true)
		play(cueKey("ImpactMetal"), p.P)
	elseif kind == "W" or kind == "G" then
		impactAt(p.P, false)
		play(cueKey("ImpactGround"), p.P)
	end
end

local function bindFx()
	task.spawn(function()
		local waited = 0
		while waited <= FX_POLL_MAX_SECONDS do
			local ev = Remotes.TryGetUnreliableEvent(Constants.RemoteNames.WeaponFx)
			if ev then
				ev.OnClientEvent:Connect(onFx)
				return
			end
			task.wait(FX_POLL_SECONDS)
			waited += FX_POLL_SECONDS
		end
		warn("[WeaponVisuals] WeaponFx remote never appeared: other players' shots show no tracers")
	end)
end

---------------------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------------------

function WeaponVisuals.SetLocalWeapon(weaponId: string?, drawn: boolean)
	local wasDrawn, wasId = wantDrawn, wantWeapon
	wantWeapon = weaponId
	wantDrawn = drawn == true and weaponId ~= nil
	if wantDrawn and (not wasDrawn or wasId ~= weaponId) then
		play(cueKey("Equip"), player.Character)
	end
	if not wantDrawn then
		targetModel = nil
		local bar = targetBar
		if bar then
			HudLayout.RefreshVisibility(bar)
		end
	end
	if not syncLocalGun() then
		retryBuild()
	end
end

function WeaponVisuals.PlayReload(weaponId: string)
	play(weaponSound(weaponId, "Reload"), player.Character)
	local id = tonumber(FX.Anims and FX.Anims.Reload) or 0
	if id > 0 and wantDrawn then
		local tr = trackFor(player.Character, id)
		if tr then
			pcall(function()
				tr.Priority = Enum.AnimationPriority.Action2
				tr.Looped = false
				tr:Play(0.1)
			end)
		end
	end
end

function WeaponVisuals.Cue(name: string)
	play(cueKey(name), player.Character)
end

function WeaponVisuals.OnHitFeedback(raw: any)
	if typeof(raw) ~= "table" then
		return
	end
	local p = raw :: Types.CombatHitFeedbackPayload
	local kind = p.Kind
	if kind == "Hit" or kind == "Kill" then
		if kind == "Kill" then
			play(cueKey("Kill"))
			buzz(tonumber(FX.Haptics and FX.Haptics.Kill) or 0.5)
		elseif p.IsHeadshot then
			play(cueKey("Headshot"))
			buzz(tonumber(FX.Haptics and FX.Haptics.Hit) or 0.2)
		else
			play(cueKey("HitConfirm"))
			buzz(tonumber(FX.Haptics and FX.Haptics.Hit) or 0.2)
		end
		local dmg = tonumber(p.Damage) or 0
		local pos = p.Pos
		if typeof(pos) == "Vector3" and dmg > 0 then
			damageNumber(pos, dmg, if kind == "Kill" then "Kill" elseif p.IsHeadshot then "Headshot" else "Hit")
		end
		if p.Splash ~= true and wantDrawn then
			showTarget(p.Target, p.TargetName)
		end
	elseif kind == "Damaged" then
		play(cueKey("Hurt"))
	end
end

function WeaponVisuals.Stats(): { Tracers: number, BulletHoles: number, Impacts: number, Projectiles: number, Casings: number, FxParts: number, RemoteGuns: number, DamageNumbers: number }
	return {
		Tracers = tracersLive,
		BulletHoles = holes.Live,
		Impacts = #impacts,
		Projectiles = projLive,
		Casings = casings.Live,
		FxParts = fxPartCount() + projPartCount(),
		RemoteGuns = remoteGunCount,
		DamageNumbers = dmgLive,
	}
end

-- caps in force (tests compare Stats() against these)
function WeaponVisuals.Caps(): { [string]: number }
	return {
		Tracers = TRACER_MAX,
		Impacts = IMPACT_MAX,
		BulletHoles = HOLE_MAX,
		Projectiles = PROJ_MAX,
		Casings = if CASINGS_ON then CASING_MAX else 0,
		FxParts = PART_CAP,
		RemoteGuns = REMOTE_MAX,
		DamageNumbers = DMG_MAX,
	}
end

function WeaponVisuals.LocalGunParts(): number
	local g = localGun
	return if g then g.Parts else 0
end

WeaponVisuals._OnFx = onFx -- tests: feed WeaponFx payloads without the remote

function WeaponVisuals.Init()
	if initialized then
		return
	end
	initialized = true
	isTouch = HudLayout.IsTouch()
	TRACER_MAX = if isTouch then FX.Tracers.MaxTouch else FX.Tracers.Max
	IMPACT_MAX = if isTouch then FX.Impacts.MaxTouch else FX.Impacts.Max
	IMPACT_EMIT = if isTouch then FX.Impacts.EmitTouch else FX.Impacts.Emit
	BLAST_MAX = if isTouch then 2 else 3
	HOLE_MAX = if isTouch then FX.BulletHoles.MaxTouch else FX.BulletHoles.Max
	PROJ_MAX = if isTouch then FX.Projectiles.MaxTouch else FX.Projectiles.Max
	PROJ_PARTS = math.clamp(FX.Projectiles.PartsEach, 1, 3)
	CASINGS_ON = if isTouch then FX.Casings.EnabledTouch == true else FX.Casings.Enabled == true
	CASING_MAX = if CASINGS_ON then FX.Casings.Max else 0
	PART_CAP = if isTouch then FX.MaxFxPartsTouch else FX.MaxFxParts
	-- the three part pools always fit the hard cap (holes shrink first)
	local over = HOLE_MAX + PROJ_MAX * PROJ_PARTS + CASING_MAX - PART_CAP
	if over > 0 then
		HOLE_MAX = math.max(0, HOLE_MAX - over)
	end
	holes.Max = HOLE_MAX
	casings.Max = CASING_MAX
	REMOTE_MAX = if isTouch then FX.RemoteGuns.MaxTouch else FX.RemoteGuns.Max
	DMG_MAX = math.max(1, tonumber(FX.DamageNumbers.Max) or 4)

	for _, p in ipairs(Players:GetPlayers()) do
		trackPlayer(p)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	player.CharacterAdded:Connect(function()
		localGun = nil -- the old gun left with the old character
		holdTrack = nil
		holdKey = nil
		wantDrawn = false
	end)
	HudLayout.LayoutChanged:Connect(layoutTargetBar)
	bindFx()
end

return WeaponVisuals
