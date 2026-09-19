--!strict
--[[
	Empire Bank raid HUD — bottom progress bar (gunmetal/gold).
	Shows while InVault / HoldProgress>0 / UnderFire; cooldown text when cooling down on vault.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)

local BankRaidController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled

local _gui: ScreenGui? = nil
local progressFrame: Frame? = nil
local progressFill: Frame? = nil
local titleLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local pctLabel: TextLabel? = nil

export type BankRaidStatePayload = {
	BankId: string?,
	DisplayName: string?,
	Enabled: boolean?,
	CooldownRemaining: number?,
	RaidHoldSeconds: number?,
	HoldNeed: number?,
	HoldProgress: number?,
	InVault: boolean?,
	UnderFire: boolean?,
	CashHintMin: number?,
	CashHintMax: number?,
}

local function setVisible(visible: boolean)
	if progressFrame then
		progressFrame.Visible = visible
	end
end

function BankRaidController.Apply(payload: BankRaidStatePayload)
	if payload.Enabled == false then
		setVisible(false)
		return
	end

	local inVault = payload.InVault == true
	local underFire = payload.UnderFire == true
	local hold = tonumber(payload.HoldProgress) or 0
	local need = tonumber(payload.HoldNeed) or tonumber(payload.RaidHoldSeconds) or 8
	if need <= 0 then
		need = 8
	end
	local cd = math.max(0, math.floor(tonumber(payload.CooldownRemaining) or 0))
	local name = payload.DisplayName or "Empire Bank"

	local show = inVault or hold > 0 or underFire
	if not show then
		setVisible(false)
		return
	end

	setVisible(true)
	local pct = math.clamp(hold / need, 0, 1)
	if pctLabel then
		if cd > 0 then
			pctLabel.Text = string.format("%dm", math.ceil(cd / 60))
		else
			pctLabel.Text = string.format("%d%%", math.floor(pct * 100))
		end
	end
	if progressFill then
		progressFill.Size = UDim2.fromScale(if cd > 0 then 0 else pct, 1)
		if underFire then
			progressFill.BackgroundColor3 = Color3.fromRGB(220, 90, 70)
		elseif cd > 0 then
			progressFill.BackgroundColor3 = Color3.fromRGB(90, 100, 110)
		else
			progressFill.BackgroundColor3 = Constants.Colors.Gold
		end
	end
	if titleLabel then
		if cd > 0 then
			titleLabel.Text = string.format("%s cooldown", name)
		else
			titleLabel.Text = string.format("Raiding %s…", name)
		end
	end
	if statusLabel then
		if cd > 0 then
			local mins = math.max(1, math.ceil(cd / 60))
			statusLabel.Text = string.format("Cooldown %dm — come back later", mins)
			statusLabel.TextColor3 = Color3.fromRGB(180, 190, 200)
		elseif underFire then
			statusLabel.Text = "UNDER FIRE — clear guards"
			statusLabel.TextColor3 = Color3.fromRGB(255, 140, 90)
		else
			local cashMin = tonumber(payload.CashHintMin) or 15000
			local cashMax = tonumber(payload.CashHintMax) or 35000
			statusLabel.Text = string.format("STAND TO LOOT · $%d–$%d", cashMin, cashMax)
			statusLabel.TextColor3 = Color3.fromRGB(200, 210, 140)
		end
	end
end

function BankRaidController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireBankRaid"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	-- Above territory capture (28), below pad BUY / combat cluster
	screen.DisplayOrder = 32
	_gui = screen

	local prog = Instance.new("Frame")
	prog.Name = "BankRaidProgress"
	prog.AnchorPoint = Vector2.new(0.5, 1)
	-- Sit above territory bar / dock; clear of pad BUY (~-108) and combat HP
	prog.Position = UDim2.new(0.5, 0, 1, if isTouch then -330 else -180)
	prog.Size = UDim2.fromOffset(if isTouch then 340 else 300, if isTouch then 78 else 52)
	prog.BackgroundColor3 = Constants.Colors.Gunmetal
	prog.BackgroundTransparency = 0.05
	prog.BorderSizePixel = 0
	prog.Visible = false
	prog.ZIndex = 12
	prog.Parent = screen
	UIUtil.Corner(prog, 10)
	UIUtil.GoldStroke(prog, 2)
	progressFrame = prog

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -90, 0, if isTouch then 20 else 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = if isTouch then 15 else 13
	title.TextColor3 = Constants.Colors.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Raiding Empire Bank…"
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = prog
	titleLabel = title

	local pct = Instance.new("TextLabel")
	pct.Name = "Pct"
	pct.BackgroundTransparency = 1
	pct.AnchorPoint = Vector2.new(1, 0)
	pct.Position = UDim2.new(1, -12, 0, 6)
	pct.Size = UDim2.fromOffset(72, if isTouch then 22 else 18)
	pct.Font = Enum.Font.GothamBold
	pct.TextSize = if isTouch then 18 else 14
	pct.TextColor3 = Constants.Colors.Gold
	pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.Text = "0%"
	pct.Parent = prog
	pctLabel = pct

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(12, if isTouch then 28 else 24)
	status.Size = UDim2.new(1, -24, 0, 16)
	status.Font = Enum.Font.GothamBold
	status.TextSize = if isTouch then 12 else 11
	status.TextColor3 = Color3.fromRGB(200, 210, 140)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = "STAND TO LOOT"
	status.Parent = prog
	statusLabel = status

	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromOffset(12, if isTouch then 50 else 36)
	bg.Size = UDim2.new(1, -24, 0, if isTouch then 18 else 14)
	bg.BackgroundColor3 = Constants.Colors.Background
	bg.BorderSizePixel = 0
	bg.Parent = prog
	UIUtil.Corner(bg, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Constants.Colors.Gold
	fill.BorderSizePixel = 0
	fill.Parent = bg
	UIUtil.Corner(fill, 4)
	progressFill = fill

	Remotes.GetEvent(Constants.RemoteNames.BankRaidStateUpdate).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		BankRaidController.Apply(payload :: BankRaidStatePayload)
	end)

	print("[WAR EMPIRE] BankRaidController ready")
end

return BankRaidController
