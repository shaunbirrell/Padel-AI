--!strict
--[[
	claude-bud JOB 41 part C (2026-10-01): the TARGETS pill + list (RivalConfig). The server picks the targets
	(RivalService, FeaturePush "RivalTargets" { Rows = { PlotId, Name, Army, Verdict, Loot (a bucket), Dist } }); this
	only draws them.
	  * The pill: top-right under the top-bar pills (real px; clear of the left-rail thumbstick band, the fire / jump
	    controls and the top bar), "TARGETS" + a count badge, 48 px tall. Shown only while the server lists >= 1 target
	    (the server lists nothing during the Guided hold or without soldiers: the JOB 38 verdict says NoArmy).
	  * The list (one panel at a time: HudLayout.RegisterPanel): one row per target with the name, "Army 12",
	    "Loot $10k+" and the verdict chip; SEND ARMY = the same JOB 38 RequestArmySend remote the map uses (the server
	    re-checks everything; the army WALKS: ArmyPlan), VIEW = the world map on that base card (tap-to-pin, no travel).
	No exact loot number ever reaches this client.
	Code Bot v163 (Shaun 2026-10-01: "I can't figure out where we can see the rival players for raids"): the pill was
	hidden whenever the server listed 0 targets, which is nearly always for the owner (his server rarely has another
	player past new-player protection, with $10k+ in the ATM, beatable by his army). The pill now ALWAYS shows for
	everyone RivalConfig is live for; with no targets it is dimmed with no badge, and the list opens on an empty state
	(RivalConfig.EmptyText + the server's one-line reason, RivalTargets.Why). It steps aside (hidden) only while a
	full-screen panel is open (HudLayout "Modal", except its own list), while dead, and while the Recruit Pack card
	(WE_RecruitPack, the same top-right corner) is on screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] RivalController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local RivalConfig = require(Shared.Configs.RivalConfig)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local RivalController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local CHIP = { easy = Color3.fromRGB(70, 160, 80), even = Color3.fromRGB(150, 130, 60), risky = Color3.fromRGB(170, 70, 60) }
local PANEL_ID = "RivalTargets"

local pill: TextButton? = nil
local badge: TextLabel? = nil
local panel: Frame? = nil
local rows: { any } = {}
local why: string? = nil -- v163: the server's one-line reason when the list is empty
local open = false
local emptyLabel: TextLabel? = nil

local updatePillLater: () -> () = function() end -- v163: set once updatePill exists (setOpen is defined first)

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function setOpen(on: boolean)
	open = on
	local p = panel
	if p then
		p.Visible = on
	end
	if on then
		HudLayout.PanelOpened(PANEL_ID)
	else
		HudLayout.PanelClosed(PANEL_ID)
	end
	updatePillLater()
end

local function button(parent: Instance, text: string, color: Color3, x: UDim, w: number): TextButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(x.Scale, x.Offset, 0, 30)
	b.Size = UDim2.fromOffset(w, 48)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.Text = text
	corner(b, 8)
	b.Parent = parent
	return b
end

local function rebuildList()
	local p = panel
	if p == nil then
		return
	end
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("Frame") and c.Name == "Row" then
			c:Destroy()
		end
	end
	for i, r in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Name = "Row"
		row.Position = UDim2.fromOffset(8, 40 + (i - 1) * 86)
		row.Size = UDim2.new(1, -16, 0, 82)
		row.BackgroundColor3 = Color3.fromRGB(34, 37, 30)
		row.Parent = p
		corner(row, 8)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(8, 4)
		name.Size = UDim2.new(1, -86, 0, 22)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Text = string.format("%s  ·  Army %d  ·  Loot %s", tostring(r.Name), math.floor(tonumber(r.Army) or 0), tostring(r.Loot))
		name.Parent = row
		local chip = Instance.new("TextLabel")
		chip.Position = UDim2.new(1, -74, 0, 4)
		chip.Size = UDim2.fromOffset(66, 22)
		chip.BackgroundColor3 = CHIP[tostring(r.Verdict)] or CHIP.even
		chip.TextColor3 = Color3.new(1, 1, 1)
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 14
		chip.Text = string.upper(tostring(r.Verdict))
		chip.Parent = row
		corner(chip, 6)
		local plotId = tonumber(r.PlotId) or 0
		local send = button(row, "SEND ARMY", Color3.fromRGB(150, 60, 50), UDim.new(0, 8), 150)
		send.Activated:Connect(function()
			-- the SAME JOB 38 send path as the map's SEND ARMY (the server re-checks every fairness rule)
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestArmySend, plotId)
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRivalAction, "send", plotId)
			setOpen(false)
		end)
		local view = button(row, "VIEW", Color3.fromRGB(55, 60, 50), UDim.new(1, -118), 110)
		view.Activated:Connect(function()
			setOpen(false)
			local okM, MC = pcall(function(): any
				return require(script.Parent.MapController)
			end)
			if okM and MC and MC.OpenBase then
				MC.OpenBase(plotId) -- the map on that base card: tap-to-pin only, nothing moves the player
			end
		end)
	end
	local e = emptyLabel
	if e then
		e.Visible = #rows == 0
		e.Text = if why and why ~= "" then RivalConfig.EmptyText .. "\n" .. why else RivalConfig.EmptyText
	end
	p.Size = UDim2.fromOffset(330, if #rows == 0 then 40 + RivalConfig.EmptyHeight else 44 + #rows * 86)
end

-- v163: the pill is always there for a live player; it only steps aside for a full-screen panel (not its own list),
-- death, and the Recruit Pack card that slides into the same corner
local function recruitCardUp(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	return pg ~= nil and pg:FindFirstChild("WE_RecruitPack") ~= nil
end

local function updatePill()
	local pl = pill
	if pl == nil then
		return
	end
	local modalOther = HudLayout.GetFlag("Modal") and not open
	pl.Visible = not modalOther and not HudLayout.GetFlag("Dead") and not recruitCardUp()
end

updatePillLater = function()
	updatePill()
end

local function refresh()
	local pl, b = pill, badge
	if pl == nil or b == nil then
		return
	end
	local n = #rows
	b.Text = tostring(n)
	b.Visible = n > 0
	pl.TextTransparency = if n > 0 then 0 else 0.35 -- dimmed (still readable, still tappable) with nothing to raid
	updatePill()
	rebuildList()
end

local function build()
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if pg == nil then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_RivalTargets"
	g.ResetOnSpawn = false
	g.DisplayOrder = 30
	g.Parent = pg
	local P = RivalConfig.Pill
	local b = Instance.new("TextButton")
	b.Name = "TargetsPill"
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -P.Right, 0, P.Top)
	b.Size = UDim2.fromOffset(P.Width, P.Height)
	b.BackgroundColor3 = PLATE
	b.BackgroundTransparency = 0.15
	b.TextColor3 = GOLD
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 16
	b.Text = "TARGETS"
	b.Visible = true -- v163: always there for a live player (dimmed with no targets)
	b.TextTransparency = 0.35
	b.Parent = g
	corner(b, 24)
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 1.5
	st.Parent = b
	local bd = Instance.new("TextLabel")
	bd.AnchorPoint = Vector2.new(0.5, 0.5)
	bd.Position = UDim2.new(0, 2, 0, 4)
	bd.Size = UDim2.fromOffset(24, 24)
	bd.BackgroundColor3 = Color3.fromRGB(235, 40, 52)
	bd.TextColor3 = Color3.new(1, 1, 1)
	bd.Font = Enum.Font.GothamBold
	bd.TextSize = 14
	bd.Text = "0"
	bd.Visible = false
	bd.Parent = b
	corner(bd, 12)
	pill = b
	badge = bd
	local f = Instance.new("Frame")
	f.Name = "TargetsList"
	f.AnchorPoint = Vector2.new(1, 0)
	f.Position = UDim2.new(1, -P.Right, 0, P.Top + P.Height + 6)
	f.Size = UDim2.fromOffset(330, 130)
	f.BackgroundColor3 = PLATE
	f.BackgroundTransparency = 0.05
	f.Visible = false
	f.Parent = g
	corner(f, 12)
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -70, 0, 28)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 17
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "TARGETS"
	title.Parent = f
	-- v163: the empty state (shown while the server lists 0 targets)
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Position = UDim2.fromOffset(12, 40)
	empty.Size = UDim2.new(1, -24, 0, RivalConfig.EmptyHeight - 8)
	empty.Font = Enum.Font.GothamMedium
	empty.TextSize = 15
	empty.TextWrapped = true
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.TextYAlignment = Enum.TextYAlignment.Top
	empty.TextColor3 = Color3.fromRGB(225, 225, 215)
	empty.Text = RivalConfig.EmptyText
	empty.Parent = f
	emptyLabel = empty
	local x = Instance.new("TextButton")
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -4, 0, -4)
	x.Size = UDim2.fromOffset(48, 48)
	x.BackgroundTransparency = 1
	x.TextColor3 = Color3.new(1, 1, 1)
	x.Font = Enum.Font.GothamBold
	x.TextSize = 18
	x.Text = "X"
	x.Parent = f
	panel = f
	x.Activated:Connect(function()
		setOpen(false)
	end)
	b.Activated:Connect(function()
		if open then
			setOpen(false)
		else
			setOpen(true)
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRivalAction, "open", nil)
		end
	end)
	HudLayout.RegisterPanel(PANEL_ID, function()
		return open
	end, function()
		setOpen(false)
	end)
	-- v163: visibility follows the HUD flags and the Recruit Pack card
	HudLayout.FlagChanged:Connect(function(name: string)
		if name == "Modal" or name == "Dead" then
			updatePill()
		end
	end)
	pg.ChildAdded:Connect(function(c: Instance)
		if c.Name == "WE_RecruitPack" then
			updatePill()
		end
	end)
	pg.ChildRemoved:Connect(function(c: Instance)
		if c.Name == "WE_RecruitPack" then
			updatePill()
		end
	end)
	refresh()
end

function RivalController.Init()
	if RivalConfig.Enabled ~= true or not RivalConfig.LiveFor(player.UserId) then
		return -- OFF / not live: no pill, nothing pushed
	end
	task.spawn(build)
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind ~= "RivalTargets" or typeof(data) ~= "table" or typeof(data.Rows) ~= "table" then
			return
		end
		rows = data.Rows
		why = if typeof(data.Why) == "string" then string.sub(data.Why, 1, 120) else nil
		refresh()
	end)
end

return RivalController
