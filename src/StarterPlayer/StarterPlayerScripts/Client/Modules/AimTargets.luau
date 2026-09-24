--!strict
--[[
	AimTargets (W2 CC-3, contracts §5.2): the CLIENT mirror of the server assist cone (CombatService/CombatAssist,
	contracts §1.3 step 3). It only feeds the camera aim help (CameraFx friction / tracking); the server stays
	authoritative and re-runs its own cone on every shot. Nothing here names a target to the server.

	API
	  Init()                               idempotent; tracks players (PlayerAdded / PlayerRemoving) and tagged NPCs
	                                       (CollectionService signals) — never a tree scan
	  InputClass() -> string               "Touch" | "Gamepad" | "KeyboardAndMouse" from UserInputService.PreferredInput
	                                       (fallback: TouchEnabled and not KeyboardEnabled = Touch)
	  HelpLevel() -> (keep, tracking)      HudConfig.AimHelp level of the current class (Off = 1, 0)
	  HelpLevelFor(cls) -> (keep, tracking) same for a given class (CameraFx, per frame)
	  SetActive(on)                        scans at AimHelp.ScanHz only while on (drawn) and the level is not Off
	  Best(camCF, weaponRange) -> (Model?, BasePart?)
	                                       the last scan's in-cone hostile with the smallest angle, re-checked against
	                                       camCF (cheap math, no allocation): per frame from CameraFx
	  IsHostile(model) -> boolean          alive player (PvP on) or combat NPC; not me, not a friendly squad unit,
	                                       not shielded (WE_ShieldUntil / ForceField), not in my vehicle, not in an
	                                       enclosed seat (WE_Exposed == false)
	  SetViewSource(fn)                    CameraFx: the camera CFrame WITHOUT shake (AimCFrame) for the scan
	  _SetClassOverride(cls?)              tests

	CONE (same numbers as the server): AimAssistConfig.Classes[class].MaxConeDeg around the camera look, range
	min(weapon Range, AimAssistConfig.MaxRangeStuds), at most AimHelp.MaxCandidates candidates and AimHelp.MaxLosRays
	line-of-sight rays per scan. Clan allies are not known on the client (no attribute in W2): the server excludes
	them from its assist; the camera may still slow over an ally (assumption A-CC3-4).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local HudConfig = require(Shared.Configs.HudConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local AimAssistConfig = require(Shared.Configs.AimAssistConfig)

local AimTargets = {}

local AH = HudConfig.AimHelp
local SCAN_HZ: number = math.clamp(tonumber(AH.ScanHz) or 10, 1, 10)
local MAX_CAND: number = math.clamp(tonumber(AH.MaxCandidates) or 8, 1, 16)
local MAX_LOS: number = math.clamp(tonumber(AH.MaxLosRays) or 2, 1, 4)
local CONE_HYSTERESIS = 1.25 -- Best() keeps the scanned target while it stays inside 1.25 x the cone
local SHIELD_ATTR = "WE_ShieldUntil"
local SQUAD_FOLDER = "WarEmpireSquads"

local player = Players.LocalPlayer

local initialized = false
local active = false
local loopRunning = false
local classOverride: string? = nil
local viewSource: (() -> CFrame)? = nil
local wantRange: number = AimAssistConfig.MaxRangeStuds

local playerList: { Player } = {}
local npcModels: { [Instance]: boolean } = {}

-- last scan result
local bestModel: Model? = nil
local bestPart: BasePart? = nil
local bestHum: Humanoid? = nil
local scanCount = 0

-- preallocated candidate arrays (a scan builds no tables)
local candModel: { Model } = {}
local candPart: { BasePart } = {}
local candHum: { Humanoid } = {}
local candCos: { number } = {}
local candN = 0

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
losParams.RespectCanCollide = true
local losFilterChar: Instance? = nil
local losFilterVeh: Instance? = nil
local losFilterSquads: Instance? = nil
local losFilterList: { Instance } = {}

---------------------------------------------------------------------------------------------------------------
-- input class
---------------------------------------------------------------------------------------------------------------

local function readPreferredInput(): any
	return (UserInputService :: any).PreferredInput
end

local function readLastInput(): any
	return UserInputService:GetLastInputType()
end

function AimTargets.InputClass(): string
	local o = classOverride
	if o then
		return o
	end
	local ok, v = pcall(readPreferredInput)
	if ok and typeof(v) == "EnumItem" then
		local name = (v :: EnumItem).Name
		if name == "Touch" or name == "Gamepad" or name == "KeyboardAndMouse" then
			return name
		end
	end
	local okL, last = pcall(readLastInput)
	if okL and typeof(last) == "EnumItem" then
		local lname = (last :: EnumItem).Name
		if string.sub(lname, 1, 7) == "Gamepad" then
			return "Gamepad"
		end
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "KeyboardAndMouse"
end

function AimTargets._SetClassOverride(cls: string?)
	classOverride = cls
end

type Level = { FrictionKeep: number, Tracking: number }

local function levelFor(cls: string): Level?
	if AH.Enabled == false then
		return nil
	end
	local name = (AH.Strength :: any)[cls]
	if type(name) ~= "string" then
		return nil
	end
	local lv = (AH.Levels :: any)[name]
	if type(lv) ~= "table" then
		return nil
	end
	return lv :: Level
end

-- (FrictionKeep, Tracking) for an input class; Off / unknown = (1, 0) = no help. Per frame from CameraFx
-- (plain table reads, no allocation).
function AimTargets.HelpLevelFor(cls: string): (number, number)
	local lv = levelFor(cls)
	if lv == nil then
		return 1, 0
	end
	return math.clamp(tonumber(lv.FrictionKeep) or 1, 0.2, 1), math.clamp(tonumber(lv.Tracking) or 0, 0, 0.5)
end

-- same for the current class
function AimTargets.HelpLevel(): (number, number)
	return AimTargets.HelpLevelFor(AimTargets.InputClass())
end

local function helpOn(): boolean
	local keep, tracking = AimTargets.HelpLevel()
	return keep < 1 or tracking > 0
end

local function coneCos(clsName: string, scale: number): number
	local cls = (AimAssistConfig.Classes :: any)[clsName]
	local deg = if type(cls) == "table" then tonumber(cls.MaxConeDeg) or 0 else 0
	return math.cos(math.rad(math.clamp(deg * scale, 0, 45)))
end

---------------------------------------------------------------------------------------------------------------
-- hostility
---------------------------------------------------------------------------------------------------------------

local function torsoOf(model: Model): BasePart?
	local t = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	if t and t:IsA("BasePart") then
		return t
	end
	return nil
end

-- the vehicle model a seat belongs to (nearest ancestor tagged WE_Vehicle, else nearest Model)
local function vehicleOf(seat: Instance): Instance?
	local p = seat.Parent
	local firstModel: Instance? = nil
	local depth = 0
	while p and p ~= Workspace and depth < 8 do
		if p:IsA("Model") then
			if CollectionService:HasTag(p, Constants.Tags.Vehicle) then
				return p
			end
			if firstModel == nil then
				firstModel = p
			end
		end
		p = p.Parent
		depth += 1
	end
	return firstModel
end

local function localHumanoid(): Humanoid?
	local ch = player.Character
	if not ch then
		return nil
	end
	return ch:FindFirstChildOfClass("Humanoid")
end

local function serverNow(): number
	local ok, t = pcall(Workspace.GetServerTimeNow, Workspace)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

local function hostileHumanoid(model: Model): Humanoid?
	if model == player.Character then
		return nil
	end
	local other = Players:GetPlayerFromCharacter(model)
	if other then
		if other == player or not GameConfig.PvPEnabled then
			return nil
		end
	else
		if typeof(model:GetAttribute("NPCId")) ~= "string" then
			return nil
		end
		if model:GetAttribute("FriendlySquad") or model:GetAttribute("OwnerUserId") then
			return nil -- squad units are never targets (same filter as CombatController / SquadOrdersService)
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	local shield = model:GetAttribute(SHIELD_ATTR)
	if typeof(shield) == "number" and shield > serverNow() then
		return nil
	end
	if model:FindFirstChildOfClass("ForceField") then
		return nil
	end
	local seat = hum.SeatPart
	if seat then
		if seat:GetAttribute("WE_Exposed") == false then
			return nil -- enclosed seat: the vehicle is the target, not the occupant
		end
		local mine = localHumanoid()
		local mySeat = if mine then mine.SeatPart else nil
		if mySeat and vehicleOf(mySeat) == vehicleOf(seat) then
			return nil -- rides in my vehicle
		end
	end
	return hum
end

function AimTargets.IsHostile(model: Model): boolean
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	return hostileHumanoid(model) ~= nil
end

---------------------------------------------------------------------------------------------------------------
-- scan (AimHelp.ScanHz, only while active)
---------------------------------------------------------------------------------------------------------------

local function viewCF(): CFrame?
	local src = viewSource
	if src then
		local ok, cf = pcall(src)
		if ok and typeof(cf) == "CFrame" then
			return cf
		end
	end
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame else nil
end

local function refreshLosFilter()
	local ch = player.Character
	local hum = localHumanoid()
	local seat = if hum then hum.SeatPart else nil
	local veh = if seat then vehicleOf(seat) else nil
	local squads = Workspace:FindFirstChild(SQUAD_FOLDER)
	if ch == losFilterChar and veh == losFilterVeh and squads == losFilterSquads then
		return
	end
	losFilterChar, losFilterVeh, losFilterSquads = ch, veh, squads
	table.clear(losFilterList)
	if ch then
		table.insert(losFilterList, ch)
	end
	if veh then
		table.insert(losFilterList, veh)
	end
	if squads then
		table.insert(losFilterList, squads)
	end
	losParams.FilterDescendantsInstances = losFilterList
end

-- scan inputs (module locals so consider() is a plain function, no closure per scan)
local scanOrigin = Vector3.zero
local scanLook = Vector3.zAxis
local scanRange = 0
local scanCos = 1
local bestConeCos = 1 -- Best()'s hysteresis cone, refreshed by every scan (no per-frame class lookups)

local function consider(model: Model)
	local hum = hostileHumanoid(model)
	if not hum then
		return
	end
	local part = torsoOf(model)
	if not part then
		return -- streamed out / not built yet
	end
	local v = part.Position - scanOrigin
	local dist = v.Magnitude
	if not (dist > 0.05 and dist <= scanRange) then
		return
	end
	local c = scanLook:Dot(v) / dist
	if not (c > 0 and c >= scanCos) then
		return
	end
	-- keep the MAX_CAND candidates closest to the view centre (largest cosine)
	local slot = 0
	if candN < MAX_CAND then
		candN += 1
		slot = candN
	else
		local worst = 1
		for k = 2, candN do
			if candCos[k] < candCos[worst] then
				worst = k
			end
		end
		if candCos[worst] >= c then
			return
		end
		slot = worst
	end
	candModel[slot] = model
	candPart[slot] = part
	candHum[slot] = hum
	candCos[slot] = c
end

local function clearBest()
	bestModel, bestPart, bestHum = nil, nil, nil
end

local function scan()
	scanCount += 1
	candN = 0
	local cf = viewCF()
	if not cf or not helpOn() then
		clearBest()
		return
	end
	scanOrigin = cf.Position
	scanLook = cf.LookVector
	scanRange = math.max(0, math.min(wantRange, AimAssistConfig.MaxRangeStuds))
	local cls = AimTargets.InputClass()
	scanCos = coneCos(cls, 1)
	bestConeCos = coneCos(cls, CONE_HYSTERESIS)
	if GameConfig.PvPEnabled then
		for _, other in ipairs(playerList) do
			local ch = other.Character
			if other ~= player and ch and ch.Parent then
				consider(ch)
			end
		end
	end
	for inst in pairs(npcModels) do
		if inst.Parent == nil then
			npcModels[inst] = nil
		elseif inst:IsA("Model") then
			consider(inst)
		end
	end
	local n = candN
	local found = false
	if n > 0 then
		refreshLosFilter()
		for _ = 1, math.min(n, MAX_LOS) do
			local best = 0
			for k = 1, n do
				if candCos[k] > -2 and (best == 0 or candCos[k] > candCos[best]) then
					best = k
				end
			end
			if best == 0 then
				break
			end
			candCos[best] = -3 -- taken
			local part = candPart[best]
			local dir = part.Position - scanOrigin
			local hit = Workspace:Raycast(scanOrigin, dir, losParams)
			if hit == nil or hit.Instance:IsDescendantOf(candModel[best]) then
				bestModel, bestPart, bestHum = candModel[best], part, candHum[best]
				found = true
				break
			end
		end
	end
	if not found then
		clearBest()
	end
	-- drop instance references until the next scan
	table.clear(candModel)
	table.clear(candPart)
	table.clear(candHum)
	candN = 0
end

local function onScanError(err: any)
	warn("[AimTargets] scan failed:", err)
end

local function startLoop()
	if loopRunning then
		return
	end
	loopRunning = true
	task.spawn(function()
		local period = 1 / SCAN_HZ
		while active and helpOn() do
			if not xpcall(scan, onScanError) then
				clearBest()
			end
			task.wait(period)
		end
		loopRunning = false
		clearBest()
	end)
end

function AimTargets.SetActive(on: boolean)
	active = on == true
	if active and helpOn() then
		startLoop()
	elseif not active then
		clearBest()
	end
end

function AimTargets.IsActive(): boolean
	return active
end

function AimTargets.Best(camCF: CFrame, weaponRange: number): (Model?, BasePart?)
	if type(weaponRange) == "number" and weaponRange > 0 then
		wantRange = weaponRange
	end
	if not active then
		return nil, nil
	end
	local m, p, h = bestModel, bestPart, bestHum
	if m == nil or p == nil or h == nil then
		return nil, nil
	end
	if m.Parent == nil or p.Parent == nil or h.Health <= 0 then
		clearBest()
		return nil, nil
	end
	local v = p.Position - camCF.Position
	local dist = v.Magnitude
	local range = math.min(wantRange, AimAssistConfig.MaxRangeStuds) * 1.1
	if not (dist > 0.05 and dist <= range) then
		return nil, nil
	end
	local c = camCF.LookVector:Dot(v) / dist
	if not (c > 0 and c >= bestConeCos) then
		return nil, nil
	end
	return m, p
end

function AimTargets.SetViewSource(fn: (() -> CFrame)?)
	viewSource = fn
end

-- tests
function AimTargets._ScanNow()
	scan()
end

function AimTargets._ScanCount(): number
	return scanCount
end

---------------------------------------------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------------------------------------------

local function trackNpc(inst: Instance)
	if inst:IsA("Model") then
		npcModels[inst] = true
	end
end

function AimTargets.Init()
	if initialized then
		return
	end
	initialized = true
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(playerList, p)
	end
	Players.PlayerAdded:Connect(function(p: Player)
		if not table.find(playerList, p) then
			table.insert(playerList, p)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		local i = table.find(playerList, p)
		if i then
			table.remove(playerList, i)
		end
	end)
	local tag = Constants.Tags.NPC
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		trackNpc(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(trackNpc)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		npcModels[inst] = nil
	end)
end

return AimTargets
