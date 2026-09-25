--!strict
--[[ Capture-zone presence + tick helpers (spatial checks).
	v70 waterways: who counts inside a zone.
	  * Vehicles: only the DRIVER of a vehicle counts (TerritoryConfig.VehiclePassengersCount = false), so a crewed
	    boat or jeep no longer contests its own capture. Passengers neither capture nor contest.
	  * Naval outposts (WaterConfig.NavalOutposts, Presence "BoatOrDeck", the oil rigs): only the driver of a Naval
	    vehicle, or a player on foot standing on the deck / pier top (HumanoidRootPart.Y >= DeckMinY). Waders do not count.
	  * Presence "Any" (SouthDocks) and every other territory: anyone alive in range (drivers included).
	F10 (owner's 11 features, lane W): an OwnerOnly zone (the Home Outposts, TerritoryConfig.Starter rows with PlotId)
	counts ONLY the player who owns that plot on this server (BaseService.GetOwnerUserId(def.PlotId), bound by
	TerritoryService.Init through SetPlotOwnerResolver). Anyone else neither captures nor contests it; with no owner
	(free plot, or no resolver bound) nobody counts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local WaterConfig = require(Shared.Configs.WaterConfig)

local TerritoryCapture = {}

-- F10: plotId -> the owner's UserId on this server (BaseService.GetOwnerUserId), or nil
local plotOwnerOf: ((number) -> number?)? = nil

--[[ F10: TerritoryService.Init binds BaseService.GetOwnerUserId here (no require cycle, no BaseService dependency). ]]
function TerritoryCapture.SetPlotOwnerResolver(fn: ((number) -> number?)?)
	plotOwnerOf = fn
end

-- F10: the only UserId that counts in an OwnerOnly zone, 0 = nobody; nil = not an OwnerOnly zone (normal rule)
local function ownerOnlyUserId(def: any): number?
	if typeof(def) ~= "table" or def.OwnerOnly ~= true then
		return nil
	end
	local plotId = def.PlotId
	local resolve = plotOwnerOf
	if typeof(plotId) ~= "number" or resolve == nil then
		return 0
	end
	local ok, uid = pcall(resolve, plotId)
	if ok and typeof(uid) == "number" and uid > 0 then
		return uid
	end
	return 0
end

-- v70: the vehicle a humanoid is seated in (a Model carrying VehicleId), and whether that seat is the driver's
local function seatedVehicle(humanoid: Humanoid): (Model?, boolean)
	local seat = humanoid.SeatPart
	if not seat then
		return nil, false
	end
	local model = seat:FindFirstAncestorWhichIsA("Model")
	while model and model:GetAttribute("VehicleId") == nil do
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	if not model then
		return nil, false
	end
	return model, (seat.Name == "DriverSeat" or seat:GetAttribute("WE_DriverSeat") == true)
end

-- v70: presence rule of a naval outpost (nil = normal rule)
local function navalRule(territoryId: any): any
	if WaterConfig.Enabled == false or typeof(territoryId) ~= "string" then
		return nil
	end
	return (WaterConfig.NavalOutposts :: any)[territoryId]
end

-- v70: does this (alive, in-range) player count toward capture / contest?
local function counts(rule: any, root: BasePart, humanoid: Humanoid): boolean
	local vehicle, isDriver = seatedVehicle(humanoid)
	if vehicle and not isDriver and (TerritoryConfig :: any).VehiclePassengersCount ~= true then
		return false -- passengers neither capture nor contest (a boat crew no longer contests its own capture)
	end
	if rule ~= nil and rule.Presence == "BoatOrDeck" then
		if vehicle then
			return isDriver
				and (vehicle:GetAttribute("WE_Category") == "Naval" or vehicle:GetAttribute("WE_DriveMode") == "Boat")
		end
		return root.Position.Y >= (tonumber(rule.DeckMinY) or 24) -- on the deck / top of the pier, not wading
	end
	return true
end

-- Squared-distance presence test (flat XZ) without changing capture rules.
function TerritoryCapture.PlayersInZone(rt: any): { Player }
	local found: { Player } = {}
	local marker = rt.Marker
	local center = if marker then marker.Position else rt.Def.Position
	local radius = rt.Def.Radius
	if marker then
		local half = marker.Size.Magnitude * 0.5
		radius = math.max(radius, half)
	end
	local radiusSq = radius * radius
	local rule = navalRule(rt.Id or (rt.Def and rt.Def.Id))
	local onlyUserId = ownerOnlyUserId(rt.Def)
	if onlyUserId == 0 then
		return found -- F10: an OwnerOnly zone whose plot has no owner here: nobody captures or contests it
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if onlyUserId ~= nil and player.UserId ~= onlyUserId then
			continue -- F10 OwnerOnly: only the plot owner counts
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local dx = root.Position.X - center.X
			local dz = root.Position.Z - center.Z
			if dx * dx + dz * dz <= radiusSq and counts(rule, root, humanoid) then
				table.insert(found, player)
			end
		end
	end
	return found
end

return TerritoryCapture
