--!strict
--[[
	claude-bud JOB 17 (2026-09-29): the night lights (Shared/Configs/LightingConfig). Server-built once after the world
	dressing (MapDressing, after WorldFill), into Workspace.WE_NightLights (outside the dressing folders, so the world
	hygiene budget of 24 dressing lights is untouched). Live for all.
	  * Streetlights: along the Town's two main roads (RoadX0 / RoadZ0, off the lane), a ring round the Central Plaza,
	    the Town Square corners. Base gate + hangar floodlights on every plot. A light on the plaza flag.
	    PointLight / SpotLight, Shadows = false, tag WE_NightLight: WorldAtmosphere turns them on only at night.
	    Every second light carries WE_LowOff (the client's low-quality mode keeps those off).
	  * Glow (tag WE_NightGlow, Neon only at night): lamp heads, runway edge markers, lit windows on the town buildings'
	    real front walls (raycast onto the wall, never floating), the plaza flag.
	Nothing collides (never blocks a road, the plaza or a plot), nothing casts shadows, CanQuery / CanTouch off.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local LightingConfig = require(Shared.Configs.LightingConfig)
local WorldConfig = require(Shared.Configs.WorldConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local NightLights = {}

local L: any = LightingConfig
local lightCount = 0
NightLights.Stats = { Lights = 0, Glow = 0, Windows = 0 }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundY(x: number, z: number): number?
	local r = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -400, 0), rayParams)
	return if r then r.Position.Y else nil
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

-- Neon + NightColor at night, day material / colour by day (WorldAtmosphere.SetNightLights flips the tag)
local function glow(p: BasePart, dayColor: Color3?, nightColor: Color3?)
	p:SetAttribute("WE_DayMaterial", p.Material.Name)
	if dayColor then
		p:SetAttribute("WE_DayColor", dayColor)
	end
	if nightColor then
		p:SetAttribute("WE_NightColor", nightColor)
	end
	CollectionService:AddTag(p, L.GlowTag)
	NightLights.Stats.Glow += 1
end

local function addLight(host: BasePart, kind: string, range: number, brightness: number, color: Color3, face: Enum.NormalId?, angle: number?): Light?
	if lightCount >= L.MaxLights then
		return nil
	end
	lightCount += 1
	local light: Light
	if kind == "Spot" then
		local s = Instance.new("SpotLight")
		s.Face = face or Enum.NormalId.Front
		s.Angle = angle or 70
		s.Range = range
		light = s
	else
		local pl = Instance.new("PointLight")
		pl.Range = range
		light = pl
	end
	light.Brightness = brightness
	light.Color = color
	light.Shadows = false
	light.Enabled = false
	if lightCount % 2 == 0 then
		light:SetAttribute(L.LowOffAttribute, true) -- the client's low-quality mode keeps every second light off
	end
	light.Parent = host
	CollectionService:AddTag(light, L.LightTag)
	NightLights.Stats.Lights = lightCount
	return light
end

-- one lamp post: a steel pole, an arm and a glowing head with the light
local function post(parent: Instance, name: string, x: number, z: number, height: number, range: number, brightness: number, color: Color3, toward: Vector3?)
	local y = groundY(x, z)
	if y == nil or lightCount >= L.MaxLights then
		return
	end
	local m = Instance.new("Model")
	m.Name = name
	local base = Vector3.new(x, y, z)
	part("Pole", Vector3.new(0.5, height, 0.5), CFrame.new(base + Vector3.new(0, height / 2, 0)), Color3.fromRGB(52, 54, 58), m)
	local out = if toward then Vector3.new(toward.X - x, 0, toward.Z - z) else Vector3.new(1, 0, 0)
	out = if out.Magnitude > 1e-3 then out.Unit else Vector3.new(1, 0, 0)
	local armCentre = base + Vector3.new(0, height - 0.2, 0) + out * 1.2
	part("Arm", Vector3.new(0.3, 0.3, 2.4), CFrame.lookAt(armCentre, armCentre + out), Color3.fromRGB(52, 54, 58), m)
	local headAt = base + Vector3.new(0, height - 0.6, 0) + out * 2.4
	local head = part("Head", Vector3.new(1.4, 0.5, 1.4), CFrame.new(headAt), Color3.fromRGB(120, 112, 96), m)
	glow(head, Color3.fromRGB(120, 112, 96), color)
	addLight(head, "Point", range, brightness, color)
	m.Parent = parent
end

local function townStreets(parent: Instance)
	local S = L.Street
	local i = 0
	for t = -S.TownHalf, S.TownHalf, S.Spacing do
		if math.abs(t) >= S.SkipNearPlaza then
			i += 1
			local side = if i % 2 == 0 then 1 else -1
			-- RoadX0 runs along Z at x = 0; RoadZ0 along X at z = 0 (WaterConfig.RoadEnds): posts off the lane, arms over it
			post(parent, "StreetX_" .. i, side * S.Offset, t, S.PoleHeight, S.Range, S.Brightness, S.Color, Vector3.new(0, 0, t))
			post(parent, "StreetZ_" .. i, t, -side * S.Offset, S.PoleHeight, S.Range, S.Brightness, S.Color, Vector3.new(t, 0, 0))
		end
	end
	local P = L.PlazaRing
	for k = 0, P.Count - 1 do
		local a = math.rad(15 + k * (360 / P.Count)) -- never on the roads through the plaza (0 / 90 / 180 / 270)
		post(parent, "PlazaLamp_" .. k, math.cos(a) * P.Radius, math.sin(a) * P.Radius, L.Street.PoleHeight, P.Range, P.Brightness, S.Color, Vector3.zero)
	end
	local T = L.TownSquare
	local sq = Vector3.new(T.X, 0, T.Z)
	for k, off in ipairs({ Vector3.new(-T.Half, 0, -T.Half), Vector3.new(T.Half, 0, -T.Half), Vector3.new(T.Half + 4, 0, 0) }) do
		post(parent, "SquareLamp_" .. k, T.X + off.X, T.Z + off.Z, L.Street.PoleHeight, T.Range, T.Brightness, S.Color, sq)
	end
end

local function bases(parent: Instance)
	local B = L.Base
	local half = BaseConfig.PlotSize.X / 2
	local gateX = BaseLayoutConfig.MainGateWidth / 2 + 4
	local runway: any = nil
	for _, r in ipairs(BaseLayoutConfig.Roads) do
		if r.Name == "Runway" then
			runway = r
		end
	end
	for plotId = 1, BaseConfig.MaxPlots do
		if PlotFrame.PlotPosition(plotId) == nil then
			continue
		end
		local f = Instance.new("Folder")
		f.Name = "Plot" .. plotId .. "_Night"
		local function at(lx: number, lz: number): Vector3
			return PlotFrame.LocalToWorld(plotId, lx, lz)
		end
		-- gate floodlights, just inside the main gate on both sides of the lane, lighting the lane
		for _, sx in ipairs({ -1, 1 }) do
			local p = at(sx * gateX, half - 6)
			post(f, "GateFlood", p.X, p.Z, 12, B.GateRange, B.GateBrightness, B.Color, at(0, half - 20))
		end
		-- hangar floodlight beside the apron (never on the runway / apron rectangles)
		local h = at(-74, -101)
		post(f, "HangarFlood", h.X, h.Z, 14, B.HangarRange, B.HangarBrightness, B.Color, at(-100, -110))
		-- runway edge markers (Neon at night, no lights)
		if runway then
			local x0 = runway.X - runway.SizeX / 2
			local x1 = runway.X + runway.SizeX / 2
			for _, sz in ipairs({ -1, 1 }) do
				local lz = runway.Z + sz * (runway.SizeZ / 2 + 1)
				local lx = x0 + 2
				while lx <= x1 - 2 do
					local p = at(lx, lz)
					local y = groundY(p.X, p.Z)
					if y then
						local mk = part("RunwayEdge", Vector3.new(0.8, 0.35, 0.8), CFrame.new(p.X, y + 0.18, p.Z), Color3.fromRGB(90, 86, 70), f)
						glow(mk, Color3.fromRGB(90, 86, 70), B.RunwayMarkerColor)
					end
					lx += B.RunwayMarkerSpacing
				end
			end
		end
		f.Parent = parent
	end
end

-- the plaza flag: glows at night, one spotlight from the pole top onto it (TerritoryService builds it; waited for)
local function plazaFlag(parent: Instance)
	local F = L.Flag
	task.spawn(function()
		for _ = 1, 30 do
			local pole = Workspace:FindFirstChild(F.Pole, true)
			if pole and pole:IsA("BasePart") then
				local top = pole.Position + Vector3.new(0, pole.Size.Y / 2 + 0.6, 0)
				local lamp = part("FlagLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.lookAt(top, top - Vector3.new(0, 1, 0) + Vector3.new(0.01, 0, 0)), Color3.fromRGB(90, 90, 90), parent)
				addLight(lamp, "Spot", F.Range, F.Brightness, Color3.fromRGB(255, 244, 220), Enum.NormalId.Front, F.Angle)
				local flag = Workspace:FindFirstChild(F.Flag, true)
				if flag and flag:IsA("BasePart") then
					glow(flag, nil, nil) -- Neon at night in its owner colour (TerritoryService keeps writing the colour)
				end
				local ok, WA = pcall(require, script.Parent.WorldAtmosphere)
				if ok and type(WA) == "table" and (WA :: any).IsNight then
					pcall((WA :: any).SetNightLights, (WA :: any).IsNight())
				end
				return
			end
			task.wait(2)
		end
	end)
end

-- Id -> Yaw of every town "block" cluster (the building's front faces (-sin yaw, 0, -cos yaw))
local function blockYaws(): { [string]: number }
	local out: { [string]: number } = {}
	local seen: { [any]: boolean } = {}
	local function walk(t: any, depth: number)
		if depth > 6 or seen[t] then
			return
		end
		seen[t] = true
		if typeof(t.Id) == "string" and t.Role == "block" and typeof(t.Yaw) == "number" then
			out[t.Id] = t.Yaw
		end
		for _, v in pairs(t) do
			if type(v) == "table" then
				walk(v, depth + 1)
			end
		end
	end
	walk(WorldConfig, 0)
	return out
end

local function windows(parent: Instance)
	local W = L.Windows
	if not W.Enabled then
		return
	end
	local yaws = blockYaws()
	local wf = Instance.new("Folder")
	wf.Name = "Windows"
	local hitParams = RaycastParams.new()
	hitParams.FilterType = Enum.RaycastFilterType.Include
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("WE_Cluster") == "poi:block" and yaws[m.Name] ~= nil then
			local yaw = math.rad(yaws[m.Name])
			local front = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
			local right = Vector3.new(-front.Z, 0, front.X)
			local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					mn = mn:Min(d.Position - d.Size / 2)
					mx = mx:Max(d.Position + d.Size / 2)
				end
			end
			if mn.X == math.huge then
				continue
			end
			local centre = (mn + mx) / 2
			local ext = mx - mn
			local depth = math.abs(ext.X * front.X) + math.abs(ext.Z * front.Z)
			local width = math.abs(ext.X * right.X) + math.abs(ext.Z * right.Z)
			hitParams.FilterDescendantsInstances = { m }
			local placed = 0
			local cols = math.clamp(math.floor(width / W.ColumnSpacing) - 1, 1, 3)
			for floor = 1, 2 do
				local y = mn.Y + W.FirstFloorY + (floor - 1) * W.FloorHeight
				if y > mx.Y - 2 then
					break
				end
				for c = 1, cols do
					if placed >= W.MaxPerBuilding then
						break
					end
					local lat = (c - (cols + 1) / 2) * W.ColumnSpacing
					local from = Vector3.new(centre.X, y, centre.Z) + front * (depth / 2 + 6) + right * lat
					local r = Workspace:Raycast(from, -front * (depth + 8), hitParams)
					if r and r.Normal:Dot(front) > 0.9 then
						local p = r.Position + r.Normal * 0.08
						local win = part("Window", W.Size, CFrame.lookAt(p, p + r.Normal), W.DayColor, wf)
						placed += 1
						NightLights.Stats.Windows += 1
						-- deterministic "lit" pattern (the same on every server)
						local h = (#m.Name * 7 + floor * 13 + c * 5) % 10
						if h < W.LitShare * 10 then
							glow(win, W.DayColor, W.NightColor)
						end
					end
				end
			end
		end
	end
	wf.Parent = parent
end

function NightLights.Build()
	if not LightingConfig.Enabled then
		return
	end
	local old = Workspace:FindFirstChild("WE_NightLights")
	if old then
		old:Destroy()
	end
	lightCount = 0
	NightLights.Stats = { Lights = 0, Glow = 0, Windows = 0 }
	local f = Instance.new("Folder")
	f.Name = "WE_NightLights"
	rayParams.FilterDescendantsInstances = { f }
	local ok1, e1 = pcall(townStreets :: any, f)
	local ok2, e2 = pcall(bases :: any, f)
	local ok3, e3 = pcall(windows :: any, f)
	if not (ok1 and ok2 and ok3) then
		warn("[NightLights] partial build:", e1, e2, e3)
	end
	f.Parent = Workspace
	plazaFlag(f)
	local ok, WA = pcall(require, script.Parent.WorldAtmosphere)
	if ok and type(WA) == "table" and (WA :: any).IsNight then
		pcall((WA :: any).SetNightLights, (WA :: any).IsNight())
	end
	print(string.format("[NightLights] %d lights, %d glow parts, %d windows", NightLights.Stats.Lights, NightLights.Stats.Glow, NightLights.Stats.Windows))
end

return NightLights
