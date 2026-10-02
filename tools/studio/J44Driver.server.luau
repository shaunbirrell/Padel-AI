--[[
	claude-bud JOB 44 (2026-10-01): the 2-player Studio test DRIVER. TEST-ONLY: never in default.project.json, never on
	live; tools/studio/build_j44_place.py builds a separate place (J44Test.rbxl) with this Script added.

	Use: open J44Test.rbxl in Studio -> Test -> Clients and Servers -> Local Server, 2 players -> Start. The driver runs on
	the server by itself and prints "[J44] ..." lines plus a final "[J44] REPORT" block in the SERVER output. Paste
	that block back.

	It drives the REAL game code (the same calls the remotes make; the army units are server-owned, so the march /
	siege is decided here):
	  fixture  Player2 gets DefensiveWalls (so his base has a gate, guards and turrets); Player1's army is filled to
	           its cap; WE_ArmyDebug on for Player1 (the [ARMY ...] lines);
	  A        ArmyCommand.Send(Player1, Player2's plot): march -> gate -> siege (gate HP falls) -> breach -> loot ->
	           return. Every second: phase, gate HP, block centre, distance to the gate. A STALL line when the block
	           moves < 3 studs in 20 s outside Siege / Loot / Fight;
	  B1       ArmyCommand.Send(Player1, the Crossroads area): the block reaches the area;
	  B3       Player1 stands by his base's rear airfield / runway (the test moves the TEST PLAYER, never the army),
	           the army follows him there, then a SEND far away: the block must leave the base without stalling.
	It changes nothing in the game code and fakes no result: every PASS / FAIL comes from the live state.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server", 60)
local function mod(path: string): any
	local node: Instance = Server
	for part in string.gmatch(path, "[^/]+") do
		node = node:WaitForChild(part, 30)
	end
	return require(node)
end

local DataService = mod("Services/DataService")
local BaseService = mod("Services/BaseService")
local GateDefenseService = mod("Services/GateDefenseService")
local SquadOrdersService = mod("Services/SquadOrdersService")
local SoldierService = mod("Services/SoldierService")
local ArmyCommand = mod("Modules/ArmyCommand")
local ArmyPlan = mod("Modules/ArmyPlan")
local MapAreas = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("MapAreas"))

local results: { string } = {}
local fails = 0
local function log(s: string)
	print("[J44] " .. s)
end
local function check(ok: boolean, msg: string)
	table.insert(results, (if ok then "PASS  " else "FAIL  ") .. msg)
	if not ok then
		fails += 1
	end
	log((if ok then "PASS  " else "FAIL  ") .. msg)
end
local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function vs(v: Vector3?): string
	return if v then string.format("(%.0f,%.0f)", v.X, v.Z) else "nil"
end
local function waitFor(seconds: number, fn: () -> boolean): boolean
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		local ok, r = pcall(fn)
		if ok and r then
			return true
		end
		task.wait(0.5)
	end
	return false
end

local function unitCount(p: Player): number
	local st = SquadOrdersService.StateOf(p)
	return if st and typeof(st.Units) == "table" then #st.Units else 0
end

-- watch one plan; returns a summary table
local function watch(p: Player, label: string, maxSeconds: number, goal: Vector3?, goalRadius: number?, plotId: number?): { [string]: any }
	local uid = p.UserId
	local sum = { Phases = {}, Stalls = 0, GateStart = nil, GateMin = nil, Breached = false, Reached = false, Ended = false, Seconds = 0 }
	local hist: { { t: number, c: Vector3 } } = {}
	local lastPhase = nil
	local t0 = os.clock()
	while os.clock() - t0 < maxSeconds do
		task.wait(1)
		local t = os.clock() - t0
		sum.Seconds = t
		local status = ArmyPlan.Status(uid)
		local st = SquadOrdersService.StateOf(p)
		local centre = if st then ArmyPlan.BlockCentre(st) else nil
		local phase = if status then tostring(status.Phase) else "none"
		if phase ~= lastPhase then
			table.insert(sum.Phases, string.format("%s@%.0fs", phase, t))
			lastPhase = phase
		end
		local gateTxt = ""
		if plotId then
			local info = GateDefenseService.SiegeInfo(plotId)
			if info then
				local hp = tonumber(info.GateHp) or 0
				sum.GateStart = sum.GateStart or hp
				sum.GateMin = math.min(sum.GateMin or hp, hp)
				sum.Breached = sum.Breached or info.Breached == true
				gateTxt = string.format(" gate=%.0f/%.0f%s", hp, tonumber(info.GateMax) or 0, if info.Breached then " BREACHED" else "")
			end
		end
		local dist = if goal and centre then flat(centre, goal) else nil
		if dist and goalRadius and dist <= goalRadius then
			sum.Reached = true
		end
		log(string.format("%s t=%3.0f phase=%s text=%q centre=%s dist=%s units=%d%s", label, t, phase,
			tostring(status and status.Text or ""), vs(centre), if dist then string.format("%.0f", dist) else "-", unitCount(p), gateTxt))
		if centre then
			table.insert(hist, { t = t, c = centre })
			while #hist > 0 and t - hist[1].t > 20 do
				table.remove(hist, 1)
			end
			local moving = phase == "March" or phase == "Seek" or phase == "Return" or phase == "Travel"
			if moving and #hist >= 18 and flat(hist[1].c, centre) < 3 then
				sum.Stalls += 1
				log(string.format("%s STALL t=%.0f phase=%s centre=%s (moved %.1f studs in 20 s) text=%q", label, t, phase, vs(centre),
					flat(hist[1].c, centre), tostring(status and status.Text or "")))
				table.clear(hist)
			end
		end
		if status == nil and t > 3 then
			sum.Ended = true
			break
		end
	end
	return sum
end

task.spawn(function()
	log("waiting for 2 players with saves + plots (Test -> Clients and Servers, 2 players)")
	local ok = waitFor(180, function()
		local list = Players:GetPlayers()
		if #list < 2 then
			return false
		end
		for _, p in ipairs(list) do
			if DataService.GetProfile(p) == nil or BaseService.GetOwnedPlotId(p) == nil then
				return false
			end
		end
		return true
	end)
	if not ok then
		log("REPORT: ABORT - 2 players with profiles + plots never appeared")
		return
	end
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	local p1, p2 = list[1], list[2]
	local plot1, plot2 = BaseService.GetOwnedPlotId(p1), BaseService.GetOwnedPlotId(p2)
	log(string.format("sender=%s plot %s  victim=%s plot %s", p1.Name, tostring(plot1), p2.Name, tostring(plot2)))
	p1:SetAttribute("WE_ArmyDebug", true)

	-- fixture: walls for the victim (a gate + guards + turrets), a full army for the sender
	local prof2 = DataService.GetProfile(p2)
	prof2.BaseUpgrades = prof2.BaseUpgrades or {}
	prof2.BaseUpgrades.DefensiveWalls = math.max(1, tonumber(prof2.BaseUpgrades.DefensiveWalls) or 0)
	pcall(BaseService.RefreshAllVisuals, p2)
	pcall(GateDefenseService.EnsurePlot, plot2)
	check(waitFor(30, function()
		return GateDefenseService.HasDefenses(plot2) and GateDefenseService.GetGateCFrame(plot2) ~= nil
	end), "fixture: the victim's base has a gate (DefensiveWalls " .. tostring(prof2.BaseUpgrades.DefensiveWalls) .. ")")
	local prof1 = DataService.GetProfile(p1)
	prof1.Soldiers = math.max(tonumber(prof1.Soldiers) or 0, SoldierService.GetCap(p1))
	pcall(SquadOrdersService.SyncArmy, p1)
	check(waitFor(30, function()
		return unitCount(p1) > 0
	end), "fixture: the sender has an army (" .. unitCount(p1) .. " units, cap " .. tostring(SoldierService.GetCap(p1)) .. ")")
	task.wait(5)

	-- A: SEND to the victim's base
	local gateCf = GateDefenseService.GetGateCFrame(plot2)
	local sent, why = ArmyCommand.Send(p1, plot2)
	check(sent == true, "A: SEND to " .. p2.Name .. "'s base accepted" .. (if sent then "" else " (" .. tostring(why) .. ")"))
	if sent then
		local a = watch(p1, "A", 420, gateCf and gateCf.Position, 45, plot2)
		log("A phases: " .. table.concat(a.Phases, " "))
		check(a.Reached, "A: the block reached the gate (within 45 studs)")
		check(a.GateStart ~= nil and a.GateMin ~= nil and a.GateMin < a.GateStart, string.format("A: the gate HP fell from real shots (%s -> %s)", tostring(a.GateStart), tostring(a.GateMin)))
		check(a.Breached, "A: the gate was breached")
		local phases = table.concat(a.Phases, " ")
		check(string.find(phases, "Loot") ~= nil, "A: the army reached the Loot phase (filed in)")
		check(string.find(phases, "Return") ~= nil or a.Ended, "A: the army walked out / the plan ended")
		check(a.Stalls == 0, "A: no stall (" .. a.Stalls .. " stall lines)")
	end
	waitFor(240, function()
		return ArmyPlan.Status(p1.UserId) == nil
	end)

	-- B1: SEND to the Crossroads area
	local areaId = "A:Town"
	local okT = pcall(function()
		if MapAreas.ById("Town") == nil then
			for _, ar in ipairs(MapAreas.List()) do
				if string.find(string.lower(tostring(ar.Name)), "crossroads") then
					areaId = "A:" .. ar.Id
					break
				end
			end
		end
	end)
	local area = MapAreas.ById(string.sub(areaId, 3))
	local sentB, whyB = ArmyCommand.Send(p1, areaId)
	check(okT and sentB == true, "B1: SEND to " .. areaId .. " accepted" .. (if sentB then "" else " (" .. tostring(whyB) .. ")"))
	if sentB and area then
		local b = watch(p1, "B1", 300, Vector3.new(area.X, 0, area.Z), math.min(area.R, 80) + 60, nil)
		log("B1 phases: " .. table.concat(b.Phases, " "))
		check(b.Reached, "B1: the block reached Crossroads")
		check(b.Stalls == 0, "B1: no stall (" .. b.Stalls .. " stall lines)")
	end
	pcall(ArmyPlan.Cancel, p1, SquadOrdersService.StateOf(p1), "j44")
	task.wait(3)

	-- B3: start from the rear airfield / runway inside the sender's base
	local runway: BasePart? = nil
	local plotSpawn = BaseService.GetPlotSpawnCFrame(plot1)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and plotSpawn and (string.find(d.Name, "Runway") or string.find(d.Name, "Airfield")) and flat(d.Position, plotSpawn.Position) < 260 then
			runway = d
			break
		end
	end
	local char = p1.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if runway and root and char then
		char:PivotTo(CFrame.new(runway.Position + Vector3.new(0, 6, 0))) -- moves the TEST PLAYER only (fixture)
		local okF = waitFor(60, function()
			local st = SquadOrdersService.StateOf(p1)
			local c = st and ArmyPlan.BlockCentre(st)
			return c ~= nil and flat(c, runway.Position) < 60
		end)
		check(okF, "B3: the army followed " .. p1.Name .. " to the rear airfield (" .. runway:GetFullName() .. ")")
		local sentC, whyC = ArmyCommand.Send(p1, areaId)
		check(sentC == true, "B3: SEND from the airfield accepted" .. (if sentC then "" else " (" .. tostring(whyC) .. ")"))
		if sentC then
			local c = watch(p1, "B3", 120, plotSpawn and plotSpawn.Position, nil, nil)
			log("B3 phases: " .. table.concat(c.Phases, " "))
			check(c.Stalls == 0, "B3: no stall leaving the base from the airfield (" .. c.Stalls .. " stall lines)")
		end
	else
		table.insert(results, "SKIP  B3: no Runway / Airfield part found near " .. p1.Name .. "'s base (or no character)")
		log(results[#results])
	end

	print("[J44] REPORT ------------------------------------------------")
	for _, r in ipairs(results) do
		print("[J44] " .. r)
	end
	print(string.format("[J44] REPORT: %d failed", fails))
end)
