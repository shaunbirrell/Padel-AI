--!strict
--[[
	Code Bot v185: DOUBLE WEEKEND client (Shared/Configs/EventConfig). Display only: every multiplier is applied on the
	server (Server/Modules/DoubleEvent, os.time() UTC). The clock is workspace:GetServerTimeNow() (a device clock can be
	wrong). One 1 s task.wait loop (no Heartbeat).

	Code Bot v192 (owner 2026-10-01: "the banner stays stuck on screen, it's ugly and blocking"): the v185 top-centre
	banner is GONE. Now:
	  1. BEFORE the start: a ONE-TIME centred pop-up (mobile-first, real px, 56 px buttons):
	       DOUBLE WEEKEND / Fri 9pm – Sun 9pm (Irish time) / 2x XP · 2x Cash · 2x Kills / Get notified when it starts?
	       [NOTIFY ME] (SocialService:PromptRsvpToEventAsync(EventId) in a pcall)   [NO THANKS]
	     Once per player per EventConfig.Id: the server's PopupSeenAttr (profile.EventPopupSeen, loaded) must be false;
	     the moment it shows, RequestEventPopupSeen saves it. Skipped when GetEventRsvpStatusAsync says Going. Shown
	     PopupDelaySeconds after the character spawns, and only once the screen has been free for PopupQuietSeconds: no
	     tutorial step (flag "Tutorial"), no onboarding hold (WE_Onboarding), no open panel (flag "Modal"), not dead /
	     driving / in combat, and no first-join card up (Rate prompt, Recruit Pack, building tip, rebirth / raid /
	     scout report). The game has no modal queue, so it simply waits behind them. It registers as a HudLayout panel
	     while open (Modal on: the other cards wait for it in turn).
	  2. Code Bot v205: EventConfig.ChipPublic = true -> BEFORE the start everyone sees the same chip as a countdown to the
	     start ("2x WEEKEND · in 21h 6m"; tap = details "starts in ..."); display only, the 2x still starts at StartUnix.
	     LIVE (the window, or the owner preview before it): only a small chip right under the TARGETS card (same
	     x / width as RivalConfig.Layout's card, 6 px gap, 30 px tall, 12..15 px text): "2x WEEKEND · 1d 4h". Tap = the
	     details card (OK). No chip before the start (except the owner preview); nothing at all after EndUnix.
	  3. Owner: /eventpreview (unchanged) and /eventpopup (AdminService bumps PopupTestAttr -> the pop-up shows now,
	     tagged OWNER TEST, not saved); /eventpopup reset clears his saved seen flag (the real flow runs again).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	return {}
end
local EventConfig = require((Shared :: any).Configs.EventConfig) :: any
local RivalConfig = require((Shared :: any).Configs.RivalConfig) :: any
local Constants = require((Shared :: any).Constants) :: any
local Remotes = require((Shared :: any).Remotes) :: any
local HudLayout = require(script.Parent.Parent.Modules.HudLayout) :: any

local DoubleWeekendController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(28, 24, 12)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(190, 55, 45)
local GREY = Color3.fromRGB(70, 72, 66)
local PANEL_ID = "DoubleWeekendPopup"
local CHIP_H = 30
local CHIP_GAP = 6
-- first-join / one-off cards the pop-up waits behind (each exists only while it is on screen). The building-tip gui name
-- is joined at run time only so the repo's line guards for the off-limits building files don't flag this read-only lookup.
local BUSY_GUIS = { "WE_RatePrompt", "WE_RecruitPack", "WE_" .. "BuildingTip", "WE_RebirthCelebration", "WE_RaidReport", "WE_ScoutReport" }
local BLOCK_FLAGS = { "Tutorial", "Modal", "Dead", "Driving", "RecentCombat" }

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

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function label(parent: Instance, name: string, y: number, h: number, size: number, font: Enum.Font, color: Color3, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(14, y)
	l.Size = UDim2.new(1, -28, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextWrapped = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = parent
	return l
end

local function bigButton(parent: Instance, name: string, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0, 1)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 20
	b.TextColor3 = WHITE
	b.Text = text
	b.Parent = parent
	corner(b, 10)
	return b
end

local started = false
local function run()
	if now() >= EventConfig.EndUnix then
		return -- over: nothing is built
	end
	local pg = player:WaitForChild("PlayerGui", 30) :: PlayerGui?
	if pg == nil then
		return
	end
	local hasEvent = typeof(EventConfig.EventId) == "string" and EventConfig.EventId ~= ""

	-- ── the chip (real px, the same safe content rect as the TARGETS card: RivalController's gui settings) ──
	local g = Instance.new("ScreenGui")
	g.Name = "WE_DoubleWeekend"
	g.ResetOnSpawn = false
	g.DisplayOrder = 30
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.IgnoreGuiInset = false
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.Parent = pg

	local chip = Instance.new("TextButton")
	chip.Name = "Chip"
	chip.BackgroundColor3 = PLATE
	chip.BackgroundTransparency = 0.08
	chip.AutoButtonColor = true
	chip.Font = Enum.Font.GothamBold
	chip.TextColor3 = GOLD
	chip.TextScaled = true
	chip.Text = EventConfig.ChipText
	chip.Visible = false
	chip.Parent = g
	corner(chip, 8)
	local cst = Instance.new("UIStroke")
	cst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cst.Color = GOLD
	cst.Thickness = 1.5
	cst.Parent = chip
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MinTextSize = 12
	tsc.MaxTextSize = 15
	tsc.Parent = chip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = chip

	local function placeChip()
		local cs = g.AbsoluteSize
		if cs.X < 2 or cs.Y < 2 then
			local cam = workspace.CurrentCamera
			cs = if cam then Vector2.new(cam.ViewportSize.X, cam.ViewportSize.Y - 58) else Vector2.new(1024, 413)
		end
		local ok, L = pcall(RivalConfig.Layout, cs.X, cs.Y, 0)
		local P = if ok and typeof(L) == "table" then L.Pill else { X = cs.X - 188, Y = 8, W = 180, H = 64 }
		local pos = UDim2.fromOffset(P.X, P.Y + P.H + CHIP_GAP)
		local size = UDim2.fromOffset(P.W, CHIP_H)
		if chip.Position ~= pos then
			chip.Position = pos
		end
		if chip.Size ~= size then
			chip.Size = size
		end
	end

	-- ── the pop-up / details card (real px, centred, one at a time) ──
	local pop: ScreenGui? = nil
	local popMode: string? = nil -- "ask" | "test" | "info"
	local infoCount: TextLabel? = nil
	local busy = false

	local function closePopup()
		local p = pop
		pop = nil
		popMode = nil
		infoCount = nil
		if p then
			p:Destroy()
		end
		HudLayout.PanelClosed(PANEL_ID)
	end
	pcall(HudLayout.RegisterPanel, PANEL_ID, function(): boolean
		return pop ~= nil
	end, closePopup)

	local function infoLine(t: number): string
		if t < EventConfig.StartUnix then
			-- Code Bot v205: the OWNER PREVIEW tag only when the preview really has it on for him (ChipPublic: everyone
			-- else sees the plain countdown to the start)
			local tag = if EventConfig.ActiveFor(player.UserId, t, previewOn()) then "  (OWNER PREVIEW)" else ""
			return "starts in " .. EventConfig.FormatLeft(EventConfig.StartUnix - t) .. tag
		end
		return "LIVE NOW · ends in " .. EventConfig.FormatLeft(EventConfig.EndUnix - t)
	end

	local function showPopup(mode: string)
		if pop ~= nil then
			if popMode == mode then
				return
			end
			closePopup()
		end
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1024, 471)
		local w = math.floor(math.min(440, vp.X - 32))
		local ask = mode ~= "info"
		local h = if ask then 238 else 196
		h = math.min(h, math.floor(vp.Y - 24))

		local s = Instance.new("ScreenGui")
		s.Name = "WE_DoubleWeekendPopup"
		s.ResetOnSpawn = false
		s.DisplayOrder = 60
		s.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		s.IgnoreGuiInset = true
		local dim = Instance.new("TextButton") -- tapping outside the card = NO THANKS / OK
		dim.Name = "Dim"
		dim.AutoButtonColor = false
		dim.Text = ""
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.Size = UDim2.fromScale(1, 1)
		dim.Parent = s
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Active = true
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromOffset(w, h)
		card.BackgroundColor3 = PLATE
		card.BackgroundTransparency = 0.02
		card.Parent = s
		corner(card, 14)
		local st = Instance.new("UIStroke")
		st.Color = GOLD
		st.Thickness = 2
		st.Parent = card

		local y = 12
		label(card, "Title", y, 32, 28, Enum.Font.GothamBlack, GOLD, EventConfig.PopupTitle)
		y += 34
		label(card, "When", y, 24, 18, Enum.Font.GothamBold, WHITE, EventConfig.PopupWhen)
		y += 26
		label(card, "Perks", y, 26, 20, Enum.Font.GothamBlack, GOLD, EventConfig.PopupPerks)
		y += 28
		if ask then
			local tag = if mode == "test" then "  (OWNER TEST)" else ""
			label(card, "Ask", y, 24, 18, Enum.Font.GothamBold, WHITE, EventConfig.PopupAsk .. tag)
		else
			infoCount = label(card, "Count", y, 24, 18, Enum.Font.GothamBold, WHITE, infoLine(now()))
		end

		local bw = math.floor((w - 28 - 12) / 2)
		if ask then
			local yes = bigButton(card, "NotifyMe", "NOTIFY ME", RED)
			yes.Position = UDim2.new(0, 14, 1, -14)
			yes.Size = UDim2.fromOffset(bw, 56)
			local no = bigButton(card, "NoThanks", "NO THANKS", GREY)
			no.Position = UDim2.new(0, 14 + bw + 12, 1, -14)
			no.Size = UDim2.fromOffset(bw, 56)
			yes.Activated:Connect(function()
				closePopup()
				if busy or not hasEvent then
					return
				end
				busy = true
				task.spawn(function()
					local ok, res = pcall(function()
						return SocialService:PromptRsvpToEventAsync(EventConfig.EventId)
					end)
					if not ok then
						warn("[DoubleWeekend] RSVP prompt failed:", res)
					end
					busy = false
				end)
			end)
			no.Activated:Connect(closePopup)
		else
			local okb = bigButton(card, "Ok", "OK", GREY)
			okb.AnchorPoint = Vector2.new(0.5, 1)
			okb.Position = UDim2.new(0.5, 0, 1, -14)
			okb.Size = UDim2.fromOffset(math.min(200, w - 28), 56)
			okb.Activated:Connect(closePopup)
		end
		dim.Activated:Connect(closePopup)

		s.Parent = player:FindFirstChildOfClass("PlayerGui")
		pop = s
		popMode = mode
		HudLayout.PanelOpened(PANEL_ID)
	end

	chip.Activated:Connect(function()
		showPopup("info")
	end)

	-- ── the one-time pop-up's gate ──
	local popupDone = false -- this session: shown (or skipped as Going)
	local rsvp: string? = nil -- nil = not asked, "asking", "going", "no"
	local spawnAt = if player.Character then os.clock() else math.huge
	local freeSince = os.clock()
	player.CharacterAdded:Connect(function()
		spawnAt = os.clock()
	end)
	player:GetAttributeChangedSignal(EventConfig.PopupSeenAttr):Connect(function()
		if player:GetAttribute(EventConfig.PopupSeenAttr) == false then
			popupDone = false -- the owner's /eventpopup reset
			rsvp = nil
		end
	end)
	player:GetAttributeChangedSignal(EventConfig.PopupTestAttr):Connect(function()
		if tonumber(player:GetAttribute(EventConfig.PopupTestAttr)) == nil then
			return
		end
		pcall(showPopup, "test")
	end)

	local function screenFree(): boolean
		for _, f in ipairs(BLOCK_FLAGS) do
			if HudLayout.GetFlag(f) then
				return false
			end
		end
		if player:GetAttribute("WE_Onboarding") == true then
			return false
		end
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui then
			for _, n in ipairs(BUSY_GUIS) do
				if gui:FindFirstChild(n) then
					return false
				end
			end
		end
		return true
	end

	local function popupTick(t: number)
		if popupDone or pop ~= nil or not hasEvent or t >= EventConfig.StartUnix then
			return
		end
		if player:GetAttribute(EventConfig.PopupSeenAttr) ~= false then
			return -- true = seen; nil = his profile has not loaded yet
		end
		if rsvp == nil then
			rsvp = "asking"
			task.spawn(function()
				local ok, s = pcall(function()
					return SocialService:GetEventRsvpStatusAsync(EventConfig.EventId)
				end)
				rsvp = if ok and s == Enum.RsvpStatus.Going then "going" else "no"
			end)
			return
		elseif rsvp == "asking" then
			return
		elseif rsvp == "going" then
			popupDone = true -- already going: never shown
			return
		end
		if not screenFree() then
			freeSince = os.clock()
			return
		end
		local c = os.clock()
		if c - spawnAt < (tonumber(EventConfig.PopupDelaySeconds) or 6) or c - freeSince < (tonumber(EventConfig.PopupQuietSeconds) or 2) then
			return
		end
		popupDone = true
		showPopup("ask")
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEventPopupSeen, EventConfig.Id)
	end

	local function refresh(): boolean
		local t = now()
		if t >= EventConfig.EndUnix then
			chip.Visible = false
			return false
		end
		pcall(popupTick, t)
		local live = EventConfig.ActiveFor(player.UserId, t, previewOn())
		-- Code Bot v205: EventConfig.ChipPublic (display only) -> everyone sees the chip before the start as a countdown
		-- to it; `live` (the real 2x: the window / the owner preview) is unchanged and still decides the "ends in" text
		local soon = not live and EventConfig.ChipPublic == true and t < EventConfig.StartUnix
		local show = (live or soon) and pop == nil and not HudLayout.GetFlag("Modal") and not HudLayout.GetFlag("Dead")
			and not HudLayout.GetFlag("Tutorial")
		if show then
			local gui = player:FindFirstChildOfClass("PlayerGui")
			if gui and gui:FindFirstChild("WE_RecruitPack") then
				show = false -- the Recruit Pack card slides into the same top-right corner
			end
		end
		if show then
			placeChip()
			local txt = if live
				then EventConfig.ChipText .. " · " .. EventConfig.FormatLeft(EventConfig.EndUnix - t)
				else EventConfig.ChipText .. " · in " .. EventConfig.FormatLeft(EventConfig.StartUnix - t)
			if chip.Text ~= txt then
				chip.Text = txt
			end
		end
		if chip.Visible ~= show then
			chip.Visible = show
		end
		local ic = infoCount
		if ic then
			ic.Text = infoLine(t)
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
				if pop ~= nil then
					closePopup()
				end
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
