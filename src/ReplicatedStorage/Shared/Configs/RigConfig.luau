--!strict
--[[
	RigConfig (R-RIG): animated soldier figures and the escorts that make an army look bigger as it grows.

	Server (VisualAssetService + RigBuilder): a soldier's Part-kit body is swapped ONCE, when it spawns, for the Roblox
	"Soldier" R6 body (VisualAssetConfig.Characters rows with Rig = "R6"). The host keeps its HumanoidRootPart (collider,
	Humanoid root) and Humanoid; the kit Head (headshot part), Helmet, Rifle and Pack move INTO the rig sub-model
	"WE_Rig" with the Soldier's torso and limbs. The server never plays an animation. A host that asked while the
	Soldier file was still loading or waiting for a retry gets the rig when the file arrives (VisualAssetService).
	Server (SquadOrdersService.SyncArmy): each squad unit carries WE_Escorts = how many escort figures it shows
	(RigConfig.EscortsFor: soldiers owned, units in the field, Barracks level; EscortShare: the front pair first).
	Client (RigAnimator): animates the nearest figures only, builds the escorts LOCALLY (never replicated, never hit by
	a shot, never on the server) inside the per-device budget below, hides any escort that would stand between the
	camera and the player, and shows every figure it does not animate as plain blocks with the rifle held forward.
	Animation ids: Roblox-owned R6 animations (creator Roblox): they play in any experience.
]]

local RigConfig = {
	Enabled = true, -- false: VisualAssetService never rigs (every soldier keeps its Part kit, no escorts) and clients do nothing
	Tag = "WE_Rig", -- CollectionService tag on every server-built soldier rig (clients find figures by it)

	-- The host Humanoid (server, set once at attach). RigType "Keep" leaves the kit's default untouched (HEAD
	-- behaviour); "R15" is the Studio fallback if the Humanoid ever measures hip height from the rig's legs (spec §10).
	Host = {
		RigType = "Keep", -- "Keep" | "R15"
		RequiresNeck = false, -- a rig Neck can never kill the host; the server decides death by Health, as today
	},

	-- Hit silhouette (owner decision R4, default "keep today's"): the rig Torso becomes a queryable hit box this deep
	-- (FileMesh bodies ignore the part size, so the look does not change). 1.45 puts the side-on hit area of every
	-- hostile kind back at today's (the kit rifle / stock were hittable); 0 = the rig Torso is not hittable.
	Hit = {
		TorsoDepth = 1.45,
	},

	Anim = {
		Enabled = true, -- false: rigs stay in their rest pose, no tracks on any client
		TickHz = 4, -- client LOD pass rate (task.wait loop; the camera guard also runs alone at Escort.Camera.GuardHz; never RenderStepped / Heartbeat)
		NearStuds = 120, -- beyond this a figure is not animated (rest pose)
		HysteresisStuds = 10, -- an animated figure stops only past NearStuds + this
		MaxAnimated = 24, -- figures animated per client (own army first, then nearest); escorts counted apart
		MaxActivationsPerTick = 6, -- figures that start animating per pass (spreads LoadAnimation)
		StickyStuds = 15, -- an animated figure keeps its place in the pick until another is this much closer (no churn)
		WalkMinStuds = 1.5, -- studs/s of flat root movement that counts as walking
		WalkSpeedRef = 14.5, -- Walk track speed = figure speed / WalkSpeedRef (clamped)
		WalkRateMin = 0.6,
		WalkRateMax = 2.4, -- claude-bud JOB 22: up to the army catch-up speed (34 studs/s / 14.5): no foot sliding
		AimSeconds = 1.2, -- after an NPC shot (WeaponFx S = 0) the shooter plays Aim this long, if standing
		AimMatchStuds = 3, -- a shot's origin within this many studs (flat) of a figure's root = its shot
		FadeSeconds = 0.2,
		AnimateStatic = false, -- anchored base statues (WE_RigStatic) keep their baked pose and never load a track
		StaticHoldDeg = 89, -- the Hold keyframe's right-arm angle (0 = arm down at the side)
		HoldUntracked = true, -- an armed figure with no tracks (not picked / far / not loaded yet) holds its rifle
		-- forward: the client turns its Right Shoulder C0 by StaticHoldDeg locally, and back before Hold plays
		Ids = {
			Hold = 182393478, -- "ToolLoopAnimation" (Roblox): right arm forward, the rifle points ahead (Idle priority)
			Idle = 180435571, -- "Idle1LoopAnimation" (Roblox), Core priority
			Walk = 180426354, -- "WalkLoopAnimation" (Roblox), Core priority
			Aim = 183817498, -- "Soldier Aiming" (Roblox; the Soldier file's own), Action priority
		},
	},

	-- Mesh LOD: only the figures this client animates (the pick, <= Anim.MaxAnimated), the nearest MaxMeshedStatic
	-- base statues within FarMeshStuds and the escorts wear the Roblox body (FileMesh); every other figure shows plain
	-- blocks (SpecialMesh.MeshType Brick, local only) with its beret hidden. That bounds soldier triangles per phone at
	-- (MaxAnimated + MaxMeshedStatic + Escort.MaxPerClient) x Budget.TrianglesPerMeshedFigure however big the crowd.
	Lod = {
		FarMeshStuds = 120, -- statues past this never get the Roblox body (= Anim.NearStuds)
		HysteresisStuds = 15,
		MaxMeshedStatic = 8, -- statues shown with the Roblox body at once (nearest first)
		MaxSwapsPerTick = 12, -- blocks -> Roblox body per pass (Roblox body -> blocks is never delayed)
	},

	-- Escorts (army decision D14, 2026-09-27: "the army on screen grows"): client-only copies of a squad unit's body that
	-- march with it. Server cost 0 (no part, no Humanoid, no network); each client caps them by its own budget.
	Escort = {
		Enabled = true,
		SquadSizeBase = 2, -- soldiers one unit can stand for = SquadSizeBase + SquadSizePerBarracks x Barracks (1..5)
		SquadSizePerBarracks = 2,
		BarracksMin = 1, -- a Barracks-0 base counts as level 1 here (squads of 4)
		BarracksMax = 5,
		SoldiersPerEscort = 4, -- one escort figure per this many fielded soldiers beyond one per unit
		MaxPerArmy = 12, -- escorts per army (all units together): own army up to 8 units + 12 = 20 figures (owner D14-a)
		MaxPerUnit = 3, -- = #Offsets
		MaxPerClient = 22, -- escorts built on one client (owner D14-b): (Budget.PhoneFigureParts - Budget.LeadFigureParts)
		-- / Budget.PartsPerEscort = (940 - 760) / 8; re-derive when the Front garrison ships (army lane)
		NearStuds = 90, -- escorts only for an animated unit this close to the camera
		HysteresisStuds = 10,
		MaxBuildsPerTick = 4, -- escort bodies cloned per pass
		-- In the unit's own frame (-Z = ahead of it; a unit in its Follow slot faces where the player faces): a file of up
		-- to three AHEAD of the unit, out of the corridor between the third-person camera and the player (behind him).
		-- 7 / 2.4 steps: no figure overlaps a unit, another escort or the player for 1-8 units (FollowSlots + ranks), and
		-- with the camera straight behind the player every escort is past the guard's show line (v3/camera3.py).
		Offsets = { Vector3.new(0, 0, -7), Vector3.new(0, 0, -9.4), Vector3.new(0, 0, -11.8) } :: { Vector3 },
		-- Camera guard (client, every pass + GuardHz): an escort is hidden while its root is nearer the camera than the
		-- local player's root + PlayerMarginStuds, or closer along the view than FigureStuds / (2 x MaxScreenFrac x
		-- tan(FOV / 2)) + DepthMarginStuds (it would cover more than MaxScreenFrac of the screen height). It shows
		-- again ShowHysteresisStuds past both lines. Hidden = every part AND every Decal (the kit head's face) of it.
		Camera = {
			MaxScreenFrac = 0.25,
			FigureStuds = 5.3, -- feet to beret / helmet top
			DepthMarginStuds = 0.25,
			PlayerMarginStuds = 0.5,
			ShowHysteresisStuds = 0.5,
			-- faces lane (owner screenshot, v83): the guard also runs on its own GuardHz times a second (0 = off: only in
			-- the 4 Hz pass; BuyPathStatic allows 0 or 20-60). A camera swipe or a turning unit swings an escort file (a
			-- rigid 7-11.8 stud arm) through the camera faster than a 4 Hz pass follows. Each run reads <= Anim.MaxAnimated
			-- roots and <= MaxPerClient torsos; with nothing to guard the loop sleeps a whole pass.
			GuardHz = 30,
			-- an own squad unit (a real unit) nearer the camera than the player and drawn taller than this share of the
			-- screen height is hidden on this client the same way: the nearest point of its body along the view is closer
			-- than FigureStuds / (2 x LeadScreenFrac x tan(FOV / 2)) + DepthMarginStuds. Depth, not distance: a phone in
			-- landscape sees about 113 degrees across, so a soldier 5-6 studs off to the side still fills a bottom corner
			-- (the owner's camo "blob"). Shows ShowHysteresisStuds past either line. 0 = off (BuyPathStatic allows 0 or
			-- 0.8-1.0; lower hides wing soldiers of a running army at the default zoom).
			LeadScreenFrac = 0.9,
			RootToFeetStuds = 3, -- a squad unit's root to its feet (root half-height 1 + Humanoid.HipHeight 2)
		},
	},

	-- Figure budget (BuyPathStatic pins these; the census driver checks them)
	Budget = {
		MaxPartsPerFigure = 10, -- host root + Torso + 4 limbs + Head + headwear + Rifle (+ Pack on heavy kinds)
		PartsPerEscort = 8, -- Torso + 4 limbs + Head + headwear + Rifle (no root, no Humanoid)
		PhoneFigureParts = 940, -- today's (HEAD) moving-figure parts on a phone: 48 squads x 9 + 22 NPCs x 16 + 12 guards x 13
		LeadFigureParts = 760, -- the same figures rigged: 48 x 9 + 22 x 10 + 12 x 9
		TrianglesPerMeshedFigure = 1530, -- Roblox body: limbs 282 + 282 + 204 + 204, torso 216, beret 342
		MaxMeshedTriangles = 85000, -- (MaxAnimated + Lod.MaxMeshedStatic + Escort.MaxPerClient) x 1530 must stay under
	},
}

-- Soldiers one unit can stand for at this Barracks level (4 / 6 / 8 / 10 / 12).
function RigConfig.SquadSize(barracks: number): number
	local e = RigConfig.Escort
	local b = math.clamp(math.floor(tonumber(barracks) or 0), e.BarracksMin, e.BarracksMax)
	return e.SquadSizeBase + e.SquadSizePerBarracks * b
end

-- Escort figures for a whole army: soldiers owned, units in the field (5..8), Barracks level. Pure; never negative.
function RigConfig.EscortsFor(soldiers: number, units: number, barracks: number): number
	local e = RigConfig.Escort
	local u = math.max(0, math.floor(tonumber(units) or 0))
	local s = math.max(0, math.floor(tonumber(soldiers) or 0))
	if u == 0 or e.Enabled ~= true then
		return 0
	end
	local fielded = math.min(s, u * RigConfig.SquadSize(barracks))
	local n = math.floor(math.max(0, fielded - u) / math.max(1, e.SoldiersPerEscort))
	return math.clamp(n, 0, math.min(e.MaxPerArmy, u * e.MaxPerUnit))
end

-- The share of `total` escorts for the index-th unit (1-based, in slot order) of `units`: the front pair of slots
-- (1, 2) fills first, alternating left / right, then the pair (3, 4), and so on; a lone last slot takes the rest.
-- Front slots stand nearest the player's line, so their files (Offsets, ahead) are the ones the camera sees.
function RigConfig.EscortShare(total: number, units: number, index: number): number
	local per = RigConfig.Escort.MaxPerUnit
	local t = math.max(0, math.floor(tonumber(total) or 0))
	if units <= 0 or index < 1 or index > units then
		return 0
	end
	local first = if index % 2 == 1 then index else index - 1 -- the pair's first slot
	local pairSize = if first + 1 <= units then 2 else 1
	local left = math.max(0, t - (first - 1) * per) -- escorts not taken by the pairs in front
	local here = math.min(left, per * pairSize)
	if pairSize == 1 then
		return here
	end
	if index == first then
		return math.min(per, (here + 1) // 2)
	end
	return math.min(per, here // 2)
end

return RigConfig
