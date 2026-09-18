--!strict
--[[ Capture-zone presence + tick helpers (spatial checks). ]]

local Players = game:GetService("Players")

local TerritoryCapture = {}

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

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local dx = root.Position.X - center.X
			local dz = root.Position.Z - center.Z
			if dx * dx + dz * dz <= radiusSq then
				table.insert(found, player)
			end
		end
	end
	return found
end

return TerritoryCapture
