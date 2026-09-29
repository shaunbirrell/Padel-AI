--!strict
--[[
	claude-bud JOB 26: the MY ARMOUR panel (Army menu -> MY ARMOUR). Lists the ArmourConfig tiers with the current one
	marked, BUY on the next (the server checks the order, the Command Center level, that he stands in his own base and
	his Cash), and an "Armour look" toggle (stats stay). Reads the server's player attributes WE_ArmourTier /
	WE_ArmourLookOff. Text 15-16 px real (no UIScale on this gui), buttons 48 px tall, centred, closes with X.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] ArmourController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local ArmourConfig = require(Shared.Configs.ArmourConfig)

local ArmourController = {}

local GOLD = Color3.fromRGB(235, 195, 90)
local KHAKI = Color3.fromRGB(215, 205, 170)
local PLATE = Color3.fromRGB(22, 24, 20)
local gui: ScreenGui? = nil

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. out:gsub("^,", "")
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

local function btn(parent: Instance, text: string, pos: UDim2, size: UDim2, gold: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = if gold then Color3.fromRGB(120, 100, 40) else Color3.fromRGB(55, 60, 50)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.Text = text
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.Parent = parent
	return b
end

local function build()
	close()
	local lp = Players.LocalPlayer
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	local tier = tonumber(lp:GetAttribute("WE_ArmourTier")) or 0
	local g = Instance.new("ScreenGui")
	g.Name = "WE_ArmourPanel"
	g.ResetOnSpawn = false
	g.DisplayOrder = 35
	local rows = #ArmourConfig.Tiers
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(380, 70 + rows * 56 + 64)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.04
	card.Parent = g
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 10)
	cc.Parent = card
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = card
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(420, 560)
	fit.Parent = card
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "MY ARMOUR"
	title.Parent = card
	local x = btn(card, "X", UDim2.new(1, -58, 0, 6), UDim2.fromOffset(48, 48), false)
	x.Activated:Connect(close)
	for i, def in ipairs(ArmourConfig.Tiers) do
		local y = 58 + (i - 1) * 56
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(14, y)
		l.Size = UDim2.new(1, -150, 0, 48)
		l.Font = Enum.Font.GothamBold
		l.TextSize = 15
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = if i <= tier then GOLD else KHAKI
		l.Text = string.format("%s  -%d%% damage\nCC level %d · %s", def.Name, math.floor(def.Reduction * 100 + 0.5), def.NeedCommandCenter, money(def.Cost))
		l.Parent = card
		local label = if i <= tier then "OWNED" elseif i == tier + 1 then "BUY" else "LOCKED"
		local b = btn(card, label, UDim2.new(1, -128, 0, y), UDim2.fromOffset(114, 48), i == tier + 1)
		b.Active = i == tier + 1
		b.AutoButtonColor = i == tier + 1
		if i == tier + 1 then
			local want = i
			b.Activated:Connect(function()
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestBuyArmour, want)
			end)
		end
	end
	local off = lp:GetAttribute("WE_ArmourLookOff") == true
	local look = btn(card, if off then "Armour look: HIDDEN" else "Armour look: SHOWN", UDim2.new(0, 14, 1, -58), UDim2.new(1, -28, 0, 48), false)
	look.Activated:Connect(function()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestArmourLook, lp:GetAttribute("WE_ArmourLookOff") ~= true)
	end)
	g.Parent = pg
	gui = g
end

function ArmourController.Open()
	if ArmourConfig.Enabled == true then
		build()
	end
end

function ArmourController.Init()
	local lp = Players.LocalPlayer
	-- an open panel follows a purchase / the look setting
	for _, a in ipairs({ "WE_ArmourTier", "WE_ArmourLookOff" }) do
		lp:GetAttributeChangedSignal(a):Connect(function()
			if gui then
				build()
			end
		end)
	end
end

return ArmourController
