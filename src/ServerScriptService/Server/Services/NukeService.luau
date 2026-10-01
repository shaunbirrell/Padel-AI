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
local Workspace = game:GetService("Workspace")

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

-- claude-bud JOB 39 phase 5: the Tactical Warhead (EndgameService's one purchase path pays; this only loads the slot)
function NukeService.CanFillSlot(player: Player): boolean
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not live(player.UserId) or siloLevel(player) < 1 then
		return false
	end
	local ready, cap = silo(player, profile)
	return ready < cap
end

function NukeService.FillSlot(player: Player): boolean
	if not NukeService.CanFillSlot(player) then
		return false
	end
	local profile = deps.DataService.GetProfile(player)
	local ready, cap = silo(player, profile)
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
	-- claude-bud JOB 39 phase 5: a held Heavy Warhead rides on this launch (x1.3 radius, x1.2 damage; x1 while not live)
	local heavyDmg = 1
	do
		local okE, EGS = pcall(function(): any
			return require(script.Parent.EndgameService)
		end)
		if okE and EGS and EGS.HeavyWarheadMults then
			local rm, dm, held = EGS.HeavyWarheadMults(player)
			if held then
				R *= rm
				heavyDmg = dm
				pcall(EGS.SpendHeavy, player)
			end
		end
		if okE and EGS and EGS.NoteContract then
			pcall(EGS.NoteContract, player, "Warhead", 1)
		end
	end
	local secs = countdown()
	pushAll("NukeIncoming", { Name = tg.Name, X = tg.Pos.X, Z = tg.Pos.Z, Radius = R, Seconds = secs, Siren = N.SirenSoundId })
	if deps.AnalyticsService then
		pcall(deps.AnalyticsService.Log, "NUKE_LAUNCH", uid, { target = tg.Id })
	end
	-- claude-bud JOB 34: the profile's existing launch counter (NukeStats.Launched) + the "LAUNCHED A NUKE" achievement
	if typeof(profile.NukeStats) == "table" then
		profile.NukeStats.Launched = (tonumber(profile.NukeStats.Launched) or 0) + 1
	end
	if deps.AchievementService and deps.AchievementService.Check then
		pcall(deps.AchievementService.Check, player)
	end
	task.delay(secs, function()
		busy = false
		local cs = deps.CombatService
		local res: any = nil
		if cs and cs.ApplyRadiusDamage then
			local okD, r = pcall(cs.ApplyRadiusDamage, if player.Parent then player else nil, tg.Pos, R, N.Damage * heavyDmg, {
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

-- ── claude-bud JOB 65: the NUKE INSTANT RAID (RebirthZonesConfig.NukeRaid) ─────────────────────────────────────────
local NR: any = (RebirthZonesConfig :: any).NukeRaid

function NukeService.RaidLive(uid: number): boolean
	return live(uid) and typeof(NR) == "table" and (require(Shared.Configs.RetentionConfig) :: any).Live(NR, uid)
end

local function raidCooldownLeft(profile: any): number
	local last = tonumber(profile and profile.NukeLastLaunch) or 0
	return if last > 0 then math.max(0, math.ceil(NR.CooldownSeconds - (os.time() - last))) else 0
end

local function isAdmin(p: Player): boolean
	local a = deps.AdminService
	if a and a.IsAdmin then
		local ok, v = pcall(a.IsAdmin, p)
		return ok and v == true
	end
	return false
end

--[[ May `player` nuke the base `plotId` now? Returns (ok, why, info). Every rule is server-side; info carries what the
	preview card shows: Name, Level, Amount (the FULL raidable ATM, the exact number a launch moves), CooldownLeft. ]]
function NukeService.RaidVerdict(player: Player, plotId: any): (boolean, string, any)
	local info: any = { PlotId = tonumber(plotId) or 0, Name = "?", Level = 0, Amount = 0, CooldownLeft = 0 }
	local uid = player.UserId
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not NukeService.RaidLive(uid) then
		return false, "Off", info
	end
	if siloLevel(player) < 1 then
		return false, "NoSilo", info
	end
	local pid = tonumber(plotId)
	local bs = deps.BaseService
	local ownerId = if pid and bs and bs.GetOwnerUserId then bs.GetOwnerUserId(pid) else nil
	local victim = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	if victim == nil or pid == nil then
		return false, "NoBase", info
	end
	local vProfile = deps.DataService.GetProfile(victim)
	info.Name = victim.DisplayName
	info.Level = math.floor(tonumber(vProfile and vProfile.Level) or 0)
	local mc = deps.MoneyCollectorService
	info.Amount = if mc and mc.GetRaidableBalance then math.max(0, math.floor(tonumber(mc.GetRaidableBalance(victim)) or 0)) else 0
	info.CooldownLeft = raidCooldownLeft(profile)
	local T = NR.Targets
	if victim == player then
		return false, "Self", info
	end
	if not T.Admins and isAdmin(victim) then
		return false, "Admin", info
	end
	local gd = deps.GateDefenseService
	if not T.Allies and gd and gd.IsAlly and gd.IsAlly(victim.UserId, player) == true then
		return false, "Ally", info
	end
	local cs = deps.CombatService
	if not T.Shielded and cs and cs.ProtectedReason then
		local okP, why = pcall(cs.ProtectedReason, victim) -- the ONE protection rule: spawn / novice shield
		if okP and why ~= nil then
			return false, "Protected", info
		end
	end
	if not T.CampCooldown then
		local okA, left = pcall(function()
			return (require(script.Parent.AntiCampService) :: any).CooldownLeft(uid, pid)
		end)
		if okA and typeof(left) == "number" and left > 0 then
			return false, "CampCooldown", info
		end
	end
	if mc and mc.CanArmyRaid then
		local okR, why = mc.CanArmyRaid(player, victim) -- ally / new player / raid shield / low balance (the raid rules)
		if not okR then
			return false, tostring(why or "Blocked"), info
		end
	end
	if info.CooldownLeft > 0 then
		return false, "Cooldown", info
	end
	if NR.UsesWarhead and silo(player, profile) < 1 then
		return false, "NotReady", info
	end
	return true, "Ok", info
end

function NukeService.RaidPreview(player: Player, plotId: any)
	local ok, why, info = NukeService.RaidVerdict(player, plotId)
	if why == "Off" then
		return
	end
	info.Ok = ok
	info.Why = why
	push(player, "NukeRaidPreview", info)
end

local function strikeFx(player: Player, victim: Player, plotId: number)
	if not NR.Vfx then
		return
	end
	local okS, sv = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	local gd = deps.GateDefenseService
	local to: Vector3? = nil
	if gd and gd.GetGateCFrame then
		local okG, cf = pcall(gd.GetGateCFrame, plotId)
		if okG and typeof(cf) == "CFrame" then
			to = (cf :: CFrame).Position
		end
	end
	to = to or PlotFrame.PlotPosition(plotId)
	local myPlot = if deps.BaseService and deps.BaseService.GetOwnedPlotId then deps.BaseService.GetOwnedPlotId(player) else nil
	local fromBase = if typeof(myPlot) == "number" then PlotFrame.PlotPosition(myPlot) else nil
	if to == nil then
		return
	end
	local from = (fromBase or to + Vector3.new(0, 0, 400)) + Vector3.new(0, 20, 0)
	local dist = (to - from).Magnitude
	local ev = deps.RemoteSetup and deps.RemoteSetup.Get(Constants.RemoteNames.MissileStrikeFx)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireAllClients({
			StrikeId = "nuke_" .. player.UserId .. "_" .. os.time(),
			AttackerUserId = player.UserId,
			AttackerName = player.DisplayName,
			VictimUserId = victim.UserId,
			VictimName = victim.DisplayName,
			PlotId = plotId,
			From = from,
			To = to,
			ArcHeight = math.clamp(dist * 0.25, 60, 400),
			LaunchTime = if okS then sv else os.time(),
			FlightSeconds = NR.FlightSeconds,
			Outcome = "Hit",
		})
	end
	task.delay(NR.FlightSeconds, function()
		pushAll("NukeBlast", { X = to.X, Z = to.Z, Radius = 30 }) -- the light flash at the base (NukeController.blast)
	end)
end

function NukeService.RaidLaunch(player: Player, plotId: any): (boolean, string)
	local ok, why, info = NukeService.RaidVerdict(player, plotId)
	if not ok then
		return false, why
	end
	local profile = deps.DataService.GetProfile(player)
	local victim = Players:GetPlayerByUserId(deps.BaseService.GetOwnerUserId(info.PlotId))
	if victim == nil then
		return false, "NoBase"
	end
	-- the warhead + the cooldown before the money moves (a double tap can never launch twice)
	local s = profile.NukeSilo
	local readyBefore = silo(player, profile)
	local oldLast = profile.NukeLastLaunch
	if NR.UsesWarhead then
		profile.NukeSilo = { Ready = readyBefore - 1, ChargeFrom = if (tonumber(s and s.ChargeFrom) or 0) > 0 then s.ChargeFrom else os.time() }
	end
	profile.NukeLastLaunch = os.time()
	deps.DataService.MarkDirty(player)
	local moved = deps.MoneyCollectorService.NukeRaid(player, victim, NR.Text.Hit)
	if moved <= 0 then -- nothing moved (a race: shield / balance changed): give the warhead and the cooldown back
		profile.NukeSilo = s
		profile.NukeLastLaunch = oldLast
		deps.DataService.MarkDirty(player)
		return false, "Blocked"
	end
	print(string.format("[NukeRaid] uid=%d -> victim=%d plot=%d preview=%d moved=%d", player.UserId, victim.UserId, info.PlotId, info.Amount, moved))
	if deps.NotificationService then
		pcall(deps.NotificationService.Notify, player, string.format(NR.Text.Launched, NukeService.FormatCash(moved), victim.DisplayName), "Success", 6)
	end
	pcall(strikeFx, player, victim, info.PlotId)
	return true, "Ok"
end

function NukeService.HasSilo(player: Player): boolean
	return siloLevel(player) >= 1
end

function NukeService.FormatCash(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
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
		elseif action == "rpreview" then -- claude-bud JOB 65: targetId = the plot id (the server decides everything)
			NukeService.RaidPreview(player, targetId)
		elseif action == "rlaunch" then
			local ok, why = NukeService.RaidLaunch(player, targetId)
			if not ok and d.NotificationService and NR then
				local copy = if why == "Cooldown" then string.format(NR.Text.Cooldown, "wait")
					elseif why == "NotReady" then NR.Text.NotReady
					elseif why == "NoSilo" then NR.Text.NoSilo
					else string.format(NR.Text.Blocked, why)
				pcall(d.NotificationService.Notify, player, copy, "Warn", 4)
			end
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
