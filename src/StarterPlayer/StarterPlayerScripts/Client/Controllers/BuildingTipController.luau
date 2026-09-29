--!strict
--[[
	claude-bud JOB 24 §5: the "NEW BUILDING" card (Shared/Configs/BuildingTutorialConfig; the server decides when:
	Server/Services/BuildingTips, BuildingTip remote { Id }). One card at a time (queued), never while he sits in a
	vehicle, small and mid-top (clear of the thumbstick, the jump button and the top-bar pills). OK closes it; SHOW ME
	draws a beam from him to that building's console (the server's WE_ConsolePos_<Id> stamp) for ShowSeconds.
	Text 16 px real (no UIScale on this gui), buttons 48 px tall.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- (streaming2 C5: bounded wait; no Shared = the module stays empty, never throws)
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] BuildingTipController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local BuildingTutorialConfig = require(Shared.Configs.BuildingTutorialConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BusinessConfig = require(Shared.Configs.BusinessConfig)

local BuildingTipController = {}

local GOLD = Color3.fromRGB(235, 195, 90)
local KHAKI = Color3.fromRGB(215, 205, 170)
local PLATE = Color3.fromRGB(22, 24, 20)

local queue: { string } = {}
local showing = false

local function displayName(id: string): string
	local okB, def = pcall(function()
		return (BaseConfig :: any).Structures[id]
	end)
	if okB and typeof(def) == "table" and typeof(def.DisplayName) == "string" then
		return def.DisplayName
	end
	local bc: any = BusinessConfig
	if typeof(bc) == "table" then
		for _, b in pairs(bc.Businesses or {}) do
			if typeof(b) == "table" and b.Id == id and typeof(b.DisplayName) == "string" then
				return b.DisplayName
			end
		end
	end
	return (string.gsub(id, "(%l)(%u)", "%1 %2"))
end

local function showMe(id: string)
	local lp = Players.LocalPlayer
	local target = lp:GetAttribute("WE_ConsolePos_" .. id)
	local ch = lp.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if typeof(target) ~= "Vector3" or root == nil then
		return
	end
	local marker = Instance.new("Part")
	marker.Name = "WE_TipMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.4, 6, 6)
	marker.CFrame = CFrame.new(target) * CFrame.Angles(0, 0, math.rad(90))
	marker.Material = Enum.Material.Neon
	marker.Color = GOLD
	marker.Transparency = 0.35
	marker.Parent = Workspace
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 3, 0)
	a1.Parent = marker
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Color = ColorSequence.new(GOLD)
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.Parent = marker
	task.delay(BuildingTutorialConfig.ShowSeconds, function()
		a0:Destroy()
		marker:Destroy()
	end)
end

local function button(text: string, x: number, parent: Instance, primary: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.5, -12, 0, 48)
	b.Position = UDim2.new(x, if x == 0 then 8 else 4, 1, -56)
	b.BackgroundColor3 = if primary then Color3.fromRGB(120, 100, 40) else Color3.fromRGB(55, 60, 50)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.Text = text
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.Parent = parent
	return b
end

local function report(name: string, id: string)
	pcall(function()
		Remotes.FireServer(Constants.RemoteNames.RequestAnalyticsEvent, name, id)
	end)
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	local lp = Players.LocalPlayer
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	-- never over a drive (one message at a time, nothing screen-covering while driving)
	local ch = lp.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart ~= nil then
		task.delay(3, showNext)
		return
	end
	showing = true
	local id = table.remove(queue, 1) :: string
	local tip = BuildingTutorialConfig.Tips[id]
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_BuildingTip"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 72)
	card.Size = UDim2.new(0, 360, 0, 96 + 26 * #tip.Lines)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.06
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = card
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(420, 400)
	size.Parent = card
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 26)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = "NEW: " .. string.upper(displayName(id)) .. " UNLOCKED"
	title.Parent = card
	for i, line in ipairs(tip.Lines) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(12, 10 + 26 * i)
		l.Size = UDim2.new(1, -24, 0, 24)
		l.Font = Enum.Font.GothamMedium
		l.TextSize = 16
		l.TextColor3 = KHAKI
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextWrapped = true
		l.Text = line
		l.Parent = card
	end
	local okB = button("OK", 0, card, false)
	local showB = button("SHOW ME", 0.5, card, true)
	gui.Parent = pg
	report("TipShown", id)
	local closed = false
	local function close(show: boolean)
		if closed then
			return
		end
		closed = true
		gui:Destroy()
		report("TipClosed", id)
		if show then
			showMe(id)
		end
		showing = false
		task.delay(0.5, showNext)
	end
	okB.Activated:Connect(function()
		close(false)
	end)
	showB.Activated:Connect(function()
		close(true)
	end)
	task.delay(25, function()
		close(false) -- (never left on screen)
	end)
end

function BuildingTipController.Init()
	if BuildingTutorialConfig.Enabled ~= true then
		return
	end
	Remotes.BindEvent(Constants.RemoteNames.BuildingTip, function(payload: any)
		local id = typeof(payload) == "table" and payload.Id
		if typeof(id) == "string" and BuildingTutorialConfig.Tips[id] and not table.find(queue, id) then
			table.insert(queue, id)
			showNext()
		end
	end)
end

return BuildingTipController
