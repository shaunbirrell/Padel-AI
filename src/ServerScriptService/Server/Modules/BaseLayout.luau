--!strict
--[[
	v68: geometry helpers for Configs/BaseLayoutConfig (plot-local layout → world CFrames).
	v70: every plot has its own frame. BaseLayout.PlotCFrame(plotPos) = plot position turned by the plot yaw; with
	BaseLayoutConfig.FaceMapCentre the plot's FRONT (local +Z) faces the map centre (yaw snapped to 90), otherwise yaw 0.
	All helpers below take the plot position (signatures unchanged) and derive the yaw from it, so callers never pass it.

	Yaw convention (matches CFrame.Angles(0, yaw, 0)): a building's local +Z (its FRONT) maps to world
	(sin yaw, 0, cos yaw). Yaw 0 = faces +Z (plot front / main gate), 90 = +X, -90 = -X, 180 = -Z.

	Heights: the site frame sits at the plot pad CENTRE height. Part-kit offsets were authored against the
	old 1.2-tall plinth (kit bottoms at local ≈ +0.5..+0.6), so at pad-centre height they land on the pad
	top (pad is 1 stud thick) instead of floating where the plinth used to be.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)
-- F10 (owner's 11 features, lane W): the plot yaw / frame maths lives in Shared/Util/PlotFrame (moved there verbatim
-- by lane K1 so configs and the client can use it); BaseLayout delegates, so server and client can never disagree.
local PlotFrame = require(Shared.Util.PlotFrame)

local BaseLayout = {}

BaseLayout.CONSOLE_SIZE = Vector3.new(2.6, 3.4, 1.4)
local PAD_HALF_HEIGHT = 0.5 -- MapSetup PlotPad is 1 stud thick, centred on the plot position

function BaseLayout.Enabled(): boolean
	return BaseLayoutConfig.Enabled == true
end

function BaseLayout.Config(): any
	return BaseLayoutConfig
end

function BaseLayout.PlotSize(default: number): number
	if BaseLayout.Enabled() then
		return BaseLayoutConfig.PlotSize
	end
	return default
end

function BaseLayout.Site(structureId: string): any?
	if not BaseLayout.Enabled() then
		return nil
	end
	return (BaseLayoutConfig.Structures :: any)[structureId]
end

-- v70: true when plots are turned to face the map centre (waterways layout). F10: PlotFrame.FacesMapCentre.
function BaseLayout.FacesMapCentre(): boolean
	return PlotFrame.FacesMapCentre()
end

-- v70: plot yaw in degrees (0 / 90 / -90 / 180). Front (main gate) toward the map centre. F10: PlotFrame.PlotYaw.
function BaseLayout.PlotYaw(plotPos: Vector3): number
	return PlotFrame.PlotYaw(plotPos)
end

-- v70: plot frame at the plot position (pad centre height). World = PlotCFrame(plotPos) * plot-local.
-- F10: PlotFrame.PlotCFrame (exact quarter-turn matrix, no 6e-17 noise from cos(pi/2)).
function BaseLayout.PlotCFrame(plotPos: Vector3): CFrame
	return PlotFrame.PlotCFrame(plotPos)
end

-- v70: unit vector of the plot FRONT (local +Z) in world space
function BaseLayout.PlotForward(plotPos: Vector3): Vector3
	return BaseLayout.PlotCFrame(plotPos):VectorToWorldSpace(Vector3.new(0, 0, 1))
end

-- Rotate a plot-local (x, z) offset by yaw degrees (same convention as CFrame.Angles(0, yaw, 0)).
function BaseLayout.Rotate(x: number, z: number, yawDeg: number): (number, number)
	local a = math.rad(yawDeg)
	return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)
end

-- Plot-local point → world (y relative to plotPos.Y). v70: turned by the plot yaw.
function BaseLayout.PlotPoint(plotPos: Vector3, x: number, z: number, y: number?): Vector3
	return BaseLayout.PlotCFrame(plotPos):PointToWorldSpace(Vector3.new(x, y or 0, z))
end

-- v70: plot-local CFrame → world. yawDeg turns the part inside the plot (same convention as Site.Yaw).
function BaseLayout.PlotLocalCFrame(plotPos: Vector3, x: number, y: number, z: number, yawDeg: number?): CFrame
	local cf = BaseLayout.PlotCFrame(plotPos) * CFrame.new(x, y, z)
	if yawDeg and yawDeg ~= 0 then
		cf *= CFrame.Angles(0, math.rad(yawDeg), 0)
	end
	return cf
end

local function r2(v: number): number
	return math.round(v * 100) / 100
end

-- v70: plot-local axis-aligned rect (centre cx, cz; size sx, sz) → world centre (y = plotPos.Y) and world X/Z sizes.
-- For water and other parts that must stay axis-aligned in the world: build them with CFrame.new(centre) and the
-- returned sizes (swapped for yaw +-90) instead of rotating them.
function BaseLayout.PlotRect(plotPos: Vector3, cx: number, cz: number, sx: number, sz: number): (Vector3, number, number)
	local c = BaseLayout.PlotPoint(plotPos, cx, cz)
	c = Vector3.new(r2(c.X), plotPos.Y, r2(c.Z))
	if BaseLayout.PlotYaw(plotPos) % 180 ~= 0 then
		return c, sz, sx
	end
	return c, sx, sz
end

-- Site frame for a structure at pad-centre height (kit offsets are relative to this).
function BaseLayout.SiteCFrame(plotPos: Vector3, structureId: string): CFrame?
	local s = BaseLayout.Site(structureId)
	if not s then
		return nil
	end
	return BaseLayout.PlotLocalCFrame(plotPos, s.Site.X, 0, s.Site.Z, s.Yaw or 0)
end

-- Console (upgrade slot) CFrame. Walk-in: inside the building near the door, facing the room.
-- Outdoor: kiosk on the pad, facing the plot centre.
function BaseLayout.ConsoleCFrame(plotPos: Vector3, structureId: string): CFrame?
	local s = BaseLayout.Site(structureId)
	if not s then
		return nil
	end
	local h = BaseLayout.CONSOLE_SIZE.Y
	if s.WalkIn and s.Console then
		local site = BaseLayout.PlotLocalCFrame(plotPos, s.Site.X, PAD_HALF_HEIGHT, s.Site.Z, s.Yaw or 0)
		-- building floor top is 0.4 above the pad (HollowBuildingBuilder); face local -X (into the room)
		return site * CFrame.new(s.Console.X, 0.4 + h * 0.5, s.Console.Z) * CFrame.Angles(0, math.rad(90), 0)
	end
	local k = s.Kiosk or s.Site
	local at = BaseLayout.PlotPoint(plotPos, k.X, k.Z, PAD_HALF_HEIGHT + h * 0.5)
	local centre = Vector3.new(plotPos.X, at.Y, plotPos.Z)
	if (centre - at).Magnitude < 1 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, centre)
end

-- Plot-local point → world, on the pad top.
function BaseLayout.GroundPoint(plotPos: Vector3, x: number, z: number, lift: number?): Vector3
	return BaseLayout.PlotPoint(plotPos, x, z, PAD_HALF_HEIGHT + (lift or 0))
end

return BaseLayout
