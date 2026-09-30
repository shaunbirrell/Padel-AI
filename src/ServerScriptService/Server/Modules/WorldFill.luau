--!strict
--[[
	claude-bud JOB 3 (2026-09-29): the world fill (Shared/Configs/WorldFillConfig). One Workspace folder,
	WorldFillConfig.FolderName, rebuilt with the dressing (MapDressing.Dress calls ReserveRoads after the POIs, so the
	travel dressing avoids the new roads, and Build after the rest of the dressing, so the fill avoids everything).
	Server only, run once per map build (no per-frame work). Every item is a WorldKits kit (<= 8 parts, no scripts), a
	Terrain rock (0 parts) or a plain anchored part (roads, bridges); every one is re-checked with WorldDress.Blocked
	against the shared occupancy and skipped (counted in the log line) when blocked. Tier 2 items build on Full only.
	The build stops placing once MaxPartsFull / MaxPartsLow would be passed.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldFillConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("WorldFillConfig"))

local WorldFill = {}

local GROUND_Y = 0.5 -- MapSetup.GROUND_TOP_Y (flat desert floor)

local state = { Parts = 0, Skipped = 0, Folder = nil :: Folder? }

local function folderFresh(): Folder
	local old = Workspace:FindFirstChild(WorldFillConfig.FolderName)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = WorldFillConfig.FolderName
	f.Parent = Workspace
	return f
end

local function plain(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, collide: boolean, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.CanCollide = collide
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function countParts(inst: Instance): number
	local n = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function cap(full: boolean): number
	return if full then WorldFillConfig.MaxPartsFull else WorldFillConfig.MaxPartsLow
end

--[[ Step A (after the POIs, before WorldDress): the connector roads, and their clearance reserved in `occ` so the travel
	dressing never lands on them. Returns the parts built. ]]
function WorldFill.ReserveRoads(occ: any, wd: any): number
	state.Parts = 0
	state.Skipped = 0
	if WorldFillConfig.Enabled ~= true then
		local old = Workspace:FindFirstChild(WorldFillConfig.FolderName)
		if old then
			old:Destroy()
		end
		state.Folder = nil
		return 0
	end
	local folder = folderFresh()
	state.Folder = folder
	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = folder
	local R = WorldFillConfig.Road
	for _, r in ipairs(WorldFillConfig.Roads) do
		local alongX = r.Z0 == r.Z1
		local len = if alongX then math.abs(r.X1 - r.X0) else math.abs(r.Z1 - r.Z0)
		local mx, mz = (r.X0 + r.X1) * 0.5, (r.Z0 + r.Z1) * 0.5
		plain(
			r.Name,
			if alongX then Vector3.new(len, 0.15, R.Width) else Vector3.new(R.Width, 0.15, len),
			CFrame.new(mx, GROUND_Y + 0.05, mz), -- top 0.625, like the world roads
			R.Color,
			Enum.Material.Asphalt,
			false,
			roads
		)
		state.Parts += 1
		if occ and wd and wd.AddDisc then
			local steps = math.max(1, math.floor(len / R.ReserveStep))
			for i = 0, steps do
				local t = i / steps
				wd.AddDisc(occ, r.X0 + (r.X1 - r.X0) * t, r.Z0 + (r.Z1 - r.Z0) * t, R.ReserveRadius, "fillroad")
			end
		end
	end
	return state.Parts
end

-- one bridge: deck, 2 ramps, 2 rails, 2 bank piers (7 parts); both landings must be free
local function buildBridge(b: any, folder: Instance, occ: any, wd: any): number
	local B = WorldFillConfig.Bridge
	local deckTop = B.DeckBottomY + B.DeckThick
	local south, north = b.Z0 - B.RampLen, b.Z1 + B.RampLen
	if occ and wd and wd.Blocked then
		for _, z in ipairs({ south + B.Width * 0.5, north - B.Width * 0.5 }) do
			local why = wd.Blocked(occ, b.X, z, B.Width * 0.5)
			if why then
				warn(string.format("[WorldFill] bridge %s skipped: landing blocked (%s)", b.Name, tostring(why)))
				return 0
			end
		end
	end
	local m = Instance.new("Model")
	m.Name = b.Name
	local span = b.Z1 - b.Z0
	local mid = (b.Z0 + b.Z1) * 0.5
	plain("Deck", Vector3.new(B.Width, B.DeckThick, span), CFrame.new(b.X, B.DeckBottomY + B.DeckThick * 0.5, mid), B.Color, Enum.Material.Concrete, true, m)
	local rise = deckTop - GROUND_Y
	local ang = math.atan2(rise, B.RampLen)
	local rampLen = math.sqrt(rise * rise + B.RampLen * B.RampLen)
	local cy = GROUND_Y + rise * 0.5 - B.DeckThick * 0.5
	-- south ramp climbs toward +Z (onto the deck), north ramp climbs toward -Z
	plain("RampS", Vector3.new(B.Width, B.DeckThick, rampLen), CFrame.new(b.X, cy, b.Z0 - B.RampLen * 0.5) * CFrame.Angles(-ang, 0, 0), B.Color, Enum.Material.Concrete, true, m)
	plain("RampN", Vector3.new(B.Width, B.DeckThick, rampLen), CFrame.new(b.X, cy, b.Z1 + B.RampLen * 0.5) * CFrame.Angles(ang, 0, 0), B.Color, Enum.Material.Concrete, true, m)
	for _, s in ipairs({ -1, 1 }) do
		plain("Rail", Vector3.new(0.6, B.RailH, span), CFrame.new(b.X + s * (B.Width * 0.5 - 0.3), deckTop + B.RailH * 0.5, mid), Color3.fromRGB(80, 78, 72), Enum.Material.Metal, true, m)
	end
	-- piers stand on the 6-stud bank slabs (Z0 / Z1 are the bank edges), never in the channel
	local pierH = B.DeckBottomY - GROUND_Y
	for _, z in ipairs({ b.Z0 + 1.5, b.Z1 - 1.5 }) do
		plain("Pier", Vector3.new(B.Width - 2, pierH, 2), CFrame.new(b.X, GROUND_Y + pierH * 0.5, z), B.Color, Enum.Material.Concrete, true, m)
	end
	m:SetAttribute("WE_AllowInWater", true)
	m.Parent = folder
	if occ and wd and wd.AddDisc then
		for z = south, north, 12 do
			wd.AddDisc(occ, b.X, z, B.Width * 0.5, "fillbridge")
		end
	end
	return 7
end

-- item offset (field frame) -> world x, z; kit yaw (degrees)
local function toWorld(field: any, it: any): (number, number, number)
	local a = math.rad(field.Yaw or 0)
	local c, s = math.cos(a), math.sin(a)
	-- CFrame.Angles(0, a, 0) turns local (x, z) to (x c + z s, -x s + z c)
	local wx = field.X + it.X * c + it.Z * s
	local wz = field.Z - it.X * s + it.Z * c
	return wx, wz, (field.Yaw or 0) + (it.Yaw or 0)
end

--[[ Step B (after the dressing): bridges, fields and the plaza ring. `quality` "Full" | "Low". Returns (parts, skipped). ]]
function WorldFill.Build(quality: string, occ: any, wd: any, wk: any): (number, number)
	local folder = state.Folder
	if WorldFillConfig.Enabled ~= true or folder == nil or folder.Parent == nil or wk == nil then
		return 0, 0
	end
	local full = quality == "Full"
	local limit = cap(full)

	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = folder
	for _, b in ipairs(WorldFillConfig.Bridges) do
		if state.Parts + 7 <= limit then
			local n = buildBridge(b, bridges, occ, wd)
			state.Parts += n
			if n == 0 then
				state.Skipped += 1
			end
		end
	end

	local rng = wk.Rng(29092026)
	for _, field in ipairs(WorldFillConfig.Fields) do
		local items = (WorldFillConfig.Templates :: any)[field.Template]
		if items then
			local ff = Instance.new("Folder")
			ff.Name = "Field_" .. field.Id
			ff.Parent = folder
			for i, it in ipairs(items) do
				if it.Tier == 1 or full then
					local wx, wz, yaw = toWorld(field, it)
					if it.Kit == "Rock" then
						local r = it.Radius or 10
						local why = if occ and wd then wd.Blocked(occ, wx, wz, r) else nil
						if why == nil then
							pcall(wk.Rock, Vector3.new(wx, GROUND_Y, wz), it.Kind or "boulders", rng, { Radius = r })
							if occ and wd then
								wd.AddDisc(occ, wx, wz, r, "fillrock")
							end
						else
							state.Skipped += 1
						end
					else
						local fp = wk.Footprint(it.Kit, it.Opts)
						local planned = if fp then fp.Parts else 8
						local r = if fp then math.max(fp.X1 - fp.X0, fp.Z1 - fp.Z0) * 0.5 else 5
						local why = if occ and wd then wd.Blocked(occ, wx, wz, r, { Spacing = WorldFillConfig.ItemSpacing }) else nil
						if why ~= nil or state.Parts + planned > limit then
							state.Skipped += 1
						else
							local cf = CFrame.new(wx, GROUND_Y, wz) * CFrame.Angles(0, math.rad(yaw), 0)
							local model = wk.Place(it.Kit, cf, ff, {
								Name = string.format("Fill_%s_%d_%s", field.Id, i, it.Kit),
								Cluster = { Source = "fill", Kind = it.Kit, Anchor = "natural", AnchorX = wx, AnchorZ = wz, Tier = it.Tier },
								Kit = it.Opts,
							})
							if model then
								for _, d in ipairs(model:GetDescendants()) do
									if d:IsA("Script") or d:IsA("LocalScript") then
										d:Destroy() -- never scripts in world props
									end
								end
								state.Parts += countParts(model)
								if occ and wd then
									wd.AddDisc(occ, wx, wz, r, "fill")
								end
							else
								state.Skipped += 1
							end
						end
					end
				end
			end
		end
	end
	pcall(WorldFill.Build2, quality, occ, wd, wk) -- claude-bud JOB 18: WorldFill 2 (same folder, same occupancy)
	folder:SetAttribute("WE_FillParts", state.Parts)
	folder:SetAttribute("WE_FillSkipped", state.Skipped)
	print(string.format("[WAR EMPIRE] WorldFill: quality=%s parts=%d skipped=%d (cap %d)", string.lower(quality), state.Parts, state.Skipped, limit))
	return state.Parts, state.Skipped
end

-- ── claude-bud JOB 18: WorldFill 2 (WorldFillConfig.Fill2) ─────────────────────────────────────────────────────────
local F2: any = (WorldFillConfig :: any).Fill2
local fill2 = { Parts = 0, Skipped = 0, Limit = 0, Full = true }

local function hash(a: number, b: number): number
	local h = bit32.bxor(math.floor(a * 7385) % 2147483647, math.floor(b * 1934) % 2147483647)
	return math.abs(h) % 1000003
end

-- one themed item at world (wx, wz); returns true when placed
local function placeItem(ff: Instance, name: string, it: any, wx: number, wz: number, yaw: number, occ: any, wd: any, wk: any, rng: any, allowPOI: string?, text: string?): boolean
	if not (it.Tier == 1 or fill2.Full) then
		return false
	end
	if it.Kit == "Rock" then
		local r = it.Radius or 10
		local why = if occ and wd then wd.Blocked(occ, wx, wz, r, { AllowPOI = allowPOI }) else nil
		if why ~= nil then
			fill2.Skipped += 1
			return false
		end
		pcall(wk.Rock, Vector3.new(wx, GROUND_Y, wz), it.Kind or "boulders", rng, { Radius = r })
		if occ and wd then
			wd.AddDisc(occ, wx, wz, r, "fill2rock")
		end
		return true
	end
	local opts = it.Opts
	if text then
		opts = table.clone(opts or {})
		opts.Text = text
	end
	local fp = wk.Footprint(it.Kit, it.Opts)
	local planned = if fp then fp.Parts else 8
	local r = if fp then math.max(fp.X1 - fp.X0, fp.Z1 - fp.Z0) * 0.5 else 5
	local why = if occ and wd then wd.Blocked(occ, wx, wz, r, { Spacing = WorldFillConfig.ItemSpacing, AllowPOI = allowPOI }) else nil
	if why ~= nil or fill2.Parts + planned > fill2.Limit then
		fill2.Skipped += 1
		return false
	end
	local cf = CFrame.new(wx, GROUND_Y, wz) * CFrame.Angles(0, math.rad(yaw), 0)
	local model = wk.Place(it.Kit, cf, ff, {
		Name = name,
		Cluster = { Source = "fill2", Kind = it.Kit, Anchor = "natural", AnchorX = wx, AnchorZ = wz, Tier = it.Tier },
		Kit = opts,
	})
	if model == nil then
		fill2.Skipped += 1
		return false
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- never scripts in world props
		elseif d:IsA("BasePart") then
			d.Anchored = true
			if d.Size.Magnitude < 8 then
				d.CastShadow = false -- small props cast no shadows
			end
		end
	end
	fill2.Parts += countParts(model)
	if occ and wd then
		wd.AddDisc(occ, wx, wz, r, "fill2")
	end
	return true
end

-- a theme's items round (cx, cz) turned by yaw; the first placeable NameSign-worthy spot carries `sign`
local function placeTheme(parent: Instance, id: string, theme: string, cx: number, cz: number, yaw: number, occ: any, wd: any, wk: any, rng: any, allowPOI: string?, sign: string?): number
	local items = F2.Themes[theme]
	if items == nil then
		return 0
	end
	local ff = Instance.new("Folder")
	ff.Name = "Fill2_" .. id
	ff.Parent = parent
	local field = { X = cx, Z = cz, Yaw = yaw }
	local n = 0
	for i, it in ipairs(items) do
		local wx, wz, y = toWorld(field, it)
		if placeItem(ff, string.format("Fill2_%s_%d_%s", id, i, it.Kit), it, wx, wz, y, occ, wd, wk, rng, allowPOI, nil) then
			n += 1
		end
	end
	if sign then
		local sx, sz, y = toWorld(field, { X = 0, Z = -34, Yaw = 180 })
		placeItem(ff, "Fill2_" .. id .. "_Sign", { Kit = "NameSign", Tier = 1 }, sx, sz, y, occ, wd, wk, rng, allowPOI, sign)
	end
	if #ff:GetChildren() == 0 then
		ff:Destroy()
	end
	return n
end

-- nothing placed and no POI within EmptyRadius of (x, z)
local function emptyAt(occ: any, wd: any, x: number, z: number): boolean
	local R = F2.Cells.EmptyRadius
	for _, d in ipairs(occ.Discs) do
		if (d.X - x) ^ 2 + (d.Z - z) ^ 2 < (R + d.R) ^ 2 then
			return false
		end
	end
	for _, p in ipairs(occ.Zones.POIs or {}) do
		if wd.POIDist and wd.POIDist(p, x, z) < R then
			return false
		end
	end
	return true
end

local function themeFor(x: number, z: number): string
	for _, r in ipairs(F2.Cells.Regions) do
		if x >= r.X0 and x <= r.X1 and z >= r.Z0 and z <= r.Z1 then
			return r.Theme
		end
	end
	local mix = F2.Cells.MixThemes
	return mix[(hash(x, z) % #mix) + 1]
end

local function countryside(parent: Instance, occ: any, wd: any, wk: any, rng: any): (number, number)
	local C = F2.Cells
	local cells, filled = 0, 0
	local signed = false
	local e = C.Extent
	for gx = -e + C.Size / 2, e, C.Size do
		for gz = -e + C.Size / 2, e, C.Size do
			cells += 1
			local h = hash(gx, gz)
			local cx = gx + ((h % 101) / 100 - 0.5) * 2 * C.Jitter
			local cz = gz + (((h // 101) % 101) / 100 - 0.5) * 2 * C.Jitter
			-- a patch needs its centre clear (ring, water, plots, roads...) and nothing around it yet
			if wd.Blocked(occ, cx, cz, C.PatchRadius * 0.5) == nil and emptyAt(occ, wd, cx, cz) then
				local theme = themeFor(cx, cz)
				local sign: string? = nil
				if theme == "Farm" and not signed then
					sign = F2.SignFarms
					signed = true
				end
				if placeTheme(parent, string.format("Cell_%d_%d", gx, gz), theme, cx, cz, (h % 8) * 45, occ, wd, wk, rng, nil, sign) > 0 then
					filled += 1
				end
			end
		end
	end
	return cells, filled
end

-- pylons every Step along the highways outside the Town, two wires between neighbours
local function powerLines(parent: Instance, occ: any, wd: any, wk: any)
	local P = F2.Power
	local pf = Instance.new("Folder")
	pf.Name = "Fill2_Power"
	pf.Parent = parent
	local function line(alongX: boolean, sign: number)
		local prevTop: { Vector3 }? = nil
		local t = P.From
		while t <= P.To do
			local along = t * sign
			local x = if alongX then along else P.Offset
			local z = if alongX then P.Offset else along
			local yaw = if alongX then 0 else 90
			local placed = false
			if fill2.Parts + 5 <= fill2.Limit and wd.Blocked(occ, x, z, 5, { RoadClear = 8, RoadR = 0 }) == nil then
				local cf = CFrame.new(x, GROUND_Y, z) * CFrame.Angles(0, math.rad(yaw), 0)
				local m = wk.Place("Pylon", cf, pf, {
					Name = "Fill2_Pylon",
					Cluster = { Source = "fill2", Kind = "Pylon", Anchor = "natural", AnchorX = x, AnchorZ = z, Tier = 1 },
				})
				if m then
					placed = true
					fill2.Parts += countParts(m)
					wd.AddDisc(occ, x, z, 5, "fill2pylon")
					local right = cf.RightVector
					local tops = { cf.Position + Vector3.new(0, 22.9, 0) - right * 4, cf.Position + Vector3.new(0, 22.9, 0) + right * 4 }
					if prevTop then
						for k = 1, 2 do
							local a, b = prevTop[k], tops[k]
							local mid = (a + b) / 2 - Vector3.new(0, P.WireSag, 0)
							plain("Fill2_Wire", Vector3.new(0.15, 0.15, (b - a).Magnitude), CFrame.lookAt(mid, mid + (b - a)), P.WireColor, Enum.Material.Metal, false, pf)
							fill2.Parts += 1
						end
					end
					prevTop = tops
				end
			end
			if not placed then
				prevTop = nil -- a skipped pylon (plot, water, POI) breaks the line: no wire across it
			end
			t += P.Step
		end
	end
	line(true, 1)
	line(true, -1)
	line(false, 1)
	line(false, -1)
end

-- flat dirt tracks from the Town corners to the outer POIs; pieces over water / plots / aprons / captures skipped
local function tracks(parent: Instance, occ: any, wd: any)
	local T = F2.Tracks
	local tf = Instance.new("Folder")
	tf.Name = "Fill2_Tracks"
	tf.Parent = parent
	for i, l in ipairs(T.Lines) do
		local a, b = Vector3.new(l.X0, 0, l.Z0), Vector3.new(l.X1, 0, l.Z1)
		local len = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.floor(len / T.Piece)
		for k = 0, n - 1 do
			local c = a + dir * (k + 0.5) * T.Piece
			local why = wd.Blocked(occ, c.X, c.Z, T.Width * 0.5, { RoadClear = -1000, SkipRing = false })
			local ok = why == nil or string.sub(why, 1, 4) == "poi:" or string.sub(why, 1, 7) == "anchor:" or string.sub(why, 1, 10) == "structure:"
			if ok and fill2.Parts < fill2.Limit then
				local p = plain("Fill2_Track" .. i, Vector3.new(T.Width, 0.12, T.Piece + 1), CFrame.lookAt(Vector3.new(c.X, GROUND_Y + 0.02, c.Z), Vector3.new(c.X, GROUND_Y + 0.02, c.Z) + dir), T.Color, Enum.Material.Ground, false, tf)
				p.CanQuery = false
				fill2.Parts += 1
			end
		end
	end
end

-- rooftop clutter on the town buildings (raycast onto the real roof)
local function rooftops(parent: Instance, wk: any)
	local R = F2.Rooftops
	if not R.Enabled or not fill2.Full then
		return
	end
	local rf = Instance.new("Folder")
	rf.Name = "Fill2_Rooftops"
	rf.Parent = parent
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("WE_Cluster") == "poi:block" then
			local ok, cf, size = pcall(m.GetBoundingBox, m)
			if ok then
				params.FilterDescendantsInstances = { m }
				for k = 1, R.PerBuilding do
					if fill2.Parts + 2 > fill2.Limit then
						return
					end
					local off = Vector3.new((if k == 1 then -0.25 else 0.25) * size.X, 0, (if k == 1 then 0.2 else -0.2) * size.Z)
					local from = cf.Position + off + Vector3.new(0, size.Y / 2 + 10, 0)
					local r = Workspace:Raycast(from, Vector3.new(0, -size.Y - 20, 0), params)
					if r and r.Normal.Y > 0.9 and r.Position.Y > cf.Position.Y - size.Y / 2 + 5 then
						local kit = R.Kits[(hash(from.X, from.Z + k) % #R.Kits) + 1]
						local model = wk.Place(kit, CFrame.new(r.Position) * CFrame.Angles(0, math.rad(hash(from.Z, from.X) % 360), 0), rf, {
							Name = "Fill2_Roof_" .. kit,
							Cluster = { Source = "fill2", Kind = kit, Anchor = "natural", AnchorX = r.Position.X, AnchorZ = r.Position.Z, Tier = 2 },
						})
						if model then
							fill2.Parts += countParts(model)
						end
					end
				end
			end
		end
	end
end

-- the dune belt: low sand ridges in front of the skyline (north, east, west), one Atomic model
local function dunes(parent: Instance)
	local D = F2.Dunes
	if not D.Enabled then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Fill2_Dunes"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- (Persistent is reserved for WorldBounds / WorldPOI)
	local sides = {
		{ Axis = "z", Sign = -1 }, -- north (-Z)
		{ Axis = "x", Sign = 1 }, -- east
		{ Axis = "x", Sign = -1 }, -- west
	}
	local span = 2 * D.ROuter
	for si, s in ipairs(sides) do
		for i = 1, D.PerSide do
			local h = hash(si * 100 + i, 7)
			local along = -D.ROuter + (i - 0.5) * span / D.PerSide
			local depthAt = D.RInner + (h % 1000) / 1000 * (D.ROuter - D.RInner - 200)
			local height = D.Height[1] + (h % 97) / 97 * (D.Height[2] - D.Height[1])
			local len = span / D.PerSide + 60
			local pos: Vector3
			local yaw: number
			if s.Axis == "z" then
				pos = Vector3.new(along, GROUND_Y + height / 2 - 4, s.Sign * depthAt)
				yaw = 0
			else
				pos = Vector3.new(s.Sign * depthAt, GROUND_Y + height / 2 - 4, along)
				yaw = 90
			end
			-- a ridge = a wedge facing the map + a wedge facing out (a triangular dune profile), 2 parts
			local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
			local col = if i % 2 == 0 then D.Color else D.ColorFar
			for _, face in ipairs({ 1, -1 }) do
				local w = Instance.new("WedgePart")
				w.Name = "Fill2_Dune"
				w.Anchored = true
				w.CanCollide = false
				w.CanQuery = false
				w.CanTouch = false
				w.CastShadow = false
				w.Material = Enum.Material.Sand
				w.Color = col
				w.Size = Vector3.new(len, height, height * 2.2)
				w.CFrame = cf * CFrame.new(0, 0, face * height * 1.1) * CFrame.Angles(0, if face < 0 then 0 else math.pi, 0) -- slopes face out, vertical backs meet
				w.Parent = m
				fill2.Parts += 1
			end
		end
	end
	m.Parent = parent
end

function WorldFill.Build2(quality: string, occ: any, wd: any, wk: any): (number, number)
	fill2.Parts, fill2.Skipped = 0, 0
	local folder = state.Folder
	if F2 == nil or F2.Enabled ~= true or folder == nil or folder.Parent == nil or wk == nil or occ == nil or wd == nil then
		return 0, 0
	end
	fill2.Full = quality == "Full"
	fill2.Limit = if fill2.Full then F2.MaxParts2Full else F2.MaxParts2Low
	pcall(function()
		(wk :: any).Fill2Signs = 0
	end)
	local root = Instance.new("Folder")
	root.Name = "Fill2"
	root.Parent = folder
	local rng = wk.Rng(18092026)
	-- identity first (the towns), then the long lines, then the countryside fills what is left
	for _, f in ipairs(F2.Identity) do
		pcall(placeTheme, root, f.Id, f.Theme, f.X, f.Z, f.Yaw, occ, wd, wk, rng, f.AllowPOI, f.Sign)
	end
	pcall(powerLines, root, occ, wd, wk)
	pcall(tracks, root, occ, wd)
	pcall(rooftops, root, wk)
	local okC, cells, filled = pcall(countryside, root, occ, wd, wk, rng)
	pcall(dunes, root)
	folder:SetAttribute("WE_Fill2Parts", fill2.Parts)
	folder:SetAttribute("WE_Fill2Skipped", fill2.Skipped)
	print(string.format("[WAR EMPIRE] WorldFill2: quality=%s parts=%d skipped=%d cells=%s filled=%s (cap %d)", string.lower(quality), fill2.Parts, fill2.Skipped, tostring(if okC then cells else "?"), tostring(if okC then filled else "?"), fill2.Limit))
	-- claude-bud JOB 31: the detailed props' extra parts over the plain kits (WorldDetailConfig.MaxExtraParts caps them)
	local ds = (wk :: any).DetailStats
	if typeof(ds) == "table" then
		folder:SetAttribute("WE_DetailExtra", ds.Extra)
		print(string.format("[WorldDetail] detailed kits=%d extra=%d plain-after-cap=%d (cap %s)", ds.Kits, ds.Extra, ds.Plain, tostring(require(game:GetService("ReplicatedStorage").Shared.Configs.WorldDetailConfig).MaxExtraParts)))
	end
	return fill2.Parts, fill2.Skipped
end

return WorldFill
