--!strict
--[[
	claude-bud JOB 52 (2026-10-01): the "nothing in range" card for ATTACK at range (ArmyOrdersConfig.AttackRange, owner-
	first). The server found no valid enemy within the ATTACK range and pushes FeaturePush "ArmyNearest" { Text =
	"No enemies within 112 m. Nearest: 174 m NE", X, Y, Z, Target = "N:<npcId>" }. One card in the HUD top stack
	(HudLayout.RegisterTopStack: no overlap with the other top items, never under the thumbstick / fire / jump):
	  PIN  -> the ONE objective marker on that spot (ObjectiveMarker.ShowWith, Pin) - his own pin, nothing moves;
	  SEND -> RequestArmySend with the server's id only (ArmyTargets resolves it; the client never sends a position).
	Gone after CardSeconds or a tap. Display only; the server decides every order.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] ArmyNearestController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)

local ArmyNearestController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local STACK = "ArmyNearestCard"
local CARD_SECONDS = 9

local gui: ScreenGui? = nil
local seq = 0

local function close()
	local g = gui
	gui = nil
	pcall(HudLayout.UnregisterTopStack, STACK)
	if g then
		g:Destroy()
	end
end

local function button(parent: Instance, text: string, x: number, color: Color3, onTap: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name = text
	b.Position = UDim2.new(x, 6, 0, 46)
	b.Size = UDim2.new(0.5, -12, 0, 64) -- 64 code px under the HUD UIScale (~0.7) = ~45 px real, a finger target
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 22
	b.Text = text
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b
	b.Activated:Connect(onTap)
	return b
end

local function show(data: any)
	close()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_ArmyNearestCard"
	g.ResetOnSpawn = false
	g.DisplayOrder = 34
	g.Parent = pg
	gui = g
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 80)
	f.Size = UDim2.fromOffset(460, 122)
	f.BackgroundColor3 = PLATE
	f.BackgroundTransparency = 0.08
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(12, 8)
	t.Size = UDim2.new(1, -24, 0, 32)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 21 -- >= 14 px real at the phone HUD scale
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = tostring(data.Text or "")
	t.Parent = f
	local x, y, z = tonumber(data.X), tonumber(data.Y), tonumber(data.Z)
	button(f, "PIN", 0, Color3.fromRGB(60, 66, 54), function()
		if x and y and z then
			pcall(ObjectiveMarker.ShowWith, { Short = "ENEMY", X = x, Y = y, Z = z }, { Pin = true, ArriveStuds = 15 })
		end
		close()
	end)
	local target = if typeof(data.Target) == "string" and #data.Target <= 70 then data.Target else nil
	local send = button(f, "SEND ARMY", 0.5, Color3.fromRGB(170, 55, 45), function()
		if target then
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestArmySend, target)
		end
		close()
	end)
	send.Visible = target ~= nil
	pcall(HudLayout.ApplyScreen, g)
	pcall(HudLayout.RegisterTopStack, STACK, f, 14)
	seq += 1
	local my = seq
	task.delay(CARD_SECONDS, function()
		if seq == my then
			close()
		end
	end)
end

function ArmyNearestController.Init()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind == "ArmyNearest" and typeof(data) == "table" then
			show(data)
		end
	end)
end

return ArmyNearestController
