--!strict
--[[
	claude-bud JOB 33 (2026-09-30): the silo panel, the nuke siren and the blast. Client only; it shows what the server
	(NukeService) pushes and sends taps; every rule is checked on the server.
	  * FeaturePush "NukePanel" { Ready, Cap, ChargeLeft, RushCost, CooldownLeft, Targets }: a centred card. It shows
	    the warheads, when the next one is ready, RUSH $X, and one LAUNCH row per target. RequestNuke "rush" / "launch".
	  * FeaturePush "NukeIncoming" { Name, X, Z, Radius, Seconds, Siren }: for every player, a countdown banner at the top
	    ("NUKE INCOMING  Central Plaza  7"), a red ring on the target's ground, and the siren sound when the owner has
	    set one (RebirthZonesConfig.Nuke.SirenSoundId).
	  * FeaturePush "NukeBlast" { X, Z, Radius }: an expanding flash sphere at the target and a short white screen flash
	    for anyone near it.
	Real px (no UIScale on these guis): text >= 15, buttons 48 tall; copy names no keys. Nothing runs between events;
	the countdown ticks at 1 Hz and the effects clean themselves up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] NukeController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local NukeController = {}

local player = Players.LocalPlayer
local RED = Color3.fromRGB(220, 60, 50)
local GOLD = Color3.fromRGB(235, 195, 90)
local PLATE = Color3.fromRGB(22, 22, 20)
local panelGui: ScreenGui? = nil

local function mmss(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. out:gsub("^,", "")
end

local function gui(name: string, order: number): ScreenGui?
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

local function btn(parent: Instance, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(120, 48)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 16
	b.Text = text
	corner(b, 8)
	b.Parent = parent
	return b
end

local function closePanel()
	if panelGui then
		panelGui:Destroy()
		panelGui = nil
	end
end

local function openPanel(d: any)
	local g = gui("WE_NukePanel", 36)
	if g == nil then
		return
	end
	panelGui = g
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(380, 330)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.04
	card.Parent = g
	corner(card, 12)
	local st = Instance.new("UIStroke")
	st.Color = RED
	st.Thickness = 2
	st.Parent = card
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(420, 360)
	fit.Parent = card
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 19
	title.TextColor3 = RED
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "NUCLEAR SILO"
	title.Parent = card
	local x = btn(card, "X", Color3.fromRGB(60, 60, 56))
	x.Size = UDim2.fromOffset(48, 48)
	x.Position = UDim2.new(1, -56, 0, 6)
	x.Activated:Connect(closePanel)
	local ready, cap = tonumber(d.Ready) or 0, tonumber(d.Cap) or 0
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(14, 40)
	status.Size = UDim2.new(1, -28, 0, 40)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 15
	status.TextWrapped = true
	status.TextColor3 = GOLD
	status.TextXAlignment = Enum.TextXAlignment.Left
	local cd = tonumber(d.CooldownLeft) or 0
	status.Text = string.format("Warheads %d/%d%s%s", ready, cap,
		if (tonumber(d.ChargeLeft) or 0) > 0 then "  ·  next in " .. mmss(d.ChargeLeft) else "",
		if cd > 0 then "\nSilo cooling down " .. mmss(cd) else "")
	status.Parent = card
	local y = 86
	if (tonumber(d.RushCost) or 0) > 0 and ready < cap then
		local r = btn(card, "RUSH " .. money(d.RushCost), Color3.fromRGB(120, 100, 40))
		r.Size = UDim2.new(1, -28, 0, 48)
		r.Position = UDim2.fromOffset(14, y)
		r.Activated:Connect(function()
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestNuke, "rush")
		end)
		y += 56
	end
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(14, y)
	list.Size = UDim2.new(1, -28, 1, -(y + 10))
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.ScrollBarThickness = 6
	list.Parent = card
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 6)
	lay.Parent = list
	for _, t in ipairs(d.Targets or {}) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.fromRGB(40, 40, 36)
		row.Size = UDim2.new(1, -8, 0, 52)
		row.Parent = list
		corner(row, 8)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(10, 0)
		name.Size = UDim2.new(1, -140, 1, 0)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = tostring(t.Name)
		name.Parent = row
		local b = btn(row, "LAUNCH", RED)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -2, 0.5, 0)
		b.AutoButtonColor = ready >= 1 and cd <= 0
		b.BackgroundTransparency = if ready >= 1 and cd <= 0 then 0 else 0.6
		local id = tostring(t.Id)
		b.Activated:Connect(function()
			if ready >= 1 and cd <= 0 then
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestNuke, "launch", id)
				closePanel()
			end
		end)
	end
end

-- ── the siren + countdown (everyone) ──────────────────────────────────────────────────────────────────────────────
local function incoming(d: any)
	local secs = math.clamp(math.floor(tonumber(d.Seconds) or 10), 1, 30)
	local R = math.clamp(tonumber(d.Radius) or 150, 10, 400)
	local g = gui("WE_NukeIncoming", 44)
	if g == nil then
		return
	end
	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 70)
	banner.Size = UDim2.fromOffset(420, 56)
	banner.BackgroundColor3 = Color3.fromRGB(60, 10, 10)
	banner.BackgroundTransparency = 0.1
	banner.TextColor3 = Color3.fromRGB(255, 220, 210)
	banner.Font = Enum.Font.GothamBlack
	banner.TextSize = 20
	banner.TextWrapped = true
	banner.Parent = g
	corner(banner, 10)
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(460, 70)
	fit.Parent = banner
	local ring = Instance.new("Part")
	ring.Name = "WE_NukeRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, R * 2, R * 2)
	ring.CFrame = CFrame.new(tonumber(d.X) or 0, 1.2, tonumber(d.Z) or 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = RED
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = 0.65
	ring.Parent = Workspace.CurrentCamera or Workspace
	local sound: Sound? = nil
	if typeof(d.Siren) == "string" and d.Siren ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = if string.find(d.Siren, "rbxassetid://") then d.Siren else "rbxassetid://" .. d.Siren
		s.Looped = true
		s.Volume = 0.6
		s.Parent = g
		s:Play()
		sound = s
	end
	task.spawn(function()
		for left = secs, 1, -1 do
			if not banner.Parent then
				break
			end
			banner.Text = string.format("NUKE INCOMING  %s  %d", tostring(d.Name or ""), left)
			task.wait(1)
		end
		if sound then
			sound:Stop()
		end
		task.delay(1.5, function()
			if g.Parent then
				g:Destroy()
			end
			ring:Destroy()
		end)
	end)
end

local function blast(d: any)
	local R = math.clamp(tonumber(d.Radius) or 150, 10, 400)
	local at = Vector3.new(tonumber(d.X) or 0, 2, tonumber(d.Z) or 0)
	local sphere = Instance.new("Part")
	sphere.Name = "WE_NukeFlash"
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(10, 10, 10)
	sphere.Position = at
	sphere.Color = Color3.fromRGB(255, 236, 200)
	sphere.Material = Enum.Material.SmoothPlastic
	sphere.Transparency = 0.15
	sphere.Parent = Workspace.CurrentCamera or Workspace
	TweenService:Create(sphere, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(R * 2.2, R * 2.2, R * 2.2), Transparency = 1 }):Play()
	task.delay(1.6, function()
		sphere:Destroy()
	end)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - at).Magnitude < R * 3 then
		local g = gui("WE_NukeWhite", 45)
		if g then
			g.IgnoreGuiInset = true
			local f = Instance.new("Frame")
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			f.BackgroundTransparency = 0.1
			f.BorderSizePixel = 0
			f.Parent = g
			TweenService:Create(f, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
			task.delay(1.3, function()
				g:Destroy()
			end)
		end
	end
end

-- ── claude-bud JOB 65: the nuke-raid preview card (FeaturePush "NukeRaidPreview", all numbers from the server) ───
local WHY: { [string]: string } = {
	NoSilo = "Build the Nuclear Silo first",
	NoBase = "That base is empty now",
	Self = "That's your own base",
	Admin = "This base can't be nuked",
	Ally = "That's an ally",
	Protected = "Protected right now",
	CampCooldown = "Base cooldown: wait",
	Shielded = "Shielded after a raid",
	NewPlayer = "New player: protected",
	LowBalance = "Their ATM is almost empty",
	Cooldown = "Silo cooling down",
	NotReady = "No warhead ready",
}

local function clockText(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function raidPreview(d: any)
	local g = gui("WE_NukeRaidPreview", 37)
	if g == nil then
		return
	end
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(420, 268)
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.03
	card.Parent = g
	corner(card, 14)
	local st = Instance.new("UIStroke")
	st.Color = RED
	st.Thickness = 3
	st.Parent = card
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(440, 300)
	fit.Parent = card
	local function line(y: number, h: number, size: number, color: Color3, text: string, font: Enum.Font?)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(18, y)
		l.Size = UDim2.new(1, -36, 0, h)
		l.Font = font or Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Text = text
		l.Parent = card
		return l
	end
	line(12, 30, 24, RED, "NUKE " .. string.upper(tostring(d.Name or "?")) .. "?", Enum.Font.GothamBlack)
	line(46, 24, 20, Color3.fromRGB(220, 220, 210), string.format("Base level %d", tonumber(d.Level) or 0))
	line(74, 34, 28, Color3.fromRGB(120, 255, 140), "+" .. money(tonumber(d.Amount) or 0), Enum.Font.GothamBlack)
	line(110, 22, 18, Color3.fromRGB(200, 196, 180), "Their whole ATM, straight to your cash")
	local ok = d.Ok == true
	local why = if ok then "" else (WHY[tostring(d.Why)] or tostring(d.Why))
	if tostring(d.Why) == "Cooldown" then
		why = "Silo cooling down: " .. clockText(tonumber(d.CooldownLeft) or 0)
	end
	line(136, 24, 18, Color3.fromRGB(255, 200, 80), why)
	local cancel = btn(card, "CANCEL", Color3.fromRGB(70, 72, 66))
	cancel.Name = "Cancel"
	cancel.Size = UDim2.fromOffset(170, 64)
	cancel.Position = UDim2.new(0, 18, 1, -82)
	cancel.TextSize = 20
	cancel.Activated:Connect(function()
		g:Destroy()
	end)
	local launch = btn(card, if ok then "LAUNCH" elseif tostring(d.Why) == "Cooldown" then clockText(tonumber(d.CooldownLeft) or 0) else "LOCKED", if ok then RED else Color3.fromRGB(90, 50, 46))
	launch.Name = "Launch"
	launch.Size = UDim2.fromOffset(190, 64)
	launch.Position = UDim2.new(1, -208, 1, -82)
	launch.TextSize = 22
	launch.AutoButtonColor = ok
	launch.Activated:Connect(function()
		if not ok then
			return
		end
		g:Destroy()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestNuke, "rlaunch", tostring(d.PlotId))
	end)
end

-- the TARGETS card / map ask for the preview of one base (the server answers with NukeRaidPreview)
function NukeController.PreviewRaid(plotId: number)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestNuke, "rpreview", tostring(plotId))
end

function NukeController.Init()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if typeof(data) ~= "table" then
			return
		end
		if kind == "NukePanel" then
			openPanel(data)
		elseif kind == "NukeIncoming" then
			incoming(data)
		elseif kind == "NukeBlast" then
			blast(data)
		elseif kind == "NukeRaidPreview" then
			raidPreview(data) -- claude-bud JOB 65
		end
	end)
end

return NukeController
