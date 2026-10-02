--!strict
--[[
	claude-bud JOB 40 part D (2026-09-30): the "Enjoying WAR EMPIRE?" card. The server decides WHEN
	(RatePromptService, FeaturePush "RatePrompt"); this only draws the card and reports the tapped button on
	RequestRatePromptAnswer ("later" | "never" | "favorite" | "timeout"). NO REWARD: nothing here gives, promises or
	implies anything, and nothing checks a like (there is no API for one). "⭐ Favorite" makes the same
	AvatarEditorService:PromptSetFavorite call as the Shop's "Favorite WAR EMPIRE" row.

	Phone first (real px, no UIScale on this gui): a small card top-centre under the top-bar pills (never over the
	thumbstick zone, the fire buttons or jump), <= 420 wide so it fits 800x360, buttons 48 tall, text >= 15. It waits
	until the screen is free (not driving / dead / in combat, no panel open, and 20 s since the last combat), slides
	in, and hides itself after RatePromptConfig.AutoHideSeconds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] RatePromptController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Cfg = require(Shared.Configs.RatePromptConfig)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local RatePromptController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local BLOCK_FLAGS = { "Driving", "Dead", "RecentCombat", "Modal" }

local showing = false
local lastCombatSeen = -math.huge

local function blocked(): boolean
	if HudLayout.GetFlag("RecentCombat") then
		lastCombatSeen = os.clock()
	end
	if os.clock() - lastCombatSeen < Cfg.CombatQuietSeconds then
		return true
	end
	for _, f in ipairs(BLOCK_FLAGS) do
		if HudLayout.GetFlag(f) then
			return true
		end
	end
	return false
end

local function answer(a: string)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRatePromptAnswer, a)
end

local function button(parent: Instance, text: string, x: number, w: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(x, 4, 1, -10)
	b.Size = UDim2.new(w, -8, 0, 48)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextWrapped = true
	b.Text = text
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.Parent = parent
	return b
end

local function showCard()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		answer("timeout")
		return
	end
	local old = pg:FindFirstChild("WE_RatePrompt")
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_RatePrompt"
	g.ResetOnSpawn = false
	g.DisplayOrder = 37
	g.Parent = pg
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -160)
	card.Size = UDim2.new(0.9, 0, 0, 132)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.06
	card.Parent = g
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(420, 132)
	fit.Parent = card
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 12)
	cc.Parent = card
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = card
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -72, 0, 26)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = Cfg.Text.Title
	title.Parent = card
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(14, 36)
	body.Size = UDim2.new(1, -72, 0, 22)
	body.Font = Enum.Font.GothamBold
	body.TextSize = 15
	body.TextColor3 = Color3.fromRGB(215, 205, 170)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextWrapped = true
	body.Text = Cfg.Text.Body
	body.Parent = card
	local x = Instance.new("TextButton")
	x.Position = UDim2.new(1, -54, 0, 6)
	x.Size = UDim2.fromOffset(48, 48)
	x.BackgroundColor3 = Color3.fromRGB(55, 60, 50)
	x.TextColor3 = Color3.new(1, 1, 1)
	x.Font = Enum.Font.GothamBold
	x.TextSize = 16
	x.Text = "X"
	local xc = Instance.new("UICorner")
	xc.CornerRadius = UDim.new(0, 8)
	xc.Parent = x
	x.Parent = card
	local fav = button(card, Cfg.Text.Favorite, 0, 0.3, Color3.fromRGB(120, 100, 40))
	local later = button(card, Cfg.Text.Later, 0.3, 0.32, Color3.fromRGB(55, 60, 50))
	local never = button(card, Cfg.Text.Never, 0.62, 0.38, Color3.fromRGB(70, 45, 40))
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 58),
	}):Play()
	local done = false
	local function close(a: string)
		if done then
			return
		end
		done = true
		showing = false
		answer(a)
		if g.Parent then
			g:Destroy()
		end
	end
	fav.Activated:Connect(function()
		-- the same call as the Shop's favourite row; no reward, and nothing checks what the player chose
		pcall(function()
			game:GetService("AvatarEditorService"):PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
		close("favorite")
	end)
	later.Activated:Connect(function()
		close("later")
	end)
	x.Activated:Connect(function()
		close("later")
	end)
	never.Activated:Connect(function()
		close("never")
	end)
	task.delay(Cfg.AutoHideSeconds, function()
		close("timeout")
	end)
end

function RatePromptController.Init()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, _data: any)
		if kind ~= "RatePrompt" or showing then
			return
		end
		showing = true
		task.spawn(function()
			local left = Cfg.ClientWaitMaxSeconds
			while blocked() and left > 0 do
				task.wait(1)
				left -= 1
			end
			if left <= 0 or player.Parent == nil then
				showing = false
				answer("timeout")
				return
			end
			showCard()
		end)
	end)
end

return RatePromptController
