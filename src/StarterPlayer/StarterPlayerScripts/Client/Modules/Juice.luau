--!strict
--[[
	claude-bud JOB 11 (2026-09-29): purchase burst + rebirth celebration (Shared/Configs/JuiceConfig). Client only.
	Listens to PurchaseResult (Ok) and FeaturePush "Rebirth". Everything it makes is destroyed within a few seconds.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Juice = {}

local function lowFx(): boolean
	local ok, PF = pcall(require, script.Parent.ProductionFx)
	if ok and type(PF) == "table" and (PF :: any).IsLowFx then
		local ok2, v = pcall((PF :: any).IsLowFx)
		return ok2 and v == true
	end
	return false
end

local function burst(J: any)
	local lp = Players.LocalPlayer
	local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local B = J.Burst
	local at = (root :: BasePart).Position - Vector3.new(0, 2.8, 0)
	local ring = Instance.new("Part")
	ring.Name = "WE_JuiceRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = B.Color
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace.CurrentCamera or Workspace
	TweenService:Create(ring, TweenInfo.new(B.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, B.RingStuds, B.RingStuds),
		Transparency = 1,
	}):Play()
	if not lowFx() then
		local att = Instance.new("Attachment")
		att.Parent = ring
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(B.Color)
		pe.LightEmission = 0.4
		pe.Size = NumberSequence.new(0.35, 0)
		pe.Lifetime = NumberRange.new(0.5, 0.9)
		pe.Speed = NumberRange.new(10, 18)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rate = 0
		pe.Parent = att
		pe:Emit(B.Particles)
	end
	task.delay(B.Seconds + 1, function()
		ring:Destroy()
	end)
end

local function celebrate(J: any, data: any)
	local lp = Players.LocalPlayer
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	local R = J.Rebirth
	local okH, HudLayout = pcall(require, script.Parent.HudLayout)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_RebirthCelebration"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	local banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 90)
	banner.Size = UDim2.fromOffset(420, 84)
	banner.BackgroundColor3 = Color3.fromRGB(28, 26, 18)
	banner.BackgroundTransparency = 0.1
	banner.TextColor3 = Color3.fromRGB(255, 205, 60)
	banner.Font = Enum.Font.GothamBlack
	banner.TextSize = 30
	banner.TextWrapped = true
	local p = tonumber(typeof(data) == "table" and data.Prestige) or 0
	banner.Text = string.format("REBIRTH P%d!\n%s", p, tostring(typeof(data) == "table" and data.Sub or "Cash earnings up"))
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = banner
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 205, 60)
	st.Thickness = 2
	st.Parent = banner
	banner.Parent = gui
	-- light confetti: small frames falling from the top edge, then gone
	if not lowFx() then
		for i = 1, R.Confetti do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = R.Colors[(i % #R.Colors) + 1]
			f.Size = UDim2.fromOffset(8, 12)
			f.Position = UDim2.new(math.random(), 0, 0, -20)
			f.Rotation = math.random(0, 180)
			f.Parent = gui
			TweenService:Create(f, TweenInfo.new(1.6 + math.random() * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(f.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.05, 0),
				Rotation = f.Rotation + 360,
			}):Play()
		end
	end
	gui.Parent = pg
	if okH and type(HudLayout) == "table" then
		pcall((HudLayout :: any).ApplyScreen, gui)
		pcall((HudLayout :: any).RegisterTopStack, "Rebirth", banner, 15)
	end
	local okA, Audio = pcall(require, script.Parent.AudioController)
	if okA and type(Audio) == "table" and (Audio :: any).Play then
		pcall((Audio :: any).Play, "Level.Up")
	end
	task.delay(R.BannerSeconds, function()
		if okH and type(HudLayout) == "table" then
			pcall((HudLayout :: any).UnregisterTopStack, "Rebirth")
		end
		gui:Destroy()
	end)
end

function Juice.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	local J = require((Shared :: any).Configs.JuiceConfig) :: any
	if not J.LiveFor(Players.LocalPlayer.UserId) then
		return
	end
	local Remotes = require((Shared :: any).Remotes) :: any
	local Constants = require((Shared :: any).Constants) :: any
	Remotes.BindEvent(Constants.RemoteNames.PurchaseResult, function(payload: any)
		if typeof(payload) == "table" and payload.Ok == true then
			burst(J)
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind == "Rebirth" then
			celebrate(J, data)
		end
	end)
end

return Juice
