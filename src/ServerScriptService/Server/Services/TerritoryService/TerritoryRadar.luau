--!strict
--[[ Radar / minimap reveal helpers + tag-list cache for markers. ]]

local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)

local TerritoryRadar = {}

local _cache: { [string]: { at: number, list: { Instance } } } = {}
local TTL = 2.5

function TerritoryRadar.GetTaggedCached(tag: string): { Instance }
	local now = os.clock()
	local entry = _cache[tag]
	if entry and (now - entry.at) < TTL then
		return entry.list
	end
	local list = CollectionService:GetTagged(tag)
	_cache[tag] = { at = now, list = list }
	return list
end

function TerritoryRadar.Invalidate()
	table.clear(_cache)
end

function TerritoryRadar.FindMarker(territoryId: string): BasePart?
	for _, inst in ipairs(TerritoryRadar.GetTaggedCached(Constants.Tags.CaptureZone)) do
		if inst:IsA("BasePart") and inst:GetAttribute("TerritoryId") == territoryId then
			return inst
		end
	end
	for _, inst in ipairs(TerritoryRadar.GetTaggedCached(Constants.Tags.Territory)) do
		if inst:IsA("BasePart") and (inst:GetAttribute("TerritoryId") == territoryId or inst.Name == territoryId) then
			return inst
		end
	end
	return nil
end

function TerritoryRadar.RevealRadius(): number
	return TerritoryConfig.RadarRevealRadius or 220
end

--[[ F10 (owner's 11 features, lane W): is this zone listed for a viewer whose own plot is viewerPlotId? Every zone
	is, except another plot's Home Outpost (TerritoryConfig.Starter row): only its owner can take it, so it never shows
	in anyone else's territory list, radar or tutorial target. A viewer without a plot (nil) sees no Home Outpost. ]]
function TerritoryRadar.ShownTo(def: TerritoryConfig.TerritoryDef?, viewerPlotId: number?): boolean
	if def == nil then
		return false
	end
	if not TerritoryConfig.IsStarterDef(def) then
		return true
	end
	return viewerPlotId ~= nil and def.PlotId == viewerPlotId
end

return TerritoryRadar
