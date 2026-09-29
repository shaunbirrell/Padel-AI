--!strict
--[[
	claude-bud JOB 13 (2026-09-29): the event banner + countdown and the leaderboard board (EngagementConfig). Client
	only, display only; shown when the server marked this player (WE_Engagement: events / leaderboards live for him).
	  * Banner: in the HUD top stack while an event runs ("DOUBLE CASH WEEKEND · 1d 4h left"), refreshed at 1 Hz.
	  * Board: one client-built part + SurfaceGui (MaxDistance 80) at Town Square, filled from
	    ReplicatedStorage.WE_Leaderboards (the server's top 10 per board), rebuilt only when a board changes.
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
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function buildBoard(E: any): (BasePart, Frame)
	local part = Instance.new("Part")
	part.Name = "WE_LeaderboardBoard"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(34, 36, 38)
	part.Size = Vector3.new(24, 11, 0.6)
	local at = Vector3.new(E.BoardX, 6, E.BoardZ)
	part.CFrame = CFrame.lookAt(at, Vector3.new(-150, 6, 150)) -- faces Town Square
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.PixelsPerStud = 30
	sg.MaxDistance = 80
	sg.Parent = part
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = sg
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Parent = root
	part.Parent = Workspace.CurrentCamera or Workspace
	return part, root
end

local function fillColumn(root: Frame, id: string, data: any)
	local col = root:FindFirstChild(id)
	if col == nil then
		local c = Instance.new("TextLabel")
		c.Name = id
		c.Size = UDim2.fromScale(1 / 3, 1)
		c.BackgroundTransparency = 1
		c.TextColor3 = Color3.fromRGB(240, 235, 220)
		c.Font = Enum.Font.GothamBold
		c.TextSize = 22
		c.TextXAlignment = Enum.TextXAlignment.Left
		c.TextYAlignment = Enum.TextYAlignment.Top
		c.Parent = root
		col = c
	end
	local lines = { tostring(data.Title or id) }
	for i, r in ipairs(data.Rows or {}) do
		table.insert(lines, string.format("%d. %s  %s", i, tostring(r.N), short(tonumber(r.V) or 0)))
	end
	(col :: TextLabel).Text = table.concat(lines, "\n")
end

function EngagementClient.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
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
					label.Visible = true
				else
					label.Visible = false
				end
				task.wait(1)
			end
		end)
		-- board
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild("WE_Leaderboards", 600)
			if folder == nil then
				return
			end
			local _, root = buildBoard(E)
			local function refresh(sv: Instance)
				if sv:IsA("StringValue") then
					local ok, data = pcall(HttpService.JSONDecode, HttpService, sv.Value)
					if ok and typeof(data) == "table" then
						fillColumn(root, sv.Name, data)
					end
				end
			end
			for _, sv in ipairs(folder:GetChildren()) do
				refresh(sv)
				sv.Changed:Connect(function()
					refresh(sv)
				end)
			end
			folder.ChildAdded:Connect(function(sv)
				refresh(sv)
				sv.Changed:Connect(function()
					refresh(sv)
				end)
			end)
		end)
	end
	start()
	lp:GetAttributeChangedSignal("WE_Engagement"):Connect(start)
end

return EngagementClient
