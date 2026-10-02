--!strict
--[[
	claude-bud JOB 19 (2026-09-29): purchase stand motion on this client only (MonetizationConfig.PremiumPads.Stand):
	the hologram turns slowly (a 120-degree tween every SpinSeconds / 3, never per frame) and the floor ring pulses (one
	looping tween). Low quality (WE_LowQuality) or a stand that streams out: nothing moves. Display only.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local StandFx = {}

local running: { [Instance]: boolean } = {}

local function low(): boolean
	return Players.LocalPlayer:GetAttribute("WE_LowQuality") == true
end

local function animate(top: Instance, S: any)
	if running[top] or not top:IsA("BasePart") or top:GetAttribute("WE_Stand") ~= true then
		return
	end
	local model = top.Parent
	local holo = model and model:FindFirstChild("Hologram")
	local ring = model and model:FindFirstChild("FloorRing")
	if not (holo and holo:IsA("BasePart")) then
		return
	end
	running[top] = true
	if ring and ring:IsA("BasePart") and not low() then
		local base = ring.Transparency
		TweenService:Create(ring, TweenInfo.new(S.PulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = math.min(0.9, base + 0.3) }):Play()
	end
	task.spawn(function()
		local pos = holo.Position
		local tilt = CFrame.Angles(math.rad(45), 0, math.rad(45))
		local a = 0
		local step = S.SpinSeconds / 3
		while holo.Parent and top.Parent do
			if low() then
				task.wait(2)
			else
				a += 2 * math.pi / 3
				local tw = TweenService:Create(holo, TweenInfo.new(step, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) * CFrame.Angles(0, a, 0) * tilt })
				tw:Play()
				tw.Completed:Wait()
			end
		end
		running[top] = nil
	end)
end

function StandFx.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	local MC = require((Shared :: any).Configs.MonetizationConfig) :: any
	local S = MC.PremiumPads and MC.PremiumPads.Stand
	if S == nil then
		return
	end
	local Constants = require((Shared :: any).Constants) :: any
	local tag = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		task.defer(animate, inst, S)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		task.defer(animate, inst, S)
	end)
end

return StandFx
