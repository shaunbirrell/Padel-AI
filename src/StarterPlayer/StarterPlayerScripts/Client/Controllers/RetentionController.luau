--!strict
--[[
	claude-bud JOB 29 (2026-09-30): retention, client side. It only shows what the server pushes (FeaturePush) and
	reports taps; every amount is decided on the server (RetentionService / MissionService).
	  * "StarterPayout" {Cash}: coins fly from the middle of the screen to the cash pill, with a big "+$X" (FastStart).
	  * "WelcomeBack" {Cash, Seconds, Capped, Premium}: the "Welcome back: +$X while away" card. The server already
	    paid it into his ATM (PendingCash); OK / X / 12 s only close the card.
	  * "Streak" {Days, Today, Cash, Big, TomorrowCash, Boost, Seconds}: one card with the 7-day strip and "Come back
	    tomorrow for $Y". Top-centre under the top bar, tap to close, gone after Seconds.
	  * "NotifOptIn": the server's calm-moment ask (after the tutorial). Modules/NotifOptIn asks Roblox and reports
	    the result (Settings has the same TURN ON).
	  * The FastStart arrow: while WE_Onboarding is on and the Command Center is not bought, a big pulsing arrow
	    floats over HIS Command Center console (WE_ConsolePos_CommandCenter). Only one TweenService loop, no per-frame
	    work.
	The cards wait while the player drives, is dead, is in combat or has a panel open (HudLayout flags), up to 60 s.
	Real px (no UIScale on these guis): text >= 15, buttons 48 tall. Copy names no keys.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] RetentionController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local StreakStrip = require(script.Parent.Parent.Modules.StreakStrip)
local NotifOptIn = require(script.Parent.Parent.Modules.NotifOptIn)

local RetentionController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local BLOCK_FLAGS = { "Driving", "Dead", "RecentCombat", "Modal" }

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. out:gsub("^,", "")
end

local function blocked(): boolean
	for _, f in ipairs(BLOCK_FLAGS) do
		if HudLayout.GetFlag(f) then
			return true
		end
	end
	return false
end

-- run `fn` once the screen is free (not driving / dead / in combat / a panel open), giving up after 60 s
local function whenFree(fn: () -> ())
	task.spawn(function()
		local left = 60
		while blocked() and left > 0 do
			task.wait(1)
			left -= 1
		end
		if left > 0 then
			fn()
		end
	end)
end

local function screen(name: string, order: number): ScreenGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	local old = pg:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.DisplayOrder = order
	g.Parent = pg
	return g
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

-- ── coins to the cash pill ─────────────────────────────────────────────────────────────────────────────────────────
local function coinBurst(amount: number, headline: string?)
	local g = screen("WE_CoinBurst", 45)
	if g == nil then
		return
	end
	g.IgnoreGuiInset = true
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	local from = Vector2.new(vp.X * 0.5, vp.Y * 0.55)
	local pillPos, pillSize = HudLayout.GetRect("CashPill")
	local to = if pillSize.X > 0 then pillPos + pillSize * 0.5 + Vector2.new(0, 36) else Vector2.new(vp.X * 0.5, 30)
	local big = label(g, (headline and (headline .. "\n") or "") .. "+" .. money(amount), 30, GOLD, Enum.Font.GothamBlack)
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromOffset(from.X, from.Y - 40)
	big.Size = UDim2.fromOffset(320, 84)
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(40, 30, 0)
	st.Parent = big
	TweenService:Create(big, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(from.X, from.Y - 90),
		TextTransparency = 0.15,
	}):Play()
	for i = 1, 12 do
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Size = UDim2.fromOffset(18, 18)
		c.BackgroundColor3 = GOLD
		c.BorderSizePixel = 0
		c.Position = UDim2.fromOffset(from.X + math.random(-70, 70), from.Y + math.random(-30, 30))
		corner(c, 9)
		c.Parent = g
		local t = 0.55 + i * 0.05
		task.delay(0.1, function()
			TweenService:Create(c, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(to.X, to.Y),
				Size = UDim2.fromOffset(10, 10),
			}):Play()
		end)
	end
	pcall(HudLayout.CashFloat, amount)
	task.delay(2.2, function()
		g:Destroy()
	end)
end

-- ── the "Welcome back: +$X while away" card ─────────────────────────────────────────────────────────────────────────────────
local function awayText(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return string.format("%d h %d min", h, m)
	end
	return string.format("%d min", m)
end

local function welcomeBackCard(data: any)
	local cash = math.floor(tonumber(data.Cash) or 0)
	if cash <= 0 then
		return
	end
	local g = screen("WE_WelcomeBackCard", 38)
	if g == nil then
		return
	end
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(360, 206)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.04
	card.Parent = g
	corner(card, 12)
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = card
	local newCard = data.Collect == true -- claude-bud JOB 49 B: "Welcome back! Collect $X" (owner-first; nil = the JOB 29 card)
	local title = label(card, if newCard then "WELCOME BACK!" else "WELCOME BACK", 17, GOLD, Enum.Font.GothamBlack)
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -76, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local body = label(card, if newCard then "Your base earned while you were away" else "While you were away you earned", 15, Color3.fromRGB(215, 205, 170), Enum.Font.GothamBold)
	body.Position = UDim2.fromOffset(14, 44)
	body.Size = UDim2.new(1, -28, 0, 20)
	local amt = label(card, "+" .. money(cash), 32, GOLD, Enum.Font.GothamBlack)
	amt.Position = UDim2.fromOffset(14, 66)
	amt.Size = UDim2.new(1, -28, 0, 38)
	local capH = math.floor(tonumber(data.CapHours) or 8)
	local sub = awayText(tonumber(data.Seconds) or 0) .. (if data.Capped == true then (if newCard then string.format(" (capped at %d h)", capH) else " (8 h max)") else "") .. " · in your ATM"
	if data.Premium == true then
		sub ..= " · Premium +10%"
	end
	local subL = label(card, sub, 15, Color3.fromRGB(190, 190, 180), Enum.Font.GothamMedium)
	subL.Position = UDim2.fromOffset(14, 106)
	subL.Size = UDim2.new(1, -28, 0, 20)
	local x = Instance.new("TextButton")
	x.Position = UDim2.new(1, -56, 0, 6)
	x.Size = UDim2.fromOffset(48, 48)
	x.BackgroundColor3 = Color3.fromRGB(55, 60, 50)
	x.TextColor3 = Color3.new(1, 1, 1)
	x.Font = Enum.Font.GothamBold
	x.TextSize = 16
	x.Text = "X"
	corner(x, 8)
	x.Parent = card
	local collect = Instance.new("TextButton")
	collect.AnchorPoint = Vector2.new(0.5, 1)
	collect.Position = UDim2.new(0.5, 0, 1, -14)
	collect.Size = UDim2.fromOffset(220, 52)
	collect.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
	collect.TextColor3 = Color3.new(1, 1, 1)
	collect.Font = Enum.Font.GothamBlack
	collect.TextSize = 18
	collect.Text = if newCard then "COLLECT " .. money(cash) else "OK"
	corner(collect, 10)
	collect.Parent = card
	-- the money is already in his ATM (server, PendingCash): both buttons only close the card
	local function close()
		if g.Parent then
			g:Destroy()
		end
	end
	collect.Activated:Connect(function()
		if newCard then
			-- claude-bud JOB 49 B: the gold line to HIS ATM (walk up to collect; no travel, no second claim)
			pcall(function()
				local CW: any = require(script.Parent.Parent.Modules.ConsoleWaypoint)
				CW.ShowAtm(tonumber(player:GetAttribute("WE_PlotId")))
			end)
		end
		close()
	end)
	x.Activated:Connect(close)
	task.delay(12, close)
end

-- ── the streak card ────────────────────────────────────────────────────────────────────────────────────────────────
local function streakCard(data: any)
	local g = screen("WE_StreakCard", 36)
	if g == nil then
		return
	end
	local today = math.floor(tonumber(data.Today) or 1)
	local cash = if typeof(data.Cash) == "table" then tonumber(data.Cash[today]) or 0 else 0
	local big = typeof(data.Big) == "table" and data.Big[today] == true
	local card = Instance.new("TextButton") -- tap anywhere to close
	card.AutoButtonColor = false
	card.Text = ""
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 58)
	card.Size = UDim2.fromOffset(420, if data.Boost == true then 150 else 128)
	card.BackgroundColor3 = if big then Color3.fromRGB(40, 32, 10) else PLATE
	card.BackgroundTransparency = 0.06
	card.Parent = g
	corner(card, 12)
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(420, 170)
	fit.Parent = card
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = if big then 3 else 2
	st.Parent = card
	local title = label(card, string.format(if big then "DAY %d! BIG REWARD +%s" else "DAY %d STREAK  +%s", today, money(cash)), if big then 20 else 17, GOLD, Enum.Font.GothamBlack)
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20, 0, 26)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, 36)
	holder.Size = UDim2.new(1, 0, 0, 46)
	holder.Parent = card
	local strip = StreakStrip.Build(holder, data, 52, 46, 15)
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.fromScale(0.5, 0)
	local y = 88
	if data.Boost == true then
		local b = label(card, string.format("+ ARMY BOOST for %d min", math.floor(tonumber(data.BoostMinutes) or 30)), 16, Color3.fromRGB(255, 120, 80), Enum.Font.GothamBlack)
		b.Position = UDim2.fromOffset(10, y)
		b.Size = UDim2.new(1, -20, 0, 22)
		y += 24
	end
	local tomorrow = tonumber(data.TomorrowCash) or 0
	local nextText = StreakStrip.NextText(data, data._ReceivedAt) -- claude-bud JOB 49 A: the real countdown (nil = none)
	local foot = label(card, (if tomorrow > 0 then "Come back tomorrow for " .. money(tomorrow) else "Come back tomorrow!")
		.. (if nextText then " · " .. nextText else ""), 15, Color3.fromRGB(215, 205, 170), Enum.Font.GothamBold)
	foot.Position = UDim2.fromOffset(10, y)
	foot.Size = UDim2.new(1, -20, 0, 22)
	card.Activated:Connect(function()
		g:Destroy()
	end)
	if big then
		coinBurst(cash, nil)
	end
	task.delay(math.clamp(tonumber(data.Seconds) or 6, 3, 12), function()
		if g.Parent then
			g:Destroy()
		end
	end)
end

-- ── the FastStart arrow over his Command Center console ────────────────────────────────────────────────────────────
local arrowGui: BillboardGui? = nil
local arrowAnchor: Part? = nil
local arrowTween: Tween? = nil

local function clearArrow()
	if arrowTween then
		arrowTween:Cancel()
		arrowTween = nil
	end
	if arrowGui then
		arrowGui:Destroy()
		arrowGui = nil
	end
	if arrowAnchor then
		arrowAnchor:Destroy()
		arrowAnchor = nil
	end
end

local function showArrow()
	local pos = player:GetAttribute("WE_ConsolePos_CommandCenter")
	if player:GetAttribute("WE_Onboarding") ~= true or typeof(pos) ~= "Vector3" then
		clearArrow()
		return
	end
	if arrowAnchor and (arrowAnchor.Position - (pos + Vector3.new(0, 7, 0))).Magnitude < 0.5 then
		return
	end
	clearArrow()
	local a = Instance.new("Part")
	a.Name = "WE_FastStartArrow"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.new(0.2, 0.2, 0.2)
	a.Position = pos + Vector3.new(0, 7, 0)
	a.Parent = Workspace.CurrentCamera or Workspace
	local b = Instance.new("BillboardGui")
	b.Name = "Arrow"
	b.Adornee = a
	b.Size = UDim2.fromScale(5, 5) -- studs: shrinks with distance like the world it points at
	b.MaxDistance = 40
	b.LightInfluence = 0
	b.Parent = a
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = GOLD
	t.TextStrokeTransparency = 0.2
	t.Text = "▼"
	t.Parent = b
	arrowAnchor = a
	arrowGui = b
	local tw = TweenService:Create(b, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = UDim2.fromScale(6.5, 6.5),
		StudsOffset = Vector3.new(0, 1, 0),
	})
	tw:Play()
	arrowTween = tw
end

function RetentionController.Init()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind == "StarterPayout" and typeof(data) == "table" then
			clearArrow()
			coinBurst(math.floor(tonumber(data.Cash) or 0), if typeof(data.Text) == "string" then data.Text else nil)
		elseif kind == "WelcomeBack" and typeof(data) == "table" then
			whenFree(function()
				welcomeBackCard(data)
			end)
		elseif kind == "Streak" and typeof(data) == "table" then
			data._ReceivedAt = os.clock() -- claude-bud JOB 49 A: the countdown keeps counting while the card waits
			whenFree(function()
				streakCard(data)
			end)
		elseif kind == "NotifOptIn" then
			whenFree(function()
				NotifOptIn.Ask("auto")
			end)
		end
	end)
	player:GetAttributeChangedSignal("WE_Onboarding"):Connect(showArrow)
	player:GetAttributeChangedSignal("WE_ConsolePos_CommandCenter"):Connect(showArrow)
	showArrow()
end

return RetentionController
