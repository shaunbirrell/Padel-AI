--!strict
--[[
	v68: geometry helpers for Configs/BaseLayoutConfig (plot-local layout → world CFrames).

	Yaw convention (matches CFrame.Angles(0, yaw, 0)): a building's local +Z (its FRONT) maps to world
	(sin yaw, 0, cos yaw). Yaw 0 = faces +Z (plot front / main gate), 90 = +X, -90 = -X, 180 = -Z.

	Heights: the site frame sits at the plot pad CENTRE height. Part-kit offsets were authored against the
	old 1.2-tall plinth (kit bottoms at local ≈ +0.5..+0.6), so at pad-centre height they land on the pad
	top (pad is 1 stud thick) instead of floating where the plinth used to be.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)

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

-- Rotate a plot-local (x, z) offset by yaw degrees (same convention as CFrame.Angles(0, yaw, 0)).
function BaseLayout.Rotate(x: number, z: number, yawDeg: number): (number, number)
	local a = math.rad(yawDeg)
	return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)
end

function BaseLayout.PlotPoint(plotPos: Vector3, x: number, z: number, y: number?): Vector3
	return plotPos + Vector3.new(x, y or 0, z)
end

-- Site frame for a structure at pad-centre height (kit offsets are relative to this).
function BaseLayout.SiteCFrame(plotPos: Vector3, structureId: string): CFrame?
	local s = BaseLayout.Site(structureId)
	if not s then
		return nil
	end
	return CFrame.new(plotPos + Vector3.new(s.Site.X, 0, s.Site.Z)) * CFrame.Angles(0, math.rad(s.Yaw or 0), 0)
end

-- Console (upgrade slot) CFrame. Walk-in: inside the building near the door, facing the room.
-- Outdoor: kiosk on the pad, facing the plot centre.
function BaseLayout.ConsoleCFrame(plotPos: Vector3, structureId: string): CFrame?
	local s = BaseLayout.Site(structureId)
	if not s then
		return nil
	end
	local h = BaseLayout.CONSOLE_SIZE.Y
	local padTop = plotPos.Y + PAD_HALF_HEIGHT
	if s.WalkIn and s.Console then
		local site = CFrame.new(Vector3.new(plotPos.X + s.Site.X, padTop, plotPos.Z + s.Site.Z)) * CFrame.Angles(0, math.rad(s.Yaw or 0), 0)
		-- building floor top is 0.4 above the pad (HollowBuildingBuilder); face local -X (into the room)
		return site * CFrame.new(s.Console.X, 0.4 + h * 0.5, s.Console.Z) * CFrame.Angles(0, math.rad(90), 0)
	end
	local k = s.Kiosk or s.Site
	local at = Vector3.new(plotPos.X + k.X, padTop + h * 0.5, plotPos.Z + k.Z)
	local centre = Vector3.new(plotPos.X, at.Y, plotPos.Z)
	if (centre - at).Magnitude < 1 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, centre)
end

-- Plot-local point → world, on the pad top.
function BaseLayout.GroundPoint(plotPos: Vector3, x: number, z: number, lift: number?): Vector3
	return Vector3.new(plotPos.X + x, plotPos.Y + PAD_HALF_HEIGHT + (lift or 0), plotPos.Z + z)
end

return BaseLayout
