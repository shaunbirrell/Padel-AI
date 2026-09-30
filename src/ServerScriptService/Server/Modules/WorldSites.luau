--!strict
--[[
	claude-bud JOB 31 (2026-09-30): the named sites that fill the empty desert (WorldSitesConfig). Server only; built once
	by MapDressing right after WorldFill, so everything else already stands and a site avoids it.

	Build(quality, wk) -> (sitesBuilt, parts)
	  For each WorldSitesConfig.Sites row: find a clear centre, then build the kind's cluster rows with WorldKits
	  (NewCluster + Add + Finish). Each cluster is a Model under Workspace.WorldFill.Sites carrying WE_Cluster
	  "site:<kind>", so QualityGovernor treats its small decor as decor and never culls a building (JOB 27).
	  The site Folder "Site_<Id>" carries the attributes WE_SiteId / WE_SiteName / WE_SiteKind / WE_SiteX / WE_SiteZ /
	  WE_SiteR.

	  A clear centre is the configured point, or the first point on rings around it (every 45 degrees, 40 studs apart,
	  up to SearchStuds), such that:
	    * no part inside the site's radius, except floor-size slabs (both X and Z >= 300): roads, buildings and props
	      all block;
	    * it is >= PlotClearStuds from every base plot and outside every named area (MapAreas);
	    * it is on dry land.
	  A site with no clear centre, or that would pass MaxParts, is skipped and logged.

	Get(id) / List() -> the built sites { Id, Name, Kind, X, Z, R, Y, Tower: CFrame? } (read by MapService and
	SiteActivityService; Tower = the overwatch watchtower's deck, the Rooftop Sniper perch).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldSitesConfig = require(Shared.Configs.WorldSitesConfig)
local WorldConfig = require(Shared.Configs.WorldConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotFrame = require(Shared.Util.PlotFrame)
local MapAreas = require(Shared.Util.MapAreas)

local WorldSites = {}

export type Built = { Id: string, Name: string, Kind: string, X: number, Z: number, R: number, Y: number, Tower: CFrame? }

local built: { Built } = {}
local byId: { [string]: Built } = {}

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = false

local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Include

local function rotY(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- pure: may a site of radius r stand at (x, z)? (the part test is separate: it needs the world)
function WorldSites.PlaceOk(x: number, z: number, r: number): (boolean, string?)
	local L = WorldSitesConfig.Land
	if x - r < L.X0 or x + r > L.X1 or z - r < L.Z0 or z + r > L.Z1 then
		return false, "land"
	end
	for plotId = 1, BaseConfig.MaxPlots do
		local ok, p = pcall(PlotFrame.PlotPosition, plotId)
		if ok and typeof(p) == "Vector3" then
			local dx, dz = p.X - x, p.Z - z
			if math.sqrt(dx * dx + dz * dz) < WorldSitesConfig.PlotClearStuds then
				return false, "plot"
			end
		end
	end
	for _, a in ipairs(MapAreas.List()) do
		-- the site's disc must not touch an area: test the centre and 8 rim points
		for i = 0, 8 do
			local px, pz = x, z
			if i > 0 then
				local ang = (i - 1) * math.pi / 4
				px, pz = x + r * math.cos(ang), z + r * math.sin(ang)
			end
			if MapAreas.Inside(a, px, pz) then
				return false, "area:" .. a.Id
			end
		end
	end
	return true, nil
end

-- the world test: nothing but floor-size slabs inside the radius
local function clearOfParts(x: number, z: number, r: number): boolean
	local hits = Workspace:GetPartBoundsInRadius(Vector3.new(x, 8, z), r, overlap)
	for _, p in ipairs(hits) do
		if not (p.Size.X >= 300 and p.Size.Z >= 300) then
			return false
		end
	end
	return true
end

-- the pure candidate order: the configured point, then rings (every 45 degrees, 40 studs apart) up to maxStuds
function WorldSites.Candidates(x: number, z: number, maxStuds: number): { { number } }
	local out = { { x, z } }
	local ring = 40
	while ring <= maxStuds do
		for i = 0, 7 do
			local ang = i * math.pi / 4
			table.insert(out, { math.floor(x + ring * math.cos(ang) + 0.5), math.floor(z + ring * math.sin(ang) + 0.5) })
		end
		ring += 40
	end
	return out
end

local function groundY(x: number, z: number): number
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		ground.FilterDescendantsInstances = { terrain }
		local hit = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -700, 0), ground)
		if hit then
			return hit.Position.Y
		end
	end
	return WorldConfig.Kits and (WorldConfig.Kits :: any).GroundY or 0.5
end

function WorldSites.Build(quality: string, wk: any): (number, number)
	table.clear(built)
	table.clear(byId)
	if WorldSitesConfig.Enabled ~= true or wk == nil then
		return 0, 0
	end
	local fill = Workspace:FindFirstChild("WorldFill") or Workspace
	local old = fill:FindFirstChild("Sites")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Sites"
	root.Parent = fill
	local total, count = 0, 0
	for _, site in ipairs(WorldSitesConfig.Sites) do
		local kind = WorldSitesConfig.Kinds[site.Kind]
		if kind == nil then
			continue
		end
		-- plan: the plain parts this site needs (Footprint = the plain kit; detail extras come from their own allowance)
		local planned = 0
		for _, c in ipairs(kind.Clusters) do
			for _, k in ipairs(c.Kits) do
				local fp = wk.Footprint(k.Kit, { Variant = k.Variant, Count = k.Count, Length = k.Length, Scale = k.Scale })
				planned += if fp then fp.Parts else 0
			end
		end
		if total + planned > WorldSitesConfig.MaxParts then
			print(string.format("[WorldSites] %s skipped: parts %d + %d > cap %d", site.Id, total, planned, WorldSitesConfig.MaxParts))
			continue
		end
		local cx: number?, cz: number? = nil, nil
		for _, cand in ipairs(WorldSites.Candidates(site.X, site.Z, WorldSitesConfig.SearchStuds)) do
			if WorldSites.PlaceOk(cand[1], cand[2], kind.R) and clearOfParts(cand[1], cand[2], kind.R) then
				cx, cz = cand[1], cand[2]
				break
			end
		end
		if cx == nil or cz == nil then
			print(string.format("[WorldSites] %s skipped: no clear ground within %d studs of (%d, %d)", site.Id, WorldSitesConfig.SearchStuds, site.X, site.Z))
			continue
		end
		local x, z = cx :: number, cz :: number
		local y = groundY(x, z)
		local folder = Instance.new("Folder")
		folder.Name = "Site_" .. site.Id
		folder:SetAttribute("WE_SiteId", site.Id)
		folder:SetAttribute("WE_SiteName", site.Name)
		folder:SetAttribute("WE_SiteKind", site.Kind)
		folder:SetAttribute("WE_SiteX", x)
		folder:SetAttribute("WE_SiteZ", z)
		folder:SetAttribute("WE_SiteR", kind.R)
		folder.Parent = root
		local parts = 0
		local tower: CFrame? = nil
		for i, c in ipairs(kind.Clusters) do
			local ccf = CFrame.new(x + c.X, 0, z + c.Z) * rotY(c.Yaw or 0)
			local cluster = wk.NewCluster(string.format("Site_%s_%d", site.Id, i), {
				Source = "site",
				Kind = c.Kind,
				Anchor = "site:" .. site.Id,
				AnchorX = x,
				AnchorZ = z,
				Tier = 1,
			})
			for _, k in ipairs(c.Kits) do
				local kcf = ccf * CFrame.new(k.X, 0, k.Z) * rotY(k.Yaw or 0)
				local gy = groundY(kcf.Position.X, kcf.Position.Z)
				kcf = CFrame.new(kcf.Position.X, gy, kcf.Position.Z) * kcf.Rotation
				parts += wk.Add(cluster, k.Kit, kcf, { Variant = k.Variant, Count = k.Count, Length = k.Length, Scale = k.Scale })
				if k.Kit == "Watchtower" and site.Kind == "overwatch" and tower == nil then
					local deckY = (WorldConfig.Kits :: any).WatchtowerDeckY or 14
					tower = kcf * CFrame.new(0, deckY, -1.25)
				end
			end
			local info = wk.Finish(cluster, folder)
			if not info.Ok then
				print(string.format("[WorldSites] %s cluster %d dropped: %s", site.Id, i, tostring(info.Reason)))
			end
		end
		total += parts
		count += 1
		local rec: Built = { Id = site.Id, Name = site.Name, Kind = site.Kind, X = x, Z = z, R = kind.R, Y = y, Tower = tower }
		table.insert(built, rec)
		byId[site.Id] = rec
	end
	root:SetAttribute("WE_SiteParts", total)
	print(string.format("[WorldSites] quality=%s sites=%d parts=%d (cap %d)", string.lower(quality), count, total, WorldSitesConfig.MaxParts))
	return count, total
end

function WorldSites.List(): { Built }
	return built
end

function WorldSites.Get(id: string): Built?
	return byId[id]
end

return WorldSites
