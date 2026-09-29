--!strict
--[[
	claude-bud JOB 14 (2026-09-29): game feel (Shared/Configs/GameFeelConfig). Server side; display only, never money.
	  * Kill feed: CombatService.OnPlayerDeath (PvP, not blast deaths) + VehicleHealth.OnDamage (a player wrecked a
	    vehicle) → FeaturePush "KillFeed" to every player the feed is live for. Server-wide MaxPerSecond, extra lines
	    dropped.
	  * Vehicle numbers: VehicleHealth.OnDamage → the owner of the damaged vehicle gets FeaturePush "VehDmg" (merged per
	    AggregateSeconds); a splash hit on a vehicle gives its attacker a CombatHitFeedback (hit marker + number), as a
	    direct hit already does.
	  * Raid report: GateDefenseService / MoneyCollectorService call GameFeelService.NoteRaid; QuietSeconds after the
	    last event the owner gets ONE FeaturePush "RaidReport" (Lost = the ATM was robbed, else Defended).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local GameFeelConfig = require(Shared.Configs.GameFeelConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)

local GameFeelService = {}

local G: any = GameFeelConfig

local function live(feature: string, p: Player?): boolean
	return p ~= nil and GameFeelConfig.LiveFor(feature, p.UserId)
end

local function push(p: Player, kind: string, data: { [string]: any })
	local ev = Remotes.TryGetEvent(Constants.RemoteNames.FeaturePush)
	if ev then
		pcall((ev :: any).FireClient, ev, p, kind, data)
	end
end

-- ── kill feed ──
local feedSecond, feedCount = 0, 0

local function weaponLabel(id: string?): string
	if typeof(id) ~= "string" then
		return ""
	end
	local w = (WeaponConfig.Weapons :: any)[id]
	return if w and typeof(w.DisplayName) == "string" then w.DisplayName else ""
end

local function feed(killer: Player, victimName: string, victim: Player?, weapon: string)
	local sec = math.floor(os.clock())
	if sec ~= feedSecond then
		feedSecond, feedCount = sec, 0
	end
	if feedCount >= G.KillFeed.MaxPerSecond then
		return -- over the cap: dropped, never queued
	end
	feedCount += 1
	for _, p in ipairs(Players:GetPlayers()) do
		if live("KillFeed", p) then
			push(p, "KillFeed", {
				K = killer.DisplayName,
				V = victimName,
				W = weapon,
				Mine = p == killer,
				Me = victim ~= nil and p == victim,
			})
		end
	end
end

-- ── vehicle numbers ──
type Pending = { Owner: Player, Dealt: number, Pos: Vector3, Due: boolean }
local pendingVeh: { [Model]: Pending } = {}

local function flushVehicle(model: Model)
	local pnd = pendingVeh[model]
	pendingVeh[model] = nil
	if pnd and pnd.Owner.Parent ~= nil and pnd.Dealt >= 1 then
		push(pnd.Owner, "VehDmg", { D = math.floor(pnd.Dealt + 0.5), P = pnd.Pos })
	end
end

local function onVehicleDamage(model: Model, ownerUserId: number, name: string, dealt: number, attacker: Player?, hitPos: Vector3?, destroyed: boolean, splash: boolean)
	local pos = hitPos
	if pos == nil then
		local ok, cf = pcall(model.GetPivot, model)
		pos = if ok then cf.Position else nil
	end
	-- the owner (usually the driver) sees what his vehicle takes
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if owner and owner ~= attacker and pos and live("VehicleNumbers", owner) then
		local pnd = pendingVeh[model]
		if pnd == nil then
			pendingVeh[model] = { Owner = owner, Dealt = dealt, Pos = pos, Due = true }
			task.delay(G.VehicleNumbers.AggregateSeconds, flushVehicle, model)
		else
			pnd.Dealt += dealt
			pnd.Pos = pos
		end
	end
	-- a splash hit on a vehicle: the attacker gets the same marker + number a direct hit gets
	if splash and attacker and pos and live("VehicleNumbers", attacker) then
		local ev = Remotes.TryGetEvent(Constants.RemoteNames.CombatHitFeedback)
		if ev then
			pcall((ev :: any).FireClient, ev, attacker, {
				Kind = if destroyed then "Kill" else "Hit",
				Damage = dealt,
				TargetName = name,
				WeaponId = nil,
				IsHeadshot = false,
				TargetKind = "Vehicle",
				Pos = pos,
				Splash = true,
			})
		end
	end
	if destroyed and attacker and attacker.UserId ~= ownerUserId then
		local ownerName = if owner then owner.DisplayName .. "'s " else ""
		feed(attacker, ownerName .. name, nil, "")
	end
end

-- a gun / missile hit on a vehicle with no hit point: where to show the attacker's number (nil = as before)
function GameFeelService.VehicleNumberPos(attacker: Player?, model: Model): Vector3?
	if not live("VehicleNumbers", attacker) then
		return nil
	end
	local ok, cf = pcall(model.GetPivot, model)
	return if ok then cf.Position else nil
end

-- ── raid report ──
type Raid = { Last: number, Lost: number, By: { [string]: boolean }, Breached: boolean }
local raids: { [number]: Raid } = {}

--[[ kind: "Hit" (gate / guard / defense hit), "Breach", "Hold" (an ATM raid hold), "Robbed" (amount = the cash
	taken), "AtmDefended". Only for an owner the report is live for; everything else is ignored. ]]
function GameFeelService.NoteRaid(ownerUserId: number, kind: string, attacker: Player?, amount: number?)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if owner == nil or owner == attacker or not live("RaidReport", owner) then
		return
	end
	local r = raids[ownerUserId]
	if r == nil then
		r = { Last = 0, Lost = 0, By = {}, Breached = false }
		raids[ownerUserId] = r
	end
	local raid = r :: Raid
	raid.Last = os.clock()
	if attacker then
		raid.By[attacker.DisplayName] = true
	end
	if kind == "Robbed" then
		raid.Lost += math.max(0, math.floor(tonumber(amount) or 0))
	elseif kind == "Breach" then
		raid.Breached = true
	end
end

local function names(set: { [string]: boolean }): string
	local list = {}
	for n in pairs(set) do
		table.insert(list, n)
	end
	table.sort(list)
	if #list == 0 then
		return ""
	elseif #list == 1 then
		return list[1]
	end
	return list[1] .. " +" .. tostring(#list - 1)
end

local function reportDue()
	local now = os.clock()
	for uid, r in pairs(raids) do
		if now - r.Last >= G.RaidReport.QuietSeconds then
			raids[uid] = nil
			local owner = Players:GetPlayerByUserId(uid)
			if owner then
				push(owner, "RaidReport", {
					Lost = r.Lost,
					By = names(r.By),
					Breached = r.Breached,
				})
			end
		end
	end
end

function GameFeelService.Init(d: { [string]: any })
	local cs = d.CombatService
	if cs and cs.OnPlayerDeath then
		cs.OnPlayerDeath(function(victim: Player, killer: Player?, info: any)
			if killer == nil or killer == victim or (typeof(info) == "table" and info.Quiet == true) then
				return
			end
			feed(killer, victim.DisplayName, victim, weaponLabel(if typeof(info) == "table" then info.WeaponId else nil))
		end)
	end
	local okV, VehicleHealth = pcall(require, script.Parent.Parent.Modules.VehicleHealth)
	if okV and type(VehicleHealth) == "table" then
		(VehicleHealth :: any).OnDamage = function(...)
			local ok, err = pcall(onVehicleDamage :: any, ...)
			if not ok then
				warn("[GameFeelService] vehicle damage cue failed", err)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		raids[p.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(reportDue)
		end
	end)
end

return GameFeelService
