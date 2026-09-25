--!strict
--[[
	Phase 5 — Territory control.
	Server-authoritative stand-in-zone capture; bonuses for Economy / XP / Vehicles / Combat.

	v71 (HUD v70 spec §5, roadmap W1 F): the capture marker and ring only take the owner colour (no forced Neon,
	no transparency / size writes — World v2 owns their look); the flag is painted (SmoothPlastic) and sits at
	basePos.Y + flagLift − 1 (oil-rig decks too); the zone label is one stud-scaled WorldLabel with the zone name
	in the owner colour (capture % and "contested" live on the HUD capture bar); the WE_FlagBillboard diamond is
	28 px and draws through walls only while contested (WorldLabel.SetRole). No "Capturing X..." toast.

	Owner's 11 features, lane W:
	  F3  Empire Tax. Capture / loss / steal toasts are EconomyConfig.OutpostIncomeBuff templates with the player's
	      TOTAL Empire Tax % (EconomyService.SyncOutpostIncomeStacks recounts it from profile.Territories).
	      PersistClaims (flag): on join, replantClaims re-plants the saved claims onto Neutral / NPC-held zones (a zone
	      another online player holds is dropped with the ToastClaimHeld toast), and on leave the leaver's zones go back
	      to Neutral (the saved claims are NOT wiped, so the next server re-plants them). Off = the old soft release.
	  F6  A shielded novice standing in a contested zone loses the novice shield (CombatService.EndNoviceShield
	      "contest", pcall).
	  F10 Home Outposts (TerritoryConfig.Starter rows, IsStarterId): owner-only capture (TerritoryCapture), 10 s,
	      +StarterPct Empire Tax, never a stack, never counted toward MaxPersonalTerritories, never evicted or stolen,
	      no stipend, no light or stripe. The first capture sets profile.StarterOutpostTaken; later the plot owner holds
	      it automatically on BaseService.OnPlotReady. It goes back to Neutral when the owner leaves or the plot changes
	      hands. Other plots' Home Outposts are not in a player's territory list (TerritoryRadar.ShownTo).
	  Nations B2: the contested pulse and the capture HUD fall back to amber when the two nation colours are closer
	      than NationConfig.ContestMinColorDistance; an owned zone never takes a colour that reads as NPC red, Clan
	      blue or contested amber (legacy roster colour, else green); a leaver's colour is kept while that UserId still
	      owns a zone (R15, then dropped); outpost nation flags (Textures only, never a SurfaceGui) and their sizes sit
	      behind NationConfig.OutpostFlags (off), shown only on a Player-owned, uncontested zone (RefreshOwnerFlags).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local WorldLabel = require(Shared.Util.WorldLabel)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig) -- F3 toasts + PersistClaims (EconomyConfig requires nothing)
local NationConfig = require(Shared.Configs.NationConfig) -- B2: contest colour distance, OutpostFlags
local NationColorConfig = require(Shared.Configs.NationColorConfig) -- B2: the legacy roster colour fallback
local NationTexture = require(Shared.Util.NationTexture) -- B2: outpost flag Textures (behind OutpostFlags)

local TerritoryRadar = require(script.TerritoryRadar)
local TerritoryOwnership = require(script.TerritoryOwnership)
local TerritoryCapture = require(script.TerritoryCapture)

type TerritoryDef = TerritoryConfig.TerritoryDef

type TerritoryRuntime = {
	Id: string,
	Def: TerritoryDef,
	OwnerType: string,
	OwnerUserId: number, -- 0 neutral, -1 NPC, else player
	ClanId: string?,
	Progress: number, -- seconds accumulated toward capture
	CapturingUserId: number, -- 0 if none
	ProtectedUntil: number, -- unix
	Contested: boolean,
	-- v38: up to two contester UserIds for dual nation-color pulse
	ContesterA: number?,
	ContesterB: number?,
	Marker: BasePart?,
}

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local TerritoryService = {}

local ClanWarService: any = nil

local DataService: any = nil
local _EconomyService: any = nil
local _XPService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local MissionService: any = nil
local TutorialService: any = nil
local RemoteSetup: any = nil
local BaseService: any = nil
local NationColorService: any = nil
local CombatService: any = nil -- F6: EndNoviceShield("contest")

local territories: { [string]: TerritoryRuntime } = {}
local firstOutpostLogged: { [number]: boolean } = {}
local lastPushAt = 0
local pushDirty = true

local function ownerTypes()
	return TerritoryConfig.OwnerTypes
end

local function nowUnix(): number
	return os.time()
end

local function findMarker(territoryId: string): BasePart?
	return TerritoryRadar.FindMarker(territoryId)
end

local function ensureRuntime()
	for id, def in pairs(TerritoryConfig.Territories) do
		if not territories[id] then
			territories[id] = {
				Id = id,
				Def = def,
				OwnerType = ownerTypes().Neutral,
				OwnerUserId = TerritoryConfig.NeutralOwnerId,
				ClanId = nil,
				Progress = 0,
				CapturingUserId = 0,
				ProtectedUntil = 0,
				Contested = false,
				Marker = findMarker(id),
			}
		elseif not territories[id].Marker or not territories[id].Marker.Parent then
			territories[id].Marker = findMarker(id)
		end
	end
end

local function countPersonalTerritories(userId: number): number
	local n = 0
	for _, rt in pairs(territories) do
		if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == userId then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------
-- F10 Home Outposts (TerritoryConfig.Starter rows)
---------------------------------------------------------------------------------------------------------------

--[[ F10 (spec §2 cross-lane API): true for a Home Outpost id (a TerritoryConfig.Starter row, only while
	Starter.Enabled). Never yields. ]]
function TerritoryService.IsStarterId(id: any): boolean
	if typeof(id) ~= "string" then
		return false
	end
	return TerritoryConfig.IsStarterDef(TerritoryConfig.Territories[id])
end

local function isStarterRt(rt: TerritoryRuntime): boolean
	return TerritoryConfig.IsStarterDef(rt.Def)
end

-- the runtime of plot plotId's Home Outpost, or nil (Starter off / unknown plot)
local function starterRtForPlot(plotId: any): TerritoryRuntime?
	if typeof(plotId) ~= "number" then
		return nil
	end
	local st = TerritoryConfig.Starter
	local id = tostring(st.IdPrefix) .. tostring(plotId)
	local rt = territories[id]
	if rt and isStarterRt(rt) and rt.Def.PlotId == plotId then
		return rt
	end
	return nil
end

-- F10: personal zones that count toward MaxPersonalTerritories (a Home Outpost never does)
local function countPersonalNonStarter(userId: number): number
	local n = 0
	for _, rt in pairs(territories) do
		if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == userId and not isStarterRt(rt) then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------
-- Nations B2: colours that never read as NPC / Clan / contested, and the R15 leaver cache
---------------------------------------------------------------------------------------------------------------

local AMBER = Color3.fromRGB(255, 140, 35) -- contested
local NPC_RED = Color3.fromRGB(210, 45, 45) -- NPC-held
local CLAN_BLUE = Color3.fromRGB(70, 120, 240) -- clan-held
local OWNED_FALLBACK = Color3.fromRGB(55, 210, 95) -- a player-held zone with no usable colour

-- RGB distance (0..1.73)
local function colorDistance(a: Color3, b: Color3): number
	local dr, dg, db = a.R - b.R, a.G - b.G, a.B - b.B
	return math.sqrt(dr * dr + dg * dg + db * db)
end

local function tooClose(a: Color3, b: Color3): boolean
	local minD = tonumber((NationConfig :: any).ContestMinColorDistance) or 0.25
	return colorDistance(a, b) < minD
end

-- a colour that would read as NPC-held, clan-held or contested
local function nearReserved(c: Color3): boolean
	return tooClose(c, NPC_RED) or tooClose(c, CLAN_BLUE) or tooClose(c, AMBER)
end

local function rawNationColor(userId: number?): Color3?
	if typeof(userId) ~= "number" or userId <= 0 or not NationColorService or not NationColorService.GetColor then
		return nil
	end
	local ok, c = pcall(NationColorService.GetColor, userId)
	return if ok and typeof(c) == "Color3" then c else nil
end

-- the player's legacy 8-colour roster colour (NationColorConfig), or nil
local function legacyRosterColor(userId: number): Color3?
	if not NationColorService or not NationColorService.GetColorId then
		return nil
	end
	local ok, id = pcall(NationColorService.GetColorId, userId)
	if not ok or typeof(id) ~= "string" then
		return nil
	end
	for _, def in ipairs(NationColorConfig.Colors) do
		if def.Id == id then
			return def.Color
		end
	end
	return nil
end

--[[ R15: the colour (and nation id, for the outpost flag) of every player who owns a zone, refreshed while they are
	online. NationColorService forgets a leaver at once; this keeps the leaver's entry only while that UserId still
	owns at least one zone, then drops it (pruneOwnerCache), so it never grows with the server's lifetime. ]]
type OwnerLook = { Color: Color3, NationId: string? }
local ownerLookCache: { [number]: OwnerLook } = {}
local FALLBACK_LOOK: OwnerLook = { Color = OWNED_FALLBACK, NationId = nil }

local function nationIdFor(userId: number): string?
	if not NationColorService or not NationColorService.GetNationId then
		return nil
	end
	local ok, id = pcall(NationColorService.GetNationId, userId) -- art-gated: nil until nations may be shown
	return if ok and typeof(id) == "string" then id else nil
end

-- B2 (c): an owned zone's colour. The nation (or legacy) colour, unless it reads as NPC red, Clan blue or contested
-- amber: then the legacy roster colour, else OWNED_FALLBACK. Offline owner: the cached look (R15).
local function ownerLook(userId: number): OwnerLook
	local raw = rawNationColor(userId)
	if raw then
		local c = raw
		if nearReserved(c) then
			local legacy = legacyRosterColor(userId)
			c = if legacy and not nearReserved(legacy) then legacy else OWNED_FALLBACK
		end
		local nid = if NationConfig.OutpostFlags == true then nationIdFor(userId) else nil
		local cached = ownerLookCache[userId]
		if cached and cached.Color == c and cached.NationId == nid then
			return cached
		end
		local look: OwnerLook = { Color = c, NationId = nid }
		ownerLookCache[userId] = look
		return look
	end
	return ownerLookCache[userId] or FALLBACK_LOOK
end

-- R15: drop a UserId's cached look once it owns no zone (called after every release)
local function pruneOwnerCache(userId: number?)
	if typeof(userId) == "number" and ownerLookCache[userId] ~= nil and countPersonalTerritories(userId) == 0 then
		ownerLookCache[userId] = nil
	end
end

-- B2 (a) / (b): the two contester colours, with B replaced by amber when A and B are too close to tell apart, and
-- both dropped (the default amber pulse) when A itself reads as amber.
local function contestColors(rt: TerritoryRuntime): (Color3?, Color3?)
	local colA = rawNationColor(rt.ContesterA)
	local colB = rawNationColor(rt.ContesterB)
	if colA and colB and tooClose(colA, colB) then
		if tooClose(colA, AMBER) then
			return nil, nil
		end
		return colA, AMBER
	end
	return colA, colB
end

---------------------------------------------------------------------------------------------------------------
-- Nations B2 (e): outpost nation flags, behind NationConfig.OutpostFlags (off). Textures only, never a SurfaceGui.
---------------------------------------------------------------------------------------------------------------

local FLAG_TEXTURE_NAMES = { "WE_NationTexA", "WE_NationTexB" }
local FLAG_SHOWN_ATTR = "WE_NationShown"
-- 4:3 flag sizes while OutpostFlags is on (owned / contested / neutral)
local OUTPOST_FLAG_OWNED = Vector3.new(4.8, 3.6, 0.28)
local OUTPOST_FLAG_CONTESTED = Vector3.new(5.2, 3.9, 0.3)
local OUTPOST_FLAG_NEUTRAL = Vector3.new(3.6, 2.7, 0.22)

--[[ Show nationId's flag on a zone flag part (2 Textures on the thin faces, like Modules/NationFlag), or blank them
	(nationId nil, or no art wired). Textures are created only when a flag is first shown. Idempotent: an unchanged
	view writes nothing (WE_NationShown key). Returns true while a nation flag image shows. ]]
local function dressOutpostFlag(flag: BasePart, nationId: string?): boolean
	local def = if nationId then NationConfig.Get(nationId) else nil
	local faceA, faceB, w, h = NationTexture.ThinFaces(flag.Size.X, flag.Size.Y, flag.Size.Z)
	local src = if def then NationTexture.Source(def.Id) else nil
	local props = if src then NationTexture.TextureProps(w, h, src.Rect) else nil
	local image = if src and props then src.Image else ""
	local key = string.format("%s|%.2fx%.2f|%s", if def and image ~= "" then def.Id else "-", w, h, image)
	if flag:GetAttribute(FLAG_SHOWN_ATTR) == key then
		return image ~= ""
	end
	local faces = { faceA, faceB }
	for i, name in ipairs(FLAG_TEXTURE_NAMES) do
		local t = flag:FindFirstChild(name)
		local tex: Texture? = if t and t:IsA("Texture") then t else nil
		if image ~= "" and props then
			if tex == nil then
				local created = Instance.new("Texture")
				created.Name = name
				created.Parent = flag
				tex = created
			end
			local tx = tex :: Texture
			local face = (Enum.NormalId :: any)[faces[i]]
			if tx.Face ~= face then
				tx.Face = face
			end
			tx.Texture = image
			tx.StudsPerTileU = props.StudsPerTileU
			tx.StudsPerTileV = props.StudsPerTileV
			tx.OffsetStudsU = props.OffsetStudsU
			tx.OffsetStudsV = props.OffsetStudsV
			tx.Transparency = 0
		elseif tex then
			tex.Texture = ""
			tex.Transparency = 1
		end
	end
	flag:SetAttribute(FLAG_SHOWN_ATTR, key)
	return image ~= ""
end

local function syncProfileOwnership(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	if typeof(profile.Territories) ~= "table" then
		profile.Territories = {}
	end
	-- Clear then re-apply owned
	for id in pairs(profile.Territories) do
		profile.Territories[id] = nil
	end
	for id, rt in pairs(territories) do
		if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId then
			profile.Territories[id] = true
		end
	end
	DataService.MarkDirty(player)
end

-- Zone label: the zone name only, in the owner colour (spec §5). MapSetup's old "Label" card (name + [NEUTRAL] ·
-- Stand to capture, 220 studs) is replaced by this one stud-scaled WorldLabel above the flag pole.
local ZONE_LABEL_HEIGHT = 16 -- studs above the marker centre (the pole is 14 tall)

local function ensureZoneLabel(rt: TerritoryRuntime, marker: BasePart): BillboardGui
	local existing = marker:FindFirstChild("WE_ZoneLabel")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end
	local legacy = marker:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") then
		legacy:Destroy()
	end
	return WorldLabel.Create(marker, rt.Def.DisplayName, {
		Name = "WE_ZoneLabel",
		Studs = Vector2.new(8, 1.6),
		Offset = Vector3.new(0, ZONE_LABEL_HEIGHT, 0),
		MaxDistance = 40,
	})
end

local function updateMarkerVisual(rt: TerritoryRuntime)
	local marker = rt.Marker
	if not marker then
		return
	end
	local ot = ownerTypes()
	local contested = rt.Contested or rt.OwnerType == ot.Contested
	local color: Color3
	local flagTransparency = 0.15
	local flagLift = 12 -- studs above the marker for the flag centre (+ basePos.Y − 1 below)
	local ownerNationId: string? = nil -- B2 (e): the owner's nation flag (only while OutpostFlags is on)

	if contested then
		-- v38: pulse between both nation colors when two contesting players known.
		-- Nations B2 (a): two colours closer than NationConfig.ContestMinColorDistance pulse A <-> amber instead
		-- (contestColors hands back amber as B), and a colour that itself reads as amber is plain amber.
		local colA, colB = contestColors(rt)
		if colA and colB then
			local pulse = (math.sin(os.clock() * 4) + 1) * 0.5
			color = colA:Lerp(colB, pulse)
		elseif colA and not tooClose(colA, AMBER) then
			local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
			color = colA:Lerp(AMBER, pulse)
		else
			color = AMBER
		end
		flagTransparency = 0.05
		flagLift = 13.5
	elseif rt.OwnerType == ot.Player then
		-- Nations B2 (c): never a colour that reads as NPC red, Clan blue or contested amber; R15: an owner who left
		-- keeps the cached colour while they still own a zone
		local look = ownerLook(rt.OwnerUserId)
		color = look.Color
		ownerNationId = look.NationId
		flagTransparency = 0.0
		flagLift = 14.5
	elseif rt.OwnerType == ot.NPC then
		color = NPC_RED
		flagTransparency = 0.05
		flagLift = 13.2
	elseif rt.OwnerType == ot.Clan then
		color = CLAN_BLUE
		flagTransparency = 0.0
		flagLift = 14.0
	else
		color = rt.Def.Color
		flagTransparency = 0.35
		flagLift = 11.0
	end

	-- v71: colour only (no forced Neon / transparency: World v2 decides how the marker looks)
	if marker.Color ~= color then
		marker.Color = color
	end
	marker:SetAttribute("OwnerType", if contested then ot.Contested else rt.OwnerType)
	marker:SetAttribute("OwnerUserId", rt.OwnerUserId)
	marker:SetAttribute("CaptureProgress", rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds))

	local tid = marker:GetAttribute("TerritoryId")
	if typeof(tid) ~= "string" then
		return
	end
	local parent = marker.Parent
	if not parent then
		return
	end

	local flag = parent:FindFirstChild(tid .. "_Flag")
	if flag and flag:IsA("BasePart") then
		flag.Color = color
		flag.Material = Enum.Material.SmoothPlastic -- v71: painted, not neon (not a light source)
		flag.Transparency = flagTransparency
		-- Raise owned flags; lower neutral so ownership reads at a glance. Height from the marker, so a flag on
		-- an oil-rig deck (marker high above the sea) stays on its pole instead of dropping to y ≈ 12.
		local basePos = marker.Position
		local outpostFlags = NationConfig.OutpostFlags == true
		if outpostFlags then
			-- Nations B2 (e): 4:3 flag sizes for the nation Texture (owned / contested / neutral)
			flag.Size = if contested then OUTPOST_FLAG_CONTESTED elseif rt.OwnerType == ot.Neutral then OUTPOST_FLAG_NEUTRAL else OUTPOST_FLAG_OWNED
		else
			flag.Size = if contested then Vector3.new(6.2, 3.6, 0.3) elseif rt.OwnerType == ot.Neutral then Vector3.new(4.2, 2.4, 0.22) else Vector3.new(5.5, 3.2, 0.28)
		end
		flag.Position = Vector3.new(basePos.X + flag.Size.X * 0.5 + 0.2, basePos.Y + flagLift - 1, basePos.Z)
		-- Nations B2 (e): a nation flag only on a Player-owned, uncontested zone, and only while OutpostFlags is on
		-- (with it off no Texture is ever made here). Never a SurfaceGui; never while contested (no flag as a target).
		local nationFlagShows = false
		if outpostFlags then
			local showId = if not contested and rt.OwnerType == ot.Player then ownerNationId else nil
			nationFlagShows = dressOutpostFlag(flag, showId)
		end
		-- W3 step 2 (spec w3s2 §1.11, lane P): no owner light on the flag any more. It broke the world light policy
		-- (Brightness 2.4-3.2 and Range 28 > 0.8 / 18, one per zone); the painted flag, stripe and diamond show the owner.
		-- A leftover one (a place saved with an older build's flag) is removed. F10: a Home Outpost never had one.
		if not isStarterRt(rt) then
			local oldLight = flag:FindFirstChild("WE_OwnerLight")
			if oldLight then
				oldLight:Destroy()
			end
		end

		-- Keep stripe locked to flag (nation color visibility polish). F10: a Home Outpost has no stripe.
		-- Nations B2 (e): the stripe hides (Transparency 1) while a nation flag image shows.
		local stripe = if isStarterRt(rt) then nil else parent:FindFirstChild(tid .. "_FlagStripe")
		if stripe and stripe:IsA("BasePart") then
			stripe.Size = Vector3.new(flag.Size.X, math.max(0.35, flag.Size.Y * 0.14), flag.Size.Z + 0.06)
			stripe.Position = flag.Position
			stripe.Color = Color3.fromRGB(245, 245, 245)
			stripe.Transparency = if nationFlagShows then 1 elseif rt.OwnerType == ot.Neutral then 0.45 else 0.08
		end

		-- Nation-colour diamond over the flag: 28 px, MaxDistance <= 40, through walls ONLY while contested
		-- (WorldLabel.SetRole "contested"; WorldLabelPolicy honours the role). Range is set once, never per refresh.
		local flagBbInst = flag:FindFirstChild("WE_FlagBillboard")
		local flagBb: BillboardGui
		if flagBbInst and flagBbInst:IsA("BillboardGui") and flagBbInst:GetAttribute("WE_V71") == true then
			flagBb = flagBbInst
		else
			if flagBbInst then
				flagBbInst:Destroy()
			end
			local created = Instance.new("BillboardGui")
			created.Name = "WE_FlagBillboard"
			created.Size = UDim2.fromOffset(28, 28)
			created.StudsOffset = Vector3.new(0, 2.2, 0)
			created.AlwaysOnTop = false
			created.LightInfluence = 0
			created.MaxDistance = 40
			created:SetAttribute("WE_V71", true)
			local diamond = Instance.new("Frame")
			diamond.Name = "NationDiamond"
			diamond.AnchorPoint = Vector2.new(0.5, 0.5)
			diamond.Position = UDim2.fromScale(0.5, 0.5)
			diamond.Size = UDim2.fromScale(0.62, 0.62)
			diamond.Rotation = 45
			diamond.BorderSizePixel = 0
			diamond.Parent = created
			local ds = Instance.new("UIStroke")
			ds.Name = "DiamondStroke"
			ds.Thickness = 2
			ds.Color = Color3.fromRGB(255, 255, 255)
			ds.Parent = diamond
			created.Parent = flag
			flagBb = created
		end
		local showFlag = rt.OwnerType ~= ot.Neutral or contested
		if flagBb.Enabled ~= showFlag then
			flagBb.Enabled = showFlag
		end
		WorldLabel.SetRole(flagBb, if contested then "contested" else nil)
		local diamond = flagBb:FindFirstChild("NationDiamond")
		if diamond and diamond:IsA("Frame") then
			diamond.BackgroundColor3 = color
			local ds = diamond:FindFirstChild("DiamondStroke")
			if ds and ds:IsA("UIStroke") then
				ds.Color = if contested then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(255, 255, 255)
			end
		end
	end

	-- v71: the ring writes colour only (roadmap W1 F; no Neon while contested, no size / transparency churn)
	local ring = parent:FindFirstChild(tid .. "_Ring")
	if ring and ring:IsA("BasePart") and ring.Color ~= color then
		ring.Color = color
	end

	local pole = parent:FindFirstChild(tid .. "_FlagPole")
	if pole and pole:IsA("BasePart") then
		pole.Color = if contested then Color3.fromRGB(180, 90, 30) elseif rt.OwnerType == ot.Neutral then Color3.fromRGB(55, 55, 55) else Color3.fromRGB(40, 45, 40)
	end

	-- Zone label: name only, owner colour (neutral = white); % / contested are on the HUD capture bar
	local zoneLabel = ensureZoneLabel(rt, marker)
	local title = zoneLabel:FindFirstChild("Title")
	local nameColor = if contested then Color3.fromRGB(255, 176, 48) elseif rt.OwnerType == ot.Neutral then Color3.new(1, 1, 1) else color
	if title and title:IsA("TextLabel") and title.TextColor3 ~= nameColor then
		title.TextColor3 = nameColor
	end
end

local function buildPayloadForPlayer(player: Player?): Types.TerritoryStatePayload
	local list: { Types.TerritoryEntryPayload } = {}
	local localCapture = {
		TerritoryId = nil :: string?,
		Progress = 0,
		Capturing = false,
		Contested = false,
		Protected = false,
	}
	-- F10: another plot's Home Outpost is not listed (only its owner can take it; TerritoryRadar.ShownTo)
	local viewerPlotId: number? = nil
	if player and BaseService and BaseService.GetOwnedPlotId then
		local okPlot, pid = pcall(BaseService.GetOwnedPlotId, player)
		if okPlot and typeof(pid) == "number" then
			viewerPlotId = pid
		end
	end

	for _, rt in pairs(territories) do
		if not TerritoryRadar.ShownTo(rt.Def, viewerPlotId) then
			continue
		end
		table.insert(list, {
			Id = rt.Id,
			DisplayName = rt.Def.DisplayName,
			OwnerType = if rt.Contested then ownerTypes().Contested else rt.OwnerType,
			OwnerUserId = rt.OwnerUserId,
			ClanId = rt.ClanId,
			Progress = math.clamp(rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds), 0, 1),
			CapturingUserId = rt.CapturingUserId,
			ProtectedUntil = rt.ProtectedUntil,
			BonusType = rt.Def.BonusType,
			BonusValue = rt.Def.BonusValue,
			Contested = rt.Contested,
		})
		if player and rt.CapturingUserId == player.UserId and rt.Progress > 0 then
			localCapture.TerritoryId = rt.Id
			localCapture.Progress = math.clamp(rt.Progress / math.max(1, rt.Def.CaptureTimeSeconds), 0, 1)
			localCapture.Capturing = true
			localCapture.Contested = rt.Contested == true
			localCapture.Protected = rt.ProtectedUntil > nowUnix()
				and rt.OwnerUserId ~= TerritoryConfig.NeutralOwnerId
				and rt.OwnerUserId ~= player.UserId
			-- v38: dual nation colors for contested pulse HUD.
			-- Nations B2 (b): the same rule as the world pulse (contestColors): two colours too close to tell apart
			-- send B = amber, and a colour that itself reads as amber sends neither (the HUD's own amber pulse), so
			-- the capture bar never pulses between two identical colours.
			if rt.Contested then
				local function packColor(c: Color3?): { number }?
					if not c then
						return nil
					end
					return { c.R, c.G, c.B }
				end
				local colA, colB = contestColors(rt)
				;(localCapture :: any).ContesterColorA = packColor(colA)
				;(localCapture :: any).ContesterColorB = packColor(colB)
			end
		end
	end

	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)

	local radar = false
	local radarRadius = TerritoryConfig.RadarRevealRadius or 220
	if player then
		radar = TerritoryService.HasRadarReveal(player)
	end

	return {
		Territories = list,
		LocalCapture = localCapture,
		RadarReveal = radar,
		RadarRadius = radarRadius,
	}
end

function TerritoryService.PushAll()
	ensureRuntime()
	local remote = RemoteSetup.Get(Constants.RemoteNames.TerritoryStateUpdate) :: RemoteEvent
	for _, player in ipairs(Players:GetPlayers()) do
		remote:FireClient(player, buildPayloadForPlayer(player))
	end
	lastPushAt = os.clock()
end

function TerritoryService.PushPlayer(player: Player)
	ensureRuntime()
	local remote = RemoteSetup.Get(Constants.RemoteNames.TerritoryStateUpdate) :: RemoteEvent
	remote:FireClient(player, buildPayloadForPlayer(player))
end

function TerritoryService.GetController(territoryId: string): number?
	local rt = territories[territoryId]
	if not rt then
		return nil
	end
	if rt.OwnerType == ownerTypes().Neutral or rt.OwnerType == ownerTypes().Contested then
		return nil
	end
	return rt.OwnerUserId
end

function TerritoryService.GetRuntime(territoryId: string): TerritoryRuntime?
	return territories[territoryId]
end

--[[ Aggregate bonus values for territories controlled by this player (or their clan). ]]
function TerritoryService.GetBonusesForPlayer(player: Player): { [string]: number }
	local bonuses: { [string]: number } = {}
	local profile = DataService and DataService.GetProfile(player)
	local clanId = if profile then profile.ClanId else nil

	for _, rt in pairs(territories) do
		local owns = (rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId)
			or (rt.OwnerType == ownerTypes().Clan and clanId ~= nil and rt.ClanId == clanId)
		if owns then
			-- Flat and multiplicative bonuses both accumulate additively into the map;
			-- consumers interpret FlatPassiveCash/MinimapReveal as flat, *Mult as fractions.
			local key = rt.Def.BonusType
			local value = rt.Def.BonusValue
			bonuses[key] = (bonuses[key] or 0) + value
		end
	end
	return bonuses
end

function TerritoryService.GetPassiveCashBonus(player: Player): (number, number)
	-- returns (multiplierAdd, flatAdd) e.g. 0.10, 50
	local b = TerritoryService.GetBonusesForPlayer(player)
	return b.PassiveCashMult or 0, b.FlatPassiveCash or 0
end

function TerritoryService.GetXPMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	return 1 + (b.XPMult or 0)
end

function TerritoryService.GetDamageMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	return 1 + (b.DamageMult or 0)
end

function TerritoryService.GetVehicleCooldownMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	-- BonusValue for WestDepot is -0.20 → cooldown * 0.80
	return 1 + (b.VehicleCooldownMult or 0)
end

function TerritoryService.GetMissionCashMult(player: Player): number
	local b = TerritoryService.GetBonusesForPlayer(player)
	return 1 + (b.MissionCashMult or 0)
end

--[[ True when player (or their clan) controls a MinimapReveal territory (Radar Hill). ]]
function TerritoryService.HasRadarReveal(player: Player): boolean
	return TerritoryOwnership.HasRadar(player)
end

function TerritoryService.GetRadarRevealRadius(): number
	return TerritoryConfig.RadarRevealRadius or 220
end

-- F3: the player's total Empire Tax % (EconomyService.EmpireTaxPct), 0 when unknown
local function empireTaxPctOf(player: Player): number
	if _EconomyService and _EconomyService.EmpireTaxPct then
		local ok, pct = pcall(_EconomyService.EmpireTaxPct, player)
		if ok and typeof(pct) == "number" then
			return pct
		end
	end
	return 0
end

-- F3: recount the outpost stacks from profile.Territories (EconomyService.SyncOutpostIncomeStacks, which also writes
-- WE_EmpireTaxPct on change). Returns (oldStacks, newStacks, total Empire Tax %).
local function syncEmpireTax(player: Player): (number, number, number)
	if _EconomyService and _EconomyService.SyncOutpostIncomeStacks then
		local oldStacks, newStacks, _perStack, total = _EconomyService.SyncOutpostIncomeStacks(player)
		local pct = if typeof(total) == "number" then total else empireTaxPctOf(player)
		return tonumber(oldStacks) or 0, tonumber(newStacks) or 0, pct
	end
	return 0, 0, empireTaxPctOf(player)
end

-- F3: a toast from an EconomyConfig.OutpostIncomeBuff template (never errors: a bad template gives the fallback)
local function fmtToast(template: any, fallback: string, ...: any): string
	if typeof(template) ~= "string" then
		return fallback
	end
	local ok, msg = pcall(string.format, template, ...)
	return if ok and typeof(msg) == "string" then msg else fallback
end

--[[ reason: "captured" (stolen by another player), "max_personal" (evicted by the owner's own new capture),
	"leave" (F3 PersistClaims / F10: the owner is leaving the server: the runtime goes Neutral but the profile is NOT
	touched, so the saved claims survive for the next server), "plot" (F10: a Home Outpost whose plot changed hands). ]]
local function releaseOwnership(rt: TerritoryRuntime, reason: string)
	local prevUserId = rt.OwnerUserId
	local prevType = rt.OwnerType
	rt.OwnerType = ownerTypes().Neutral
	rt.OwnerUserId = TerritoryConfig.NeutralOwnerId
	rt.ClanId = nil
	rt.ProtectedUntil = 0
	pushDirty = true

	if prevType == ownerTypes().Player and prevUserId > 0 then
		local prevPlayer = Players:GetPlayerByUserId(prevUserId)
		if prevPlayer and reason ~= "leave" then
			syncProfileOwnership(prevPlayer)
			-- Contested: recount OutpostIncomeStacks from remaining owned zones (SyncOutpostIncomeStacks)
			local _, _, pct = syncEmpireTax(prevPlayer)
			if NotificationService and reason ~= "plot" then
				local zoneName = if rt.Def and rt.Def.DisplayName then rt.Def.DisplayName else "Outpost"
				local buff = EconomyConfig.OutpostIncomeBuff
				-- F3: the TOTAL Empire Tax % left ("Central Plaza taken  Empire Tax +10%")
				local lostToast = if reason == "captured"
					then fmtToast(buff and buff.ToastStolenFromYou, "Outpost lost: " .. zoneName, zoneName, pct)
					else fmtToast(buff and buff.ToastLost, "Outpost lost", pct)
				NotificationService.Notify(prevPlayer, lostToast, "Warn", 4.5)
			end
		end
		if prevPlayer and AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.TERRITORY_LOST, prevUserId, {
				territory = rt.Id,
				reason = reason,
			})
		end
		if prevPlayer and reason ~= "leave" and BaseService then
			BaseService.PushState(prevPlayer)
		end
	end
	pruneOwnerCache(prevUserId) -- R15: the leaver's colour goes once they own no zone
end

local function awardCapture(player: Player, rt: TerritoryRuntime)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local starter = isStarterRt(rt) -- F10 Home Outpost
	local beforePct = empireTaxPctOf(player)

	-- Enforce max personal territories. F10: a Home Outpost never counts toward the cap and is never evicted.
	-- If already owning this one (re-secure), skip max check
	local alreadyOwns = rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == player.UserId
	if not starter and not alreadyOwns and countPersonalNonStarter(player.UserId) >= TerritoryConfig.MaxPersonalTerritories then
		-- Drop oldest unprotected personal territory
		local oldest: TerritoryRuntime? = nil
		local oldestTime = math.huge
		for _, other in pairs(territories) do
			if other.Id ~= rt.Id and other.OwnerType == ownerTypes().Player and other.OwnerUserId == player.UserId and not isStarterRt(other) then
				if other.ProtectedUntil < oldestTime then
					oldestTime = other.ProtectedUntil
					oldest = other
				end
			end
		end
		if oldest then
			releaseOwnership(oldest, "max_personal")
			updateMarkerVisual(oldest)
		end
	end

	-- Previous owner loses it (v33: mark steal for toast clarity). F10: a Home Outpost is never stolen: a stale owner
	-- (the plot changed hands) just lets go of it, with no steal toast.
	local stoleFromPlayer = false
	if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId ~= player.UserId and rt.OwnerUserId > 0 then
		if starter then
			releaseOwnership(rt, "plot")
		else
			stoleFromPlayer = true
			releaseOwnership(rt, "captured")
		end
	end

	rt.OwnerType = ownerTypes().Player
	rt.OwnerUserId = player.UserId
	rt.ClanId = profile.ClanId
	if ClanWarService and ClanWarService.OnTerritoryCaptured and not starter then
		ClanWarService.OnTerritoryCaptured(player)
	end
	rt.Progress = 0
	rt.CapturingUserId = 0
	rt.Contested = false
	rt.ContesterA = nil
	rt.ContesterB = nil
	rt.ProtectedUntil = nowUnix() + TerritoryConfig.ProtectionPeriodSeconds
	pushDirty = true

	-- F10: the first Home Outpost capture is remembered; later sessions hold it from the start (OnPlotReady)
	if starter and (profile :: any).StarterOutpostTaken ~= true then
		(profile :: any).StarterOutpostTaken = true
	end
	profile.Stats.TerritoriesCaptured += 1
	syncProfileOwnership(player)

	-- F3 Empire Tax: recount from owned zones (stealable by re-capture); the toast names the TOTAL %
	local incomeToastShown = false
	local incomePct = 0
	if _EconomyService and _EconomyService.SyncOutpostIncomeStacks then
		local _, _, total = syncEmpireTax(player)
		if total > beforePct then
			incomePct = total
			incomeToastShown = true
		end
	elseif _EconomyService and _EconomyService.GrantOutpostIncomeStack then
		local granted, _stacks, pct = _EconomyService.GrantOutpostIncomeStack(player)
		if granted and pct > 0 then
			incomePct = pct
			incomeToastShown = true
		end
	end

	if NotificationService then
		local zoneName = rt.Def.DisplayName
		local wasSteal = stoleFromPlayer
		if incomeToastShown then
			-- v33: explicit who gets the +income. F3: "Took Central Plaza  Empire Tax +20%" / "Outpost taken  Empire Tax +10%"
			local buff = EconomyConfig.OutpostIncomeBuff
			local msg = if wasSteal
				then fmtToast(buff and buff.ToastStealGain, "★ SECURED " .. zoneName, zoneName, incomePct)
				else fmtToast(buff and buff.ToastSecured, "★ SECURED " .. zoneName, incomePct)
			NotificationService.Notify(player, msg, "Reward", 5)
		else
			local bonusHint = rt.Def.Description or ""
			if #bonusHint > 60 then
				bonusHint = string.sub(bonusHint, 1, 57) .. "..."
			end
			NotificationService.Notify(
				player,
				string.format("★ SECURED %s! %s", zoneName, bonusHint),
				"Reward",
				5
			)
		end
	end

	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.TERRITORY_CAPTURED, player.UserId, {
			territory = rt.Id,
			total = profile.Stats.TerritoriesCaptured,
		})
		if profile.Stats.TerritoriesCaptured == 1 and not firstOutpostLogged[player.UserId] then
			firstOutpostLogged[player.UserId] = true
			AnalyticsService.Log(AnalyticsConfig.Events.FIRST_OUTPOST, player.UserId, { territory = rt.Id })
		end
	end

	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "CaptureTerritory", 1)
	end
	if TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "CaptureTerritory", rt.Id)
	end

	if BaseService then
		BaseService.PushState(player)
	end

	updateMarkerVisual(rt)
end

local function playersInZone(rt: TerritoryRuntime): { Player }
	return TerritoryCapture.PlayersInZone(rt)
end

local function tickTerritory(rt: TerritoryRuntime, dt: number)
	local inside = playersInZone(rt)
	local ot = ownerTypes()

	if #inside == 0 then
		rt.Contested = false
		rt.ContesterA = nil
		rt.ContesterB = nil
		if rt.Progress > 0 then
			rt.Progress = math.max(0, rt.Progress - TerritoryConfig.ProgressDecayPerSecond * dt)
		end
		if rt.Progress <= 0 then
			rt.CapturingUserId = 0
		end
		updateMarkerVisual(rt)
		return
	end

	-- Contested if 2+ distinct players and not all already the owner
	local unique: { [number]: boolean } = {}
	for _, p in ipairs(inside) do
		unique[p.UserId] = true
	end
	local uniqueCount = 0
	for _ in pairs(unique) do
		uniqueCount += 1
	end

	if uniqueCount >= 2 then
		rt.Contested = true
		-- F6: contesting a zone ends a novice's shield for good (CombatService decides; its EndOnContestedCapture
		-- switch can turn this reason off). Cross-lane call: pcall + nil check.
		if CombatService and CombatService.IsNoviceShielded and CombatService.EndNoviceShield then
			for _, p in ipairs(inside) do
				local okShield, shielded = pcall(CombatService.IsNoviceShielded, p)
				if okShield and shielded == true then
					pcall(CombatService.EndNoviceShield, p, "contest")
				end
			end
		end
		-- v38: remember first two contesting players for dual-color pulse
		do
			local ids: { number } = {}
			for uid in pairs(unique) do
				table.insert(ids, uid)
			end
			table.sort(ids)
			rt.ContesterA = ids[1]
			rt.ContesterB = ids[2]
		end
		rt.OwnerType = if rt.OwnerUserId == TerritoryConfig.NeutralOwnerId then ot.Contested else rt.OwnerType
		-- Contested: ContestedProgressMult scales capture; 0 freezes and applies ContestedDecayMult decay
		local mult = TerritoryConfig.ContestedProgressMult
		if mult <= 0 then
			local decayMult = TerritoryConfig.ContestedDecayMult or 0.5
			rt.Progress = math.max(0, rt.Progress - TerritoryConfig.ProgressDecayPerSecond * decayMult * dt)
		else
			-- Rare path: allow slow contested progress for both (not used at default 0)
			rt.Progress += dt * mult
		end
		updateMarkerVisual(rt)
		return
	end

	rt.Contested = false
	rt.ContesterA = nil
	rt.ContesterB = nil
	local capturer = inside[1]
	-- If capturer already owns it, just refresh presence (no progress needed)
	if rt.OwnerType == ot.Player and rt.OwnerUserId == capturer.UserId then
		rt.CapturingUserId = 0
		rt.Progress = 0
		updateMarkerVisual(rt)
		return
	end

	-- Protection period hook: slower capture while protected
	local rate = 1
	if rt.ProtectedUntil > nowUnix() and rt.OwnerUserId ~= TerritoryConfig.NeutralOwnerId then
		rate = TerritoryConfig.ProtectedCaptureMult
	end

	rt.CapturingUserId = capturer.UserId
	rt.Progress += dt * rate

	if rt.Progress >= rt.Def.CaptureTimeSeconds then
		awardCapture(capturer, rt)
	else
		updateMarkerVisual(rt)
	end
end

--[[
	Optional explicit request — mainly for UI "begin capture" ping; actual progress is proximity-based.
]]
function TerritoryService.BeginCapture(player: Player, territoryId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(territoryId, 48) then
		return false, "InvalidTerritory"
	end
	if not RemoteGuard.RequireProfile(DataService, player) then
		return false, "NoProfile"
	end
	ensureRuntime()
	local rt = territories[territoryId]
	if not rt then
		return false, "UnknownTerritory"
	end
	local inside = playersInZone(rt)
	local present = false
	for _, p in ipairs(inside) do
		if p == player then
			present = true
			break
		end
	end
	if not present then
		if NotificationService then
			NotificationService.Notify(player, "Enter the capture zone first.", "Warn")
		end
		return false, "NotInZone"
	end
	-- (no "Capturing X..." toast per request: the HUD capture bar shows it — spec §4.2)
	TerritoryService.PushPlayer(player)
	return true, nil
end

--[[ Nations B2 (e): redraw every zone this UserId owns or contests (NationColorService calls it after an accepted
	nation pick while NationConfig.OutpostFlags is on). Never yields. ]]
function TerritoryService.RefreshOwnerFlags(userId: number)
	if typeof(userId) ~= "number" then
		return
	end
	for _, rt in pairs(territories) do
		if rt.OwnerUserId == userId or rt.ContesterA == userId or rt.ContesterB == userId then
			updateMarkerVisual(rt)
		end
	end
end

local function persistClaimsOn(): boolean
	local buff = EconomyConfig.OutpostIncomeBuff
	return buff ~= nil and buff.PersistClaims == true
end

--[[ F3 PersistClaims: re-plant the claims this player's last server saved (profile.Territories) before
	syncProfileOwnership rewrites that list from this server's zones. A claim on a Neutral (incl. a neutral zone being
	contested) or NPC-held zone becomes the player's again with the normal protection period; a claim on a zone
	another ONLINE player holds is dropped with the ToastClaimHeld toast; any other claim (clan-held, a leftover
	offline holder, a zone that no longer exists) is dropped silently. Home Outposts are skipped (OnPlotReady holds
	the own one). At most MaxPersonalTerritories are planted. No capture toast, stat, mission or tutorial event. ]]
local function replantClaims(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile or typeof(profile.Territories) ~= "table" then
		return
	end
	local ot = ownerTypes()
	local ids: { string } = {}
	for id, v in pairs(profile.Territories) do
		if typeof(id) == "string" and v == true then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	local owned = countPersonalNonStarter(player.UserId)
	local now = nowUnix()
	local buff = EconomyConfig.OutpostIncomeBuff
	for _, id in ipairs(ids) do
		local rt = territories[id]
		if rt == nil or isStarterRt(rt) then
			continue
		end
		if rt.OwnerType == ot.Player and rt.OwnerUserId == player.UserId then
			continue -- still ours on this server
		end
		local free = rt.OwnerUserId == TerritoryConfig.NeutralOwnerId or rt.OwnerType == ot.NPC
		if free and owned < TerritoryConfig.MaxPersonalTerritories then
			rt.OwnerType = ot.Player
			rt.OwnerUserId = player.UserId
			rt.ClanId = profile.ClanId
			rt.Progress = 0
			rt.CapturingUserId = 0
			rt.ProtectedUntil = now + TerritoryConfig.ProtectionPeriodSeconds
			owned += 1
			pushDirty = true
			updateMarkerVisual(rt)
		elseif rt.OwnerType == ot.Player and rt.OwnerUserId > 0 and NotificationService then
			local holder = Players:GetPlayerByUserId(rt.OwnerUserId)
			if holder then
				local zoneName = rt.Def.DisplayName
				NotificationService.Notify(
					player,
					fmtToast(buff and buff.ToastClaimHeld, zoneName .. " is held", zoneName, holder.DisplayName),
					"Warn",
					4.5
				)
			end
		end
	end
end

-- F10: the owner holds their Home Outpost from the start once they have taken it (StarterOutpostTaken). Silent (no
-- capture toast / stat / mission / tutorial event); it adds StarterPct to the Empire Tax (SyncOutpostIncomeStacks).
local function holdStarter(player: Player, rt: TerritoryRuntime, profile: any)
	rt.OwnerType = ownerTypes().Player
	rt.OwnerUserId = player.UserId
	rt.ClanId = profile.ClanId
	rt.Progress = 0
	rt.CapturingUserId = 0
	rt.Contested = false
	rt.ContesterA = nil
	rt.ContesterB = nil
	rt.ProtectedUntil = 0 -- owner-only: nobody else can take it anyway
	pushDirty = true
	syncProfileOwnership(player)
	syncEmpireTax(player)
	if BaseService then
		BaseService.PushState(player)
	end
	updateMarkerVisual(rt)
end

--[[ F10 BaseService.OnPlotReady (listener only): a Home Outpost follows its plot's owner. Another holder of this
	plot's Home Outpost (the plot changed hands) and any Home Outpost this player holds on another plot go back to
	Neutral; then the owner holds their own one if they have taken it before. Idempotent. ]]
local function onPlotReady(player: Player, plotId: number)
	ensureRuntime()
	local uid = player.UserId
	local ot = ownerTypes()
	for _, other in pairs(territories) do
		if isStarterRt(other) and other.OwnerType == ot.Player and other.OwnerUserId == uid and other.Def.PlotId ~= plotId then
			releaseOwnership(other, "plot")
			updateMarkerVisual(other)
		end
	end
	local rt = starterRtForPlot(plotId)
	if rt == nil then
		return -- Starter off (no row) or unknown plot
	end
	if rt.OwnerType == ot.Player and rt.OwnerUserId ~= uid then
		releaseOwnership(rt, "plot")
		updateMarkerVisual(rt)
	end
	local profile = DataService.GetProfile(player)
	if profile and (profile :: any).StarterOutpostTaken == true and not (rt.OwnerType == ot.Player and rt.OwnerUserId == uid) then
		holdStarter(player, rt, profile)
	end
end

--[[ Seed a few territories as NPC-held for contested feel (Studio / empty servers). ]]
local function seedNpcOwners()
	local npcHeld = { "EastArmory", "RadarHill", "CoastalOilAlpha", "CoastalOilBravo" }
	for _, id in ipairs(npcHeld) do
		local rt = territories[id]
		if rt and rt.OwnerType == ownerTypes().Neutral then
			rt.OwnerType = ownerTypes().NPC
			rt.OwnerUserId = TerritoryConfig.NPCOwnerId
			rt.ProtectedUntil = nowUnix() + 30
			updateMarkerVisual(rt)
		end
	end
end

function TerritoryService.Init(deps: { [string]: any })
	ClanWarService = deps.ClanWarService
	DataService = deps.DataService
	_EconomyService = deps.EconomyService
	_XPService = deps.XPService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService
	RemoteSetup = deps.RemoteSetup
	BaseService = deps.BaseService
	NationColorService = deps.NationColorService
	CombatService = deps.CombatService

	-- F10: OwnerOnly zones (Home Outposts) count only their plot's owner (TerritoryCapture.PlayersInZone)
	if BaseService and BaseService.GetOwnerUserId then
		TerritoryCapture.SetPlotOwnerResolver(function(plotId: number): number?
			return BaseService.GetOwnerUserId(plotId)
		end)
	end

	TerritoryOwnership.Bind({
		territories = territories,
		ownerTypes = ownerTypes,
		DataService = DataService,
	})

	ensureRuntime()
	seedNpcOwners()

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestCaptureTerritory) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, territoryId: any)
		if not RateLimitService.Allow(player, "capture_territory", 1, 2) then
			return
		end
		TerritoryService.BeginCapture(player, territoryId)
	end)

	-- Late marker discovery (StudioSetup may run after Bootstrap)
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(1)
			ensureRuntime()
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: Types.PlayerProfile)
		ensureRuntime()
		-- F3 PersistClaims: the saved claims first (profile.Territories still holds the last server's list)
		if persistClaimsOn() then
			replantClaims(player)
		end
		syncProfileOwnership(player)
		-- recount OutpostIncomeStacks / WE_EmpireTaxPct (EconomyService.SyncOutpostIncomeStacks)
		syncEmpireTax(player)
		TerritoryService.PushPlayer(player)
	end)

	-- F10: a Home Outpost follows its plot's owner (listener only; BaseService is not edited)
	if BaseService and BaseService.OnPlotReady then
		local okHook, errHook = pcall(BaseService.OnPlotReady, onPlotReady)
		if not okHook then
			warn("[TerritoryService] OnPlotReady hook failed:", errHook)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		-- Soft-release (PersistClaims off): keep world ownership so others can contest; clear profile sync only.
		-- F3 PersistClaims on: the leaver's zones go back to Neutral (their saved claims are kept for the next server).
		-- F10: a Home Outpost always goes back to Neutral when its owner leaves.
		local uid = player.UserId
		firstOutpostLogged[uid] = nil
		local persist = persistClaimsOn()
		for _, rt in pairs(territories) do
			if rt.OwnerType == ownerTypes().Player and rt.OwnerUserId == uid and (persist or isStarterRt(rt)) then
				releaseOwnership(rt, "leave")
				updateMarkerVisual(rt)
			end
		end
		pruneOwnerCache(uid)
	end)

	-- Capture loop
	task.spawn(function()
		local tickSec = TerritoryConfig.CaptureTickSeconds or 0.5
		while true do
			local dt = tickSec
			task.wait(dt)
			ensureRuntime()
			local anyProgress = false
			for _, rt in pairs(territories) do
				local before = rt.Progress
				local beforeCap = rt.CapturingUserId
				tickTerritory(rt, dt)
				if rt.Progress ~= before or rt.CapturingUserId ~= beforeCap or rt.Contested then
					anyProgress = true
				end
			end
			-- Throttle full pushes; skip when idle and recently pushed
			local now = os.clock()
			if anyProgress or pushDirty or (now - lastPushAt >= 2.0) then
				if now - lastPushAt >= (if anyProgress then 0.5 else 2.0) then
					TerritoryService.PushAll()
					pushDirty = false
				end
			end
		end
	end)

	if RunService:IsStudio() then
		print("[TerritoryService] Initialized", (function()
			local n = 0
			for _ in pairs(TerritoryConfig.Territories) do
				n += 1
			end
			return n
		end)(), "territories")
	end
end

return TerritoryService
