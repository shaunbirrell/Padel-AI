--!strict
--[[
	AudioHooks (W1 SND): turns EXISTING remotes and client signals into AudioController cues. It only listens: it never
	fires a remote, never writes another controller's state and needs no edit in Missile / Vehicle / Combat or any
	other controller. Keys and ids: Shared/Configs/SoundConfig.luau (Hooks table).

	  Notification            payload.Type (after NotificationConfig.Rewrite) → the key NotificationController's own
	                          PlayNotification plays for that line (SetNextNotificationKey), so a dropped / throttled
	                          line stays silent and a shown line makes exactly one sound. A HudConfig.Toast.Reroute rule
	                          with AlertSeconds ("BASE UNDER ATTACK!" banner) types that ping as Hooks.AlertReroute.
	  HudLayout.CashFloatRequested  +amount → Cash.Collect · −amount → Cash.Purchase
	  PurchaseResult          Ok → Cash.Purchase · not Ok → UI.Denied
	  TerritoryStateUpdate    diffs: my capture starts → Capture.Start · a zone becomes mine → Capture.Secured ·
	                          a zone stops being mine → Capture.Lost (the first payload is the baseline: silent)
	  AtmRaidStateUpdate      Phase "Alarm" (I am being robbed) → Alarm.Raid (1 s pushes; the key cooldown spaces it)
	  MissileStrikeFx         I am the victim → Alarm.Missile (the real siren), once per StrikeId; MissileController's
	                          own click siren (SoundService."WE_MissileSiren") is muted by name when that key is valid
	  XPUpdate                LevelUp → Level.Up
	  Humanoid.SeatPart       a vehicle seat → the "Engine" loop; its pitch follows the chassis speed, sampled at
	                          Engine.SampleHz (10 Hz) — the only periodic audio work while seated
	  HudLayout flags         Drawn AND Hurt (not Dead) → "Music" channel = combat layer; back to the base theme
	                          Music.CombatHoldSeconds after it clears
	  Ambience                ONE loop: desert wind, or surf within Ambience.NearWaterStuds of a WE_Water part
	                          (checked every Ambience.CheckSeconds, not per frame)

	Every handler is pcall-guarded: a bad payload can never break the remote's other listeners.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local SoundConfig = require(Shared.Configs.SoundConfig)
local NotificationConfig = require(Shared.Configs.NotificationConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local AudioController = require(script.Parent.AudioController)
local HudLayout = require(script.Parent.HudLayout)

local Hooks = SoundConfig.Hooks

local AudioHooks = {}

local initDone = false

local function guard(name: string, fn: (...any) -> ()): (...any) -> ()
	return function(...: any)
		local ok, err = pcall(fn :: any, ...)
		if not ok then
			warn("[AudioHooks] " .. name .. " failed:", err)
		end
	end
end

local function myUserId(): number
	local lp = Players.LocalPlayer
	return if lp then lp.UserId else -1
end

---------------------------------------------------------------------------------------------------------------
-- Notification remote
---------------------------------------------------------------------------------------------------------------

local function onNotification(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local text = if type(payload.Message) == "string" then payload.Message else ""
	local t = if type(payload.Type) == "string" then payload.Type else "Info"
	-- same first-match Rewrite NotificationController applies (it can change the type, e.g. LEVEL → Reward)
	for _, rule in ipairs(NotificationConfig.Rewrite) do
		if string.find(text, rule.Match) then
			if rule.Type then
				t = rule.Type
			end
			break
		end
	end
	-- same first-match Reroute: an Alert rule ("DEF HIT" → the BASE UNDER ATTACK! banner) pings through
	-- NotificationController.ShowAlert, and only when the rule's MinGapSeconds lets the banner show
	local key: string? = nil
	for _, rule in ipairs(HudConfig.Toast.Reroute) do
		if string.find(text, rule.Match) then
			if rule.AlertSeconds and rule.AlertSeconds > 0 then
				key = Hooks.AlertReroute
			elseif rule.Type then
				t = rule.Type
			end
			break
		end
	end
	key = key or Hooks.NotificationTypes[t]
	if key then
		AudioController.SetNextNotificationKey(key)
	end
end

---------------------------------------------------------------------------------------------------------------
-- cash float + purchase results + level up + raid alarm
---------------------------------------------------------------------------------------------------------------

local function onCashFloat(amount: any)
	if type(amount) ~= "number" or amount ~= amount or amount == 0 then
		return
	end
	AudioController.Play(if amount > 0 then Hooks.CashGain else Hooks.CashSpend)
end

local function onPurchaseResult(payload: any)
	if type(payload) ~= "table" then
		return
	end
	AudioController.Play(if payload.Ok == true then Hooks.PurchaseOk else Hooks.PurchaseFail)
end

local function onXP(payload: any)
	if type(payload) == "table" and payload.LevelUp == true then
		AudioController.Play(Hooks.LevelUp)
	end
end

local function onAtmRaid(payload: any)
	if type(payload) == "table" and payload.Phase == Hooks.RaidAlarmPhase then
		AudioController.Play(Hooks.RaidAlarm)
	end
end

---------------------------------------------------------------------------------------------------------------
-- territory diffs
---------------------------------------------------------------------------------------------------------------

local territoryBaseline = false
local mine: { [string]: boolean } = {}
local capturingId: string? = nil

local function onTerritory(payload: any)
	if type(payload) ~= "table" or type(payload.Territories) ~= "table" then
		return
	end
	local me = myUserId()
	local nowMine: { [string]: boolean } = {}
	local secured, lost = false, false
	for _, e in ipairs(payload.Territories) do
		if type(e) == "table" and type(e.Id) == "string" then
			local owned = tonumber(e.OwnerUserId) == me and e.OwnerType ~= "Neutral" and e.OwnerType ~= "NPC"
			if owned then
				nowMine[e.Id] = true
				if not mine[e.Id] then
					secured = true
				end
			elseif mine[e.Id] then
				lost = true
			end
		end
	end
	local lc = payload.LocalCapture
	local capId: string? = nil
	if type(lc) == "table" and lc.Capturing == true and type(lc.TerritoryId) == "string" then
		capId = lc.TerritoryId
	end
	local started = capId ~= nil and capId ~= capturingId and not nowMine[capId :: string]
	mine = nowMine
	capturingId = capId
	if not territoryBaseline then
		territoryBaseline = true -- join / first push: what I already own is not news
		return
	end
	-- one cue per push (a push that both secures and loses is rare; the bigger news wins)
	if secured then
		AudioController.Play(Hooks.CaptureSecured)
	elseif lost then
		AudioController.Play(Hooks.CaptureLost)
	elseif started then
		AudioController.Play(Hooks.CaptureStart)
	end
end

---------------------------------------------------------------------------------------------------------------
-- missile strike (victim siren)
---------------------------------------------------------------------------------------------------------------

local seenStrikes: { [number]: boolean } = {}
local seenCount = 0

local function serverNow(): number
	local ok, t = pcall(function(): number
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

local function onMissileFx(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if tonumber(payload.VictimUserId) ~= myUserId() then
		return
	end
	local id = tonumber(payload.StrikeId)
	if id == nil or seenStrikes[id] then
		return
	end
	seenCount += 1
	if seenCount > 256 then
		seenStrikes = {}
		seenCount = 1
	end
	seenStrikes[id] = true
	local launch = tonumber(payload.LaunchTime)
	local flight = tonumber(payload.FlightSeconds)
	if launch and flight and serverNow() > launch + flight + Hooks.MissileLateSeconds then
		return -- late joiner: the strike is already over
	end
	AudioController.Play(Hooks.MissileVictim)
end

-- MissileController plays its own click "siren" (a Sound named WE_MissileSiren in SoundService). The victim hears
-- the licensed siren from onMissileFx instead, so that click is silenced here — no edit to MissileController.
local function onSoundServiceChild(child: Instance)
	local name = Hooks.LegacyMissileSirenName
	if name == "" or child.Name ~= name or not child:IsA("Sound") then
		return
	end
	if AudioController.HasSound(Hooks.MissileVictim) then
		(child :: Sound).Volume = 0
	end
end

---------------------------------------------------------------------------------------------------------------
-- engine loop (Humanoid.SeatPart)
---------------------------------------------------------------------------------------------------------------

type Profile = SoundConfig.EngineProfile

local engineToken = 0

local function vehicleModelOf(seat: Instance): Model?
	local m = seat:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:GetAttribute("WE_Category") ~= nil or CollectionService:HasTag(m, Constants.Tags.Vehicle) then
			return m
		end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

-- profile + max speed for a seat; nil = not a vehicle (a bench or a chair)
local function engineFor(seat: Instance): (Profile?, number)
	local E = SoundConfig.Engine
	local model = vehicleModelOf(seat)
	if model == nil then
		if seat:IsA("VehicleSeat") then
			return E.Default, E.DefaultMaxSpeed
		end
		return nil, E.DefaultMaxSpeed
	end
	local maxSpeed = tonumber(model:GetAttribute("WE_MaxSpeed")) or E.DefaultMaxSpeed
	if maxSpeed <= 0 then
		maxSpeed = E.DefaultMaxSpeed
	end
	local family = model:GetAttribute("WE_KitFamily")
	if type(family) == "string" then
		for _, f in ipairs(E.Families) do
			if string.sub(family, 1, #f.Prefix) == f.Prefix then
				return { Key = f.Key, PitchMin = f.PitchMin, PitchMax = f.PitchMax }, maxSpeed
			end
		end
	end
	local cat = model:GetAttribute("WE_Category")
	if type(cat) == "string" and E.Categories[cat] then
		return E.Categories[cat], maxSpeed
	end
	return E.Default, maxSpeed
end

local function stopEngine()
	engineToken += 1
	AudioController.Loop("Engine", nil)
end

local function speedOf(seat: BasePart): number
	local v: any = nil
	pcall(function()
		v = seat.AssemblyLinearVelocity
	end)
	if typeof(v) == "Vector3" then
		local m = (v :: Vector3).Magnitude
		if m == m then
			return m
		end
	end
	return 0
end

local function startEngine(seat: BasePart)
	local profile, maxSpeed = engineFor(seat)
	if profile == nil then
		stopEngine()
		return
	end
	engineToken += 1
	local token = engineToken
	local p = profile :: Profile
	AudioController.Loop("Engine", p.Key)
	AudioController.SetLoopPitch("Engine", p.PitchMin)
	local dt = 1 / math.max(1, SoundConfig.Engine.SampleHz)
	task.spawn(function()
		while token == engineToken do
			task.wait(dt)
			if token ~= engineToken then
				break
			end
			if seat.Parent == nil then
				stopEngine()
				break
			end
			local frac = math.clamp(speedOf(seat) / maxSpeed, 0, 1)
			AudioController.SetLoopPitch("Engine", p.PitchMin + (p.PitchMax - p.PitchMin) * frac)
		end
	end)
end

local function onSeatPart(seat: Instance?)
	if seat ~= nil and seat:IsA("BasePart") then
		startEngine(seat)
	else
		stopEngine()
	end
end

local humConns: { RBXScriptConnection } = {}

local function clearHumanoid()
	for _, c in ipairs(humConns) do
		c:Disconnect()
	end
	table.clear(humConns)
end

local function bindHumanoid(hum: Humanoid)
	onSeatPart(hum.SeatPart)
	table.insert(humConns, hum:GetPropertyChangedSignal("SeatPart"):Connect(guard("SeatPart", function()
		onSeatPart(hum.SeatPart)
	end)))
	table.insert(humConns, hum.Died:Connect(guard("Died", function()
		stopEngine()
	end)))
end

local function bindCharacter(char: Model)
	clearHumanoid()
	stopEngine()
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		bindHumanoid(hum)
		return
	end
	local conn: RBXScriptConnection? = nil
	conn = char.ChildAdded:Connect(guard("CharacterChild", function(c: Instance)
		if c:IsA("Humanoid") then
			if conn then
				conn:Disconnect()
			end
			bindHumanoid(c)
		end
	end))
	if conn then
		table.insert(humConns, conn)
	end
end

---------------------------------------------------------------------------------------------------------------
-- music layer (HudLayout flags)
---------------------------------------------------------------------------------------------------------------

local combatOn = false
local combatToken = 0

local function evalCombat()
	local M = SoundConfig.Music
	local want = HudLayout.GetFlag("Drawn") and HudLayout.GetFlag("Hurt") and not HudLayout.GetFlag("Dead")
	if want then
		combatToken += 1
		if not combatOn then
			combatOn = true
			AudioController.Loop("Music", M.Combat, M.FadeSeconds)
		end
		return
	end
	if not combatOn then
		return
	end
	combatToken += 1
	local token = combatToken
	local hold = if HudLayout.GetFlag("Dead") then 0 else M.CombatHoldSeconds
	task.delay(hold, function()
		if token == combatToken and combatOn then
			combatOn = false
			AudioController.Loop("Music", M.Base, M.FadeSeconds)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- ambience (one loop: wind, or surf near WE_Water)
---------------------------------------------------------------------------------------------------------------

local waterParts: { BasePart } = {}
local nearWaterNow = false

local function addWater(inst: Instance)
	if inst:IsA("BasePart") and not table.find(waterParts, inst) then
		table.insert(waterParts, inst)
	end
end

local function removeWater(inst: Instance)
	local i = table.find(waterParts, inst :: any)
	if i then
		table.remove(waterParts, i)
	end
end

local function waterWithin(pos: Vector3, studs: number): boolean
	local r2 = studs * studs
	for _, p in ipairs(waterParts) do
		if p.Parent then
			local lp = p.CFrame:PointToObjectSpace(pos)
			local hs = p.Size * 0.5
			local dx = math.max(math.abs(lp.X) - hs.X, 0)
			local dz = math.max(math.abs(lp.Z) - hs.Z, 0)
			if dx * dx + dz * dz <= r2 then
				return true
			end
		end
	end
	return false
end

local function ear(): Vector3?
	local cam = Workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	return nil
end

local function checkAmbience()
	local A = SoundConfig.Ambience
	local pos = ear()
	if pos then
		if nearWaterNow then
			nearWaterNow = waterWithin(pos, A.LeaveWaterStuds)
		else
			nearWaterNow = waterWithin(pos, A.NearWaterStuds)
		end
	end
	AudioController.Loop("Ambience", if nearWaterNow then A.NearWater else A.Default, A.FadeSeconds)
end

---------------------------------------------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------------------------------------------

function AudioHooks.Init()
	if initDone then
		return
	end
	initDone = true
	AudioController.Init()

	local R = Constants.RemoteNames
	Remotes.BindEvent(R.Notification, guard("Notification", onNotification))
	Remotes.BindEvent(R.PurchaseResult, guard("PurchaseResult", onPurchaseResult))
	Remotes.BindEvent(R.TerritoryStateUpdate, guard("TerritoryStateUpdate", onTerritory))
	Remotes.BindEvent(R.AtmRaidStateUpdate, guard("AtmRaidStateUpdate", onAtmRaid))
	Remotes.BindEvent(R.MissileStrikeFx, guard("MissileStrikeFx", onMissileFx))
	Remotes.BindEvent(R.XPUpdate, guard("XPUpdate", onXP))
	HudLayout.CashFloatRequested:Connect(guard("CashFloat", onCashFloat))
	HudLayout.FlagChanged:Connect(guard("FlagChanged", function(name: string, _on: boolean)
		if name == "Drawn" or name == "Hurt" or name == "Dead" then
			evalCombat()
		end
	end))
	SoundService.ChildAdded:Connect(guard("SoundServiceChild", onSoundServiceChild))

	local lp = Players.LocalPlayer
	if lp then
		if lp.Character then
			guard("Character", bindCharacter)(lp.Character)
		end
		lp.CharacterAdded:Connect(guard("CharacterAdded", bindCharacter))
		lp.CharacterRemoving:Connect(guard("CharacterRemoving", function()
			clearHumanoid()
			stopEngine()
		end))
	end

	local tag = Constants.Tags.Water
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		addWater(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(addWater)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeWater)
	guard("Ambience", checkAmbience)()
	task.spawn(function()
		while true do
			task.wait(SoundConfig.Ambience.CheckSeconds)
			guard("Ambience", checkAmbience)()
		end
	end)
end

return AudioHooks
