--!strict
--[[ Lightweight compass: direction + distance to own base and nearest unowned territory. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local UIUtil = require(Shared.Util.UIUtil)

local CompassController = {}

local player = Players.LocalPlayer
local myPlotId: number? = nil
local territoryOwners: { [string]: { OwnerType: string, OwnerUserId: number } } = {}

local baseLabel: TextLabel? = nil
local outpostLabel: TextLabel? = nil
local accum = 0

local CARDINAL_LABELS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function bearingLabel(from: Vector3, to: Vector3, look: Vector3): string
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if dir.Magnitude < 1 then
		return "•"
	end
	dir = dir.Unit
	local lookFlat = Vector3.new(look.X, 0, look.Z)
	if lookFlat.Magnitude < 0.05 then
		lookFlat = Vector3.new(0, 0, -1)
	else
		lookFlat = lookFlat.Unit
	end
	-- Relative bearing vs camera look (0 = ahead)
	local worldAngle = math.deg(math.atan2(dir.X, -dir.Z)) % 360
	local lookAngle = math.deg(math.atan2(lookFlat.X, -lookFlat.Z)) % 360
	local relative = (worldAngle - lookAngle + 360) % 360
	local idx = (math.floor((relative + 22.5) / 45) % 8) + 1
	return CARDINAL_LABELS[idx] or "N"
end

local function formatDist(studs: number): string
	if studs < 1000 then
		return string.format("%dm", math.floor(studs))
	end
	return string.format("%.1fkm", studs / 1000)
end

local function getRoot(): (Vector3?, Vector3?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil, nil
	end
	local cam = Workspace.CurrentCamera
	local look = if cam then cam.CFrame.LookVector else hrp.CFrame.LookVector
	return hrp.Position, look
end

local function baseWorldPos(): Vector3?
	if typeof(myPlotId) ~= "number" then
		return nil
	end
	local pos = BaseConfig.PlotPositions[myPlotId]
	if pos then
		return pos
	end
	return nil
end

local function nearestUnowned(from: Vector3): (string?, Vector3?, number?)
	local bestId: string? = nil
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	for id, def in pairs(TerritoryConfig.Territories) do
		local own = territoryOwners[id]
		local ownedByMe = own and own.OwnerType == "Player" and own.OwnerUserId == player.UserId
		local isNeutral = (not own) or own.OwnerType == "Neutral" or own.OwnerType == ""
		-- Prefer unowned/neutral; skip own holdings
		if not ownedByMe and (isNeutral or (own and own.OwnerType ~= "Player")) then
			-- Prefer truly neutral over NPC/clan when choosing "unowned" target
			local weight = if isNeutral then 0 else 80
			local d = (def.Position - from).Magnitude + weight
			if d < bestDist then
				bestDist = d
				bestId = def.DisplayName
				bestPos = def.Position
			end
		end
	end
	if bestId and bestPos then
		return bestId, bestPos, (bestPos - from).Magnitude
	end
	return nil, nil, nil
end

local function tickCompass()
	if not baseLabel or not outpostLabel then
		return
	end
	local pos, look = getRoot()
	if not pos or not look then
		baseLabel.Text = "⌂ BASE  —"
		outpostLabel.Text = "◎ OUTPOST  —"
		return
	end

	local bPos = baseWorldPos()
	if bPos then
		local dist = (bPos - pos).Magnitude
		local dir = bearingLabel(pos, bPos, look)
		baseLabel.Text = string.format("⌂ BASE  %s  %s", dir, formatDist(dist))
	else
		baseLabel.Text = "⌂ BASE  …"
	end

	local name, tPos, dist = nearestUnowned(pos)
	if name and tPos and dist then
		local dir = bearingLabel(pos, tPos, look)
		outpostLabel.Text = string.format("◎ %s  %s  %s", name, dir, formatDist(dist))
	else
		outpostLabel.Text = "◎ OUTPOST  all held"
	end
end

function CompassController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarEmpireCompass"
	gui.DisplayOrder = 20
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(gui, false)

	local frame = Instance.new("Frame")
	frame.Name = "Compass"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -16, 0, 100)
	frame.Size = UDim2.fromOffset(210, 52)
	frame.BackgroundColor3 = Constants.Colors.Panel
	frame.BackgroundTransparency = 0.22
	frame.BorderSizePixel = 0
	frame.Parent = gui
	UIUtil.Corner(frame, 8)
	UIUtil.Stroke(frame, Color3.fromRGB(70, 100, 80), 1)

	local base = Instance.new("TextLabel")
	base.Name = "BaseHint"
	base.BackgroundTransparency = 1
	base.Position = UDim2.fromOffset(8, 4)
	base.Size = UDim2.new(1, -12, 0, 20)
	base.Font = Enum.Font.GothamBold
	base.TextSize = 12
	base.TextXAlignment = Enum.TextXAlignment.Left
	base.TextColor3 = Color3.fromRGB(160, 220, 170)
	base.Text = "⌂ BASE  —"
	base.Parent = frame
	baseLabel = base

	local out = Instance.new("TextLabel")
	out.Name = "OutpostHint"
	out.BackgroundTransparency = 1
	out.Position = UDim2.fromOffset(8, 26)
	out.Size = UDim2.new(1, -12, 0, 20)
	out.Font = Enum.Font.GothamMedium
	out.TextSize = 12
	out.TextXAlignment = Enum.TextXAlignment.Left
	out.TextColor3 = Color3.fromRGB(220, 200, 120)
	out.Text = "◎ OUTPOST  —"
	out.Parent = frame
	outpostLabel = out

	Remotes.GetEvent(Constants.RemoteNames.BaseStateUpdate).OnClientEvent:Connect(function(basePayload: Types.BaseStatePayload)
		if typeof(basePayload.PlotId) == "number" then
			myPlotId = basePayload.PlotId
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		if state.Base and typeof(state.Base.PlotId) == "number" then
			myPlotId = state.Base.PlotId
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.TerritoryStateUpdate).OnClientEvent:Connect(function(payload: Types.TerritoryStatePayload)
		for _, entry in ipairs(payload.Territories) do
			territoryOwners[entry.Id] = {
				OwnerType = entry.OwnerType,
				OwnerUserId = entry.OwnerUserId or 0,
			}
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= 0.25 then
			accum = 0
			tickCompass()
		end
	end)
end

return CompassController
