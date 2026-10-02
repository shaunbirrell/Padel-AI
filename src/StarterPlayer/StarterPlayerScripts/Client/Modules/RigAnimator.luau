--!strict
--[[
	RigAnimator (R-RIG): animates the WE_Rig soldier figures and builds the army escorts on THIS client only. Nothing
	here replicates; the server never plays a track.
	  • Registry from CollectionService "WE_Rig" (added / removed signals; streaming-safe: a figure that streams out is
	    removed, one that streams in is added). Never scans the workspace.
	  • One task.wait loop at RigConfig.Anim.TickHz, plus the camera guard alone at Escort.Camera.GuardHz (the guard
	    buffer only: <= MaxAnimated picked figures; it sleeps a whole pass while the buffer is empty). No per-frame
	    (render or physics step) work, no per-pass tables.
	  • Animated: the MaxAnimated figures within NearStuds, own squad units first, then nearest. Anchored base statues
	    (WE_RigStatic) never animate (their pose is baked on the server).
	  • Rifle held forward without tracks: an armed figure that is not animated (outside the pick, far, or waiting for
	    its tracks) gets its Right Shoulder C0 turned by Anim.StaticHoldDeg locally; the turn is undone before Hold plays.
	  • State per figure from its root's flat speed between passes: Walk / Idle; Hold keeps the rifle forward; Aim for
	    AimSeconds after an NPC shot whose origin is at that figure (WeaponFx S = 0), only while standing.
	  • Mesh LOD: only the animated figures, the nearest Lod.MaxMeshedStatic statues and the escorts wear the Roblox
	    body (FileMesh); every other figure shows plain blocks and hides its beret (local properties).
	  • Escorts: an animated squad unit within Escort.NearStuds shows min(WE_Escorts, MaxPerUnit) local copies of its
	    body AHEAD of it (RigConfig.Escort.Offsets), at most Escort.MaxPerClient on this client, own army first. They
	    are parented under the unit (they go when it goes), can never be hit (CanQuery false; the aim filter skips the
	    squad folder anyway) and copy the unit's state. Camera guard: an escort nearer the camera than the local
	    player's root, or close enough to cover more than Escort.Camera.MaxScreenFrac of the screen height, is hidden:
	    its parts AND its Decals (the kit head's face; Roblox draws a Decal whatever its part's transparency). The guard
	    runs in every pass and on its own Camera.GuardHz times a second: a camera swipe or a turning unit swings a file
	    through the camera faster than a 4 Hz pass can follow. An own squad unit nearer the camera than the player and
	    drawn taller than Camera.LeadScreenFrac of the screen (judged by depth along the view, so the wide screen's
	    corners count too) is hidden the same way (on this client only; it is still there and hittable).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) :: Instance -- Bootstrap already waited for it; bounded anyway
local RigConfig = require((Shared :: any).Configs.RigConfig) :: any
-- v114/v115 (Code Bot Roblox): ArmyConfig.Follow3 escort layout (v115: on the unit's own path behind it)
local okArmyCfg, ArmyConfigOrErr = pcall(require, (Shared :: any).Configs.ArmyConfig)
local follow3: any = if okArmyCfg and typeof(ArmyConfigOrErr) == "table" then (ArmyConfigOrErr :: any).Follow3 else nil

local RigAnimator = {}

type Tracks = { Hold: AnimationTrack?, Idle: AnimationTrack?, Walk: AnimationTrack?, Aim: AnimationTrack? }
type Escort = { Model: Model, Tracks: Tracks?, State: string, Torso: BasePart?, Parts: { BasePart }, Decals: { Decal }, Hidden: boolean }
-- v114: an escort's RootJoint, its index in the unit's row and the last local offset written (weak: goes with the escort)
type EscLayout = { Joint: Motor6D, Index: number, Off: Vector3? }
local escLayout: { [any]: EscLayout } = setmetatable({}, { __mode = "k" }) :: any
-- v119: an escort's helmet and whether the helmet budget hides it this pass (weak: goes with the escort)
type EscHelm = { Part: BasePart, Off: boolean }
local escHelm: { [any]: EscHelm } = setmetatable({}, { __mode = "k" }) :: any
type Entry = {
	Rig: Model,
	Index: number,
	Host: Model?,
	Root: BasePart?,
	Animator: Animator?,
	Tracks: Tracks?,
	State: string, -- "" (not animated) | "Idle" | "Walk" | "Aim"
	LastPos: Vector3?,
	Speed: number,
	AimUntil: number,
	Armed: boolean,
	Static: boolean,
	Squad: boolean,
	Own: boolean,
	Dist: number, -- studs to the camera this pass
	Key: number, -- sort key this pass: Dist, minus StickyStuds while animated, own squad units first
	Picked: boolean, -- animated this pass
	SPicked: boolean, -- a static statue that wears the Roblox body this pass
	Far: boolean, -- true = plain blocks (Brick meshes, beret hidden)
	Meshes: { SpecialMesh },
	FileScales: { Vector3 },
	BrickScales: { Vector3 },
	Beret: BasePart?,
	Shoulder: Motor6D?,
	ShoulderC0: CFrame?, -- the server's Right Shoulder C0 (never changed by this module while tracks play)
	HoldBaked: boolean,
	WantEsc: number, -- escorts this figure asks for this pass (WE_Escorts, capped; 0 when not eligible)
	Escorts: { Escort },
	LeadHidden: boolean, -- an own squad unit in the camera's face: its rig hidden on this client (parts + Decals)
	Cloth: { Texture }, -- v119: the WE_Cloth Textures of a cloth body (hidden while Far)
	HasLod: boolean, -- v119: FileMesh limbs or cloth: the figure has a far look (blocks) to swap to
	HelmetOff: boolean, -- v119: a cloth body's helmet hidden this pass (over Budget.MaxMeshedTriangles)
}

local TAG: string = RigConfig.Tag
local CLOTH_NAME = "WE_Cloth" -- v119: RigBuilder.ClothName (server)
local clothCfg = (RigConfig :: any).Cloth or {}
local ESCORT_NAME = "WE_Escort"
local TRACK_NAMES = { "Hold", "Idle", "Walk", "Aim" }
local LIMB_NAMES = { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local NOMINAL: { [string]: Vector3 } = { -- R6 body sizes the Roblox meshes are made for (Brick meshes scale by part size)
	Torso = Vector3.new(2, 2, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
}
local ROOT_ROT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) -- R6 RootJoint C0 / C1 rotation
local OWN_BIAS = -1e9 -- own squad units sort before every other figure
local cfg = RigConfig.Anim
local lod = RigConfig.Lod
local esc = RigConfig.Escort
local camCfg = esc.Camera
local HOLD_TURN = CFrame.Angles(0, 0, math.rad(tonumber(cfg.StaticHoldDeg) or 0))
local entries: { Entry } = {}
local byRig: { [Model]: Entry } = {}
local animations: { [string]: Animation } = {}
local pick: { Entry? } = {} -- fixed-size buffer: the MaxAnimated figures this pass, best first
local pickN = 0
local spick: { Entry? } = {} -- fixed-size buffer: the MaxMeshedStatic statues this pass, nearest first
local spickN = 0
local lastStep = 0
local localUserId = 0
local guard: { Entry? } = {} -- fixed-size buffer: the picked figures the camera guard watches (escorts, own units)
local guardN = 0
local stats = {
	Passes = 0, Animated = 0, Loads = 0, Registered = 0, Escorts = 0, EscortParts = 0, EscortBuilds = 0, FarSwaps = 0,
	Meshed = 0, MeshedStatic = 0, EscortsHidden = 0, EscortHides = 0, HoldBaked = 0, LeadsHidden = 0, LeadHides = 0,
	GuardPasses = 0, HelmetsOn = 0, HelmetsOff = 0, MeshedTris = 0,
}

local function animation(name: string): Animation?
	local a = animations[name]
	if a then
		return a
	end
	local id = cfg.Ids[name]
	if typeof(id) ~= "number" or id <= 0 then
		return nil
	end
	local made = Instance.new("Animation")
	made.AnimationId = "rbxassetid://" .. tostring(id)
	animations[name] = made
	return made
end

local function animatorOf(m: Model): Animator?
	local ac = m:FindFirstChildOfClass("AnimationController")
	return if ac then ac:FindFirstChildOfClass("Animator") else nil
end

local function loadTracks(an: Animator?, armed: boolean, withAim: boolean): Tracks?
	if an == nil then
		return nil
	end
	local t: Tracks = {}
	for _, k in ipairs(TRACK_NAMES) do
		if (k ~= "Hold" or armed) and (k ~= "Aim" or withAim) then
			local a = animation(k)
			if a then
				local ok, tr = pcall(an.LoadAnimation, an, a)
				if ok and tr then
					(t :: any)[k] = tr
					stats.Loads += 1
				end
			end
		end
	end
	return t
end

local function stopTracks(t: Tracks?)
	if t == nil then
		return
	end
	for _, k in ipairs(TRACK_NAMES) do
		local tr = (t :: any)[k] :: AnimationTrack?
		if tr then
			tr:Stop(cfg.FadeSeconds)
			tr:Destroy()
		end
	end
end

-- module level (no closure per call): start / stop one track
local function playTrack(tr: AnimationTrack?, on: boolean)
	if tr == nil then
		return
	end
	if on and not tr.IsPlaying then
		tr:Play(cfg.FadeSeconds)
	elseif not on and tr.IsPlaying then
		tr:Stop(cfg.FadeSeconds)
	end
end

local function applyState(t: Tracks?, armed: boolean, want: string, speed: number)
	if t == nil then
		return
	end
	playTrack(t.Hold, armed and want ~= "Aim")
	playTrack(t.Idle, want == "Idle")
	playTrack(t.Walk, want == "Walk")
	playTrack(t.Aim, want == "Aim")
	if want == "Walk" and t.Walk then
		t.Walk:AdjustSpeed(math.clamp(speed / cfg.WalkSpeedRef, cfg.WalkRateMin, cfg.WalkRateMax))
	end
end

-- rifle forward with no track: turn the Right Shoulder C0 locally (undone before Hold plays)
local function setHoldBaked(e: Entry, baked: boolean)
	if e.HoldBaked == baked or e.Shoulder == nil or e.ShoulderC0 == nil then
		return
	end
	e.HoldBaked = baked
	local s = e.Shoulder :: Motor6D
	s.C0 = if baked then (e.ShoulderC0 :: CFrame) * HOLD_TURN else e.ShoulderC0 :: CFrame
	stats.HoldBaked += if baked then 1 else -1
end

-- ── escorts ──────────────────────────────────────────────────────────────────────────────────────────────────────
local function setEscortHidden(x: Escort, hidden: boolean)
	if x.Hidden == hidden then
		return
	end
	x.Hidden = hidden
	for _, p in ipairs(x.Parts) do
		p.LocalTransparencyModifier = if hidden then 1 else 0
	end
	local hb = escHelm[x]
	if hb and hb.Off and not hidden then
		hb.Part.LocalTransparencyModifier = 1 -- v119: shown again, but its helmet stays over the triangle budget
	end
	for _, d in ipairs(x.Decals) do -- the face: a Decal is drawn even on a hidden part
		d.LocalTransparencyModifier = if hidden then 1 else 0
	end
	stats.EscortsHidden += if hidden then 1 else -1
	if hidden then
		stats.EscortHides += 1
	end
end

-- an own squad unit in the camera's face: its rig's parts and their Decals hidden on this client only (the unit is
-- still there for everybody, hits included). Runs only when the state flips: one rig's children (<= 10 parts).
local function setLeadHidden(e: Entry, hidden: boolean)
	if e.LeadHidden == hidden then
		return
	end
	e.LeadHidden = hidden
	for _, c in ipairs(e.Rig:GetChildren()) do
		if c:IsA("BasePart") then
			c.LocalTransparencyModifier = if hidden or (c == e.Beret and e.Far) then 1 else 0
			if c == e.Beret and e.HelmetOff then
				c.LocalTransparencyModifier = 1 -- v119: a helmet over the triangle budget stays hidden
			end
			for _, d in ipairs(c:GetChildren()) do
				if d:IsA("Decal") then -- the kit head's face: a Decal is drawn even on a hidden part
					d.LocalTransparencyModifier = if hidden then 1 else 0
					if e.Far and d.Name == CLOTH_NAME then
						d.LocalTransparencyModifier = 1 -- v119: a far cloth body shows its kit-colour blocks
					end
				end
			end
		end
	end
	stats.LeadsHidden += if hidden then 1 else -1
	if hidden then
		stats.LeadHides += 1
	end
end

local function dropEscort(e: Entry)
	local x = table.remove(e.Escorts)
	if x then
		if x.Hidden then
			stats.EscortsHidden -= 1
		end
		stopTracks(x.Tracks)
		pcall(x.Model.Destroy, x.Model)
		stats.Escorts -= 1
		stats.EscortParts -= RigConfig.Budget.PartsPerEscort
	end
end

local function dropAllEscorts(e: Entry)
	while #e.Escorts > 0 do
		dropEscort(e)
	end
end

-- a local copy of the unit's body, `offset` from its root (unit frame). Joints are re-linked by part name inside the
-- copy, so this never depends on how Clone remaps references; the copy loses the WE_Rig tag (Clone keeps tags).
local function buildEscort(e: Entry, offset: Vector3, index: number): Escort?
	local root, host = e.Root, e.Host
	if root == nil or host == nil then
		return nil
	end
	local okClone, copyOrNil = pcall(e.Rig.Clone, e.Rig)
	if not okClone or typeof(copyOrNil) ~= "Instance" then
		return nil
	end
	local copy = copyOrNil :: Model
	CollectionService:RemoveTag(copy, TAG)
	copy.Name = ESCORT_NAME
	copy:SetAttribute("WE_RigStatic", nil)
	local byName: { [string]: BasePart } = {}
	local parts: { BasePart } = {}
	local decals: { Decal } = {}
	local joint: Motor6D? = nil
	for _, d in ipairs(copy:GetDescendants()) do -- one small body (<= 30 instances), once per build, never per frame
		if d:IsA("Decal") then -- the kit head's face (a Texture is a Decal too)
			d.LocalTransparencyModifier = 0
			table.insert(decals, d)
		elseif d:IsA("BasePart") then
			byName[d.Name] = d
			table.insert(parts, d)
			d.CanQuery = false
			d.CanTouch = false
			d.CanCollide = false
			d.CastShadow = false
			d.Massless = true
			d.Anchored = false
			d.LocalTransparencyModifier = 0
		end
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("JointInstance") then
			local p0, p1 = d.Part0, d.Part1
			if p0 and not p0:IsDescendantOf(copy) and p0 ~= root and byName[p0.Name] then
				d.Part0 = byName[p0.Name]
			end
			if p1 and not p1:IsDescendantOf(copy) and byName[p1.Name] then
				d.Part1 = byName[p1.Name]
			end
			if d.Name == "RootJoint" and d:IsA("Motor6D") then
				d.Part0 = root
				d.C0 = CFrame.new(offset) * ROOT_ROT
				joint = d
			elseif d.Name == "Right Shoulder" and d:IsA("Motor6D") and e.ShoulderC0 then
				d.C0 = e.ShoulderC0 :: CFrame -- the escort plays Hold itself: never copy a baked hold turn
			end
		elseif d:IsA("SpecialMesh") and d:GetAttribute("WE_FileMesh") then
			d.MeshType = Enum.MeshType.FileMesh -- the lead may be in blocks right now; an escort is always near
			local p = d.Parent
			local nominal = if p then NOMINAL[p.Name] else nil
			if nominal then
				d.Scale = Vector3.new(1, 1, 1)
			end
		end
	end
	local torso = byName.Torso
	if torso then
		torso.CFrame = root.CFrame * CFrame.new(offset)
	end
	copy.Parent = host -- goes with the unit (death, despawn, stream-out)
	stats.Escorts += 1
	stats.EscortParts += RigConfig.Budget.PartsPerEscort
	stats.EscortBuilds += 1
	local rec: Escort = { Model = copy, Tracks = loadTracks(animatorOf(copy), true, false), State = "", Torso = torso, Parts = parts, Decals = decals, Hidden = false }
	escHelm[rec] = if byName.Beret then { Part = byName.Beret, Off = false } else nil -- v119: the copy's helmet
	if joint then
		escLayout[rec] = { Joint = joint, Index = index, Off = nil }
	end
	return rec
end

-- ── registry ─────────────────────────────────────────────────────────────────────────────────────────────────────
local function resolve(e: Entry): boolean
	if e.Root == nil or e.Root.Parent == nil then
		local host = e.Rig.Parent
		e.Host = if host and host:IsA("Model") then host else nil
		local root = if e.Host then (e.Host.PrimaryPart or e.Host:FindFirstChild("HumanoidRootPart")) else nil
		e.Root = if root and root:IsA("BasePart") then root else nil
		if e.Host then
			e.Squad = e.Host:GetAttribute("FriendlySquad") == true
			e.Own = e.Squad and e.Host:GetAttribute("OwnerUserId") == localUserId
		end
	end
	if e.Animator == nil or e.Animator.Parent == nil then
		e.Animator = animatorOf(e.Rig)
	end
	return e.Root ~= nil and e.Animator ~= nil
end

local function stopAll(e: Entry)
	stopTracks(e.Tracks)
	e.Tracks = nil
	e.State = ""
	dropAllEscorts(e)
	if e.Armed and not e.Static and cfg.HoldUntracked == true then
		setHoldBaked(e, true)
	end
end

local function setFar(e: Entry, far: boolean)
	if e.Far == far then
		return
	end
	e.Far = far
	for i, m in ipairs(e.Meshes) do
		m.MeshType = if far then Enum.MeshType.Brick else Enum.MeshType.FileMesh
		m.Scale = if far then e.BrickScales[i] else e.FileScales[i]
	end
	if e.Beret then
		e.Beret.LocalTransparencyModifier = if far or e.LeadHidden then 1 else 0
		if e.HelmetOff then
			e.Beret.LocalTransparencyModifier = 1 -- v119: over the helmet triangle budget
		end
	end
	for _, t in ipairs(e.Cloth) do -- v119: the cloth body's far look is its kit-colour blocks
		t.LocalTransparencyModifier = if far or e.LeadHidden then 1 else 0
	end
	stats.FarSwaps += 1
end

local function add(inst: Instance)
	if not inst:IsA("Model") or byRig[inst] then
		return
	end
	local rig = inst :: Model
	local meshes: { SpecialMesh } = {}
	local fileScales: { Vector3 } = {}
	local brickScales: { Vector3 } = {}
	for _, n in ipairs(LIMB_NAMES) do
		local p = rig:FindFirstChild(n)
		local m = if p then p:FindFirstChildOfClass("SpecialMesh") else nil
		if p and p:IsA("BasePart") and m and m.MeshType == Enum.MeshType.FileMesh then
			m:SetAttribute("WE_FileMesh", true)
			table.insert(meshes, m)
			table.insert(fileScales, m.Scale)
			local s = p.Size
			local nominal = NOMINAL[n]
			table.insert(brickScales, Vector3.new(nominal.X / s.X, nominal.Y / s.Y, nominal.Z / s.Z)) -- a 1.45-deep hit torso still looks 1 deep
		end
	end
	local cloth: { Texture } = {}
	for _, n in ipairs(LIMB_NAMES) do -- the WE_Cloth Textures sit on the limbs (RigBuilder.PaintCloth), once per figure
		local p = rig:FindFirstChild(n)
		if p then
			for _, d in ipairs(p:GetChildren()) do
				if d:IsA("Texture") and d.Name == CLOTH_NAME then
					table.insert(cloth, d)
				end
			end
		end
	end
	local beret = rig:FindFirstChild("Beret")
	local torso = rig:FindFirstChild("Torso")
	local shoulder = if torso then torso:FindFirstChild("Right Shoulder") else nil
	local e: Entry = {
		Rig = rig,
		Index = #entries + 1,
		Host = nil,
		Root = nil,
		Animator = nil,
		Tracks = nil,
		State = "",
		LastPos = nil,
		Speed = 0,
		AimUntil = 0,
		Armed = rig:FindFirstChild("Rifle") ~= nil,
		Static = rig:GetAttribute("WE_RigStatic") == true,
		Squad = false,
		Own = false,
		Dist = math.huge,
		Key = math.huge,
		Picked = false,
		SPicked = false,
		Far = false,
		Meshes = meshes,
		FileScales = fileScales,
		BrickScales = brickScales,
		Beret = if beret and beret:IsA("BasePart") then beret else nil,
		Shoulder = if shoulder and shoulder:IsA("Motor6D") then shoulder else nil,
		ShoulderC0 = if shoulder and shoulder:IsA("Motor6D") then shoulder.C0 else nil,
		HoldBaked = false,
		WantEsc = 0,
		Escorts = {},
		LeadHidden = false,
		Cloth = cloth,
		HasLod = #meshes > 0 or #cloth > 0,
		HelmetOff = false,
	}
	entries[e.Index] = e
	byRig[rig] = e
	stats.Registered = #entries
	if e.Armed and not e.Static and cfg.HoldUntracked == true then
		setHoldBaked(e, true) -- rifle forward from the first frame this client sees it
	end
end

local function remove(inst: Instance)
	local e = byRig[inst :: Model]
	if e == nil then
		return
	end
	stopTracks(e.Tracks)
	e.Tracks = nil
	dropAllEscorts(e)
	if e.HoldBaked then
		stats.HoldBaked -= 1 -- the instance is gone (streamed out / died); nothing to restore
	end
	if e.LeadHidden then
		setLeadHidden(e, false) -- a streamed-out rig can come back as the same instance: never leave it hidden
	end
	for i = 1, guardN do
		if guard[i] == e then
			guard[i] = guard[guardN]
			guard[guardN] = nil
			guardN -= 1
			break
		end
	end
	byRig[e.Rig] = nil
	local last = entries[#entries]
	entries[e.Index] = last
	last.Index = e.Index
	entries[#entries] = nil
	stats.Registered = #entries
end

-- insertion into a fixed buffer of the best `cap` (ascending Key); returns the new count
local function insertBest(buf: { Entry? }, n: number, cap: number, e: Entry): number
	if n < cap then
		n += 1
		buf[n] = e
	elseif cap > 0 and e.Key < (buf[n] :: Entry).Key then
		buf[n] = e
	else
		return n
	end
	local i = n
	while i > 1 and (buf[i - 1] :: Entry).Key > (buf[i] :: Entry).Key do
		buf[i - 1], buf[i] = buf[i], buf[i - 1]
		i -= 1
	end
	return n
end

--[[ v115 (ArmyConfig.Follow3.EscortTrail, docs/ARMY-FOLLOW-ROOTCAUSE-3.md): escort figures are client-drawn copies of
	a unit; the server's TrailBlock formation keeps a cell for each of them in the rows DIRECTLY BEHIND their unit (same
	column, Follow3.RowSpacing apart). Here escort i (its stable escLayout Index, never a pairs() order) stands i x
	RowSpacing of path behind its unit along the unit's OWN walked path (a per-unit breadcrumb trail, CrumbStep apart,
	a backtrack pruned), so a turning unit's escorts walk round the corner behind it like the rows do, instead of
	a rigid file / side row swinging with its yaw (v114: the side-row wings, gone). Past the trail's end they run on
	straight back (its last direction, else -WE_FormYaw, else the root's back). One RootJoint C0 write per escort only
	when it moved > 0.05 studs; runs with the camera guard (GuardHz). ]]
local ESC_CRUMB = 0.4
local escTrail: { [Instance]: { Vector3 } } = setmetatable({}, { __mode = "k" }) :: any

local function escTrailStep(host: Instance, pos: Vector3, keep: number): { Vector3 }
	local pts = escTrail[host]
	if pts == nil then
		pts = {}
		escTrail[host] = pts
	end
	local p = Vector3.new(pos.X, pos.Y, pos.Z)
	-- a backtrack (it walks back over its own trail): drop the points now ahead of it
	while #pts >= 2 do
		local a, b = pts[#pts - 1], pts[#pts]
		local seg = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local to = Vector3.new(p.X - b.X, 0, p.Z - b.Z)
		if seg:Dot(to) < 0 and to.Magnitude > 0.05 then
			table.remove(pts)
		else
			break
		end
	end
	local last = pts[#pts]
	if last == nil or Vector3.new(p.X - last.X, 0, p.Z - last.Z).Magnitude >= ESC_CRUMB then
		table.insert(pts, p)
	end
	-- keep `keep` studs of path
	local arc, cut = 0, 0
	for k = #pts, 2, -1 do
		arc += Vector3.new(pts[k].X - pts[k - 1].X, 0, pts[k].Z - pts[k - 1].Z).Magnitude
		if arc > keep then
			cut = k - 2
			break
		end
	end
	for _ = 1, cut do
		table.remove(pts, 1)
	end
	return pts
end

local function layoutEscorts(e: Entry)
	if follow3 == nil or follow3.Enabled ~= true or follow3.EscortTrail == false then
		return
	end
	local host, root = e.Host, e.Root
	if host == nil or root == nil or #e.Escorts == 0 then
		return
	end
	local spacing = tonumber(follow3.RowSpacing) or 4.5
	local rcf = root.CFrame
	local pos = rcf.Position
	local pts = escTrailStep(host, pos, spacing * (#e.Escorts + 1) + 2)
	-- the run-on direction (backwards) past the trail's end
	local back: Vector3
	if #pts >= 2 then
		local a, b = pts[1], pts[2]
		back = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	else
		local yaw = host:GetAttribute("WE_FormYaw")
		if typeof(yaw) == "number" then
			local r = math.rad(yaw)
			back = -Vector3.new(math.sin(r), 0, math.cos(r))
		else
			back = -Vector3.new(rcf.LookVector.X, 0, rcf.LookVector.Z)
		end
	end
	back = if back.Magnitude > 1e-3 then back.Unit else Vector3.new(0, 0, 1)
	for _, x in ipairs(e.Escorts) do
		local L = escLayout[x]
		if L then
			-- the point L.Index x spacing of path behind the unit (root -> newest crumb -> older ...)
			local want = L.Index * spacing
			local prev = pos
			local at: Vector3? = nil
			local s = 0
			for k = #pts, 1, -1 do
				local q = pts[k]
				local seg = Vector3.new(q.X - prev.X, 0, q.Z - prev.Z).Magnitude
				if s + seg >= want and seg > 1e-4 then
					at = prev:Lerp(q, (want - s) / seg)
					break
				end
				s += seg
				prev = q
			end
			local pt: Vector3 = at or (prev + back * (want - s))
			local lo = rcf:PointToObjectSpace(pt)
			lo = Vector3.new(lo.X, math.clamp(lo.Y, -3, 3), lo.Z)
			local old = L.Off
			if old == nil or (old - lo).Magnitude > 0.05 then
				L.Off = lo
				L.Joint.C0 = CFrame.new(lo) * ROOT_ROT
			end
		end
	end
end

-- camera guard (every pass and, alone, Escort.Camera.GuardHz times a second): no escort between the camera and the
-- player, none taller than MaxScreenFrac of the screen; no own squad unit between the camera and the player drawn
-- taller than LeadScreenFrac of it. Only the guard buffer (picked figures with escorts, own units): no tables, no scans.
local function cameraGuard(camCf: CFrame, focus: Vector3?, fovDeg: number?)
	if guardN == 0 then
		return
	end
	stats.GuardPasses += 1
	local camPos = camCf.Position
	local look = camCf.LookVector
	local fov = math.clamp(tonumber(fovDeg) or 70, 1, 120)
	local tanHalf = math.tan(math.rad(fov) / 2)
	local minDepth = camCfg.FigureStuds / (2 * camCfg.MaxScreenFrac * tanHalf) + camCfg.DepthMarginStuds
	local playerDist = if focus then (focus - camPos).Magnitude + camCfg.PlayerMarginStuds else -math.huge
	local hyst = camCfg.ShowHysteresisStuds
	local leadFrac = tonumber(camCfg.LeadScreenFrac) or 0
	local leadDepth = if leadFrac > 0 then camCfg.FigureStuds / (2 * leadFrac * tanHalf) + camCfg.DepthMarginStuds else -math.huge
	local feet = camCfg.RootToFeetStuds
	-- a unit's body line runs from its feet (root - RootToFeetStuds) to its head top (FigureStuds above the feet); its
	-- nearest point along the view is the head top when the camera looks down, the feet when it looks up
	local nearLift = math.min(-feet * look.Y, (camCfg.FigureStuds - feet) * look.Y)
	for i = 1, guardN do
		local e = guard[i] :: Entry
		layoutEscorts(e) -- v115: escorts on the unit's own path behind it (before the guard judges where they are)
		for _, x in ipairs(e.Escorts) do
			local t = x.Torso
			if t then
				local v = t.Position - camPos
				local depth = v:Dot(look)
				local dist = v.Magnitude
				if x.Hidden then
					if depth >= minDepth + hyst and dist >= playerDist + hyst then
						setEscortHidden(x, false)
					end
				elseif depth < minDepth or dist < playerDist then
					setEscortHidden(x, true)
				end
			end
		end
		local root = e.Root
		if e.Own and root then
			local v = root.Position - camPos
			-- depth along the view sets how large the phone draws it, at the screen's wide corners too (distance does not)
			local near = v:Dot(look) + nearLift
			local d = v.Magnitude
			if e.LeadHidden then
				if near >= leadDepth + hyst or d >= playerDist + hyst then
					setLeadHidden(e, false)
				end
			elseif near < leadDepth and d < playerDist then
				setLeadHidden(e, true)
			end
		end
	end
end

-- ── v119 helmet budget ───────────────────────────────────────────────────────────────────────────────────────────
-- A cloth body (Army Soldier) is 60 triangles of blocks + a 2103-triangle FAST helmet; a Roblox-body figure is
-- Budget.TrianglesPerMeshedFigure (its beret included). Every meshed figure (and escort) pays its body; helmets then go
-- in pick order (own army first, nearest next, statues last) while the total stays inside Budget.MaxMeshedTriangles.
-- A unit's escorts share its helmet decision. Only a flip writes LocalTransparencyModifier.
local helmOrder: { Entry? } = {}

local function setHelmet(e: Entry, on: boolean)
	local off = not on
	if e.HelmetOff ~= off then
		e.HelmetOff = off
		if e.Beret then
			e.Beret.LocalTransparencyModifier = if e.Far or e.LeadHidden or off then 1 else 0
		end
	end
	for _, x in ipairs(e.Escorts) do
		local hb = escHelm[x]
		if hb and hb.Off ~= off then
			hb.Off = off
			hb.Part.LocalTransparencyModifier = if x.Hidden or off then 1 else 0
		end
	end
end

local function helmetBudget(hn: number)
	local budget = tonumber(RigConfig.Budget.MaxMeshedTriangles) or math.huge
	local roblox = tonumber(RigConfig.Budget.TrianglesPerMeshedFigure) or 0
	local body = tonumber(clothCfg.BodyTris) or 0
	local helm = tonumber(clothCfg.HeadwearTris) or 0
	local used = 0
	local sn = hn
	for _, e in ipairs(entries) do
		if (e.Picked or e.SPicked) and not e.Far and e.HasLod then
			used += (if #e.Cloth > 0 then body else roblox) * (1 + #e.Escorts)
			if e.SPicked then
				sn += 1
				helmOrder[sn] = e -- statues after the animated pick
			end
		end
	end
	local on, off = 0, 0
	for i = 1, sn do
		local e = helmOrder[i] :: Entry
		helmOrder[i] = nil
		if #e.Cloth > 0 and e.Beret and not e.Far then
			local want = helm * (1 + #e.Escorts)
			local show = used + want <= budget
			if show then
				used += want
				on += 1 + #e.Escorts
			else
				off += 1 + #e.Escorts
			end
			setHelmet(e, show)
		end
	end
	stats.HelmetsOn = on
	stats.HelmetsOff = off
	stats.MeshedTris = used
end

-- ── one LOD pass (also the test hook) ────────────────────────────────────────────────────────────────────────────
-- now = os.clock(); camCf = the camera CFrame; focus = the local player's root position (nil: none); fovDeg = the
-- camera's vertical field of view
function RigAnimator._Step(now: number, camCf: CFrame, focus: Vector3?, fovDeg: number?)
	local camPos = camCf.Position
	local dt = if lastStep > 0 then math.max(now - lastStep, 1e-3) else 0
	lastStep = now
	local near = cfg.NearStuds
	local maxN = cfg.MaxAnimated
	local maxS = math.max(0, math.floor(tonumber(lod.MaxMeshedStatic) or 0))
	local farAt = tonumber(lod.FarMeshStuds) or 0
	pickN = 0
	spickN = 0
	local sticky = tonumber(cfg.StickyStuds) or 0
	for _, e in ipairs(entries) do
		e.Key = math.huge
		e.Dist = math.huge
		if resolve(e) then
			local pos = (e.Root :: BasePart).Position
			local lp = e.LastPos
			if lp and dt > 0 then
				local dx, dz = pos.X - lp.X, pos.Z - lp.Z
				e.Speed = math.sqrt(dx * dx + dz * dz) / dt
			end
			e.LastPos = pos
			local d = pos - camPos
			local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
			e.Dist = math.sqrt(d2)
			if e.Static and cfg.AnimateStatic ~= true then
				-- statues: the nearest maxS within FarMeshStuds wear the Roblox body (sticky while they do)
				local reach = farAt + (if not e.Far then lod.HysteresisStuds else 0)
				if maxS > 0 and d2 <= reach * reach then
					e.Key = e.Dist - (if not e.Far then sticky else 0)
					spickN = insertBest(spick, spickN, maxS, e)
				end
			else
				local reach = near + (if e.Tracks then cfg.HysteresisStuds else 0)
				if d2 <= reach * reach then
					e.Key = e.Dist - (if e.Tracks then sticky else 0) + (if e.Own then OWN_BIAS else 0)
					pickN = insertBest(pick, pickN, maxN, e)
				end
			end
		end
	end
	for _, e in ipairs(entries) do
		e.Picked = false
		e.SPicked = false
	end
	for i = 1, pickN do
		(pick[i] :: Entry).Picked = true
	end
	for i = 1, spickN do
		(spick[i] :: Entry).SPicked = true
		spick[i] = nil
	end
	-- figures that fell out of the pick stop (and lose their escorts); anything not meshed-by-pick shows blocks
	-- at once (never delayed: it only lowers the load)
	local meshed, meshedStatic = 0, 0
	for _, e in ipairs(entries) do
		if not e.Picked and (e.Tracks or #e.Escorts > 0) then
			stopAll(e)
		end
		if not e.Picked and not e.SPicked and #e.Meshes > 0 then
			setFar(e, true)
		elseif not e.Picked and not e.SPicked and e.HasLod then
			setFar(e, true) -- v119: a cloth body (no FileMesh limbs) goes to its kit-colour blocks too
		end
		if e.LeadHidden and not e.Picked then
			setLeadHidden(e, false) -- out of the guard buffer: shown again
		end
	end
	-- blocks -> Roblox body for picked figures, at most MaxSwapsPerTick per pass
	local swaps = 0
	for _, e in ipairs(entries) do
		if (e.Picked or e.SPicked) and e.Far and swaps < lod.MaxSwapsPerTick then
			setFar(e, false)
			swaps += 1
		end
		if not e.Far and e.HasLod then
			if e.SPicked then
				meshedStatic += 1
			else
				meshed += 1
			end
		end
	end
	local activations, animated = 0, 0
	for i = 1, pickN do
		local e = pick[i] :: Entry
		e.WantEsc = 0
		if e.Tracks == nil then
			if activations >= cfg.MaxActivationsPerTick or e.Far then
				continue -- spread LoadAnimation; a figure starts moving once it wears the Roblox body (next pass)
			end
			activations += 1
			setHoldBaked(e, false) -- the Hold track lifts the arm itself
			e.Tracks = loadTracks(e.Animator, e.Armed, true)
		end
		local want = if e.Speed >= cfg.WalkMinStuds then "Walk" elseif e.AimUntil > now then "Aim" else "Idle"
		if e.State ~= want or want == "Walk" then
			applyState(e.Tracks, e.Armed, want, e.Speed)
			e.State = want
		end
		animated += 1
		if e.Squad and e.Host and esc.Enabled == true then
			local reach = esc.NearStuds + (if #e.Escorts > 0 then esc.HysteresisStuds else 0)
			if e.Dist <= reach then
				e.WantEsc = math.clamp(math.floor(tonumber(e.Host:GetAttribute("WE_Escorts")) or 0), 0, math.min(esc.MaxPerUnit, #esc.Offsets))
			end
		end
	end
	-- escorts inside Escort.MaxPerClient: (1) the own army takes what it wants, in pick order; (2) other armies keep the
	-- escorts they already have (no churn when figures swap places in the crowd); (3) other armies grow with what is left
	local room = if esc.Enabled == true then esc.MaxPerClient else 0
	local builds = 0
	for i = 1, pickN do
		local e = pick[i] :: Entry
		if e.Own and e.Tracks then
			local allow = math.min(e.WantEsc, room)
			while #e.Escorts > allow do
				dropEscort(e)
			end
			while #e.Escorts < allow and builds < esc.MaxBuildsPerTick do
				local x = buildEscort(e, esc.Offsets[#e.Escorts + 1], #e.Escorts + 1)
				builds += 1
				if x == nil then
					break
				end
				table.insert(e.Escorts, x)
			end
			room -= allow
		end
	end
	for i = 1, pickN do
		local e = pick[i] :: Entry
		if not e.Own then
			local keep = if e.Tracks then math.min(#e.Escorts, e.WantEsc, math.max(0, room)) else 0
			while #e.Escorts > keep do
				dropEscort(e)
			end
			room -= keep
		end
	end
	local gn = 0
	local hn = 0
	local leadOn = (tonumber(camCfg.LeadScreenFrac) or 0) > 0 -- off: own units without escorts need no guard runs
	for i = 1, pickN do
		local e = pick[i] :: Entry
		pick[i] = nil
		hn += 1
		helmOrder[hn] = e -- v119: helmets in pick order (own army first, then nearest)
		if not e.Own and e.Tracks then
			while #e.Escorts < e.WantEsc and room > 0 and builds < esc.MaxBuildsPerTick do
				local x = buildEscort(e, esc.Offsets[#e.Escorts + 1], #e.Escorts + 1)
				builds += 1
				if x == nil then
					break
				end
				table.insert(e.Escorts, x)
				room -= 1
			end
		end
		for _, x in ipairs(e.Escorts) do
			if x.State ~= e.State or e.State == "Walk" then
				applyState(x.Tracks, true, if e.State == "Aim" then "Idle" else e.State, e.Speed)
				x.State = e.State
			end
		end
		if #e.Escorts > 0 or (e.Own and leadOn) then
			gn += 1
			guard[gn] = e
		end
	end
	for i = gn + 1, guardN do
		guard[i] = nil
	end
	guardN = gn
	cameraGuard(camCf, focus, fovDeg)
	helmetBudget(hn) -- v119: after the escorts of this pass exist
	stats.Passes += 1
	stats.Animated = animated
	stats.Meshed = meshed
	stats.MeshedStatic = meshedStatic
end

-- WeaponFx (S = 0: an NPC shot; O = its eye): the animated figure at that origin aims for AimSeconds.
function RigAnimator._OnFx(p: any)
	if typeof(p) ~= "table" or p.S ~= 0 or typeof(p.O) ~= "Vector3" or p.K == "L" or p.K == "X" then
		return
	end
	local o = p.O :: Vector3
	local r2 = cfg.AimMatchStuds * cfg.AimMatchStuds
	for _, e in ipairs(entries) do
		local root = e.Root
		if e.Tracks and root then
			local pos = root.Position
			local dx, dz = pos.X - o.X, pos.Z - o.Z
			if dx * dx + dz * dz <= r2 then
				e.AimUntil = os.clock() + cfg.AimSeconds
				if e.Speed < cfg.WalkMinStuds then
					applyState(e.Tracks, e.Armed, "Aim", 0)
					e.State = "Aim"
				end
				return
			end
		end
	end
end

function RigAnimator._Stats(): { [string]: number }
	return table.clone(stats)
end

local started = false
function RigAnimator.Init()
	if started or RigConfig.Enabled ~= true or cfg.Enabled ~= true then
		return
	end
	started = true
	local lp = Players.LocalPlayer
	localUserId = if lp then lp.UserId else 0
	for _, r in ipairs(CollectionService:GetTagged(TAG)) do
		add(r)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
	task.spawn(function()
		local Remotes = require((Shared :: any).Remotes) :: any
		local Constants = require((Shared :: any).Constants) :: any
		for _ = 1, 60 do
			local ev = Remotes.TryGetUnreliableEvent(Constants.RemoteNames.WeaponFx)
			if ev then
				ev.OnClientEvent:Connect(RigAnimator._OnFx)
				break
			end
			task.wait(1)
		end
	end)
	task.spawn(function()
		local period = 1 / math.clamp(tonumber(cfg.TickHz) or 4, 1, 10)
		while true do
			task.wait(period)
			local cam = Workspace.CurrentCamera
			if cam then
				local ch = if lp then lp.Character else nil
				local hrp = if ch then ch:FindFirstChild("HumanoidRootPart") else nil
				local focus = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
				RigAnimator._Step(os.clock(), cam.CFrame, focus, cam.FieldOfView)
			end
		end
	end)
	local guardHz = tonumber(camCfg.GuardHz) or 0
	if guardHz > 0 then
		task.spawn(function() -- the camera guard alone between passes (a camera swipe, a turning unit's file)
			local gp = 1 / math.clamp(guardHz, 1, 60)
			local idle = 1 / math.clamp(tonumber(cfg.TickHz) or 4, 1, 10)
			while true do
				task.wait(if guardN > 0 then gp else idle) -- nothing to guard: sleep one LOD pass
				local cam = Workspace.CurrentCamera
				if cam and guardN > 0 then
					local ch = if lp then lp.Character else nil
					local hrp = if ch then ch:FindFirstChild("HumanoidRootPart") else nil
					cameraGuard(cam.CFrame, if hrp and hrp:IsA("BasePart") then hrp.Position else nil, cam.FieldOfView)
				end
			end
		end)
	end
end

return RigAnimator
