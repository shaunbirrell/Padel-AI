--!strict
--[[
	Programmatic HUD: Level+XP top-left, Cash+Gold top-right.
	Dark military theme + UIScale for mobile.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local UIUtil = require(Shared.Util.UIUtil)

local HUDController = {}

local player = Players.LocalPlayer
local _gui: ScreenGui? = nil
local levelLabel: TextLabel? = nil
local xpBarFill: Frame? = nil
local xpText: TextLabel? = nil
local cashLabel: TextLabel? = nil
local goldLabel: TextLabel? = nil
local passiveLabel: TextLabel? = nil
local seasonLabel: TextLabel? = nil

local function makeCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeStroke(parent: Instance, gold: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = if gold then Constants.Colors.Gold else Color3.fromRGB(55, 65, 55)
	s.Thickness = if gold then 1.5 else 1
	s.Transparency = if gold then 0.35 else 0
	s.Parent = parent
end

function HUDController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireHUD"
	screen.Parent = player:WaitForChild("PlayerGui")
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = false
	UIUtil.AttachMobileScale(screen, 800, 0.7, 1.15)
	_gui = screen

	-- Top-left: Level + XP
	local left = Instance.new("Frame")
	left.Name = "LevelPanel"
	left.AnchorPoint = Vector2.new(0, 0)
	left.Position = UDim2.fromOffset(16, 16)
	left.Size = UDim2.fromOffset(220, 64)
	left.BackgroundColor3 = Constants.Colors.Panel
	left.BackgroundTransparency = 0.15
	left.BorderSizePixel = 0
	left.Parent = screen
	makeCorner(left, 8)
	makeStroke(left, true)

	local lvl = Instance.new("TextLabel")
	lvl.Name = "LevelLabel"
	lvl.BackgroundTransparency = 1
	lvl.Position = UDim2.fromOffset(10, 6)
	lvl.Size = UDim2.new(1, -20, 0, 22)
	lvl.Font = Enum.Font.GothamBold
	lvl.TextSize = 18
	lvl.TextXAlignment = Enum.TextXAlignment.Left
	lvl.TextColor3 = Constants.Colors.Text
	lvl.Text = "LVL 1"
	lvl.Parent = left
	levelLabel = lvl

	local xpBg = Instance.new("Frame")
	xpBg.Name = "XPBarBG"
	xpBg.Position = UDim2.fromOffset(10, 36)
	xpBg.Size = UDim2.new(1, -20, 0, 14)
	xpBg.BackgroundColor3 = Constants.Colors.Background
	xpBg.BorderSizePixel = 0
	xpBg.Parent = left
	makeCorner(xpBg, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Constants.Colors.XP
	fill.BorderSizePixel = 0
	fill.Parent = xpBg
	makeCorner(fill, 4)
	xpBarFill = fill

	local xpLbl = Instance.new("TextLabel")
	xpLbl.Name = "XPText"
	xpLbl.BackgroundTransparency = 1
	xpLbl.Size = UDim2.fromScale(1, 1)
	xpLbl.Font = Enum.Font.Gotham
	xpLbl.TextSize = 11
	xpLbl.TextColor3 = Constants.Colors.Text
	xpLbl.Text = "0 / 100"
	xpLbl.Parent = xpBg
	xpText = xpLbl

	-- Top-right: Cash + Gold
	local right = Instance.new("Frame")
	right.Name = "EconomyPanel"
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -16, 0, 16)
	right.Size = UDim2.fromOffset(200, 72)
	right.BackgroundColor3 = Constants.Colors.Panel
	right.BackgroundTransparency = 0.15
	right.BorderSizePixel = 0
	right.Parent = screen
	makeCorner(right, 8)
	makeStroke(right, true)

	local cash = Instance.new("TextLabel")
	cash.Name = "CashLabel"
	cash.BackgroundTransparency = 1
	cash.Position = UDim2.fromOffset(10, 8)
	cash.Size = UDim2.new(1, -20, 0, 24)
	cash.Font = Enum.Font.GothamBold
	cash.TextSize = 20
	cash.TextXAlignment = Enum.TextXAlignment.Right
	cash.TextColor3 = Constants.Colors.Cash
	cash.Text = "$5,000"
	cash.Parent = right
	cashLabel = cash

	local gold = Instance.new("TextLabel")
	gold.Name = "GoldLabel"
	gold.BackgroundTransparency = 1
	gold.Position = UDim2.fromOffset(10, 34)
	gold.Size = UDim2.new(1, -20, 0, 20)
	gold.Font = Enum.Font.GothamMedium
	gold.TextSize = 16
	gold.TextXAlignment = Enum.TextXAlignment.Right
	gold.TextColor3 = Constants.Colors.Gold
	gold.Text = "◆ 0"
	gold.Parent = right
	goldLabel = gold

	local passive = Instance.new("TextLabel")
	passive.Name = "PassiveHint"
	passive.AnchorPoint = Vector2.new(1, 0)
	passive.Position = UDim2.new(1, -16, 0, 96)
	passive.Size = UDim2.fromOffset(200, 18)
	passive.BackgroundTransparency = 1
	passive.Font = Enum.Font.Gotham
	passive.TextSize = 12
	passive.TextXAlignment = Enum.TextXAlignment.Right
	passive.TextColor3 = Constants.Colors.Muted
	passive.Text = ""
	passive.Parent = screen
	passiveLabel = passive

	local season = Instance.new("TextLabel")
	season.Name = "SeasonLabel"
	season.AnchorPoint = Vector2.new(0.5, 0)
	season.Position = UDim2.new(0.5, 0, 0, 12)
	season.Size = UDim2.fromOffset(280, 22)
	season.BackgroundColor3 = Constants.Colors.Panel
	season.BackgroundTransparency = 0.25
	season.BorderSizePixel = 0
	season.Font = Enum.Font.GothamBold
	season.TextSize = 12
	season.TextColor3 = Constants.Colors.Muted
	season.Text = ""
	season.Visible = false
	season.Parent = screen
	UIUtil.Corner(season, 6)
	seasonLabel = season

	-- Remotes
	local econToken = 0
	Remotes.GetEvent(Constants.RemoteNames.EconomyUpdate).OnClientEvent:Connect(function(payload: Types.EconomyUpdatePayload)
		econToken += 1
		local my = econToken
		local cash, gold = payload.Cash, payload.Gold
		task.defer(function()
			if my == econToken then
				HUDController.SetEconomy(cash, gold)
			end
		end)
	end)

	Remotes.GetEvent(Constants.RemoteNames.XPUpdate).OnClientEvent:Connect(function(payload: Types.XPUpdatePayload)
		HUDController.SetXP(payload.Level, payload.XP, payload.XPToNext)
	end)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		HUDController.ApplyState(state)
	end)

	Remotes.GetEvent(Constants.RemoteNames.BaseStateUpdate).OnClientEvent:Connect(function(base: Types.BaseStatePayload)
		if passiveLabel and base.PassiveIncomePerTick then
			passiveLabel.Text = string.format("+%d$/tick", base.PassiveIncomePerTick)
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.SeasonStateUpdate).OnClientEvent:Connect(function(payload)
		if not seasonLabel or typeof(payload) ~= "table" then
			return
		end
		local active = payload.Active == true
		local name = tostring(payload.DisplayName or payload.SeasonId or "Season")
		if active then
			local xpB = tonumber(payload.XPBonusMult) or 1
			local cashB = tonumber(payload.CashBonusMult) or 1
			seasonLabel.Visible = true
			seasonLabel.TextColor3 = Constants.Colors.Cash
			seasonLabel.Text = string.format("%s  ·  XP×%.2f Cash×%.2f", name, xpB, cashB)
		else
			seasonLabel.Visible = true
			seasonLabel.TextColor3 = Constants.Colors.Muted
			seasonLabel.Text = name .. "  ·  ENDED"
		end
	end)

	-- Initial fetch
	task.spawn(function()
		local ok, state = pcall(function()
			return Remotes.GetFunction(Constants.RemoteNames.GetPlayerState):InvokeServer()
		end)
		if ok and state then
			HUDController.ApplyState(state :: Types.PlayerStatePayload)
		end
	end)
end

local function formatCash(n: number): string
	local formatted = tostring(math.floor(n))
	formatted = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return "$" .. formatted
end

function HUDController.SetEconomy(cash: number, gold: number)
	if cashLabel then
		cashLabel.Text = formatCash(cash)
	end
	if goldLabel then
		goldLabel.Text = "◆ " .. tostring(math.floor(gold))
	end
end

function HUDController.SetXP(level: number, xp: number, xpToNext: number)
	if levelLabel then
		levelLabel.Text = "LVL " .. tostring(level)
	end
	local denom = if xpToNext > 0 and xpToNext < math.huge then xpToNext else 1
	local alpha = math.clamp(xp / denom, 0, 1)
	if xpBarFill then
		xpBarFill.Size = UDim2.fromScale(alpha, 1)
	end
	if xpText then
		if xpToNext == math.huge or xpToNext <= 0 then
			xpText.Text = "MAX"
		else
			xpText.Text = string.format("%d / %d", xp, xpToNext)
		end
	end
end

function HUDController.ApplyState(state: Types.PlayerStatePayload)
	HUDController.SetEconomy(state.Cash, state.Gold)
	HUDController.SetXP(state.Level, state.XP, state.XPToNext)
	if passiveLabel and state.Base then
		passiveLabel.Text = string.format("+%d$/tick", state.Base.PassiveIncomePerTick)
	end
end

return HUDController
