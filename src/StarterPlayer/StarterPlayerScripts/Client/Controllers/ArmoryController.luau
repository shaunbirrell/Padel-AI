--!strict
--[[
	claude-bud JOB 35 (2026-09-30): the guns inside the base armory's glass cases (PremiumGunService builds the cases).
	Client only, display only:
	  * once a second it looks at Workspace.WE_Armories (only that folder: plots x 7 cases, never a whole-tree scan)
	    and, for each case whose Glass has streamed in within Armory.ShowDistance, shows a local copy of the gun's
	    template (ReplicatedStorage.WE_WeaponTemplates, WeaponAssetLoader), anchored, scaled to Armory.GunLength;
	  * the Armory Pass case shows the six guns in turn (3 s each);
	  * the copies turn slowly (one RenderStepped step over at most a few models, connected only while any is shown).
	A gun whose template did not load leaves its case empty (the glass and the board still show).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] ArmoryController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local PremiumGunsConfig = require(Shared.Configs.PremiumGunsConfig)

local ArmoryController = {}

local A = PremiumGunsConfig.Armory
local player = Players.LocalPlayer

type Shown = { Model: Model, Center: CFrame, WeaponId: string, Case: Model }
local shown: { [Model]: Shown } = {}
local angle = 0
local stepConn: RBXScriptConnection? = nil
local localFolder: Folder? = nil

local function holder(): Folder
	local f = localFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "WE_ArmoryDisplay" -- client-only copies
	nf.Parent = Workspace
	localFolder = nf
	return nf
end

-- a display copy of the gun template, anchored and scaled to `length` studs (nil when the template is missing)
function ArmoryController.MakeDisplay(weaponId: string, length: number): Model?
	local templates = ReplicatedStorage:FindFirstChild("WE_WeaponTemplates")
	local t = templates and templates:FindFirstChild("Weapon_" .. weaponId)
	if t == nil or not t:IsA("Model") then
		return nil
	end
	local m = t:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	local size = m:GetExtentsSize()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0.01 then
		m:ScaleTo(m:GetScale() * length / longest)
	end
	return m
end

local function passGun(): string
	local list = PremiumGunsConfig.Guns
	local i = (math.floor(os.clock() / 3) % #list) + 1
	return list[i].WeaponId
end

local function step(dt: number)
	angle = (angle + dt * math.rad(A.SpinDegPerSecond)) % (math.pi * 2)
	for _, s in pairs(shown) do
		if s.Model.Parent then
			s.Model:PivotTo(s.Center * CFrame.Angles(0, angle, 0))
		end
	end
end

local function syncStep()
	local any = next(shown) ~= nil
	if any and stepConn == nil then
		stepConn = RunService.RenderStepped:Connect(step)
	elseif not any and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local function drop(case: Model)
	local s = shown[case]
	if s then
		s.Model:Destroy()
		shown[case] = nil
	end
end

local function scan()
	local root = Workspace:FindFirstChild(A.FolderName)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local seen: { [Model]: boolean } = {}
	if root and hrp and hrp:IsA("BasePart") then
		for _, plot in ipairs(root:GetChildren()) do
			for _, case in ipairs(plot:GetChildren()) do
				local glass = case:FindFirstChild("Glass")
				if case:IsA("Model") and glass and glass:IsA("BasePart") and (glass.Position - hrp.Position).Magnitude <= A.ShowDistance then
					local gun = case:GetAttribute("WE_ArmoryGun")
					local want = if typeof(gun) == "string" then gun elseif case:GetAttribute("WE_ArmoryPass") == true then passGun() else nil
					if want then
						seen[case] = true
						local s = shown[case]
						if s == nil or s.WeaponId ~= want then
							drop(case)
							local m = ArmoryController.MakeDisplay(want, A.GunLength)
							if m then
								local center = CFrame.new(glass.Position) * CFrame.Angles(0, 0, math.rad(8))
								m:PivotTo(center)
								m.Parent = holder()
								shown[case] = { Model = m, Center = center, WeaponId = want, Case = case }
							end
						end
					end
				end
			end
		end
	end
	for case in pairs(shown) do
		if not seen[case] or case.Parent == nil then
			drop(case)
		end
	end
	syncStep()
end

function ArmoryController.Init()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(scan :: any)
			if not ok then
				warn("[ArmoryController] " .. tostring(err))
			end
		end
	end)
end

return ArmoryController
