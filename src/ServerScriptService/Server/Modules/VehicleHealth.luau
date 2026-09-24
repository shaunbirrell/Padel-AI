--!strict
--[[
	VehicleHealth — server-only HP for EVERY vehicle (W2 CC-2; money plan M4; premium_vehicles.md §3; contracts §4).
	Numbers: Shared/Configs/VehicleCombatConfig.luau. Server module: never required by client code.

	  * MaxHP = def.Health × clamp(WE_ArmorMult, Health.ArmorMultClamp) × Health.GlobalHPMult × (opts.HPMult or 1).
	    A later WE_ArmorMult change (research, VehicleService.OnResearchChanged) rescales MaxHP and keeps the HP fraction.
	  * dealt = min(HP, Amount × VehicleCombatConfig.DamageMult(class, def.Armor, WeaponMult)). The class math lives
	    here only: callers pass the raw amount (CombatService.ApplyHit never applies armor).
	  * Refused (0, false): not registered · destroyed · IsProtected (owner / someone seated in it / 5 s spawn
	    protection / trial vehicle / an attacker seated in a trial vehicle).
	  * HP 0: OnWrecked (VehicleService: charred look, server physics, seats off) → WE_Destroyed → every occupant is
	    ejected and takes Destroy.OccupantDamage (players through deps.CombatService.ApplyHit with the killer's tag,
	    squad units TakeDamage) → bounty to the last attacker within KillerWindowSeconds (not self / clan-mate /
	    trial / the same killer-victim pair within PairCooldownSeconds) → VEHICLE_DESTROYED analytics → repair lock
	    (Premium 20 s / Cash 45 s) → OnDestroyed after DebrisSeconds (VehicleService teardown). No server Explosion.
	  * Regen (1 Hz) after DelayAfterDamageSeconds: premium 1.5 %/s anywhere; Cash vehicles 2 %/s only while the
	    Chassis is on the owner's plot pad (profile.BasePlotId).
	  * Replication: WE_HP / WE_MaxHP (integers, ceil) flushed from a dirty flag at Health.AttrHz (10 Hz) for all
	    vehicles together; WE_Destroyed at once. Display only: nothing reads them back.
	  * Every dep is optional (nil-guarded + pcall). Safe to call before Init (empty registry, no loop yet).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local VehicleCombatConfig = require(Shared.Configs.VehicleCombatConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local NukeConfig = require(Shared.Configs.NukeConfig)

type VehicleDef = VehicleConfig.VehicleDef

export type Record = {
	Model: Model,
	VehicleId: string,
	OwnerUserId: number,
	MaxHP: number,
	HP: number,
	Armor: number,
	Premium: boolean,
	Trial: boolean,
	SpawnedAt: number,
	LastDamagedAt: number,
	LastAttackerUserId: number?,
	LastAttackerAt: number,
	Destroyed: boolean,
	OnDestroyed: (rec: Record, killer: Player?) -> (),
}
export type DamageHit = {
	Attacker: Player?,
	Amount: number,
	Class: string?,
	WeaponId: string?,
	WeaponMult: number?,
	HitPos: Vector3?,
}
export type RadiusOpts = {
	MinMult: number?, -- default 0.25 at the edge (linear)
	IgnoreUserId: number?, -- vehicles owned by this user are skipped
	SkipOwner: ((ownerUserId: number) -> boolean)?, -- true = skip (nuke immunity)
	CoreRadius: number?, -- class with CoreDestroys (Nuke, J8): within this, destroyed outright
	WeaponId: string?,
	WeaponMult: number?,
	IgnoreModel: Model?, -- the firing vehicle / the direct-hit vehicle
}
export type RegisterOpts = {
	Trial: boolean?,
	Premium: boolean?,
	HPMult: number?, -- M7c Tank Factory (J9); W2 passes nil
	OnWrecked: ((rec: Record) -> ())?,
	OnDestroyed: (rec: Record, killer: Player?) -> (),
}

type Entry = {
	Rec: Record,
	Def: VehicleDef,
	Owner: Player,
	HPMult: number,
	ArmorMult: number,
	OnWrecked: ((rec: Record) -> ())?,
	LastAttacker: Player?,
	LastClass: string,
	Dirty: boolean,
	WrittenHP: number,
	WrittenMax: number,
	Conns: { RBXScriptConnection },
}

local HCFG = VehicleCombatConfig.Health
local DCFG = VehicleCombatConfig.Destroy
local RCFG = VehicleCombatConfig.Regen
local BOUNTY = DCFG.Reward

local VehicleHealth = {}

local entries: { [Model]: Entry } = {}
local destroyedUntil: { [number]: { [string]: number } } = {} -- [ownerUserId][vehicleId] = os.clock() deadline
local bountyPairs: { [string]: number } = {} -- "killer:victim" → os.clock() of the last paid bounty
local ownerHitAt: { [number]: number } = {} -- [ownerUserId] = os.clock() a live vehicle of theirs last took damage (W2 verify)
local plotCache: { [number]: BasePart } = {}
local deps: { [string]: any } = {}
local loop = { Inited = false, NextFlushAt = -math.huge, NextRegenAt = -math.huge, LastRegenAt = nil :: number? }

local function now(): number
	return os.clock()
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function round3(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

-- WE_ArmorMult (research VehicleArmor, written by VehicleService) clamped to Health.ArmorMultClamp
local function armorMultOf(model: Model): number
	local v = tonumber(model:GetAttribute("WE_ArmorMult")) or 1
	if not finite(v) then
		v = 1
	end
	local c = HCFG.ArmorMultClamp
	return math.clamp(v, c[1] or 1, c[2] or 1.5)
end

local function maxHPFor(def: VehicleDef, armorMult: number, hpMult: number): number
	local base = math.max(1, tonumber(def.Health) or 1)
	local g = tonumber(HCFG.GlobalHPMult) or 1
	if not (g > 0) then
		g = 1
	end
	return math.max(1, round3(base * armorMult * g * hpMult))
end

-- (class, WeaponMult): an explicit known class wins; else InfantryWeapons[WeaponId] or DefaultInfantryClass.
-- WeaponMult defaults to the InfantryWeapons row only when that row's class is the one applied.
local function resolveClass(className: string?, weaponId: string?, weaponMult: number?): (string, number)
	local iw = if typeof(weaponId) == "string" then VehicleCombatConfig.InfantryWeapons[weaponId] else nil
	local cls: string = VehicleCombatConfig.DefaultInfantryClass
	if typeof(className) == "string" and VehicleCombatConfig.DamageClasses[className] ~= nil then
		cls = className
	elseif iw then
		cls = iw.Class
	end
	local m = if typeof(weaponMult) == "number" then weaponMult else nil
	if m == nil or not finite(m) or m < 0 then
		m = if iw and iw.Class == cls then iw.Mult else 1
	end
	return cls, m :: number
end

local function writeAttrs(e: Entry, force: boolean)
	local rec = e.Rec
	local model = rec.Model
	local hpI = math.max(0, math.ceil(rec.HP - 1e-6))
	local maxI = math.max(1, math.ceil(rec.MaxHP - 1e-6))
	e.Dirty = false
	if force or hpI ~= e.WrittenHP then
		e.WrittenHP = hpI
		model:SetAttribute("WE_HP", hpI)
	end
	if force or maxI ~= e.WrittenMax then
		e.WrittenMax = maxI
		model:SetAttribute("WE_MaxHP", maxI)
	end
end

local function playerIsIn(player: Player): boolean
	return player.Parent ~= nil
end

-- the vehicle's last attacker, if they hit it within KillerWindowSeconds and are still in the server
local function killerOf(e: Entry, t: number): Player?
	local p = e.LastAttacker
	if p and playerIsIn(p) and t - e.Rec.LastAttackerAt <= BOUNTY.KillerWindowSeconds then
		return p
	end
	return nil
end

local function clanOf(player: Player?): string?
	local cs = deps.ClanService
	if player == nil or cs == nil or typeof(cs.GetClanId) ~= "function" then
		return nil
	end
	local ok, id = pcall(cs.GetClanId, player)
	if ok and typeof(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function sameClan(a: Player, b: Player?): boolean
	local ca = clanOf(a)
	return ca ~= nil and ca == clanOf(b)
end

-- Destroy.OccupantDamage to one ejected occupant (players: CombatService.ApplyHit with the killer's creator tag;
-- squad units / anything else: TakeDamage). A missing ApplyHit (older CombatService) falls back to TakeDamage.
local function damageOccupant(hum: Humanoid, killer: Player?)
	local amount = DCFG.OccupantDamage
	local char = hum.Parent
	local player = if char then Players:GetPlayerFromCharacter(char) else nil
	if player and char then
		local cs = deps.CombatService
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
		if cs and typeof(cs.ApplyHit) == "function" and root then
			local ok = pcall(cs.ApplyHit, killer, root, amount, { WeaponId = "VehicleWreck" })
			if ok then
				return
			end
		end
	end
	pcall(function()
		hum:TakeDamage(amount)
	end)
end

local function payBounty(e: Entry, killer: Player?)
	if killer == nil or not playerIsIn(killer) then
		return
	end
	local rec = e.Rec
	if rec.Trial or killer.UserId == rec.OwnerUserId then
		return
	end
	if sameClan(killer, e.Owner) then
		return
	end
	local key = tostring(killer.UserId) .. ":" .. tostring(rec.OwnerUserId)
	local t = now()
	local last = bountyPairs[key]
	if last ~= nil and t - last < BOUNTY.PairCooldownSeconds then
		return
	end
	bountyPairs[key] = t
	local cash = math.floor(math.min(rec.MaxHP * BOUNTY.CashPerHP, BOUNTY.CashMax))
	local xp = math.floor(math.min(rec.MaxHP * BOUNTY.XPPerHP, BOUNTY.XPMax))
	local econ = deps.EconomyService
	if cash > 0 and econ and typeof(econ.AddCash) == "function" then
		pcall(econ.AddCash, killer, cash, BOUNTY.CashReason)
	end
	local xps = deps.XPService
	if xp > 0 and xps and typeof(xps.AddXP) == "function" then
		pcall(xps.AddXP, killer, xp, BOUNTY.XPReason)
	end
	local ns = deps.NotificationService
	if ns and typeof(ns.Notify) == "function" then
		-- same shape as an NPC kill ("<name> down (+$N)"): the HUD turns it into a cash float, no lane line
		pcall(ns.Notify, killer, string.format("%s down (+$%d)", e.Def.DisplayName, cash), "Reward")
	end
end

local function destroyVehicle(e: Entry, killer: Player?)
	local rec = e.Rec
	local model = rec.Model
	rec.Destroyed = true
	rec.HP = 0
	e.Dirty = true
	-- occupants first: a disabled seat (OnWrecked) drops its occupant
	local seats: { BasePart } = {}
	local occupants: { Humanoid } = {}
	for _, d in ipairs(model:GetDescendants()) do
		local occ: Humanoid? = nil
		if d:IsA("VehicleSeat") then
			table.insert(seats, d)
			occ = d.Occupant
		elseif d:IsA("Seat") then
			table.insert(seats, d)
			occ = d.Occupant
		end
		if occ then
			table.insert(occupants, occ)
		end
	end
	local wrecked = e.OnWrecked
	if wrecked then
		local ok, err = pcall(wrecked :: any, rec)
		if not ok then
			warn("[VehicleHealth] OnWrecked failed", rec.VehicleId, err)
		end
	end
	pcall(function()
		model:SetAttribute("WE_Destroyed", true)
	end)
	for _, seat in ipairs(seats) do
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			pcall(function()
				weld:Destroy()
			end)
		end
	end
	for _, hum in ipairs(occupants) do
		pcall(function()
			hum.Sit = false
		end)
		damageOccupant(hum, killer)
	end
	payBounty(e, killer)
	local an = deps.AnalyticsService
	if an and typeof(an.Log) == "function" then
		local killerId = if killer then killer.UserId else 0
		pcall(an.Log, AnalyticsConfig.Events.VEHICLE_DESTROYED, killerId, {
			vehicle = rec.VehicleId,
			premium = rec.Premium,
			killer = killerId,
			class = e.LastClass,
		})
	end
	local secs = if rec.Premium then DCFG.RepairSeconds.Premium else DCFG.RepairSeconds.Default
	local byUser = destroyedUntil[rec.OwnerUserId]
	if byUser == nil then
		byUser = {}
		destroyedUntil[rec.OwnerUserId] = byUser
	end
	byUser[rec.VehicleId] = now() + secs
	task.delay(DCFG.DebrisSeconds, function()
		-- only while this record is still the live one (a SPAWN / despawn / leave may have torn it down already)
		if entries[model] == e then
			local ok, err = pcall(rec.OnDestroyed :: any, rec, killer)
			if not ok then
				warn("[VehicleHealth] OnDestroyed failed", rec.VehicleId, err)
			end
		end
	end)
end

local function findPlot(plotId: number): BasePart?
	local cached = plotCache[plotId]
	if cached and cached.Parent ~= nil and cached:GetAttribute("PlotId") == plotId then
		return cached
	end
	plotCache[plotId] = nil
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			plotCache[plotId] = inst
			return inst
		end
	end
	return nil
end

-- the Chassis stands on the owner's plot pad (its CFrame carries the plot yaw; profile.BasePlotId)
local function inOwnPlot(e: Entry): boolean
	local ds = deps.DataService
	if ds == nil or typeof(ds.GetProfile) ~= "function" then
		return false
	end
	local ok, profile = pcall(ds.GetProfile, e.Owner)
	local plotId = if ok and typeof(profile) == "table" then tonumber(profile.BasePlotId) else nil
	if plotId == nil then
		return false
	end
	local plot = findPlot(plotId)
	local chassis = e.Rec.Model.PrimaryPart
	if plot == nil or chassis == nil then
		return false
	end
	local lp = plot.CFrame:PointToObjectSpace(chassis.Position)
	return math.abs(lp.X) <= plot.Size.X * 0.5 and math.abs(lp.Z) <= plot.Size.Z * 0.5
end

local function regenStep(t: number, dt: number)
	for _, e in pairs(entries) do
		local rec = e.Rec
		if not rec.Destroyed and rec.HP < rec.MaxHP and t - rec.LastDamagedAt >= RCFG.DelayAfterDamageSeconds then
			local pct = 0
			if rec.Premium then
				pct = RCFG.PremiumPctPerSec
			elseif inOwnPlot(e) then
				pct = RCFG.OwnPlotPctPerSec
			end
			if pct > 0 then
				rec.HP = math.min(rec.MaxHP, rec.HP + rec.MaxHP * pct * dt)
				e.Dirty = true
			end
		end
	end
	-- prune expired repair locks and bounty pairs
	for uid, byUser in pairs(destroyedUntil) do
		for vid, untilT in pairs(byUser) do
			if untilT <= t then
				byUser[vid] = nil
			end
		end
		if next(byUser) == nil then
			destroyedUntil[uid] = nil
		end
	end
	for key, at in pairs(bountyPairs) do
		if t - at >= BOUNTY.PairCooldownSeconds then
			bountyPairs[key] = nil
		end
	end
end

-- distance from p to the model's Chassis box (0 inside it); nil without a PrimaryPart
local function distanceTo(model: Model, p: Vector3): number?
	local chassis = model.PrimaryPart
	if chassis == nil then
		return nil
	end
	local lp = chassis.CFrame:PointToObjectSpace(p)
	local h = chassis.Size * 0.5
	local c = Vector3.new(math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z))
	return (lp - c).Magnitude
end

-- J8: a CoreDestroys class destroys outright inside CoreRadius; the nuke's own switch is NukeConfig.Vehicles
local function coreAllowed(className: string): boolean
	local cls = VehicleCombatConfig.DamageClasses[className]
	if cls == nil or cls.CoreDestroys ~= true then
		return false
	end
	if className == "Nuke" then
		local nv: any = (NukeConfig :: any).Vehicles
		return not (typeof(nv) == "table" and nv.CoreDestroys == false)
	end
	return true
end

-- ── API ─────────────────────────────────────────────────────────────────────────────────────────

function VehicleHealth.Init(d: { [string]: any })
	if typeof(d) == "table" then
		deps = d
	end
	if loop.Inited then
		return
	end
	loop.Inited = true
	RunService.Heartbeat:Connect(function()
		VehicleHealth._Step(now())
	end)
end

--[[ Seat and model attributes at build (VehicleService.buildVehicleModel, before parenting): WE_Premium, and on
	each seat WE_SeatRole ("Driver" DriverSeat / "Passenger" PassengerSeatN), WE_Exposed and (passengers)
	WE_CanFireFromSeat = SeatFire.OpenFamilies[def.KitFamily]. ]]
function VehicleHealth.ApplySeatAttributes(model: Model, def: VehicleDef)
	local family: string = def.KitFamily or "WheeledLight"
	local open = VehicleCombatConfig.SeatFire.OpenFamilies[family] == true
	model:SetAttribute("WE_Premium", (def :: any).Premium ~= nil)
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("VehicleSeat") or (c:IsA("BasePart") and c.Name == "DriverSeat") then
			c:SetAttribute("WE_SeatRole", "Driver")
			c:SetAttribute("WE_Exposed", open)
		elseif c:IsA("Seat") and string.sub(c.Name, 1, 13) == "PassengerSeat" then
			c:SetAttribute("WE_SeatRole", "Passenger")
			c:SetAttribute("WE_Exposed", open)
			c:SetAttribute("WE_CanFireFromSeat", open)
		end
	end
end

function VehicleHealth.Register(model: Model, def: VehicleDef, owner: Player, opts: RegisterOpts): Record
	if entries[model] then
		VehicleHealth.Unregister(model)
	end
	local t = now()
	local hpMult = tonumber(opts.HPMult) or 1
	if not (hpMult > 0) or not finite(hpMult) then
		hpMult = 1
	end
	local am = armorMultOf(model)
	local maxHP = maxHPFor(def, am, hpMult)
	local rec: Record = {
		Model = model,
		VehicleId = def.Id,
		OwnerUserId = owner.UserId,
		MaxHP = maxHP,
		HP = maxHP,
		Armor = math.max(0, tonumber(def.Armor) or 0),
		Premium = opts.Premium == true,
		Trial = opts.Trial == true,
		SpawnedAt = t,
		LastDamagedAt = -math.huge,
		LastAttackerUserId = nil,
		LastAttackerAt = -math.huge,
		Destroyed = false,
		OnDestroyed = opts.OnDestroyed,
	}
	local e: Entry = {
		Rec = rec,
		Def = def,
		Owner = owner,
		HPMult = hpMult,
		ArmorMult = am,
		OnWrecked = opts.OnWrecked,
		LastAttacker = nil,
		LastClass = VehicleCombatConfig.DefaultInfantryClass,
		Dirty = false,
		WrittenHP = -1,
		WrittenMax = -1,
		Conns = {},
	}
	entries[model] = e
	writeAttrs(e, true)
	model:SetAttribute("WE_Destroyed", false)
	table.insert(
		e.Conns,
		model:GetAttributeChangedSignal("WE_ArmorMult"):Connect(function()
			VehicleHealth.RefreshMaxHP(model)
		end)
	)
	table.insert(
		e.Conns,
		model.AncestryChanged:Connect(function()
			if model.Parent == nil and entries[model] == e then
				VehicleHealth.Unregister(model)
			end
		end)
	)
	return rec
end

function VehicleHealth.Unregister(model: Model)
	local e = entries[model]
	if e == nil then
		return
	end
	entries[model] = nil
	for _, c in ipairs(e.Conns) do
		c:Disconnect()
	end
	table.clear(e.Conns)
end

function VehicleHealth.Get(model: Model): Record?
	local e = entries[model]
	return if e then e.Rec else nil
end

-- nearest ancestor (or self) tagged Constants.Tags.Vehicle, registered or not (catalog dress sub-models included)
function VehicleHealth.FindVehicleModel(inst: Instance): Model?
	local cur: Instance? = inst
	while cur ~= nil do
		if cur:IsA("Model") and CollectionService:HasTag(cur, Constants.Tags.Vehicle) then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

function VehicleHealth.GetSeatedVehicle(player: Player): (Model?, BasePart?)
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local seat = if hum then hum.SeatPart else nil
	if seat == nil then
		return nil, nil
	end
	return VehicleHealth.FindVehicleModel(seat), seat
end

--[[ true = attacker may not damage this vehicle: unregistered · trial · inside SpawnProtectSeconds · the attacker
	owns it or sits in it · the attacker sits in a trial vehicle (Trial.DealsVehicleDamage false). ]]
function VehicleHealth.IsProtected(model: Model, attacker: Player?): boolean
	local e = entries[model]
	if e == nil then
		return true
	end
	local rec = e.Rec
	if rec.Trial and VehicleCombatConfig.Trial.TakesDamage ~= true then
		return true
	end
	if now() - rec.SpawnedAt < HCFG.SpawnProtectSeconds then
		return true
	end
	if attacker then
		if attacker.UserId == rec.OwnerUserId then
			return true
		end
		local seatedIn = VehicleHealth.GetSeatedVehicle(attacker)
		if seatedIn == model then
			return true
		end
		local ae = if seatedIn then entries[seatedIn] else nil
		if ae and ae.Rec.Trial and VehicleCombatConfig.Trial.DealsVehicleDamage ~= true then
			return true
		end
	end
	return false
end

function VehicleHealth.ApplyDamage(model: Model, hit: DamageHit): (number, boolean)
	local e = entries[model]
	if e == nil or typeof(hit) ~= "table" then
		return 0, false
	end
	local rec = e.Rec
	if rec.Destroyed then
		return 0, false
	end
	local amount = tonumber(hit.Amount)
	if amount == nil or not (amount > 0) then
		return 0, false
	end
	local attacker = hit.Attacker
	if VehicleHealth.IsProtected(model, attacker) then
		return 0, false
	end
	local cls, wmult = resolveClass(hit.Class, hit.WeaponId, hit.WeaponMult)
	local mult = VehicleCombatConfig.DamageMult(cls, rec.Armor, wmult)
	if not (mult > 0) then
		return 0, false
	end
	local raw = amount * mult -- math.huge (CoreDestroys) stays huge → the whole HP
	local dealt = if raw >= rec.HP then rec.HP else raw
	local t = now()
	rec.HP -= dealt
	rec.LastDamagedAt = t
	e.LastClass = cls
	if attacker then
		rec.LastAttackerUserId = attacker.UserId
		rec.LastAttackerAt = t
		e.LastAttacker = attacker
	end
	e.Dirty = true
	if rec.HP <= 0 then
		rec.HP = 0
		ownerHitAt[rec.OwnerUserId] = nil -- a wreck is covered by the repair timer
		destroyVehicle(e, killerOf(e, t))
		return dealt, true
	end
	ownerHitAt[rec.OwnerUserId] = t
	return dealt, false
end

function VehicleHealth.ApplyRadiusDamage(
	center: Vector3,
	radius: number,
	maxAmount: number,
	attacker: Player?,
	class: string,
	opts: RadiusOpts?
): { Model }
	local hitList: { Model } = {}
	if typeof(center) ~= "Vector3" or not (radius > 0) or not (maxAmount > 0) then
		return hitList
	end
	local o: RadiusOpts = opts or {}
	local minMult = math.clamp(tonumber(o.MinMult) or 0.25, 0, 1)
	local core = if coreAllowed(class) then tonumber(o.CoreRadius) else nil
	local list: { Entry } = {}
	for model, e in pairs(entries) do
		if not e.Rec.Destroyed and model ~= o.IgnoreModel then
			table.insert(list, e)
		end
	end
	for _, e in ipairs(list) do
		local rec = e.Rec
		if o.IgnoreUserId ~= nil and rec.OwnerUserId == o.IgnoreUserId then
			continue
		end
		local skipFn = o.SkipOwner
		if skipFn then
			local ok, skip = pcall(skipFn, rec.OwnerUserId)
			if ok and skip == true then
				continue
			end
		end
		local d = distanceTo(rec.Model, center)
		if d == nil or d > radius then
			continue
		end
		local amount = if core ~= nil and d <= core
			then math.huge
			else maxAmount * (1 + (minMult - 1) * math.clamp(d / radius, 0, 1))
		local dealt = VehicleHealth.ApplyDamage(rec.Model, {
			Attacker = attacker,
			Amount = amount,
			Class = class,
			WeaponId = o.WeaponId,
			WeaponMult = o.WeaponMult,
			HitPos = center,
		})
		if dealt > 0 then
			table.insert(hitList, rec.Model)
		end
	end
	return hitList
end

-- research: WE_ArmorMult changed → rescale MaxHP, keep the HP fraction (no-op when unchanged)
function VehicleHealth.RefreshMaxHP(model: Model)
	local e = entries[model]
	if e == nil or e.Rec.Destroyed then
		return
	end
	local am = armorMultOf(model)
	if am == e.ArmorMult then
		return
	end
	e.ArmorMult = am
	local rec = e.Rec
	local frac = if rec.MaxHP > 0 then math.clamp(rec.HP / rec.MaxHP, 0, 1) else 1
	rec.MaxHP = maxHPFor(e.Def, am, e.HPMult)
	rec.HP = rec.MaxHP * frac
	e.Dirty = true
end

-- heal a live vehicle by pct of MaxHP (0..1; a value above 1 is read as percent, e.g. 50 = 50 %)
function VehicleHealth.Repair(model: Model, pct: number)
	local e = entries[model]
	local p = tonumber(pct)
	if e == nil or e.Rec.Destroyed or p == nil or not (p > 0) then
		return
	end
	if p > 1 then
		p = p / 100
	end
	local rec = e.Rec
	rec.HP = math.min(rec.MaxHP, rec.HP + rec.MaxHP * math.min(p :: number, 1))
	e.Dirty = true
end

-- seconds until that vehicle id may be redeployed by that player (0 = ready)
function VehicleHealth.RepairLeft(userId: number, vehicleId: string): number
	local byUser = destroyedUntil[userId]
	local untilT = if byUser then byUser[vehicleId] else nil
	if byUser == nil or untilT == nil then
		return 0
	end
	local left = untilT - now()
	if left <= 0 then
		byUser[vehicleId] = nil
		return 0
	end
	return left
end

--[[ W2 verify: seconds left of `lockSeconds` since a live vehicle of this owner last took damage (0 = none). VehicleService
	refuses SPAWN meanwhile, so SPAWN or Despawn + SPAWN is never a full heal in the middle of a fight. ]]
function VehicleHealth.HitLockLeft(userId: number, lockSeconds: number): number
	local at = ownerHitAt[userId]
	if at == nil then
		return 0
	end
	local left = (tonumber(lockSeconds) or 0) - (now() - at)
	if left <= 0 then
		ownerHitAt[userId] = nil
		return 0
	end
	return left
end

-- { [vehicleId] = whole seconds left } for every id still repairing (a plain table for VehicleStateUpdate)
function VehicleHealth.RepairingFor(userId: number): { [string]: number }
	local out: { [string]: number } = {}
	local byUser = destroyedUntil[userId]
	if byUser == nil then
		return out
	end
	local t = now()
	for vid, untilT in pairs(byUser) do
		local left = untilT - t
		if left > 0 then
			out[vid] = math.max(1, math.ceil(left - 1e-6))
		end
	end
	return out
end

--[[ One scheduler step (Heartbeat; tests call it with their own clock): the 10 Hz attribute flush for every dirty
	vehicle and the 1 Hz regen tick. No allocation unless a flush or a tick is due. ]]
function VehicleHealth._Step(t: number)
	if t >= loop.NextFlushAt then
		loop.NextFlushAt = t + 1 / math.max(1, tonumber(HCFG.AttrHz) or 10)
		for _, e in pairs(entries) do
			if e.Dirty then
				local ok = pcall(writeAttrs, e, false)
				if not ok then
					e.Dirty = false
				end
			end
		end
	end
	if t >= loop.NextRegenAt then
		local tick = math.max(0.2, tonumber(RCFG.TickSeconds) or 1)
		loop.NextRegenAt = t + tick
		local last = loop.LastRegenAt
		loop.LastRegenAt = t
		if last ~= nil then
			regenStep(t, math.clamp(t - last, 0, tick * 2))
		end
	end
end

-- test hooks
function VehicleHealth._Count(): number
	local n = 0
	for _ in pairs(entries) do
		n += 1
	end
	return n
end

function VehicleHealth._Reset()
	for model in pairs(entries) do
		VehicleHealth.Unregister(model)
	end
	table.clear(destroyedUntil)
	table.clear(bountyPairs)
	table.clear(ownerHitAt)
	table.clear(plotCache)
	loop.NextFlushAt = -math.huge
	loop.NextRegenAt = -math.huge
	loop.LastRegenAt = nil
end

return VehicleHealth
