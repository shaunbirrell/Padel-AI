--!strict
--[[
	claude-bud JOB 33 (2026-09-30): the NUCLEAR SILO's nukes (RebirthZonesConfig.Nuke + .Zones.StrategicYard, NukeConfig
	for the blast radius / countdown / new-player protection). Server-authoritative; RebirthConfig.LiveFor(player, "Nuke")
	and the silo (Strategic Yard zone, reached at Rebirth 2) built to level >= 1.

	CHARGE: profile.NukeSilo = { Ready, ChargeFrom }. Warheads charge one at a time, SiloChargeMinutes each, up to
	  SiloCapacity (both by silo level). RUSH finishes the current one for RushCashPerMinute x the minutes left
	  (EconomyService.SpendCash "nuke_rush", no purchase XP).
	PANEL: the silo console's NUKE prompt calls OpenPanel -> FeaturePush "NukePanel":
	  { Ready, Cap, ChargeLeft, RushCost, CooldownLeft, Targets = { { Id, Name } } }.
	LAUNCH (RequestNuke "launch" <targetId>), re-checked here:
	  * Ready >= 1, the player cooldown and the server cooldown are over;
	  * the target is one of Targets(): the Central Plaza, an outpost, an enemy site, each >= BaseClearStuds from EVERY
	    base, so a base is never nuked and no base can be one-shotted.
	  Then FeaturePush "NukeIncoming" { Name, X, Z, Radius, Seconds } to everyone (the siren + countdown), and after
	  CountdownSeconds one CombatService.ApplyRadiusDamage(attacker, centre, Radius, Damage, { WeaponId = "Nuke",
	  MinMult }). That is THE shared PvP rule: novice shields, spawn protection, clan allies and pvp-off are respected, and
	  NPCs are hit. Then FeaturePush "NukeBlast" to everyone (the flash).
	Analytics NUKE_LAUNCH / NUKE_DETONATE. Kill switch: RebirthConfig.Live.Parts.Nuke (and the zones).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RebirthConfig = require(Shared.Configs.RebirthConfig)
local RebirthZonesConfig = require(Shared.Configs.RebirthZonesConfig)
local NukeConfig = require(Shared.Configs.NukeConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local NukeService = {}

local deps: { [string]: any } = {}
local N = RebirthZonesConfig.Nuke
local SILO = RebirthZonesConfig.Zones.StrategicYard
local serverLastLaunch = -math.huge -- os.clock(); the player cooldown is saved (profile.NukeLastLaunch, os.time())
local busy = false -- one nuke in the air at a time

local function live(uid: number): boolean
	return RebirthConfig.LiveFor(uid, "Nuke")
end

local function siloLevel(player: Player): number
	local rz = deps.RebirthZoneService
	return if rz and rz.SiloLevel then rz.SiloLevel(player) else 0
end

local function pick(list: { number }?, level: number): number
	if list == nil or level < 1 then
		return 0
	end
	return tonumber(list[math.min(level, #list)]) or 0
end

local function radius(): number
	local k: any = NukeConfig.Kinds and (NukeConfig.Kinds :: any).Nuke
	return tonumber(k and k.Radius) or 150
end

local function countdown(): number
	return math.clamp(tonumber((NukeConfig :: any).CountdownSeconds) or 10, 5, 30)
end

-- pure charge step: returns the new (ready, chargeFrom) at `now` for capacity `cap` and `secs` per warhead
function NukeService.Charge(ready: number, chargeFrom: number, now: number, cap: number, secs: number): (number, number)
	if cap <= 0 or secs <= 0 then
		return math.min(ready, math.max(cap, 0)), 0
	end
	if ready >= cap then
		return cap, 0
	end
	if chargeFrom <= 0 then
		return ready, now
	end
	local n = math.floor((now - chargeFrom) / secs)
	if n > 0 then
		ready = math.min(cap, ready + n)
		chargeFrom = if ready >= cap then 0 else chargeFrom + n * secs
	end
	return ready, chargeFrom
end

local function silo(player: Player, profile: any): (number, number, number) -- ready, cap, charge seconds left
	local lv = siloLevel(player)
	local cap = math.floor(pick(SILO.SiloCapacity, lv))
	local secs = pick(SILO.SiloChargeMinutes, lv) * 60
	local s = if typeof(profile.NukeSilo) == "table" then profile.NukeSilo else { Ready = 0, ChargeFrom = 0 }
	local ready, from = NukeService.Charge(math.max(0, math.floor(tonumber(s.Ready) or 0)), tonumber(s.ChargeFrom) or 0, os.time(), cap, secs)
	profile.NukeSilo = { Ready = ready, ChargeFrom = from }
	local left = if ready < cap and from > 0 then math.max(0, math.ceil(from + secs - os.time())) else 0
	return ready, cap, left
end

-- the targets: the Central Plaza, the outposts, the enemy sites, each far from every base
function NukeService.Targets(): { { Id: string, Name: string, Pos: Vector3 } }
	local out: { { Id: string, Name: string, Pos: Vector3 } } = {}
	local function farFromBases(p: Vector3): boolean
		for plotId = 1, BaseConfig.MaxPlots do
			local ok, pp = pcall(PlotFrame.PlotPosition, plotId)
			if ok and typeof(pp) == "Vector3" and (Vector3.new(pp.X, 0, pp.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < N.BaseClearStuds then
				return false
			end
		end
		return true
	end
	local function add(id: string, name: string, p: Vector3)
		if #out < N.MaxTargets and farFromBases(p) then
			table.insert(out, { Id = id, Name = name, Pos = p })
		end
	end
	add("Plaza", "Central Plaza", Vector3.new(0, 1, 0))
	local ids: { string } = {}
	for id, def in pairs(TerritoryConfig.Territories) do
		if def.IsStarter ~= true and id ~= "CentralPlaza" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local def = TerritoryConfig.Territories[id]
		add("Out:" .. id, tostring(def.DisplayName), def.Position)
	end
	local okW, WS = pcall(function(): any
		return require(script.Parent.Parent.Modules.WorldSites)
	end)
	if okW and WS and WS.List then
		for _, st in ipairs(WS.List()) do
			if st.Kind == "camp" or st.Kind == "overwatch" or st.Kind == "tankyard" then
				add("Site:" .. st.Id, st.Name, Vector3.new(st.X, st.Y or 1, st.Z))
			end
		end
	end
	return out
end

local function push(player: Player, kind: string, data: any)
	local ev = deps.RemoteSetup and deps.RemoteSetup.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, kind, data)
	end
end

local function pushAll(kind: string, data: any)
	for _, p in ipairs(Players:GetPlayers()) do
		push(p, kind, data)
	end
end

local function cooldownLeft(profile: any): number
	local last = tonumber(profile and profile.NukeLastLaunch) or 0
	local mine = if last > 0 then N.PlayerCooldownSeconds - (os.time() - last) else 0
	local server = N.ServerCooldownSeconds - (os.clock() - serverLastLaunch)
	return math.max(0, math.ceil(math.max(mine, server)))
end

function NukeService.OpenPanel(player: Player)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not live(player.UserId) or siloLevel(player) < 1 then
		return
	end
	local ready, cap, left = silo(player, profile)
	local targets = {}
	for _, t in ipairs(NukeService.Targets()) do
		table.insert(targets, { Id = t.Id, Name = t.Name })
	end
	push(player, "NukePanel", {
		Ready = ready,
		Cap = cap,
		ChargeLeft = left,
		RushCost = if left > 0 then math.ceil(left / 60) * N.RushCashPerMinute else 0,
		CooldownLeft = cooldownLeft(profile),
		Targets = targets,
	})
end

function NukeService.Rush(player: Player): boolean
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not live(player.UserId) or siloLevel(player) < 1 then
		return false
	end
	local ready, cap, left = silo(player, profile)
	if ready >= cap or left <= 0 then
		return false
	end
	local cost = math.ceil(left / 60) * N.RushCashPerMinute
	local ok = deps.EconomyService.SpendCash(player, cost, "nuke_rush")
	if not ok then
		return false
	end
	profile.NukeSilo = { Ready = math.min(cap, ready + 1), ChargeFrom = if ready + 1 >= cap then 0 else os.time() }
	deps.DataService.MarkDirty(player)
	NukeService.OpenPanel(player)
	return true
end

function NukeService.Launch(player: Player, targetId: any): (boolean, string?)
	local uid = player.UserId
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not live(uid) or siloLevel(player) < 1 or typeof(targetId) ~= "string" then
		return false, "Off"
	end
	if busy then
		return false, "Busy"
	end
	if cooldownLeft(profile) > 0 then
		return false, "Cooldown"
	end
	local ready = silo(player, profile)
	if ready < 1 then
		return false, "NotReady"
	end
	local target: { Id: string, Name: string, Pos: Vector3 }? = nil
	for _, t in ipairs(NukeService.Targets()) do
		if t.Id == targetId then
			target = t
		end
	end
	if target == nil then
		return false, "BadTarget"
	end
	local tg = target :: { Id: string, Name: string, Pos: Vector3 }
	-- spend the warhead and start both cooldowns before anything yields
	local s = profile.NukeSilo
	profile.NukeSilo = { Ready = ready - 1, ChargeFrom = if (tonumber(s.ChargeFrom) or 0) > 0 then s.ChargeFrom else os.time() }
	deps.DataService.MarkDirty(player)
	profile.NukeLastLaunch = os.time() -- saved: a rejoin never resets the player cooldown
	serverLastLaunch = os.clock()
	busy = true
	local R = radius()
	local secs = countdown()
	pushAll("NukeIncoming", { Name = tg.Name, X = tg.Pos.X, Z = tg.Pos.Z, Radius = R, Seconds = secs, Siren = N.SirenSoundId })
	if deps.AnalyticsService then
		pcall(deps.AnalyticsService.Log, "NUKE_LAUNCH", uid, { target = tg.Id })
	end
	task.delay(secs, function()
		busy = false
		local cs = deps.CombatService
		local res: any = nil
		if cs and cs.ApplyRadiusDamage then
			local okD, r = pcall(cs.ApplyRadiusDamage, if player.Parent then player else nil, tg.Pos, R, N.Damage, {
				WeaponId = "Nuke",
				MinMult = N.MinMult,
				RequireLos = false,
			})
			res = if okD then r else nil
		end
		pushAll("NukeBlast", { X = tg.Pos.X, Z = tg.Pos.Z, Radius = R })
		if deps.AnalyticsService and res then
			pcall(deps.AnalyticsService.Log, "NUKE_DETONATE", uid, { target = tg.Id, players = res.Players, npcs = res.Npcs, killed = res.Killed })
		end
	end)
	return true, nil
end

function NukeService.Init(d: { [string]: any })
	deps = d
	local remote = d.RemoteSetup.Get(Constants.RemoteNames.RequestNuke) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, action: any, targetId: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestNuke", action, targetId) then
			return
		end
		if d.RateLimitService and not d.RateLimitService.Allow(player, "nuke", 1, 2) then
			return
		end
		if action == "panel" then
			NukeService.OpenPanel(player)
		elseif action == "rush" then
			NukeService.Rush(player)
		elseif action == "launch" then
			local ok, why = NukeService.Launch(player, targetId)
			if not ok and d.NotificationService then
				local copy = ({ Cooldown = "The silo is cooling down", NotReady = "No warhead ready yet", Busy = "A nuke is already in the air", BadTarget = "That target is too close to a base" } :: { [string]: string })[why or ""]
				if copy then
					pcall(d.NotificationService.Notify, player, copy, "Warn", 4)
				end
			end
			NukeService.OpenPanel(player)
		end
	end)
	print("[WAR EMPIRE] NukeService Init")
end

return NukeService
