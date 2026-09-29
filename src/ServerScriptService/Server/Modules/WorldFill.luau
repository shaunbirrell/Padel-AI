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
	folder:SetAttribute("WE_FillParts", state.Parts)
	folder:SetAttribute("WE_FillSkipped", state.Skipped)
	print(string.format("[WAR EMPIRE] WorldFill: quality=%s parts=%d skipped=%d (cap %d)", string.lower(quality), state.Parts, state.Skipped, limit))
	return state.Parts, state.Skipped
end

return WorldFill
