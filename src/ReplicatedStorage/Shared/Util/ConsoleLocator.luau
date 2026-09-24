--!strict
--[[
	v71 console-only buying: which part is a structure's console on a plot, and is a player standing at it?

	One answer for server and client:
	  server  BaseService.PurchaseUpgrade (the gate), UpgradePadService (plot-ready position stamps), StudioBuySmoke
	  client  ConsoleWaypoint (Base panel GO)

	A buy point is a BasePart in Workspace tagged Constants.Tags.UpgradeSlot with attributes PlotId (number) and
	StructureId (string). WE_Console = true marks a console / kiosk (BaseLayoutConfig on). A console always wins over
	a legacy pad or a stray part the v63 StructureId sweeps tagged. Positions are the part's own world position, so
	rotated plots (BaseLayout.PlotCFrame, FaceMapCentre) need nothing here. Never yields, never WaitForChild.

	"At" = a cylinder around the part centre: horizontal (XZ) distance <= MaxDistance(part) and
	|dy| <= ConsoleBuyConfig.MaxVerticalOffset (same shape as MissileStrikeService's atCommandCenter).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ConsoleBuyConfig = require(Shared.Configs.ConsoleBuyConfig)

local ConsoleLocator = {}

-- Reasons (logs / tests only; the player-facing error is always "NotAtConsole")
export type Reason = "Ok" | "NoCharacter" | "Dead" | "Seated" | "NoConsole" | "WrongPart" | "TooFar" | "WrongFloor" | "OtherNearer"

local function plotIdOf(part: Instance): number?
	return tonumber(part:GetAttribute("PlotId") :: any)
end

local function flat(v: Vector3): number
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function ConsoleLocator.IsConsole(part: BasePart): boolean
	return part:GetAttribute("WE_Console") == true
end

-- True when `part` is a live buy point for (plotId, structureId).
function ConsoleLocator.IsBuyPointFor(part: Instance?, plotId: number, structureId: string): boolean
	if part == nil or not part:IsA("BasePart") or not part:IsDescendantOf(Workspace) then
		return false
	end
	if not CollectionService:HasTag(part, Constants.Tags.UpgradeSlot) then
		return false
	end
	return part:GetAttribute("StructureId") == structureId and plotIdOf(part) == plotId
end

-- The structure's console on that plot; a legacy pad only when the plot has no console for it; nil when none.
function ConsoleLocator.Find(plotId: number, structureId: string): BasePart?
	local fallback: BasePart? = nil
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("StructureId") == structureId and plotIdOf(inst) == plotId
			and inst:IsDescendantOf(Workspace) then
			local part = inst :: BasePart
			if ConsoleLocator.IsConsole(part) then
				return part
			end
			if fallback == nil then
				fallback = part
			end
		end
	end
	return fallback
end

-- Allowed HORIZONTAL HRP -> part-centre distance. slack defaults to ConsoleBuyConfig.ServerSlack (the client passes 0).
function ConsoleLocator.MaxDistance(part: BasePart, slack: number?): number
	local base = if ConsoleLocator.IsConsole(part)
		then ConsoleBuyConfig.ConsolePromptDistance
		else ConsoleBuyConfig.PadPromptDistance
	return base + (if slack ~= nil then slack else ConsoleBuyConfig.ServerSlack)
end

-- Where a character stands to use `part`: 3 studs in front of its face (consoles face into the room / the plot
-- centre), HRP height. StudioBuySmoke teleports here; tests use it.
function ConsoleLocator.StandCFrame(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, 1.3, -3)
end

--[[ Is `player` at the console of `structureId` on plot `plotId` (the caller passes the player's OWN plot)?
	atPart: the part whose prompt fired (UpgradePadService); it must itself be a buy point for (plotId, structureId).
	Returns (ok, reason, horizontalDistance?). Reads only the server's (or local client's) view of the character;
	nothing the client sends in a remote payload. ]]
function ConsoleLocator.Check(player: Player, plotId: number, structureId: string, atPart: BasePart?, slack: number?): (boolean, Reason, number?)
	local character = player.Character
	if character == nil then
		return false, "NoCharacter", nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local rootInst = (hum and hum.RootPart) or character:FindFirstChild("HumanoidRootPart")
	if rootInst == nil or not rootInst:IsA("BasePart") then
		return false, "NoCharacter", nil
	end
	local hrp = rootInst :: BasePart
	if not hum or hum.Health <= 0 then
		return false, "Dead", nil
	end
	if ConsoleBuyConfig.RejectSeated and hum.SeatPart ~= nil then
		return false, "Seated", nil
	end
	local target: BasePart? = nil
	if atPart ~= nil then
		if not ConsoleLocator.IsBuyPointFor(atPart, plotId, structureId) then
			return false, "WrongPart", nil
		end
		target = atPart
	else
		target = ConsoleLocator.Find(plotId, structureId)
	end
	if target == nil then
		return false, "NoConsole", nil
	end
	local offset = hrp.Position - target.Position
	local d = flat(offset)
	if d > ConsoleLocator.MaxDistance(target, slack) then
		return false, "TooFar", d
	end
	if math.abs(offset.Y) > ConsoleBuyConfig.MaxVerticalOffset then
		return false, "WrongFloor", d -- e.g. the upper floor of a two-storey walk-in, above a ground-floor console
	end
	-- Two consoles in range (close kiosks, e.g. the planned rebirth-zone silo / drone kiosks 21.5 apart): only the
	-- nearest one buys, the same rule as Roblox prompt exclusivity (OnePerButton shows one prompt per key).
	if ConsoleBuyConfig.RequireNearest then
		local margin = ConsoleBuyConfig.NearestMargin
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
			if inst ~= target and inst:IsA("BasePart") and plotIdOf(inst) == plotId
				and inst:GetAttribute("StructureId") ~= structureId
				and ConsoleLocator.IsConsole(inst) == ConsoleLocator.IsConsole(target)
				and inst:IsDescendantOf(Workspace) then
				if flat((inst :: BasePart).Position - hrp.Position) + margin < d then
					return false, "OtherNearer", d
				end
			end
		end
	end
	return true, "Ok", d
end

return ConsoleLocator
