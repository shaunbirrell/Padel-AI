--!strict
--[[
	F10 (owner's 11 features, lane K1): plot frame helpers shared by the server and the client.
	PlotYaw / PlotCFrame are moved verbatim from the server Modules/BaseLayout (v70 lines 52-80); BaseLayout delegates
	to this module (lane W). Configs may require this (TerritoryConfig does, for the Home Outposts), so it requires only
	configs that never require TerritoryConfig back: BaseLayoutConfig and BaseConfig.

	Yaw convention (matches CFrame.Angles(0, yaw, 0)): a building's local +Z (its FRONT) maps to world
	(sin yaw, 0, cos yaw). Yaw 0 = faces +Z (plot front / main gate), 90 = +X, -90 = -X, 180 = -Z.
	With BaseLayoutConfig.FaceMapCentre the plot FRONT faces the map centre (yaw snapped to 90), otherwise yaw 0.

	Pure math: no instances, no yields, safe under StreamingEnabled (never looks at the workspace).
]]

local Configs = script.Parent.Parent.Configs -- ReplicatedStorage.Shared is replicated before any script runs
local BaseLayoutConfig = require(Configs.BaseLayoutConfig)
local BaseConfig = require(Configs.BaseConfig)

local PlotFrame = {}

-- v70: true when plots are turned to face the map centre (waterways layout)
function PlotFrame.FacesMapCentre(): boolean
	return BaseLayoutConfig.Enabled == true and (BaseLayoutConfig :: any).FaceMapCentre == true
end

-- v70: plot yaw in degrees (0 / 90 / -90 / 180). Front (main gate) toward the map centre.
function PlotFrame.PlotYaw(plotPos: Vector3): number
	if not PlotFrame.FacesMapCentre() then
		return 0
	end
	local x, z = plotPos.X, plotPos.Z
	if math.abs(x) < 1 and math.abs(z) < 1 then
		return 0
	end
	if math.abs(x) >= math.abs(z) then
		return if x < 0 then 90 else -90
	end
	return if z < 0 then 0 else 180
end

-- Exact quarter-turn rotation (no 6e-17 noise from cos(pi/2)), same matrix as CFrame.Angles(0, rad(yaw), 0).
local function yawRotation(yaw: number): CFrame
	local c = if yaw == 0 then 1 elseif yaw == 180 or yaw == -180 then -1 else 0
	local s = if yaw == 90 then 1 elseif yaw == -90 then -1 else 0
	if c == 0 and s == 0 then
		return CFrame.Angles(0, math.rad(yaw), 0)
	end
	return CFrame.new(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end

-- v70: plot frame at the plot position (pad centre height). World = PlotCFrame(plotPos) * plot-local.
function PlotFrame.PlotCFrame(plotPos: Vector3): CFrame
	return CFrame.new(plotPos) * yawRotation(PlotFrame.PlotYaw(plotPos))
end

-- Plot position for a plot id (1..BaseConfig.MaxPlots); nil for an unknown id.
function PlotFrame.PlotPosition(plotId: number): Vector3?
	local list: { any } = BaseConfig.PlotPositions
	local pos = list[plotId]
	if typeof(pos) ~= "Vector3" then
		return nil
	end
	return pos
end

-- F10: plot-local (lx, lz) of plot plotId -> world point at the plot pad centre height (plotPos.Y), turned by the plot
-- yaw. An unknown plot id returns the un-turned offset from the origin (never errors at require time).
function PlotFrame.LocalToWorld(plotId: number, lx: number, lz: number): Vector3
	local pos = PlotFrame.PlotPosition(plotId)
	if pos == nil then
		return Vector3.new(lx, 0, lz)
	end
	return PlotFrame.PlotCFrame(pos):PointToWorldSpace(Vector3.new(lx, 0, lz))
end

return PlotFrame
