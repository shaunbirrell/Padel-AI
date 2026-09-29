--!strict
--[[
	claude-bud JOB 14 (2026-09-29): client side of game feel (Shared/Configs/GameFeelConfig; server: GameFeelService).
	Display and sound only. Listens to FeaturePush:
	  "KillFeed"   { K, V, W, Mine, Me } → a short line in the HUD top stack (at most KillFeed.Lines, Seconds each)
	  "VehDmg"     { D, P }              → a red number over your damaged vehicle + a metal hit sound
	  "RaidReport" { Lost, By, Breached } → ONE banner: "YOU WERE RAIDED" (red) or "BASE DEFENDED" (green) + sound
	Sound pass: GameFeelClient.Sound(cue, at?) plays GameFeelConfig.Sounds[cue] for a player the pass is live for
	(other modules call it for their once-silent actions), and it keeps every volume inside its bus band
	(SoundConfig.Mix.BandsLive). No per-frame work; everything it makes is destroyed within seconds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameFeelClient = {}

local G: any = nil
local lp = Players.LocalPlayer

local function live(feature: string): boolean
	return G ~= nil and G.LiveFor(feature, lp.UserId)
end

local function hud(): any?
	local ok, H = pcall(require, script.Parent.HudLayout)
	return if ok and type(H) == "table" then H else nil
end

--[[ Play the sound for one of GameFeelConfig.Sounds' cues (a no-op when the sound pass is off). ]]
function GameFeelClient.Sound(cue: string, at: any?)
	if G == nil then
		local okS, Shared = pcall(function()
			return ReplicatedStorage:WaitForChild("Shared", 5)
		end)
		if not okS or Shared == nil then
			return
		end
		G = require((Shared :: any).Configs.GameFeelConfig) :: any
	end
	if not live("SoundPass") then
		return
	end
	local key = G.Sounds[cue]
	if typeof(key) ~= "string" then
		return
	end
	local ok, Audio = pcall(require, script.Parent.AudioController)
	if ok and type(Audio) == "table" and (Audio :: any).Play then
		pcall((Audio :: any).Play, key, at)
	end
end

local function fmtCash(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- ── kill feed ──
local feedFrame: Frame? = nil
local feedSerial = 0

local function ensureFeed(): Frame?
	if feedFrame and feedFrame.Parent then
		return feedFrame
	end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	local K = G.KillFeed
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_KillFeed"
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Name = "Feed"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 0)
	frame.Size = UDim2.fromOffset(K.Width, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame
	frame.Parent = gui
	gui.Parent = pg
	local H = hud()
	if H then
		pcall(H.ApplyScreen, gui)
		pcall(H.RegisterTopStack, "KillFeed", frame, K.Order)
	end
	feedFrame = frame
	return frame
end

local function refreshFeed(frame: Frame)
	local n = 0
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("TextLabel") then
			n += 1
		end
	end
	frame.Visible = n > 0
	local H = hud()
	if H and H.RelayoutTopStack then
		pcall(H.RelayoutTopStack)
	end
end

local function onKillFeed(data: any)
	if typeof(data) ~= "table" or not live("KillFeed") then
		return
	end
	local frame = ensureFeed()
	if frame == nil then
		return
	end
	local K = G.KillFeed
	-- keep at most Lines: drop the oldest
	local lines: { TextLabel } = {}
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(lines, c)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #lines >= K.Lines do
		local oldest = table.remove(lines, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	feedSerial += 1
	local l = Instance.new("TextLabel")
	l.LayoutOrder = feedSerial
	l.Size = UDim2.new(1, 0, 0, K.TextSize + 8)
	l.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
	l.BackgroundTransparency = 0.35
	l.Font = Enum.Font.GothamBold
	l.TextSize = K.TextSize
	l.TextTruncate = Enum.TextTruncate.AtEnd
	local weapon = if typeof(data.W) == "string" and data.W ~= "" then "  (" .. data.W .. ")" else ""
	l.Text = string.format("%s  >  %s%s", tostring(data.K or "?"), tostring(data.V or "?"), weapon)
	l.TextColor3 = if data.Mine == true
		then Color3.fromRGB(255, 205, 60)
		elseif data.Me == true then Color3.fromRGB(255, 110, 100)
		else Color3.fromRGB(235, 235, 235)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = l
	l.Parent = frame
	refreshFeed(frame)
	if data.Me == true then
		GameFeelClient.Sound("KillFeedVictim")
	end
	task.delay(K.Seconds, function()
		l:Destroy()
		if frame.Parent then
			refreshFeed(frame)
		end
	end)
end

-- ── vehicle damage numbers (your own vehicle) ──
local liveNumbers = 0

local function onVehDmg(data: any)
	if typeof(data) ~= "table" or typeof(data.P) ~= "Vector3" or not live("VehicleNumbers") then
		return
	end
	local V = G.VehicleNumbers
	local dmg = tonumber(data.D) or 0
	if dmg < 1 then
		return
	end
	GameFeelClient.Sound("VehicleHurt", data.P)
	if liveNumbers >= V.Max then
		return
	end
	liveNumbers += 1
	local att = Instance.new("Attachment")
	att.WorldPosition = data.P + Vector3.new((math.random() - 0.5) * 2, 3, 0)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 32)
	bb.MaxDistance = 40 -- CLAUDE.md world labels: MaxDistance <= 40, never AlwaysOnTop
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextSize = V.TextSize
	t.TextColor3 = Color3.fromRGB(255, 80, 70)
	t.TextStrokeTransparency = 0.3
	t.Text = "-" .. tostring(math.floor(dmg))
	t.Parent = bb
	bb.Parent = att
	att.Parent = Workspace.Terrain
	bb.Adornee = att
	TweenService:Create(bb, TweenInfo.new(V.Seconds), { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(V.Seconds), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(V.Seconds, function()
		liveNumbers -= 1
		att:Destroy()
	end)
end

-- ── raid report ──
local function onRaidReport(data: any)
	if typeof(data) ~= "table" or not live("RaidReport") then
		return
	end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	local R = G.RaidReport
	local lost = tonumber(data.Lost) or 0
	local by = if typeof(data.By) == "string" and data.By ~= "" then data.By else nil
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_RaidReport"
	gui.ResetOnSpawn = false
	local b = Instance.new("TextLabel")
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, 0, 0, 0)
	b.Size = UDim2.fromOffset(400, 76)
	b.BackgroundTransparency = 0.1
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 26
	b.TextWrapped = true
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	if lost > 0 then
		b.BackgroundColor3 = Color3.fromRGB(60, 16, 14)
		b.TextColor3 = Color3.fromRGB(255, 120, 110)
		stroke.Color = Color3.fromRGB(220, 60, 50)
		b.Text = string.format("YOU WERE RAIDED\n-$%s%s", fmtCash(lost), if by then " · " .. by else "")
	else
		b.BackgroundColor3 = Color3.fromRGB(14, 44, 22)
		b.TextColor3 = Color3.fromRGB(130, 240, 150)
		stroke.Color = Color3.fromRGB(60, 190, 90)
		b.Text = "BASE DEFENDED\n" .. (if data.Breached == true then "Gate down · cash safe" else "Attack held off")
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = b
	b.Parent = gui
	gui.Parent = pg
	local H = hud()
	if H then
		pcall(H.ApplyScreen, gui)
		pcall(H.RegisterTopStack, "RaidReport", b, R.Order)
	end
	GameFeelClient.Sound(if lost > 0 then "RaidLost" else "RaidDefended")
	task.delay(R.BannerSeconds, function()
		if H then
			pcall(H.UnregisterTopStack, "RaidReport")
		end
		gui:Destroy()
	end)
end

function GameFeelClient.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	G = require((Shared :: any).Configs.GameFeelConfig) :: any
	if live("SoundPass") then
		local SoundConfig = require((Shared :: any).Configs.SoundConfig) :: any
		SoundConfig.Mix.BandsLive = true -- AudioController keeps each volume inside its bus band
	end
	local Remotes = require((Shared :: any).Remotes) :: any
	local Constants = require((Shared :: any).Constants) :: any
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind == "KillFeed" then
			onKillFeed(data)
		elseif kind == "VehDmg" then
			onVehDmg(data)
		elseif kind == "RaidReport" then
			onRaidReport(data)
		end
	end)
end

return GameFeelClient
