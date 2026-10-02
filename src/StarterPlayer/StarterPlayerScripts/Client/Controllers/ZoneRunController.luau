--!strict
--[[ claude-bud JOB 69 B: the zone-run how-to card + the run tracker (the server decides everything).

	  * FeaturePush "ZoneRunIntro" { Zone, Title, Goal, Steps, Reward, Seconds, CooldownLeft, Compact, InProgress }: a card
	    in the safe area (centred, clear of the thumbstick and the fire / jump buttons): the title, a one-line goal, three
	    numbered steps (the full card until the first clear, then compact), the reward and the time, big START / CANCEL.
	    START -> RequestZoneRun("start", zone) (or the caller's OnStart: the activity / job card, JOB 69 C); CANCEL closes it. A run already going: "<TITLE> in progress · m:ss" + CANCEL.
	  * FeaturePush "ZoneRun" { Title, Step, Of, Label, Pos, Left } during a run: a top progress pill "DRILL COURSE 2/4 ·
	    0:23" with a CANCEL chip (RequestZoneRun("cancel")) and the ONE objective marker arrow on the current pad;
	    { Done = true } clears both. One 1 Hz countdown while a run is on (no per-frame work). ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)

local ZoneRunController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local GREEN = Color3.fromRGB(70, 150, 70)
local GREY = Color3.fromRGB(70, 72, 66)

local Remotes: any = nil
local Constants: any = nil
local Marker: any = nil
local pill: ScreenGui? = nil
local runLeft = 0
local runTitle = ""
local runStep, runOf = 0, 0
local ticking = false

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

-- the pill text (pure; the tests)
function ZoneRunController.PillText(title: string, step: number, of: number, left: number): string
	return string.format("%s %d/%d · %s", string.upper(title), step, of, clock(left))
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

local function label(parent: Instance, text: string, y: number, h: number, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(18, y)
	l.Size = UDim2.new(1, -36, 0, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3, x: UDim, w: number): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(x.Scale, x.Offset, 1, -16)
	b.Size = UDim2.fromOffset(w, 64)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 22
	b.Text = text
	b.Parent = parent
	corner(b, 12)
	return b
end

local function send(action: string, zone: string?)
	if Remotes and Constants then
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestZoneRun, action, zone or "")
	end
end

-- the card's real-pixel layout on a W x H screen (pure; the layout sim): scaled by height, right of the thumbstick zone
-- (CLAUDE.md: nothing tappable in the left 40 % x lower 2/3), above the jump / fire corner. Returns the scale, the card
-- centre and the two button rects { x0, y0, x1, y1 } (START, CANCEL) in screen pixels.
function ZoneRunController.CardLayout(W: number, H: number, compact: boolean): (number, number, number, { number }, { number })
	local scale = math.clamp(H / 520, 0.6, 1)
	local cw, ch = 440 * scale, (if compact then 210 else 330) * scale
	local cx = math.max(W * 0.4 + cw / 2 + 8, W * 0.62)
	cx = math.min(cx, W - cw / 2 - 130) -- the card's right edge stays left of the jump / fire column (Roblox jump ~70 px + 16 px clear)
	local cy = math.min(H * 0.48, H - ch / 2 - 8)
	local x0, y1 = cx - cw / 2, cy + ch / 2
	local bh, pad = 64 * scale, 16 * scale
	local cancel = { x0 + pad, y1 - pad - bh, x0 + pad + 180 * scale, y1 - pad }
	local start = { x0 + cw - pad - 200 * scale, y1 - pad - bh, x0 + cw - pad, y1 - pad }
	return scale, cx, cy, start, cancel
end

-- the how-to card
function ZoneRunController.ShowIntro(d: any)
	local g = gui("WE_ZoneRunIntro", 39)
	if g == nil then
		return
	end
	local compact = d.Compact == true
	local steps: { any } = if typeof(d.Steps) == "table" then d.Steps else {}
	local h = if compact then 210 else 330
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromOffset(440, h)
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1024, 471)
	local scale, cx, cy = ZoneRunController.CardLayout(vp.X, vp.Y, compact)
	card.Position = UDim2.fromOffset(cx, cy)
	g.IgnoreGuiInset = true -- the layout is in real screen pixels
	local us = Instance.new("UIScale")
	us.Scale = scale
	us.Parent = card
	card.BackgroundColor3 = PLATE
	card.BackgroundTransparency = 0.03
	card.Parent = g
	corner(card, 14)
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = card
	label(card, string.upper(tostring(d.Title or "")), 12, 30, 24, GOLD, Enum.Font.GothamBlack)
	label(card, tostring(d.Goal or ""), 44, 26, 18, Color3.new(1, 1, 1))
	local y = 74
	if not compact then
		for i, sTxt in ipairs(steps) do
			if i <= 3 then
				label(card, string.format("%d.  %s", i, tostring(sTxt)), y, 26, 18, Color3.fromRGB(215, 210, 190))
				y += 28
			end
		end
		y += 4
	end
	local secs = tonumber(d.Seconds) or 0
	label(card, "Reward: " .. tostring(d.Reward or "") .. (if secs > 0 then string.format("   ·   Time: %d s", secs) else ""), y, 26, 17, Color3.fromRGB(150, 230, 140))
	y += 28
	local busy = typeof(d.InProgress) == "table"
	local cd = tonumber(d.CooldownLeft) or 0
	if busy then
		label(card, string.format("%s in progress · %s left", tostring(d.InProgress.Title), clock(tonumber(d.InProgress.Left) or 0)), y, 26, 17, Color3.fromRGB(255, 200, 80))
	elseif cd > 0 then
		label(card, "Ready again in " .. clock(cd), y, 26, 17, Color3.fromRGB(255, 200, 80))
	end
	local cancel = button(card, "CANCEL", GREY, UDim.new(0, 16), 180)
	cancel.Name = "Cancel"
	cancel.Activated:Connect(function()
		if busy then
			send("cancel", tostring(d.Zone))
		end
		g:Destroy()
	end)
	local ok = not busy and cd <= 0
	local start = button(card, if ok then tostring(d.StartText or "START") elseif busy then "RUNNING" else clock(cd), if ok then GREEN else Color3.fromRGB(60, 70, 60), UDim.new(1, -216), 200)
	start.Name = "Start"
	start.AutoButtonColor = ok
	start.Activated:Connect(function()
		if ok then
			if type(d.OnStart) == "function" then
				task.spawn(d.OnStart) -- claude-bud JOB 69 C: the caller's own start path (the server still decides)
			else
				send("start", tostring(d.Zone))
			end
			g:Destroy()
		end
	end)
end

local function setPill()
	local g = pill
	if g == nil then
		return
	end
	local t = g:FindFirstChild("Pill", true)
	if t and t:IsA("TextLabel") then
		t.Text = ZoneRunController.PillText(runTitle, runStep, runOf, runLeft)
	end
end

local function clearRun()
	runLeft = 0
	if pill then
		pill:Destroy()
		pill = nil
	end
	if Marker and Marker.Clear then
		pcall(Marker.Clear)
	end
end

function ZoneRunController.OnRun(d: any)
	if d.Done then
		clearRun()
		return
	end
	runTitle = tostring(d.Title or "RUN")
	runStep = tonumber(d.Step) or 0
	runOf = tonumber(d.Of) or 0
	runLeft = tonumber(d.Left) or 0
	if pill == nil then
		local g = gui("WE_ZoneRunPill", 37)
		if g == nil then
			return
		end
		pill = g
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.new(0.5, 0, 0, 58)
		f.Size = UDim2.fromOffset(420, 52)
		f.BackgroundColor3 = PLATE
		f.BackgroundTransparency = 0.1
		f.Parent = g
		corner(f, 26)
		local t = Instance.new("TextLabel")
		t.Name = "Pill"
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(18, 0)
		t.Size = UDim2.new(1, -130, 1, 0)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = 20
		t.TextColor3 = GOLD
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Parent = f
		local c = Instance.new("TextButton")
		c.Name = "CancelChip"
		c.AnchorPoint = Vector2.new(1, 0.5)
		c.Position = UDim2.new(1, -6, 0.5, 0)
		c.Size = UDim2.fromOffset(104, 44)
		c.BackgroundColor3 = GREY
		c.TextColor3 = Color3.new(1, 1, 1)
		c.Font = Enum.Font.GothamBold
		c.TextSize = 18
		c.Text = "CANCEL"
		c.Parent = f
		corner(c, 22)
		c.Activated:Connect(function()
			send("cancel", nil)
		end)
	end
	setPill()
	if typeof(d.Pos) == "Vector3" and Marker and Marker.ShowWith then
		local p: Vector3 = d.Pos
		pcall(Marker.ShowWith, { Short = tostring(d.Label or "NEXT"), X = p.X, Y = p.Y, Z = p.Z }, { ArriveStuds = 4, TimeoutSeconds = 120 })
	end
	if not ticking then
		ticking = true
		task.spawn(function()
			while runLeft > 0 and pill ~= nil do
				task.wait(1)
				runLeft -= 1
				setPill()
			end
			ticking = false
		end)
	end
end

function ZoneRunController.Init()
	if Shared == nil then
		return
	end
	local okR, R = pcall(function(): any
		return (require :: any)((Shared :: any).Remotes)
	end)
	local okC, C = pcall(function(): any
		return (require :: any)((Shared :: any).Constants)
	end)
	local okM, M = pcall(function(): any
		return require(script.Parent.Parent.Modules.ObjectiveMarker)
	end)
	if not okR or not okC then
		return
	end
	Remotes, Constants = R, C
	Marker = if okM then M else nil
	R.BindEvent(C.RemoteNames.FeaturePush, function(kind: any, data: any)
		if typeof(data) ~= "table" then
			return
		end
		if kind == "ZoneRunIntro" then
			ZoneRunController.ShowIntro(data)
		elseif kind == "ZoneRun" then
			ZoneRunController.OnRun(data)
		end
	end)
end

return ZoneRunController
