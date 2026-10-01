--!strict
--[[
	Code Bot v185: DOUBLE WEEKEND banner (Shared/Configs/EventConfig). Display only: every multiplier is applied on the
	server (Server/Modules/DoubleEvent, os.time() UTC). One card in the HUD top stack (HudLayout.RegisterTopStack, order
	12: under a missile Alert, above every other top item; the stack keeps it clear of the topbar, hotbar, TARGETS and the
	trackers). Mobile-first: 440 v wide at most (TopStackMaxWidthV), text >= 20 v (>= 14 real px on phones).
	  "DOUBLE WEEKEND · 2x XP · 2x CASH · 2x KILLS" + "ends in 1d 4h" while it is live for him (the window, or the
	  owner's preview before it); "starts in 5h 12m" from BannerLeadSeconds before the start; hidden after the end.
	  NOTIFY ME (only before the start, only with a Creator Hub EventId): SocialService:PromptRsvpToEventAsync in a
	  pcall; "NOTIFIED ✓" once GetEventRsvpStatusAsync / the prompt says Going.
	One 1 s task.wait loop (no Heartbeat). The clock is workspace:GetServerTimeNow() (the device clock can be wrong).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	return {}
end
local EventConfig = require((Shared :: any).Configs.EventConfig) :: any
local HudLayout = require(script.Parent.Parent.Modules.HudLayout) :: any

local DoubleWeekendController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(40, 32, 12)
local STACK = "DoubleWeekend"
local ORDER = 12

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and typeof(t) == "number" then math.floor(t) else os.time()
end

local function previewOn(): boolean
	local v = ReplicatedStorage:GetAttribute(EventConfig.PreviewAttr)
	if v == nil then
		return EventConfig.OwnerFirst == true
	end
	return v == true
end

local started = false
local function run()
	if now() >= EventConfig.EndUnix then
		return -- over: nothing is built
	end
	local pg = player:WaitForChild("PlayerGui", 30)
	if pg == nil then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_DoubleWeekend"
	g.ResetOnSpawn = false
	g.DisplayOrder = 33
	g.Parent = pg
	pcall(HudLayout.ApplyScreen, g)

	local maxW = 440
	pcall(function()
		maxW = math.min(440, math.floor(HudLayout.TopStackMaxWidthV()))
	end)
	local f = Instance.new("Frame")
	f.Name = "Banner"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 80)
	f.Size = UDim2.fromOffset(maxW, 82)
	f.BackgroundColor3 = PLATE
	f.BackgroundTransparency = 0.12
	f.Visible = false
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = f

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 4)
	title.Size = UDim2.new(1, -20, 0, 48)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.TextWrapped = true
	title.TextColor3 = GOLD
	title.Text = EventConfig.BannerText
	title.Parent = f

	local count = Instance.new("TextLabel")
	count.BackgroundTransparency = 1
	count.Position = UDim2.fromOffset(10, 52)
	count.Size = UDim2.new(1, -20, 0, 26)
	count.Font = Enum.Font.GothamBold
	count.TextSize = 22
	count.TextColor3 = Color3.new(1, 1, 1)
	count.Text = ""
	count.Parent = f

	local hasEvent = typeof(EventConfig.EventId) == "string" and EventConfig.EventId ~= ""
	local btn = Instance.new("TextButton")
	btn.Name = "NotifyMe"
	btn.AnchorPoint = Vector2.new(0.5, 0)
	btn.Position = UDim2.new(0.5, 0, 0, 82)
	btn.Size = UDim2.new(0, math.min(260, maxW - 20), 0, 56) -- 56 v = ~39 real px: a thumb-sized tap target
	btn.BackgroundColor3 = Color3.fromRGB(170, 55, 45)
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 24
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "NOTIFY ME"
	btn.AutoButtonColor = true
	btn.Visible = false
	btn.Parent = f
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 10)
	bc.Parent = btn

	local notified = false
	local busy = false
	local statusAsked = false
	local function paintButton()
		if notified then
			btn.Text = "NOTIFIED ✓"
			btn.BackgroundColor3 = Color3.fromRGB(46, 120, 60)
		else
			btn.Text = "NOTIFY ME"
			btn.BackgroundColor3 = Color3.fromRGB(170, 55, 45)
		end
	end
	local function askStatus()
		if statusAsked or not hasEvent then
			return
		end
		statusAsked = true
		task.spawn(function()
			local ok, s = pcall(function()
				return SocialService:GetEventRsvpStatusAsync(EventConfig.EventId)
			end)
			if ok and s == Enum.RsvpStatus.Going then
				notified = true
				paintButton()
			end
		end)
	end
	btn.Activated:Connect(function()
		if busy or not hasEvent or now() >= EventConfig.StartUnix then
			return
		end
		busy = true
		task.spawn(function()
			local ok, s = pcall(function()
				return SocialService:PromptRsvpToEventAsync(EventConfig.EventId)
			end)
			if ok then
				notified = s == Enum.RsvpStatus.Going
				paintButton()
			else
				warn("[DoubleWeekend] RSVP prompt failed:", s)
			end
			busy = false
		end)
	end)

	pcall(HudLayout.RegisterTopStack, STACK, f, ORDER, { Space = "Hud" })

	local function refresh(): boolean
		local t = now()
		if t >= EventConfig.EndUnix then
			f.Visible = false
			return false
		end
		local state = EventConfig.BannerState(player.UserId, t, previewOn())
		if state == "live" then
			local tag = if t < EventConfig.StartUnix then "  (OWNER PREVIEW)" else ""
			count.Text = "ends in " .. EventConfig.FormatLeft(EventConfig.EndUnix - t) .. tag
		elseif state == "soon" then
			count.Text = "starts in " .. EventConfig.FormatLeft(EventConfig.StartUnix - t)
		end
		local showBtn = state ~= nil and hasEvent and t < EventConfig.StartUnix
		if showBtn then
			askStatus()
		end
		if btn.Visible ~= showBtn then
			btn.Visible = showBtn
		end
		local h = if showBtn then 146 else 82
		if f.Size.Y.Offset ~= h then
			f.Size = UDim2.fromOffset(maxW, h)
		end
		local vis = state ~= nil
		if f.Visible ~= vis then
			f.Visible = vis
		end
		return true
	end
	ReplicatedStorage:GetAttributeChangedSignal(EventConfig.PreviewAttr):Connect(function()
		pcall(refresh)
	end)
	task.spawn(function()
		while g.Parent do
			local ok, keep = pcall(refresh)
			if ok and keep == false then
				pcall(HudLayout.UnregisterTopStack, STACK)
				g:Destroy()
				return
			end
			task.wait(1)
		end
	end)
end

function DoubleWeekendController.Init()
	if started then
		return
	end
	started = true
	task.spawn(run) -- never holds up the Bootstrap
end

return DoubleWeekendController
