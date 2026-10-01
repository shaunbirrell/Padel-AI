--!strict
--[[
	claude-bud JOB 13 (2026-09-29): the event banner + countdown and the leaderboard board (EngagementConfig). Client
	only, display only; shown when the server marked this player (WE_Engagement: events / leaderboards live for him).
	  * Banner: in the HUD top stack while an event runs ("DOUBLE CASH WEEKEND · 1d 4h left"), refreshed at 1 Hz.
	  * Boards (claude-bud BOARDS, live for everyone): the row of Town Centre notice boards (LeaderboardConfig), filled
	    from ReplicatedStorage.WE_Leaderboards (the server's one shared fetch), rebuilt only when a board changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local EngagementClient = {}

local function fmtLeft(s: number): string
	s = math.max(0, math.floor(s))
	local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

local function short(n: number): string
	if n >= 1e12 then
		return string.format("%.1fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

-- ── the Town Centre notice boards (claude-bud BOARDS, Shared/Configs/LeaderboardConfig; live for everyone) ──
-- Client-built, display only: a steel-framed board per LeaderboardConfig.Boards entry in one row along the square's
-- south edge, a gold header, the top 10 (rank, headshot, name, value; gold / silver / bronze for #1-3), "You:" when
-- the local player stands within YouRowStuds, and a spotlight at night. Filled from ReplicatedStorage.WE_Leaderboards
-- (the server's shared fetch); rebuilt only when a board's data changes. 2 Hz "You:" check, 0.1 Hz night check.
local STEEL = Color3.fromRGB(58, 62, 66)
local PANEL = Color3.fromRGB(24, 26, 28)
local GOLD = Color3.fromRGB(212, 168, 60)
local MEDAL = { Color3.fromRGB(232, 186, 58), Color3.fromRGB(190, 196, 204), Color3.fromRGB(196, 126, 70) }

local thumbs: { [number]: string } = {}
local function headshot(uid: number, img: ImageLabel)
	local cached = thumbs[uid]
	if cached then
		img.Image = cached
		return
	end
	img.Image = ""
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and typeof(content) == "string" then
			thumbs[uid] = content
			if img:GetAttribute("Uid") == uid then
				img.Image = content
			end
		end
	end)
end

local function commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function valueText(v: number, money: boolean): string
	if money then
		return "$" .. short(v)
	end
	return if v >= 1e6 then short(v) else commas(v)
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function label(parent: Instance, text: string, size: number, pos: UDim2, sz: UDim2, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = sz
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	t.Parent = parent
	return t
end

type BoardUi = {
	Def: any,
	Pos: Vector3,
	Title: TextLabel,
	Tab: TextLabel,
	Rows: { { Frame: Frame, Rank: TextLabel, Badge: Frame, Img: ImageLabel, Name: TextLabel, Value: TextLabel } },
	You: TextLabel,
	Light: SpotLight,
	Keys: { string },
	Showing: number,
}

local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	params.FilterDescendantsInstances = chars
	local r = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
	return if r then r.Position.Y else 0.5
end

local function buildBoard(L: any, def: any, index: number, folder: Folder): BoardUi
	local R = L.Row
	local size: Vector3 = L.BoardSize
	local x = R.FirstX + (index - 1) * R.StepX
	local z = R.Z
	local y0 = groundY(x, z)
	local centre = Vector3.new(x, y0 + 2 + size.Y / 2, z)
	local face = Vector3.new(0, 0, R.FaceDirZ)
	local cf = CFrame.lookAt(centre, centre + face)
	local model = Instance.new("Model")
	model.Name = "WE_NoticeBoard_" .. def.Id
	local panel = part("Panel", size, cf, PANEL, Enum.Material.DiamondPlate, model)
	local postH = size.Y + 2.4
	for _, sx in ipairs({ -1, 1 }) do
		-- from the ground (y0) up past the gold trim, just outside the panel's edges
		part("Post", Vector3.new(0.8, postH, 0.8), cf * CFrame.new(sx * (size.X / 2 + 0.4), postH / 2 - 2 - size.Y / 2, 0), STEEL, Enum.Material.Metal, model)
	end
	part("GoldTrim", Vector3.new(size.X + 1.6, 0.5, 1), cf * CFrame.new(0, size.Y / 2 + 0.25, 0), GOLD, Enum.Material.Metal, model)
	-- the night lamp: on an arm over the header, aimed at the board face
	local lampPos = (cf * CFrame.new(0, size.Y / 2 + 1.2, -3)).Position
	local lamp = part("Lamp", Vector3.new(1.2, 0.6, 1.2), CFrame.lookAt(lampPos, centre), STEEL, Enum.Material.Metal, model)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 80
	light.Range = 28
	light.Brightness = 2.5
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Enabled = false
	light.Parent = lamp
	part("Arm", Vector3.new(0.4, 0.4, 3), cf * CFrame.new(0, size.Y / 2 + 1.2, -1.5), STEEL, Enum.Material.Metal, model)
	-- the face
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = L.PixelsPerStud
	sg.MaxDistance = L.MaxDistance
	sg.LightInfluence = 0
	sg.Parent = panel
	local H = size.Y * L.PixelsPerStud
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = sg
	local header = Instance.new("Frame")
	header.BackgroundColor3 = GOLD
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(10, 10)
	header.Size = UDim2.new(1, -20, 0, 64)
	header.Parent = root
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 8)
	hc.Parent = header
	local title = label(header, def.Title, 40, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(28, 24, 14), Enum.TextXAlignment.Center)
	title.Font = Enum.Font.GothamBlack
	local tab = label(root, "", 26, UDim2.fromOffset(10, 78), UDim2.new(1, -20, 0, 30), Color3.fromRGB(200, 204, 210), Enum.TextXAlignment.Center)
	local rows = {}
	local rowH = math.floor((H - 112 - 58) / 10)
	for i = 1, 10 do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(32, 34, 37) else Color3.fromRGB(28, 30, 33)
		f.BorderSizePixel = 0
		f.Position = UDim2.fromOffset(10, 112 + (i - 1) * rowH)
		f.Size = UDim2.new(1, -20, 0, rowH - 3)
		f.Parent = root
		local badge = Instance.new("Frame")
		badge.BackgroundColor3 = MEDAL[i] or Color3.fromRGB(52, 56, 60)
		badge.BorderSizePixel = 0
		badge.Position = UDim2.fromOffset(4, 2)
		badge.Size = UDim2.fromOffset(rowH - 7, rowH - 7)
		badge.Parent = f
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(1, 0)
		bc.Parent = badge
		local rank = label(badge, tostring(i), 24, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), if i <= 3 then Color3.fromRGB(24, 20, 12) else Color3.fromRGB(230, 230, 230), Enum.TextXAlignment.Center)
		rank.Font = Enum.Font.GothamBlack
		local img = Instance.new("ImageLabel")
		img.BackgroundColor3 = Color3.fromRGB(44, 46, 50)
		img.BorderSizePixel = 0
		img.Position = UDim2.fromOffset(rowH + 2, 2)
		img.Size = UDim2.fromOffset(rowH - 7, rowH - 7)
		img.Parent = f
		local nameColor = if i <= 3 then MEDAL[i] else Color3.fromRGB(236, 236, 236)
		local name = label(f, "", 26, UDim2.fromOffset(2 * rowH + 6, 0), UDim2.new(0.62, -(2 * rowH + 6), 1, 0), nameColor)
		local value = label(f, "", 26, UDim2.new(0.62, 0, 0, 0), UDim2.new(0.38, -8, 1, 0), nameColor, Enum.TextXAlignment.Right)
		f.Visible = false
		table.insert(rows, { Frame = f, Rank = rank, Badge = badge, Img = img, Name = name, Value = value })
	end
	local you = label(root, "", 26, UDim2.fromOffset(10, H - 52), UDim2.new(1, -20, 0, 44), GOLD, Enum.TextXAlignment.Center)
	you.BackgroundColor3 = Color3.fromRGB(46, 40, 20)
	you.BackgroundTransparency = 0.1
	you.Visible = false
	model.Parent = folder
	local keys = {}
	if def.AllTime then
		table.insert(keys, def.Id)
	end
	if def.Weekly then
		table.insert(keys, def.Id .. "_W")
	end
	return { Def = def, Pos = centre, Title = title, Tab = tab, Rows = rows, You = you, Light = light, Keys = keys, Showing = 1 }
end

local function fillBoard(b: BoardUi, data: any)
	b.Tab.Text = if data.Weekly == true then "THIS WEEK" else "ALL-TIME"
	local list = if typeof(data.Rows) == "table" then data.Rows else {}
	for i, r in ipairs(b.Rows) do
		local row = list[i]
		if row then
			local uid = tonumber(row.U) or 0
			r.Frame.Visible = true
			r.Name.Text = tostring(row.N or "?")
			r.Value.Text = valueText(tonumber(row.V) or 0, data.Money == true)
			r.Img:SetAttribute("Uid", uid)
			headshot(uid, r.Img)
		else
			r.Frame.Visible = false
		end
	end
	if #list == 0 then
		b.Tab.Text ..= " · no entries yet"
	end
end

local function youText(b: BoardUi, key: string): string
	local lp = Players.LocalPlayer
	if b.Def.OptOut and lp:GetAttribute("WE_SupporterOptOut") == true then
		return "You: hidden (Settings)"
	end
	local v = tonumber(lp:GetAttribute("WE_LBVal_" .. key)) or 0
	if v <= 0 then
		return "You: not on this board yet"
	end
	local rank = tonumber(lp:GetAttribute("WE_LBRank_" .. key))
	local rt = if rank == nil then "#—" elseif rank > 0 then "#" .. commas(rank) else "#100+"
	local unit = if b.Def.Unit ~= "" then " " .. b.Def.Unit else ""
	return string.format("You: %s · %s%s", rt, valueText(v, b.Def.Money == true), unit)
end

local function noticeBoards()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	local L = require((Shared :: any).Configs.LeaderboardConfig) :: any
	local data: { [string]: any } = {}
	local folder = Instance.new("Folder")
	folder.Name = "WE_NoticeBoards"
	folder.Parent = Workspace
	local boards: { BoardUi } = {}
	for i, def in ipairs(L.Boards) do
		table.insert(boards, buildBoard(L, def, i, folder))
	end
	local function show(b: BoardUi)
		local key = b.Keys[b.Showing]
		local d = key and data[key]
		if d then
			fillBoard(b, d)
		else
			b.Tab.Text = "loading…"
		end
	end
	for _, b in ipairs(boards) do
		show(b)
	end
	task.spawn(function()
		local lb = ReplicatedStorage:WaitForChild("WE_Leaderboards", 600)
		if lb == nil then
			return
		end
		local function take(sv: Instance)
			if not sv:IsA("StringValue") then
				return
			end
			local ok, d = pcall(HttpService.JSONDecode, HttpService, (sv :: StringValue).Value)
			if ok and typeof(d) == "table" then
				data[sv.Name] = d
				for _, b in ipairs(boards) do
					if b.Keys[b.Showing] == sv.Name then
						fillBoard(b, d)
					end
				end
			end
		end
		for _, sv in ipairs(lb:GetChildren()) do
			take(sv)
			sv.Changed:Connect(function()
				take(sv)
			end)
		end
		lb.ChildAdded:Connect(function(sv)
			take(sv)
			sv.Changed:Connect(function()
				take(sv)
			end)
		end)
	end)
	-- tabs (ALL-TIME / THIS WEEK) + "You:" (2 Hz) + night lamps (every NightCheckSeconds)
	local Lighting = game:GetService("Lighting")
	local tick, nextTab, nextNight = 0, L.TabSeconds, 0
	while folder.Parent do
		task.wait(0.5)
		tick += 0.5
		if tick >= nextTab then
			nextTab = tick + L.TabSeconds
			for _, b in ipairs(boards) do
				if #b.Keys > 1 then
					b.Showing = (b.Showing % #b.Keys) + 1
					show(b)
				end
			end
		end
		if tick >= nextNight then
			nextNight = tick + L.NightCheckSeconds
			local t = Lighting.ClockTime
			local night = t < 6.3 or t > 17.7
			for _, b in ipairs(boards) do
				b.Light.Enabled = night
			end
		end
		local char = Players.LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		for _, b in ipairs(boards) do
			local near = false
			if root and root:IsA("BasePart") then
				local d = root.Position - b.Pos
				near = Vector3.new(d.X, 0, d.Z).Magnitude <= L.YouRowStuds
			end
			b.You.Visible = near
			if near then
				b.You.Text = youText(b, b.Keys[b.Showing])
			end
		end
	end
end

function EngagementClient.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	task.spawn(noticeBoards) -- claude-bud BOARDS: live for everyone (no WE_Engagement gate)
	local E = require((Shared :: any).Configs.EngagementConfig) :: any
	local lp = Players.LocalPlayer
	local started = false
	local function start()
		if started or lp:GetAttribute("WE_Engagement") ~= true then
			return
		end
		started = true
		-- banner
		local okH, HudLayout = pcall(require, script.Parent.HudLayout)
		local gui = Instance.new("ScreenGui")
		gui.Name = "WE_EventBanner"
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 0)
		label.Size = UDim2.fromOffset(360, 40)
		label.BackgroundColor3 = Color3.fromRGB(40, 32, 12)
		label.BackgroundTransparency = 0.15
		label.TextColor3 = Color3.fromRGB(255, 205, 60)
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 20
		label.Visible = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = label
		label.Parent = gui
		gui.Parent = lp:WaitForChild("PlayerGui", 30)
		if okH and type(HudLayout) == "table" then
			pcall((HudLayout :: any).ApplyScreen, gui)
			pcall((HudLayout :: any).RegisterTopStack, "EventBanner", label, 45)
		end
		task.spawn(function()
			while gui.Parent do
				local ev, t = E.EventAt(os.time())
				if ev then
					label.Text = string.format("%s · %s left", ev.Name, fmtLeft(t - os.time()))
					if not label.Visible then -- claude-bud JOB 14: the banner appearing was silent
						local okG, GF = pcall(require, script.Parent.GameFeelClient)
						if okG and type(GF) == "table" then
							pcall((GF :: any).Sound, "EventStart")
						end
					end
					label.Visible = true
				else
					label.Visible = false
				end
				task.wait(1)
			end
		end)
	end
	start()
	lp:GetAttributeChangedSignal("WE_Engagement"):Connect(start)
end

return EngagementClient
