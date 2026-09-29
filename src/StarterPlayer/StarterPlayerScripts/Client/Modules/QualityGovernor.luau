--!strict
--[[
	claude-bud JOB 8 (2026-09-29): the automatic LOW quality tier (Shared/Configs/QualityConfig). Client only.
	  * FPS: one counter bumped per Heartbeat (no allocation), evaluated once a second.
	  * Decoration: the WorldKits clusters (Model with WE_Cluster) under the QualityConfig.Folders are listed ONCE when
	    each folder appears, kept up to date by DescendantAdded (no whole-tree scans after that), and culled at CheckHz:
	    a hidden cluster is parented to nil on THIS client and put back where it was when the camera comes near again.
	  * Low also turns this client's GlobalShadows off and sets WE_LowQuality (ProductionFx.IsLowFx reads it).
	Streaming-safe: folders are found by name with FindFirstChild (never WaitForChild), a cluster that streams out
	(Parent nil by the engine) is dropped from the list.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QualityGovernor = {}

type Entry = { Model: Model, Home: Instance, Pos: Vector3, Tier: number, Hidden: boolean }

local entries: { [Model]: Entry } = {}
local watched: { [Instance]: boolean } = {}
local low = false
local shadowsBefore: boolean? = nil

function QualityGovernor.IsLow(): boolean
	return low
end

local function track(m: Instance, home: Instance)
	if not m:IsA("Model") or entries[m] ~= nil or m:GetAttribute("WE_Cluster") == nil then
		return
	end
	local okP, pivot = pcall(function()
		return m:GetPivot()
	end)
	if not okP then
		return
	end
	entries[m] = {
		Model = m,
		Home = m.Parent or home,
		Pos = (pivot :: CFrame).Position,
		Tier = tonumber(m:GetAttribute("WE_Tier")) or 1,
		Hidden = false,
	}
end

local function watchFolder(folder: Instance)
	if watched[folder] then
		return
	end
	watched[folder] = true
	for _, d in ipairs(folder:GetDescendants()) do -- once per folder
		track(d, folder)
	end
	folder.DescendantAdded:Connect(function(d)
		track(d, folder)
	end)
end

local function findFolders(Q: any)
	for _, path in ipairs(Q.Folders) do
		local node: Instance? = Workspace
		for part in string.gmatch(path, "[^/]+") do
			node = if node then node:FindFirstChild(part) else nil
		end
		if node then
			watchFolder(node)
		end
	end
end

local function setLow(on: boolean, Q: any)
	if on == low then
		return
	end
	low = on
	local lp = Players.LocalPlayer
	pcall(function()
		lp:SetAttribute("WE_LowQuality", if on then true else nil)
	end)
	-- claude-bud JOB 17: low quality keeps every second night light off (LightingConfig.LowOffAttribute); the Neon
	-- glow of lamp heads / windows still shows. The server's dusk / dawn flip is re-applied on each change.
	pcall(function()
		local LC = require((ReplicatedStorage :: any).Shared.Configs.LightingConfig) :: any
		local nl = Workspace:FindFirstChild("WE_NightLights")
		if nl then
			for _, d in ipairs(nl:GetDescendants()) do
				if d:IsA("Light") and d:GetAttribute(LC.LowOffAttribute) == true then
					if on then
						d.Enabled = false
						if not d:GetAttribute("WE_LowHooked") then
							d:SetAttribute("WE_LowHooked", true)
							d:GetPropertyChangedSignal("Enabled"):Connect(function()
								if low and d.Enabled then
									d.Enabled = false
								end
							end)
						end
					else
						-- back to normal quality: on again if it is night now (the server's night share > 0.5)
						local t = Lighting.ClockTime
						local C = LC.Cycle
						d.Enabled = t < (C.NightEnd + C.DawnEnd) / 2 or t > (C.DuskStart + C.NightStart) / 2
					end
				end
			end
		end
	end)
	if Q.ShadowsOffWhenLow then
		if on then
			shadowsBefore = Lighting.GlobalShadows
			Lighting.GlobalShadows = false
		elseif shadowsBefore ~= nil then
			Lighting.GlobalShadows = shadowsBefore
		end
	end
end

local function cull(Q: any)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local focus = cam.Focus.Position
	for m, e in pairs(entries) do
		if e.Hidden == false and m.Parent == nil then
			entries[m] = nil -- streamed out / destroyed by the server
		else
			local d = (e.Pos - focus).Magnitude
			local hide = low and ((e.Tier >= 2 and d > Q.HideTier2BeyondStuds) or d > Q.HideAnyBeyondStuds)
			if hide ~= e.Hidden then
				e.Hidden = hide
				pcall(function()
					m.Parent = if hide then nil else e.Home
				end)
			end
		end
	end
end

function QualityGovernor.Init()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
	if not Shared then
		return
	end
	local Q = require((Shared :: any).Configs.QualityConfig) :: any
	local lp = Players.LocalPlayer
	if not Q.LiveFor(lp.UserId) then
		return
	end
	local frames = 0
	RunService.Heartbeat:Connect(function()
		frames += 1
	end)
	task.spawn(function()
		local lowFor, highFor, since, lastFind = 0, 0, os.clock(), -math.huge
		local interval = 1 / math.max(0.2, Q.CheckHz)
		while lp.Parent do
			task.wait(interval)
			local now = os.clock()
			local fps = frames / math.max(0.001, now - since)
			frames, since = 0, now
			if now - lastFind >= 5 then
				lastFind = now
				findFolders(Q)
			end
			local cam = Workspace.CurrentCamera
			local vp = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
			local small = math.min(vp.X, vp.Y) <= Q.SmallScreenShortSide
			if fps < Q.LowFpsBelow then
				lowFor += interval
				highFor = 0
			elseif fps > Q.RecoverFpsAbove then
				highFor += interval
				lowFor = 0
			end
			if small or lowFor >= Q.LowFpsSeconds then
				setLow(true, Q)
			elseif low and highFor >= Q.RecoverSeconds then
				setLow(false, Q)
			end
			cull(Q)
		end
	end)
end

return QualityGovernor
