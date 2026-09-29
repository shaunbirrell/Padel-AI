--!strict
--[[
	claude-bud JOB 5b (2026-09-29): the VIP lounge (MonetizationConfig.VIPPerks). A small walled pad near the Central
	Plaza, 8 parts in Workspace.WE_VIPLounge. Its door is solid for everyone; a VIP whose perks are live turns it
	non-colliding on his OWN client (FeatureController, player attribute WE_VIPTag set by the server), so only VIPs walk
	in. Inside, the gold pad pays LoungeCash once per LoungeCooldownSeconds to a VIP who stands on it LoungeHoldSeconds:
	decided here on the server (position, VIP ownership, cooldown), never by the client.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local VIPLounge = {}

local GROUND_Y = 0.5
local lastPaid: { [number]: number } = {} -- userId -> os.clock() of the last lounge payout (kept for the server's life)
local hold: { [number]: number } = {}

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.CanCollide = collide
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[ deps: { IsVIP = (Player) -> boolean (perks live AND owns VIP), AddCash = (Player, number, string) -> (),
	Notify = (Player, string, string) -> () } ]]
function VIPLounge.Start(deps: { [string]: any })
	local P = (MonetizationConfig :: any).VIPPerks
	if typeof(P) ~= "table" or P.Lounge ~= true then
		return
	end
	local old = Workspace:FindFirstChild("WE_VIPLounge")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "WE_VIPLounge"
	local cx, cz = P.LoungeX, P.LoungeZ
	local S = 24
	local H = 6
	local gold = Color3.fromRGB(212, 175, 55)
	local wall = Color3.fromRGB(58, 60, 64)
	part("Floor", Vector3.new(S, 0.4, S), CFrame.new(cx, GROUND_Y + 0.2, cz), Color3.fromRGB(40, 40, 44), Enum.Material.Marble, true, f)
	part("WallN", Vector3.new(S, H, 1), CFrame.new(cx, GROUND_Y + H * 0.5, cz - S * 0.5), wall, Enum.Material.Concrete, true, f)
	part("WallW", Vector3.new(1, H, S), CFrame.new(cx - S * 0.5, GROUND_Y + H * 0.5, cz), wall, Enum.Material.Concrete, true, f)
	part("WallE", Vector3.new(1, H, S), CFrame.new(cx + S * 0.5, GROUND_Y + H * 0.5, cz), wall, Enum.Material.Concrete, true, f)
	-- front (+Z, toward the plaza): two wall segments and the VIP door between them
	local seg = (S - 8) * 0.5
	part("WallS_L", Vector3.new(seg, H, 1), CFrame.new(cx - 4 - seg * 0.5, GROUND_Y + H * 0.5, cz + S * 0.5), wall, Enum.Material.Concrete, true, f)
	part("WallS_R", Vector3.new(seg, H, 1), CFrame.new(cx + 4 + seg * 0.5, GROUND_Y + H * 0.5, cz + S * 0.5), wall, Enum.Material.Concrete, true, f)
	local door = part("VIPDoor", Vector3.new(8, H, 0.6), CFrame.new(cx, GROUND_Y + H * 0.5, cz + S * 0.5), gold, Enum.Material.Glass, true, f)
	door.Transparency = 0.45
	door:SetAttribute("WE_VIPDoor", true)
	local pad = part("VIPPad", Vector3.new(6, 0.3, 6), CFrame.new(cx, GROUND_Y + 0.55, cz - 4), gold, Enum.Material.SmoothPlastic, false, f)
	local bb = WorldLabel.Create(pad, "VIP", {
		Name = "Label",
		Sub = "Bonus",
		Color = gold,
		Offset = Vector3.new(0, 4, 0),
		MaxDistance = 40,
	})
	bb.AlwaysOnTop = false
	f.Parent = Workspace

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		local step = acc
		acc = 0
		if pad.Parent == nil then
			return
		end
		local now = os.clock()
		for _, pl in ipairs(Players:GetPlayers()) do
			local char = pl.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local uid = pl.UserId
			if root and root:IsA("BasePart") then
				local d = root.Position - pad.Position
				if math.abs(d.X) <= 3.5 and math.abs(d.Z) <= 3.5 and d.Y < 8 and deps.IsVIP(pl) then
					hold[uid] = (hold[uid] or 0) + step
					local last = lastPaid[uid]
					if hold[uid] >= P.LoungeHoldSeconds and (last == nil or now - last >= P.LoungeCooldownSeconds) then
						lastPaid[uid] = now
						hold[uid] = 0
						deps.AddCash(pl, P.LoungeCash, "vip_lounge")
						deps.Notify(pl, "VIP bonus +$" .. tostring(P.LoungeCash), "Reward")
					end
				else
					hold[uid] = nil
				end
			else
				hold[uid] = nil
			end
		end
	end)
end

return VIPLounge
