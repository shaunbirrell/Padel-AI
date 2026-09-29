--!strict
--[[
	claude-bud JOB 8 (2026-09-29): the automatic LOW quality tier (Shared/Configs/QualityConfig). Client only.
	  * FPS: one counter bumped per Heartbeat (no allocation), evaluated once a second.
	  * Decoration: the WorldKits clusters (Model with WE_Cluster) under the QualityConfig.Folders are listed ONCE when
	    each folder appears, kept up to date by DescendantAdded (no whole-tree scans after that), and culled at CheckHz:
	    a hidden cluster is parented to nil on THIS client and put back where it was when the camera comes near again.
	  * Low also turns this client's GlobalShadows off and sets WE_LowQuality (ProductionFx.IsLowFx reads it).
	Streaming-safe: folders are found by name with FindFirstChild (never WaitForChild), a cluster that streams out
	(Parent nil by the engine) is dropped from the list.

claude-bud JOB 27 (owner: "whole city buildings go visible -> missing -> visible"; proven root cause: THIS module, the
only code that removes world models on the client; StreamingEnabled is OFF, no server loop rebuilds them): v116-v120
culled every cluster by ONE cached pivot point, ONE distance for hide and show, once a second, including the city's
building clusters (WorldFill / Fill2 kits: their kind is the kit name, not a POI role, so JOB 24's NeverHideKinds missed
them) and rooftop props that are separate clusters on top of a building. Now:
  * a cluster's distance is to its BOUNDING BOX (GetBoundingBox once when listed), never a pivot;
  * building-sized clusters (footprint >= BuildingMinStuds or height >= BuildingMinHeight), NeverHideKinds, and any small
    cluster standing on / inside a building's box (rooftop props, signs, AC units) are NEVER culled
    (QualityConfig.CullTownBuildings = false; true = the old behaviour);
  * only small far decoration is culled, with separate LOAD / UNLOAD distances and nothing done in between
    (Tier 2: in < Tier2ShowStuds, out > Tier2HideStuds; any: in < AnyShowStuds, out > AnyHideStuds), from the camera
    and from where it will be LookAheadSeconds from now;
  * one central manager checks every CullSeconds (FastCullSeconds while the camera moves fast): no per-building
    connections, no GetDescendants after listing, no Destroy / Clone (a culled model is only re-parented);
  * QualityConfig.DebugLog prints "[BUILDING DEBUG] UNLOADING|LOADING: <name> PlayerDistance CameraDistance Chunk Reason".
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QualityGovernor = {}

type Entry = { Model: Model, Home: Instance, Min: Vector3, Max: Vector3, Tier: number, Hidden: boolean }

local entries: { [Model]: Entry } = {}
local watched: { [Instance]: boolean } = {}
local low = false
local shadowsBefore: boolean? = nil

function QualityGovernor.IsLow(): boolean
	return low
end

local neverHide: { [string]: boolean } = {}
local Qc: any = nil -- QualityConfig (set in Init)
-- claude-bud JOB 27: building boxes on a coarse grid (the "is this small cluster on a building?" lookup)
local GRID = 64
type Box = { Min: Vector3, Max: Vector3 }
local buildingGrid: { [string]: { Box } } = {}
local lastFocus: Vector3? = nil
local lastFocusAt = 0
local focusVel = Vector3.zero

-- the world-aligned box round a (possibly rotated) bounding box
local function worldBox(cf: CFrame, size: Vector3): (Vector3, Vector3)
	local h = size * 0.5
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ext = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
	return cf.Position - ext, cf.Position + ext
end

local function cellsOf(mn: Vector3, mx: Vector3): { string }
	local out = {}
	for gx = math.floor(mn.X / GRID), math.floor(mx.X / GRID) do
		for gz = math.floor(mn.Z / GRID), math.floor(mx.Z / GRID) do
			table.insert(out, gx .. ":" .. gz)
		end
	end
	return out
end

local function overlaps(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3, pad: number): boolean
	return aMin.X <= bMax.X + pad and aMax.X >= bMin.X - pad and aMin.Z <= bMax.Z + pad and aMax.Z >= bMin.Z - pad
		and aMin.Y <= bMax.Y + pad and aMax.Y >= bMin.Y - pad
end

local function onBuilding(mn: Vector3, mx: Vector3): boolean
	for _, key in ipairs(cellsOf(mn, mx)) do
		for _, b in ipairs(buildingGrid[key] or {}) do
			if overlaps(mn, mx, b.Min, b.Max, 2) then
				return true
			end
		end
	end
	return false
end

local function show(m: Model, e: Entry)
	if e.Hidden then
		e.Hidden = false
		pcall(function()
			m.Parent = e.Home
		end)
	end
end

local function track(m: Instance, home: Instance)
	if not m:IsA("Model") or entries[m] ~= nil or m:GetAttribute("WE_Cluster") == nil then
		return
	end
	local okB, cf, size = pcall(function()
		return m:GetBoundingBox()
	end)
	if not okB then
		return
	end
	local mn, mx = worldBox(cf :: CFrame, size :: Vector3)
	local sz = mx - mn
	local kind = string.match(tostring(m:GetAttribute("WE_Cluster")), ":(.+)$") or ""
	local Q = Qc or {}
	local building = neverHide[kind]
		or math.max(sz.X, sz.Z) >= (tonumber(Q.BuildingMinStuds) or 14)
		or sz.Y >= (tonumber(Q.BuildingMinHeight) or 10)
	if building and Q.CullTownBuildings ~= true then
		-- a building / landmark: never culled; remember its box, and free any small cluster already listed on it
		local box: Box = { Min = mn, Max = mx }
		for _, key in ipairs(cellsOf(mn, mx)) do
			buildingGrid[key] = buildingGrid[key] or {}
			table.insert(buildingGrid[key], box)
		end
		for om, e in pairs(entries) do
			if overlaps(e.Min, e.Max, mn, mx, 2) then
				show(om, e)
				entries[om] = nil
			end
		end
		return
	end
	if Q.CullTownBuildings ~= true and onBuilding(mn, mx) then
		return -- a rooftop prop / sign / AC unit on a building: it stays with its building
	end
	entries[m] = {
		Model = m,
		Home = m.Parent or home,
		Min = mn,
		Max = mx,
		Tier = tonumber(m:GetAttribute("WE_Tier")) or 1,
		Hidden = false,
	}
end

local function watchFolder(folder: Instance)
	if watched[folder] then
		return
	end
	watched[folder] = true
	for _, d in ipairs(folder:GetDescendants()) do -- once per folder
		track(d, folder)
	end
	folder.DescendantAdded:Connect(function(d)
		track(d, folder)
	end)
end

local function findFolders(Q: any)
	for _, path in ipairs(Q.Folders) do
		local node: Instance? = Workspace
		for part in string.gmatch(path, "[^/]+") do
			node = if node then node:FindFirstChild(part) else nil
		end
		if node then
			watchFolder(node)
		end
	end
end

local function setLow(on: boolean, Q: any)
	if on == low then
		return
	end
	low = on
	local lp = Players.LocalPlayer
	pcall(function()
		lp:SetAttribute("WE_LowQuality", if on then true else nil)
	end)
	-- claude-bud JOB 17: low quality keeps every second night light off (LightingConfig.LowOffAttribute); the Neon
	-- glow of lamp heads / windows still shows. The server's dusk / dawn flip is re-applied on each change.
	pcall(function()
		local LC = require((ReplicatedStorage :: any).Shared.Configs.LightingConfig) :: any
		local nl = Workspace:FindFirstChild("WE_NightLights")
		if nl then
			for _, d in ipairs(nl:GetDescendants()) do
				if d:IsA("Light") and d:GetAttribute(LC.LowOffAttribute) == true then
					if on then
						d.Enabled = false
						if not d:GetAttribute("WE_LowHooked") then
							d:SetAttribute("WE_LowHooked", true)
							d:GetPropertyChangedSignal("Enabled"):Connect(function()
								if low and d.Enabled then
									d.Enabled = false
								end
							end)
						end
					else
						-- back to normal quality: on again if it is night now (the server's night share > 0.5)
						local t = Lighting.ClockTime
						local C = LC.Cycle
						d.Enabled = t < (C.NightEnd + C.DawnEnd) / 2 or t > (C.DuskStart + C.NightStart) / 2
					end
				end
			end
		end
	end)
	if Q.ShadowsOffWhenLow then
		if on then
			shadowsBefore = Lighting.GlobalShadows
			Lighting.GlobalShadows = false
		elseif shadowsBefore ~= nil then
			Lighting.GlobalShadows = shadowsBefore
		end
	end
end

local function cull(Q: any)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local focus = cam.Focus.Position
	-- claude-bud JOB 24 §8: where the camera will be LookAheadSeconds from now (a car's path is shown before it gets there)
	local now = os.clock()
	if lastFocus ~= nil and now > lastFocusAt then
		focusVel = (focus - (lastFocus :: Vector3)) / (now - lastFocusAt)
	end
	lastFocus, lastFocusAt = focus, now
	local ahead = focus + focusVel * (tonumber(Q.LookAheadSeconds) or 0)
	local root = (function(): BasePart?
		local ch = Players.LocalPlayer.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return if r and r:IsA("BasePart") then r else nil
	end)()
	-- distance from a point to a box (0 inside it)
	local function boxDist(p: Vector3, mn: Vector3, mx: Vector3): number
		local dx = math.max(mn.X - p.X, 0, p.X - mx.X)
		local dy = math.max(mn.Y - p.Y, 0, p.Y - mx.Y)
		local dz = math.max(mn.Z - p.Z, 0, p.Z - mx.Z)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	for m, e in pairs(entries) do
		if e.Hidden == false and m.Parent == nil then
			entries[m] = nil -- destroyed by the server
		else
			local d = math.min(boxDist(focus, e.Min, e.Max), boxDist(ahead, e.Min, e.Max))
			local showAt = if e.Tier >= 2 then Q.Tier2ShowStuds else Q.AnyShowStuds
			local hideAt = if e.Tier >= 2 then Q.Tier2HideStuds else Q.AnyHideStuds
			-- separate LOAD and UNLOAD distances; in between nothing changes
			local want: boolean? = nil
			if not low then
				want = false
			elseif e.Hidden and d < showAt then
				want = false
			elseif not e.Hidden and d > hideAt then
				want = true
			end
			if want ~= nil and want ~= e.Hidden then
				e.Hidden = want
				pcall(function()
					m.Parent = if want then nil else e.Home
				end)
				if Q.DebugLog == true then
					local c = (e.Min + e.Max) * 0.5
					print(string.format("[BUILDING DEBUG] %s: %s PlayerDistance: %.0f CameraDistance: %.0f Chunk: %d:%d Reason: %s",
						if want then "UNLOADING" else "LOADING", m.Name, if root then boxDist(root.Position, e.Min, e.Max) else -1,
						boxDist(cam.CFrame.Position, e.Min, e.Max), math.floor(c.X / GRID), math.floor(c.Z / GRID),
						if not low then "normal quality" elseif want then string.format("low: > %d studs (tier %d)", hideAt, e.Tier) else string.format("low: < %d studs", showAt)))
				end
			end
		end
	end
end

function QualityGovernor.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	local Q = require((Shared :: any).Configs.QualityConfig) :: any
	Qc = Q
	local lp = Players.LocalPlayer
	if not Q.LiveFor(lp.UserId) then
		return
	end
	for _, k in ipairs(Q.NeverHideKinds or {}) do
		neverHide[k] = true
	end
	local frames = 0
	RunService.Heartbeat:Connect(function()
		frames += 1
	end)
	task.spawn(function()
		local lowFor, highFor, since, lastFind = 0, 0, os.clock(), -math.huge
		local interval = 1 / math.max(0.2, Q.CheckHz)
		while lp.Parent do
			task.wait(interval) -- (the FPS / quality tier check; culling has its own manager below, JOB 27)
			local now = os.clock()
			local step = now - since -- (the real loop step: the wait varies with speed, JOB 24 §8)
			local fps = frames / math.max(0.001, now - since)
			frames, since = 0, now
			if now - lastFind >= 5 then
				lastFind = now
				findFolders(Q)
			end
			local cam = Workspace.CurrentCamera
			local vp = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
			local small = math.min(vp.X, vp.Y) <= Q.SmallScreenShortSide
			if fps < Q.LowFpsBelow then
				lowFor += step
				highFor = 0
			elseif fps > Q.RecoverFpsAbove then
				highFor += step
				lowFor = 0
			end
			if small or lowFor >= Q.LowFpsSeconds then
				setLow(true, Q)
			elseif low and highFor >= Q.RecoverSeconds then
				setLow(false, Q)
			end
		end
	end)
	-- claude-bud JOB 27: ONE central cull manager, every CullSeconds (FastCullSeconds while the camera moves fast)
	task.spawn(function()
		while lp.Parent do
			task.wait(if focusVel.Magnitude > (tonumber(Q.FastStuds) or math.huge) then tonumber(Q.FastCullSeconds) or 0.2 else tonumber(Q.CullSeconds) or 0.4)
			local ok, err = pcall(cull :: any, Q)
			if not ok then
				warn("[QualityGovernor] cull: " .. tostring(err))
			end
		end
	end)
end

return QualityGovernor
