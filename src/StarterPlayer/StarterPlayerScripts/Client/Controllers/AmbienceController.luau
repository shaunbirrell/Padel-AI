--!strict
--[[ claude-bud JOB 59 (B): the world ambience, on THIS client only (SoundConfig.Pass59, owner-first).
	One loop every Pass59.TickSeconds (no per-frame work):
	  * night: the "Night" Loop channel plays crickets (land), the harbor loop (near a water spot) or the night
	    ambience above NightLoopThreshold of the night share (LightingConfig.Cycle); off by day.
	  * radio chatter by HIS Command Center (3D, his plot only), the plaza flag's flap (3D), the distant artillery only
	    out in the desert (2D, quiet, rare).
	  * his own gate (GateOpen attribute flips) plays the gate sound there (3D).
	Every sound goes through AudioController (the SFX toggle, distance skip, voice caps). OFF = nothing here runs. ]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)

local AmbienceController = {}

local player = Players.LocalPlayer
local rng = Random.new()

-- the night share of a clock time (pure; = WorldAtmosphere.NightShare on LightingConfig.Cycle)
function AmbienceController.NightShare(t: number, C: any): number
	if t < C.NightEnd or t > C.NightStart then
		return 1
	elseif t < C.DawnEnd then
		return 1 - (t - C.NightEnd) / math.max(0.01, C.DawnEnd - C.NightEnd)
	elseif t > C.DuskStart then
		return (t - C.DuskStart) / math.max(0.01, C.NightStart - C.DuskStart)
	end
	return 0
end

-- which night loop for a position (pure; the tests): nil by day
function AmbienceController.NightKey(share: number, nearWater: boolean, P: any): string?
	if share < P.NightLoopThreshold then
		return nil
	end
	return if nearWater then "Amb.HarborNight" else "Amb.NightCrickets"
end

-- the desert ring (pure): far from the map centre
function AmbienceController.InDesert(pos: Vector3, P: any): boolean
	return Vector3.new(pos.X, 0, pos.Z).Magnitude >= P.DesertFromTownStuds
end

function AmbienceController.Init()
	if Shared == nil then
		return
	end
	local okS, SC = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.SoundConfig)
	end)
	local okR, RC = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.RetentionConfig)
	end)
	local okL, LC = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.LightingConfig)
	end)
	if not (okS and okR and okL) or typeof(SC.Pass59) ~= "table" or not RC.Live(SC.Pass59, player.UserId) then
		return
	end
	local P = SC.Pass59
	local okA, Audio = pcall(function(): any
		return require(script.Parent.Parent.Modules.AudioController)
	end)
	if not okA or Audio == nil then
		return
	end
	local okW, WaterConfig = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.WaterConfig)
	end)
	local okB, BaseLayoutConfig = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.BaseLayoutConfig)
	end)
	local okF, PlotFrame = pcall(function(): any
		return (require :: any)((Shared :: any).Util.PlotFrame)
	end)
	local nextRadio, nextFlag, nextArty = 0, 0, os.clock() + 20
	local hooked: { [Instance]: boolean } = {}
	local nightKey: string? = nil
	local function nearWater(pos: Vector3): boolean
		-- his own dock basin, or the sea ring (WaterConfig) when it lists water spots
		local pid = tonumber(player:GetAttribute("WE_PlotId"))
		if pid and okB and okF and BaseLayoutConfig.Courtyard and BaseLayoutConfig.Courtyard.DockBasin then
			local b = BaseLayoutConfig.Courtyard.DockBasin
			local w = PlotFrame.LocalToWorld(pid, b.X, b.Z)
			if (Vector3.new(w.X - pos.X, 0, w.Z - pos.Z)).Magnitude <= P.HarborStuds then
				return true
			end
		end
		if okW and WaterConfig and typeof(WaterConfig.SeaInnerRadius) == "number" then
			return Vector3.new(pos.X, 0, pos.Z).Magnitude >= WaterConfig.SeaInnerRadius - P.HarborStuds
		end
		return false
	end
	task.spawn(function()
		while true do
			task.wait(P.TickSeconds)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local pos = root.Position
				local now = os.clock()
				-- the night loop
				local want = AmbienceController.NightKey(AmbienceController.NightShare(Lighting.ClockTime, LC.Cycle), nearWater(pos), P)
				if want ~= nightKey then
					nightKey = want
					pcall(Audio.Loop, "Night", want, 2)
				end
				-- radio chatter at his Command Center
				local pid = tonumber(player:GetAttribute("WE_PlotId"))
				if now >= nextRadio and pid and okB and okF then
					nextRadio = now + rng:NextNumber(P.RadioEverySeconds[1], P.RadioEverySeconds[2])
					local cc = BaseLayoutConfig.Structures.CommandCenter.Site
					local w = PlotFrame.LocalToWorld(pid, cc.X, cc.Z)
					local at = Vector3.new(w.X, pos.Y, w.Z)
					if (at - pos).Magnitude <= 45 then
						pcall(Audio.Play, if rng:NextNumber() < 0.5 then "World.Radio" else "World.Radio2", at)
					end
				end
				-- the plaza flag
				if now >= nextFlag then
					nextFlag = now + rng:NextNumber(P.FlagEverySeconds[1], P.FlagEverySeconds[2])
					local pole = Workspace:FindFirstChild("CentralPlaza_FlagPole", true)
					if pole and pole:IsA("BasePart") and (pole.Position - pos).Magnitude <= 50 then
						pcall(Audio.Play, if rng:NextNumber() < 0.5 then "World.FlagFlap" else "World.FlagFlap2", pole)
					end
				end
				-- the distant artillery (desert only)
				if now >= nextArty then
					nextArty = now + rng:NextNumber(P.ArtilleryEverySeconds[1], P.ArtilleryEverySeconds[2])
					if AmbienceController.InDesert(pos, P) then
						pcall(Audio.Play, "Amb.Artillery")
					end
				end
				-- his gate: hook new barrier parts (a resync rebuilds them)
				if pid then
					for _, p in ipairs(CollectionService:GetTagged("WE_GateBarrier")) do
						if not hooked[p] and p:IsA("BasePart") and p:GetAttribute("PlotId") == pid and p.Name == "GateBarrier_1" then
							hooked[p] = true
							p:GetAttributeChangedSignal("GateOpen"):Connect(function()
								pcall(Audio.Play, "World.Gate", p)
							end)
							p.AncestryChanged:Connect(function()
								if p.Parent == nil then
									hooked[p] = nil
								end
							end)
						end
					end
				end
			end
		end
	end)
end

return AmbienceController
