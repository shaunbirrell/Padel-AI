--!strict
--[[
	claude-bud JOB 41 part B (2026-10-01): the Recruit Pack card. The server decides WHEN (RecruitPackService,
	FeaturePush "RecruitPackOffer" { ProductId, Cash, RobuxPrice, Trigger }); this only draws one small card, reports
	"shown" (drawn) or "dropped" (the screen never got free) on RequestRecruitPackResult, and on the price tap fires the
	existing purchase-intent remote + MarketplaceService:PromptProductPurchase. Every grant stays ProcessReceipt.

	Phone first (real px, no UIScale on this gui): top-right under the top-bar pills (clear of the thumbstick zone, the
	fire / jump buttons), <= 300 wide (fits 800x360), buttons 48 tall, text >= 15. Three lines: "$<N> Cash" (his real
	number now), "2x Cash for 30 min", "Gold base trim"; the price from the server (never typed here), "Maybe later", X.
	No timer, no "only today". Waits for a free screen (not driving / dead / in combat 20 s / a panel open); hides
	itself after AutoHideSeconds. Later the pack stays in the Shop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] RecruitPackController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local RecruitPackController = {}

local O: any = (MonetizationConfig :: any).RecruitPackOffer
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local BLOCK_FLAGS = { "Driving", "Dead", "RecentCombat", "Modal" }

local showing = false
local lastCombatSeen = -math.huge

function RecruitPackController.Showing(): boolean
	return showing
end

local function blocked(): boolean
	if HudLayout.GetFlag("RecentCombat") then
		lastCombatSeen = os.clock()
	end
	if os.clock() - lastCombatSeen < O.CombatQuietSeconds then
		return true
	end
	for _, f in ipairs(BLOCK_FLAGS) do
		if HudLayout.GetFlag(f) then
			return true
		end
	end
	return false
end

local function report(r: string)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRecruitPackResult, r)
end

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function text(parent: Instance, t: string, size: number, color: Color3, font: Enum.Font, y: number, h: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(14, y)
	l.Size = UDim2.new(1, -28, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = t
	l.Parent = parent
	return l
end

local function showCard(data: any)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		showing = false
		report("dropped")
		return
	end
	local old = pg:FindFirstChild("WE_RecruitPack")
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_RecruitPack"
	g.ResetOnSpawn = false
	g.DisplayOrder = 38
	g.Parent = pg
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = UDim2.new(1, 320, 0, 58)
	card.Size = UDim2.fromOffset(300, 178)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.05
	card.Parent = g
	corner(card, 12)
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = card
	-- claude-bud JOB 66: the server may send its own title / lines (the 5 R$ ONE-TIME OFFER); else the Recruit Pack card
	if typeof(data.Title) == "string" and typeof(data.Lines) == "table" then
		text(card, data.Title, 18, GOLD, Enum.Font.GothamBlack, 8, 26)
		for i, line in ipairs(data.Lines) do
			if i <= 3 then
				text(card, tostring(line), 15, if i == 1 then Color3.new(1, 1, 1) else Color3.fromRGB(215, 205, 170), Enum.Font.GothamBold, 38 + (i - 1) * 22, 20)
			end
		end
	else
		text(card, "Recruit Pack", 18, GOLD, Enum.Font.GothamBlack, 8, 26)
		local cash = math.floor(tonumber(data.Cash) or 0)
		text(card, "$  " .. string.format(O.Lines.Cash, money(cash)), 15, Color3.new(1, 1, 1), Enum.Font.GothamBold, 38, 20)
		text(card, "x2  " .. O.Lines.Boost, 15, Color3.fromRGB(215, 205, 170), Enum.Font.GothamBold, 60, 20)
		text(card, "★  " .. O.Lines.Trim, 15, Color3.fromRGB(215, 205, 170), Enum.Font.GothamBold, 82, 20)
	end
	local x = Instance.new("TextButton")
	x.Position = UDim2.new(1, -54, 0, 6)
	x.Size = UDim2.fromOffset(48, 48)
	x.BackgroundColor3 = Color3.fromRGB(55, 60, 50)
	x.TextColor3 = Color3.new(1, 1, 1)
	x.Font = Enum.Font.GothamBold
	x.TextSize = 16
	x.Text = "X"
	corner(x, 8)
	x.Parent = card
	local price = math.floor(tonumber(data.RobuxPrice) or 0)
	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.new(0, 10, 1, -10)
	buy.Size = UDim2.new(0.5, -15, 0, 48)
	buy.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Font = Enum.Font.GothamBlack
	buy.TextSize = 18
	buy.Text = string.format("%d R$", price)
	corner(buy, 10)
	buy.Parent = card
	local later = Instance.new("TextButton")
	later.AnchorPoint = Vector2.new(1, 1)
	later.Position = UDim2.new(1, -10, 1, -10)
	later.Size = UDim2.new(0.5, -15, 0, 48)
	later.BackgroundColor3 = Color3.fromRGB(55, 60, 50)
	later.TextColor3 = Color3.new(1, 1, 1)
	later.Font = Enum.Font.GothamBold
	later.TextSize = 15
	later.Text = "Maybe later"
	corner(later, 10)
	later.Parent = card
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -16, 0, 58),
	}):Play()
	report("shown")
	local done = false
	local function close()
		if done then
			return
		end
		done = true
		showing = false
		if g.Parent then
			g:Destroy()
		end
	end
	buy.Activated:Connect(function()
		local id = tonumber(data.ProductId) or 0
		if id ~= 0 then
			local key = if typeof(data.ProductKey) == "string" then data.ProductKey else "RecruitPack" -- claude-bud JOB 66
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseDevProduct, key, "recruit_offer")
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		end
		close()
	end)
	later.Activated:Connect(close)
	x.Activated:Connect(close)
	task.delay(O.AutoHideSeconds, close)
end

function RecruitPackController.Init()
	if O == nil or O.Enabled ~= true then
		return
	end
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind ~= "RecruitPackOffer" or typeof(data) ~= "table" or showing then
			return
		end
		showing = true
		task.spawn(function()
			local left = O.ClientWaitMaxSeconds
			while blocked() and left > 0 do
				task.wait(1)
				left -= 1
			end
			if left <= 0 or player.Parent == nil then
				showing = false
				report("dropped")
				return
			end
			showCard(data)
		end)
	end)
end

return RecruitPackController
