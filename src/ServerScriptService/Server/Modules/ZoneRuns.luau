--!strict
--[[
	claude-bud JOB 50 part A (2026-10-01): THE ZONE RUNS (RebirthZonesConfig.Runs / RunRules / Rebuild, owner-first).
	A built zone's JOB 46 kiosk (WE_ZoneActivity -> RebirthZoneService.Activity) starts one short run on the apron:
	  * Steps: one marker per step; ONLY the current step carries a prompt. The server checks the trigger is the owner,
	    the run is his and running, it is THAT step, he stands inside the annex (+ AnnexSlackStuds), and the time limit
	    has not passed. Nothing the client says about time, score or position is read.
	  * Wave (Bunker): CombatService NPCs (TargetFilter = him only, the one combat path); all down inside the limit = win.
	  * Instant (Drone Hangar): the drones mark the nearest raidable rival (RivalService, the JOB 38 verdicts; a pin + SEND
	    card, no travel) and sweep the ATM.
	A win pays RebirthZonesConfig.RunCash (the ONE ShipmentCash formula x a speed factor), the first clear once more,
	saves the best time and the per-zone cooldown, applies the zone's effect and refreshes the gateway plaque. Every run
	logs ZoneActivity { zone, result, seconds, payout }. No teleport / PivotTo; nothing moves the player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZC: any = require(Shared.Configs.RebirthZonesConfig)

local ZoneRuns = {}

export type Run = {
	Uid: number,
	Zone: string,
	Level: number,
	Def: any,
	StartedAt: number,
	Deadline: number,
	Step: number,
	Frame: CFrame,
	W: number,
	D: number,
	Folder: Folder?,
	Markers: { BasePart },
	Order: { number },
	NpcIds: { string },
	Token: number,
}

local deps: { [string]: any } = {}
local runs: { [number]: Run } = {}
local seq = 0
ZoneRuns._clock = os.clock
ZoneRuns._unix = os.time
ZoneRuns._delay = function(s: number, fn: () -> ())
	task.delay(s, fn)
end

function ZoneRuns.Bind(d: { [string]: any })
	for k, v in pairs(d) do
		deps[k] = v
	end
end

local function notify(player: Player, text: string, kind: string?)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function push(player: Player, kind: string, data: any)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(require(Shared.Constants).RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, kind, data)
	end
end

local function profileOf(player: Player): any
	return deps.DataService and deps.DataService.GetProfile(player)
end

local function tbl(profile: any, key: string): { [string]: any }
	local t = profile[key]
	if typeof(t) ~= "table" then
		t = {}
		profile[key] = t
	end
	return t
end

-- his passive income per minute (the time-pack helper, timed boosts excluded); 0 when it cannot be read
local function perMin(player: Player, profile: any): number
	local ok, v = pcall(function(): any
		local MS: any = (require :: any)(script.Parent.Parent.Services.MonetizationService)
		return MS.PassivePerMin(player, profile, true)
	end)
	return if ok and typeof(v) == "number" and v == v and v > 0 then v else 0
end

local function tick(): number
	local ok, EC = pcall(function(): any
		return require(Shared.Configs.EconomyConfig)
	end)
	return if ok and EC then tonumber(EC.PassiveIncome.TickSeconds) or 5 else 5
end

-- seconds of cooldown left on this zone's run (0 = ready)
function ZoneRuns.CooldownLeft(profile: any, zoneId: string, nowUnix: number?): number
	local at = typeof(profile.ZoneRunAt) == "table" and tonumber(profile.ZoneRunAt[zoneId]) or nil
	if at == nil then
		return 0
	end
	local cd = (tonumber(ZC.RunRules.CooldownMinutes) or 20) * 60
	return math.max(0, math.ceil(at + cd - (nowUnix or ZoneRuns._unix())))
end

function ZoneRuns.Active(uid: number): Run?
	return runs[uid]
end

local function insideAnnex(player: Player, run: Run): boolean
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if r == nil or not r:IsA("BasePart") then
		return false
	end
	local lp = run.Frame:PointToObjectSpace(r.Position)
	local slack = tonumber(ZC.RunRules.AnnexSlackStuds) or 24
	return math.abs(lp.X) <= run.W / 2 + slack and lp.Z >= -run.D / 2 - slack and lp.Z <= run.D / 2 + 20 + slack
end

local function clearRun(run: Run)
	if runs[run.Uid] == run then
		runs[run.Uid] = nil
	end
	local f = run.Folder
	if f then
		f:Destroy()
	end
	run.Folder = nil
	local cs = deps.CombatService
	for _, id in ipairs(run.NpcIds) do
		if cs and cs.DespawnNPC then
			pcall(cs.DespawnNPC, id)
		end
	end
	table.clear(run.NpcIds)
end

local function log(player: Player, zoneId: string, result: string, seconds: number, payout: number)
	local a = deps.AnalyticsService
	if a and a.Log then
		pcall(a.Log, "ZONE_ACTIVITY", player.UserId, { zone = zoneId, result = result, seconds = math.floor(seconds), payout = payout })
	end
	print(string.format("[ZONE RUN] %s %s %s %.1fs $%d", player.Name, zoneId, result, seconds, payout))
end

-- the zone's effect on a win
local function applyEffect(player: Player, profile: any, run: Run, secondsUsed: number): string
	local def = run.Def
	local e = def.Effect
	if e == "nukecharge" then
		local s = profile.NukeSilo
		local cut = math.max(0, (tonumber(def.ChargeCutMinutes) or 0) * 60)
		if typeof(s) == "table" and (tonumber(s.ChargeFrom) or 0) > 0 and cut > 0 then
			s.ChargeFrom = (tonumber(s.ChargeFrom) or 0) - cut
			return string.format(" · silo charge -%d min", math.floor(cut / 60))
		end
		return " · silo already charged"
	elseif e == "reloadcut" then
		local raid = profile.Raid
		local cut = math.max(0, tonumber(def.ReloadCutSeconds) or 0)
		if typeof(raid) == "table" and (tonumber(raid.StrikeCooldownUntil) or 0) > ZoneRuns._unix() and cut > 0 then
			raid.StrikeCooldownUntil = math.max(ZoneRuns._unix(), raid.StrikeCooldownUntil - cut)
			pcall(function()
				player:SetAttribute("WE_StrikeCooldownUntil", raid.StrikeCooldownUntil)
			end)
			return string.format(" · missile reload -%d s", cut)
		end
		return " · missiles already loaded"
	elseif e == "armyboost" then
		if secondsUsed <= (tonumber(def.Par) or 0) then
			local untilUnix = ZoneRuns._unix() + math.max(1, tonumber(def.BoostMinutes) or 10) * 60
			profile.ArmyBoostUntil = math.max(tonumber(profile.ArmyBoostUntil) or 0, untilUnix)
			pcall(function()
				player:SetAttribute("WE_ArmyBoostUntil", profile.ArmyBoostUntil)
			end)
			return string.format(" · beat par: ARMY BOOST %d min", math.floor(tonumber(def.BoostMinutes) or 10))
		end
		return string.format(" · par is %d s", math.floor(tonumber(def.Par) or 0))
	elseif e == "banner" then
		profile.BunkerBanner = math.min(math.max(1, tonumber(def.BannerStages) or 3), (tonumber(profile.BunkerBanner) or 0) + 1)
		return string.format(" · bunker banner stage %d", profile.BunkerBanner)
	end
	return ""
end

local function finish(player: Player, run: Run, won: boolean, why: string)
	if runs[run.Uid] ~= run then
		return
	end
	local profile = profileOf(player)
	local used = ZoneRuns._clock() - run.StartedAt
	clearRun(run)
	if profile == nil then
		return
	end
	tbl(profile, "ZoneRunAt")[run.Zone] = ZoneRuns._unix() -- the cooldown starts on any end (a fail too: no retry spam)
	local payout = 0
	if won then
		local pm = perMin(player, profile)
		payout = ZC.RunCash(run.Zone, run.Level, tick(), used, run.Def.Seconds, pm)
		local first = tbl(profile, "ZoneFirstClear")
		local firstBonus = 0
		if first[run.Zone] ~= true then
			first[run.Zone] = true
			firstBonus = math.floor(ZC.RunBase(run.Zone, run.Level, tick(), pm) * (tonumber(ZC.RunRules.FirstClearMult) or 1))
		end
		local best = tbl(profile, "ZoneBest")
		local pb = tonumber(best[run.Zone])
		local isBest = run.Def.Seconds > 0 and (pb == nil or used < pb)
		if isBest then
			best[run.Zone] = math.floor(used * 10 + 0.5) / 10
		end
		local es = deps.EconomyService
		if es and es.AddCash and payout + firstBonus > 0 then
			pcall(es.AddCash, player, payout + firstBonus, "rebirthzone_run")
		end
		local extra = applyEffect(player, profile, run, used)
		notify(player, string.format("%s cleared%s: +$%d%s%s", run.Def.Title, if run.Def.Seconds > 0 then string.format(" in %.1f s", used) else "",
			payout + firstBonus, if firstBonus > 0 then " (first clear!)" else "", extra .. (if isBest then " · NEW BEST" else "")), "Success")
		payout += firstBonus
	else
		notify(player, string.format("%s: %s. Try again in %d min", run.Def.Title, why, math.floor(tonumber(ZC.RunRules.CooldownMinutes) or 20)), "Warn")
	end
	if deps.DataService then
		pcall(deps.DataService.MarkDirty, player)
	end
	log(player, run.Zone, if won then "win" else why, used, payout)
	push(player, "ZoneRun", { Zone = run.Zone, Done = true, Won = won })
	if deps.OnRunEnded then
		pcall(deps.OnRunEnded, player, run.Zone)
	end
end

local function marker(run: Run, i: number, label: string, x: number, dz: number): BasePart
	local p = Instance.new("Part")
	p.Name = "ZoneRunStep" .. i
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(3, 0.3, 3)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(255, 205, 60)
	p.Transparency = 0.6
	p.CFrame = run.Frame * CFrame.new(x, 0.2, run.D / 2 + dz)
	local post = Instance.new("Part")
	post.Name = "ZoneRunPost"
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.CanTouch = false
	post.Size = Vector3.new(0.5, 3.2, 0.5)
	post.Material = Enum.Material.Metal
	post.Color = Color3.fromRGB(60, 62, 58)
	post.CFrame = p.CFrame * CFrame.new(0, 1.6, 0)
	post.Parent = p
	p:SetAttribute("Label", label)
	p.Parent = run.Folder
	return p
end

local function showStep(player: Player, run: Run)
	for k, m in ipairs(run.Markers) do
		local pr = m:FindFirstChild("ZoneRunPrompt")
		if pr then
			pr:Destroy()
		end
		m.Transparency = if k == run.Order[run.Step] then 0.1 else 0.75
	end
	local idx = run.Order[run.Step]
	local m: BasePart? = run.Markers[idx]
	if m == nil then
		return
	end
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "ZoneRunPrompt"
	local label = tostring(m:GetAttribute("Label"))
	if run.Def.Shuffle and not string.find(label, " OF ", 1, true) then
		label = string.format("%s %d OF %d", label, run.Step, #run.Order) -- claude-bud JOB 69 B: "VALVE 2 OF 4"
	end
	pr.ActionText = label
	pr.ObjectText = string.format("%s %d/%d", run.Def.Title, run.Step, #run.Order)
	pr.HoldDuration = tonumber(ZC.RunRules.StepHold) or 0.3
	pr.MaxActivationDistance = tonumber(ZC.RunRules.StepReach) or 9
	pr.RequiresLineOfSight = false
	pr.Parent = m
	local token = run.Token
	pr.Triggered:Connect(function(who: Player)
		ZoneRuns.Step(who, run.Uid, token, idx)
	end)
	-- claude-bud JOB 69 B: the tracker gets the step label + where the pad is (the client pill + the arrow)
	push(player, "ZoneRun", { Zone = run.Zone, Title = run.Def.Title, Step = run.Step, Of = #run.Order, Label = label, Pos = m.Position,
		Left = math.max(0, math.ceil(run.Deadline - ZoneRuns._clock())) })
end

--[[ A step prompt fired: every rule is checked here (the owner, his running run, THIS step, inside the annex, in time).
	Returns true when it counted. ]]
function ZoneRuns.Step(player: Player, uid: number, token: number, markerIdx: number): boolean
	local run = runs[uid]
	if run == nil or player.UserId ~= uid or run.Token ~= token or run.Order[run.Step] ~= markerIdx then
		return false
	end
	if ZoneRuns._clock() > run.Deadline then
		finish(player, run, false, "out of time")
		return false
	end
	if not insideAnnex(player, run) then
		return false
	end
	run.Step += 1
	if run.Step > #run.Order then
		finish(player, run, true, "")
	else
		showStep(player, run)
	end
	return true
end

-- the Bunker's wave: one of the NPCs died (CombatService.OnNPCDeath)
function ZoneRuns.OnNPCDeath(info: any)
	if typeof(info) ~= "table" or typeof(info.GroupId) ~= "string" or string.sub(info.GroupId, 1, 8) ~= "ZoneRun." then
		return
	end
	local uid = tonumber(string.sub(info.GroupId, 9))
	local run = uid and runs[uid :: number]
	if run == nil then
		return
	end
	local idx = table.find(run.NpcIds, info.Id)
	if idx then
		table.remove(run.NpcIds, idx)
	end
	if #run.NpcIds == 0 then
		local player = Players:GetPlayerByUserId(run.Uid)
		if player then
			finish(player, run, ZoneRuns._clock() <= run.Deadline, "out of time")
		end
	end
end

local function recon(player: Player, zoneId: string, level: number)
	local okR, RS = pcall(function(): any
		return (require :: any)(script.Parent.Parent.Services.RivalService)
	end)
	local rows = {}
	if okR and RS and RS.Candidates then
		local okC, r = pcall(RS.Candidates, player)
		rows = if okC and typeof(r) == "table" then r else {}
	end
	table.sort(rows, function(a: any, b: any)
		return (tonumber(a.Dist) or math.huge) < (tonumber(b.Dist) or math.huge)
	end)
	local best = rows[1]
	local es = deps.EconomyService
	if es and es.GetPendingCash and es.CollectPendingCash and (tonumber(es.GetPendingCash(player)) or 0) > 0 then
		pcall(es.CollectPendingCash, player)
	end
	local profile = profileOf(player)
	if profile then
		tbl(profile, "ZoneRunAt")[zoneId] = ZoneRuns._unix()
	end
	if best then
		local okP, PF = pcall(function(): any
			return require(Shared.Util.PlotFrame)
		end)
		local pos = if okP and PF then PF.PlotPosition(best.PlotId) else nil
		push(player, "ArmyNearest", { Text = string.format("RECON: %s's base · %s loot", tostring(best.Name), tostring(best.Loot or "?")),
			X = pos and pos.X, Y = pos and pos.Y, Z = pos and pos.Z, Target = "B:" .. tostring(best.PlotId) })
		notify(player, "Recon flight: rival marked, ATM swept", "Success")
	else
		notify(player, "Recon flight: no raidable rival right now · ATM swept", "Info")
	end
	log(player, zoneId, if best then "win" else "no_target", 0, 0)
end

--[[ Start this zone's run for the owner. frame / W / D = the annex; parent = the zone's dressing folder. ]]
function ZoneRuns.Start(player: Player, zoneId: string, level: number, frame: CFrame, W: number, D: number, parent: Instance?): (boolean, string)
	local def = ZC.Runs[zoneId]
	local profile = profileOf(player)
	if def == nil or profile == nil or level < 1 then
		return false, "off"
	end
	if runs[player.UserId] then
		local cur = runs[player.UserId]
		if ZC.RebuildLive(player.UserId, "HowTo") then -- claude-bud JOB 69 B: say which run and how long (the CANCEL chip is on screen)
			notify(player, string.format("%s in progress · %d:%02d left", cur.Def.Title, math.max(0, math.ceil(cur.Deadline - ZoneRuns._clock())) // 60,
				math.max(0, math.ceil(cur.Deadline - ZoneRuns._clock())) % 60), "Info")
		else
			notify(player, "Finish your current run first", "Info")
		end
		return false, "busy"
	end
	local left = ZoneRuns.CooldownLeft(profile, zoneId)
	if left > 0 then
		notify(player, string.format("%s ready in %d:%02d", def.Title, left // 60, left % 60), "Info")
		return false, "cooldown"
	end
	if def.Effect == "recon" then
		recon(player, zoneId, level)
		return true, "recon"
	end
	seq += 1
	local now = ZoneRuns._clock()
	local run: Run = { Uid = player.UserId, Zone = zoneId, Level = level, Def = def, StartedAt = now, Deadline = now + def.Seconds,
		Step = 1, Frame = frame, W = W, D = D, Folder = nil, Markers = {}, Order = {}, NpcIds = {}, Token = seq }
	local f = Instance.new("Folder")
	f.Name = "ZoneRun_" .. zoneId
	f.Parent = parent
	run.Folder = f
	runs[player.UserId] = run
	if def.Wave then
		local cs = deps.CombatService
		for i, typeId in ipairs(def.Wave) do
			local at = def.WaveAt[i] or { 0, 14 }
			local cf = frame * CFrame.new(at[1], 3, D / 2 + at[2])
			local target = player
			local ok, rec = pcall(function(): any
				return cs.SpawnNPC(typeId, cf, { GroupId = "ZoneRun." .. tostring(player.UserId), NoRespawn = true, Home = cf, Leash = 40, OverCap = true,
					TargetFilter = function(p: Player): boolean
						return p == target
					end })
			end)
			if ok and rec and typeof(rec.Id) == "string" then
				table.insert(run.NpcIds, rec.Id)
			end
		end
		if #run.NpcIds == 0 then
			clearRun(run)
			return false, "no_wave"
		end
		push(player, "ZoneRun", { Zone = zoneId, Wave = #run.NpcIds, Left = def.Seconds })
		notify(player, string.format("%s: beat %d attackers in %d s!", def.Title, #run.NpcIds, def.Seconds), "Info")
	else
		for i, st in ipairs(def.Steps) do
			run.Markers[i] = marker(run, i, st[1], st[2], st[3])
			run.Order[i] = i
		end
		if def.Shuffle then
			-- a fresh order per run (the labels say which valve is next: the prompt names it)
			local rng = Random.new(seq * 7919)
			for i = #run.Order, 2, -1 do
				local j = rng:NextInteger(1, i)
				run.Order[i], run.Order[j] = run.Order[j], run.Order[i]
			end
		end
		showStep(player, run)
		notify(player, string.format("%s: %d steps in %d s. GO!", def.Title, #run.Order, def.Seconds), "Info")
	end
	local token = run.Token
	ZoneRuns._delay(def.Seconds + 0.5, function()
		local cur = runs[player.UserId]
		if cur and cur.Token == token then
			finish(player, cur, false, "out of time")
		end
	end)
	return true, "started"
end

function ZoneRuns.Cancel(uid: number)
	local run = runs[uid]
	if run then
		clearRun(run)
	end
end

-- the gateway plaque's text: who unlocked it, the rebirth, the best, ZONE COMMANDER
function ZoneRuns.PlaqueText(displayName: string, tier: number, best: number?, commander: boolean, title: string?): string
	local lines = { string.format("UNLOCKED BY %s · REBIRTH %d", string.upper(displayName), tier) }
	if title and best then
		table.insert(lines, string.format("%s BEST %d:%04.1f", title, math.floor(best / 60), best % 60))
	end
	if commander then
		table.insert(lines, "ZONE COMMANDER")
	end
	return table.concat(lines, "\n")
end

return ZoneRuns
