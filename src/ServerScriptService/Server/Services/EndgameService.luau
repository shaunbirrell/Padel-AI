--!strict
--[[
	claude-bud JOB 39 (2026-09-30): ENDGAME PROGRESSION, the server side (EndgameConfig, owner-first).
	Phase 1:
	  * the Rebirth price scale: BaseService.PurchaseUpgrade asks EndgameService.ScaledCost for every structure /
	    business buy. WE_BaseCostScale (player attribute, display only) tells the client's price labels; nil = 1.
	  * EMPIRE LEVEL: profile.Endgame.EmpireLevel (0..30), kept through both rebirth paths (PrestigeService never
	    touches profile.Endgame). EconomyService.cashMultFor multiplies by EmpireMultFor (non-exempt reasons only).
	  * the plaza stations: publishes each live station's frame (ReplicatedStorage.WE_PlazaStations) from the
	    Enterables registry (a plaza house) or a store prop's forecourt; the client builds them for live players only.
	Phase 2:
	  * BASE TIER 1..5 (bought at the HQ console = the player's own Command Center console): gate HP, soldier cap,
	    AutoGun nests, the gate rebuild time, and the look (BaseTierBuilder, rebuilt by the 5 s sweep).
	  * the DEFENCE tree (Plating / Guns / Gate / Vault x 10, bought at the Engineering Bureau): read by
	    GateDefenseService (GateHpMult / RebuildCut / TurretHpMult / TurretDmgMult / ExtraNests) and
	    MoneyCollectorService.VaultMult. Every helper returns the old number while its part is not live for the OWNER.
	  * the instant REBUILD (the HQ console): a breached gate / shot-down AutoGuns at once for 30 s of income (>= 25k).
	ONE purchase path (Purchase(player, kind, id)): the flag, the requirement, the price from config (never from the
	client), the station / console reach, not hurt in the last HurtLockSeconds, then ONE SpendCash("endgame_" .. key),
	the change, save, push. Remotes: RequestEndgameBuy (kind, id?) and RequestEndgameState () through RemoteGate +
	RateLimitService; the state goes back as FeaturePush "EndgameState".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EndgameConfig = require(Shared.Configs.EndgameConfig)
local PlazaServicesConfig = require(Shared.Configs.PlazaServicesConfig)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local ResearchConfig = require(Shared.Configs.ResearchConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)

local EndgameService = {}

local deps: { [string]: any } = {}
local hurtAt: { [number]: number? } = {}
local stationCF: { [string]: any } = {} -- station kind -> the station frame (CFrame)
local profileOwner: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- profile -> UserId
local clock: () -> number = os.clock

local DEF_NAMES = { Plating = "Turret Plating", Guns = "Turret Guns", Gate = "Gate & Walls", Vault = "Vault Plating" }

local function getProfile(player: Player): any
	local ds = deps.DataService
	return if ds and ds.GetProfile then ds.GetProfile(player) else nil
end

local function profileOf(userId: number): any
	local p = Players:GetPlayerByUserId(userId)
	return if p then getProfile(p) else nil
end

local function notify(player: Player, text: string, kind: string?)
	local ns = deps.NotificationService
	if player.Parent and ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function nonNeg(v: any): number
	local n = tonumber(v) or 0
	if n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

-- the steady income (EconomyService's WE_IncomePerSec, display attribute) the income-scaled prices read
local function incomePerSec(player: Player): number
	return tonumber(player:GetAttribute("WE_IncomePerSec")) or 0
end

local function maxMult(): number
	return tonumber((ResearchConfig :: any).MaxMult) or 3
end

-- profile.Endgame, created on demand (ProfileSchema sanitises it on load)
function EndgameService.Data(profile: any): any
	if typeof(profile.Endgame) ~= "table" then
		profile.Endgame = { EmpireLevel = 0 }
	end
	return profile.Endgame
end

function EndgameService.EmpireLevel(profile: any): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	if typeof(e) ~= "table" then
		return 0
	end
	return math.min(nonNeg(e.EmpireLevel), EndgameConfig.Empire.MaxLevel)
end

function EndgameService.Tier(profile: any): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	if typeof(e) ~= "table" then
		return 0
	end
	return math.min(nonNeg(e.BaseTier), #EndgameConfig.BaseTier.Tiers)
end

function EndgameService.DefenceLevel(profile: any, track: string): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	local d = if typeof(e) == "table" and typeof(e.Defence) == "table" then e.Defence else nil
	if d == nil then
		return 0
	end
	return math.min(nonNeg(d[track]), EndgameConfig.Defence.MaxLevel)
end

-- §2.1 the price factor for this player now (1 while the Rebirth part is not live for him)
function EndgameService.CostScale(userId: number, profile: any): number
	if typeof(profile) ~= "table" or not EndgameConfig.LiveFor(userId, "Rebirth") then
		return 1
	end
	return EndgameConfig.RebirthCostScale(nonNeg(profile.Prestige))
end

-- the price BaseService charges for a structure / business level (raw cost when the part is off)
function EndgameService.ScaledCost(player: Player, profile: any, structureId: string, cost: number): number
	return EndgameConfig.ScaleStructureCost(structureId, cost, EndgameService.CostScale(player.UserId, profile))
end

-- the Empire cash factor (EconomyService.cashMultFor, non-exempt reasons); 1 while the part is not live
function EndgameService.EmpireMultFor(player: Player, profile: any): number
	if not EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then
		return 1
	end
	return EndgameConfig.EmpireMult(EndgameService.EmpireLevel(profile))
end

-- ── phase 2 effects (by the base OWNER's UserId; the old number while the part is not live) ─────────────────────
local function tierOf(userId: number): number
	if not EndgameConfig.LiveFor(userId, "BaseTier") then
		return 0
	end
	return EndgameService.Tier(profileOf(userId))
end

local function defOf(userId: number, track: string): number
	if not EndgameConfig.LiveFor(userId, "Defence") then
		return 0
	end
	return EndgameService.DefenceLevel(profileOf(userId), track)
end

-- gate HP: Base Tier (+10 % at T1 / T2 / T4) and Gate & Walls (+12 % a level), capped at MaxMult
function EndgameService.GateHpMult(userId: number): number
	local pct = EndgameConfig.TierEffects(tierOf(userId)).GateHpPct + defOf(userId, "Gate") * EndgameConfig.Defence.GatePct
	return math.min(1 + pct / 100, maxMult())
end

-- the gate rebuild seconds: base + Base Tier 3 (-10) - Gate & Walls (3 a level), never under MinRebuildSeconds
function EndgameService.RebuildCut(userId: number, base: number): number
	local tierS = EndgameConfig.TierEffects(tierOf(userId)).RebuildSeconds
	local gate = defOf(userId, "Gate")
	if tierS == 0 and gate == 0 then
		return base
	end
	return math.max(EndgameConfig.BaseTier.MinRebuildSeconds, base + tierS - gate * EndgameConfig.Defence.GateRebuildPerLevel)
end

function EndgameService.TurretHpMult(userId: number): number
	return math.min(1 + defOf(userId, "Plating") * EndgameConfig.Defence.PlatingPct / 100, maxMult())
end

-- turret damage: the research bonus x Turret Guns, the total capped at MaxMult (the research bonus alone when off)
function EndgameService.TurretDmgMult(userId: number, research: number): number
	local g = defOf(userId, "Guns")
	if g == 0 then
		return research
	end
	return math.min(research * (1 + g * EndgameConfig.Defence.GunsPct / 100), maxMult())
end

-- claude-bud JOB 40: a Defence track level for a base owner (0 while the part is not live), for the post guards
function EndgameService.DefenceLevelFor(userId: number, track: string): number
	return defOf(userId, track)
end

function EndgameService.ExtraNests(userId: number): number
	return EndgameConfig.TierEffects(tierOf(userId)).Nests
end

-- the Base Tier soldiers for SoldierService's cap (0 until the owner's profile is known / the part is live)
function EndgameService.SoldierCapBonus(profile: any): number
	local uid = profileOwner[profile]
	if uid == nil or not EndgameConfig.LiveFor(uid, "BaseTier") then
		return 0
	end
	return EndgameConfig.TierEffects(EndgameService.Tier(profile)).SoldierCap
end

-- the victim's Vault Plating: army raids x (1 - 0.05 L), ATM raids x (1 - 0.03 L)
function EndgameService.VaultMult(userId: number, army: boolean): number
	local L = defOf(userId, "Vault")
	local per = if army then EndgameConfig.Defence.VaultArmyPerLevel else EndgameConfig.Defence.VaultAtmPerLevel
	return math.max(0, 1 - per * L)
end

-- ── phase 3: ELITE TRAINING (per soldier type; the owner's own army) ─────────────────────────────────────────────
local deaths: { [number]: { [string]: number } } = {} -- trained soldiers that died and will respawn (a fee is due)
local untrained: { [number]: { [string]: number } } = {} -- soldiers that came back untrained (the fee failed)
local feeToast: { [number]: { At: number, Sum: number } } = {}

function EndgameService.MaxMult(): number
	return maxMult()
end

function EndgameService.EliteTier(profile: any, kind: string): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	local m = if typeof(e) == "table" and typeof(e.Elite) == "table" then e.Elite else nil
	if m == nil then
		return 0
	end
	return math.min(nonNeg(m[kind]), #EndgameConfig.Elite.Tiers)
end

-- the unit record a spawn / re-dress uses: { Kind, Tier, Hp, Dmg, Scale, Untrained }
function EndgameService.EliteFor(kind: string, tier: number, untrainedNow: boolean?): { [string]: any }
	local s = EndgameConfig.EliteStats(kind, tier)
	return { Kind = kind, Tier = tier, Hp = s.Hp, Dmg = s.Dmg, Scale = s.Scale, Untrained = untrainedNow == true }
end

function EndgameService.RetrainFee(tier: number): number
	local row: any = EndgameConfig.Elite.Tiers[tier]
	return if row then tonumber(row.RetrainFee) or 0 else 0
end

local function bump(map: { [number]: { [string]: number } }, uid: number, kind: string, n: number)
	local m = map[uid]
	if m == nil then
		m = {}
		map[uid] = m
	end
	m[kind] = math.max(0, (m[kind] or 0) + n)
end

-- SquadOrdersService: a trained soldier died (its respawn owes the re-train fee)
function EndgameService.NoteUnitDeath(uid: number, kind: string, tier: number, wasUntrained: boolean?)
	if wasUntrained == true then
		bump(untrained, uid, kind, -1) -- it will ask again on its respawn
	end
	if tier > 0 or wasUntrained == true then
		bump(deaths, uid, kind, 1)
	end
end

--[[ SquadOrdersService.spawnUnit: this slot's soldier (nil while the Elite part is not live = today's soldier). A
	respawn of a trained soldier that died pays its re-train fee first (a free re-train from the Instant Army Refill,
	else Cash through the one purchase path); if the fee cannot be paid it comes back untrained. ]]
function EndgameService.UnitElite(owner: Player, slot: number): { [string]: any }?
	if not EndgameConfig.LiveFor(owner.UserId, "Elite") then
		return nil
	end
	local profile = getProfile(owner)
	if profile == nil then
		return nil
	end
	local sf = if typeof(profile.BaseUpgrades) == "table" then nonNeg(profile.BaseUpgrades.SpecialForcesFacility) else 0
	local kind = EndgameConfig.SlotKind(slot, sf)
	local tier = EndgameService.EliteTier(profile, kind)
	if tier <= 0 then
		return EndgameService.EliteFor(kind, 0)
	end
	local d = deaths[owner.UserId]
	if d and (d[kind] or 0) > 0 then
		d[kind] -= 1
		local ok = EndgameService.Purchase(owner, "Retrain", kind, true)
		if not ok then
			bump(untrained, owner.UserId, kind, 1)
			notify(owner, string.format(EndgameConfig.Text.RetrainShort, 1), "Warn")
			return EndgameService.EliteFor(kind, 0, true)
		end
		local fee = EndgameService.RetrainFee(tier)
		local t = feeToast[owner.UserId]
		if t == nil or clock() - t.At > 10 then
			feeToast[owner.UserId] = { At = clock(), Sum = fee }
			notify(owner, string.format("Re-trained a soldier: -$%dK", math.floor(fee / 1000)), "Info")
		end
	end
	return EndgameService.EliteFor(kind, tier)
end

-- the untrained soldiers now: (count, the fee to re-train them all)
function EndgameService.UntrainedNow(player: Player, profile: any): (number, number)
	local m = untrained[player.UserId]
	local n, fee = 0, 0
	for kind, c in pairs(m or {}) do
		if c > 0 then
			n += c
			fee += c * EndgameService.RetrainFee(EndgameService.EliteTier(profile, kind))
		end
	end
	return n, fee
end

-- the Instant Army Refill (49 R$, SoldierService.ConsumeRefills after the receipt is saved): every soldier comes back
-- at its trained tier with no fee (the untrained ones now, the dead ones on their respawn)
function EndgameService.GrantRefill(player: Player)
	if not EndgameConfig.LiveFor(player.UserId, "Elite") then
		return
	end
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	local owed = 0
	for _, c in pairs(deaths[player.UserId] or {}) do
		owed += c
	end
	local e = EndgameService.Data(profile)
	e.FreeRetrains = math.min(nonNeg(e.FreeRetrains) + owed, EndgameConfig.Elite.MaxFreeRetrains)
	untrained[player.UserId] = nil
	if deps.DataService and deps.DataService.MarkDirty then
		deps.DataService.MarkDirty(player)
	end
	local sq = deps.SquadOrdersService
	if sq and sq._ReapplyElite then
		pcall(sq._ReapplyElite, player)
	end
end

--[[ The look of a trained soldier (server, on the unit model before it is parented, or in place): a helmet trim band in
	the tier colour, 1 / 2 / 3 gold chevrons on the left arm (Mythic: a gold star plate), Heavy shoulder pads, the rig
	scaled by the tier (Model:ScaleTo; the hip height follows), and the attributes the damage sites / client read. ]]
function EndgameService.DressUnit(model: Model, humanoid: Humanoid, elite: { [string]: any }, hip0: number)
	for _, c in ipairs(model:GetDescendants()) do
		if c:IsA("BasePart") and c:GetAttribute("WE_EliteDress") == true then
			c:Destroy()
		end
	end
	local El = EndgameConfig.Elite
	local tier = if elite.Untrained then 0 else elite.Tier
	local head = model:FindFirstChild("Head", true)
	local arm = model:FindFirstChild("Left Arm", true) or model:FindFirstChild("ArmL", true)
	local torso = model:FindFirstChild("Torso", true) or model:FindFirstChild("Vest", true)
	local function dress(name: string, host: Instance?, size: Vector3, offset: CFrame, color: Color3)
		if host == nil or not host:IsA("BasePart") then
			return
		end
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = host.CFrame * offset
		p.Color = color
		p.Material = Enum.Material.Metal
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p:SetAttribute("WE_EliteDress", true)
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = host
		w.Part1 = p
		w.Parent = p
	end
	if tier > 0 then
		local trim = El.Trim[tier] or El.TrimAccent
		dress("EliteTrim", head, Vector3.new(1.32, 0.18, 1.32), CFrame.new(0, 0.42, 0), trim)
		if tier >= 4 then
			dress("EliteStar", arm, Vector3.new(0.12, 0.5, 0.5), CFrame.new(-0.52, 0.55, 0) * CFrame.Angles(math.rad(45), 0, 0), El.TrimAccent)
		else
			for i = 1, tier do
				dress("EliteChevron", arm, Vector3.new(0.1, 0.12, 0.7), CFrame.new(-0.52, 0.75 - i * 0.22, 0), El.TrimAccent)
			end
		end
	end
	if elite.Kind == "Heavy" then
		for _, s in ipairs({ -1, 1 }) do
			dress("HeavyPad", torso, Vector3.new(0.9, 0.35, 1.2), CFrame.new(1.05 * s, 1.0, 0), Color3.fromRGB(52, 60, 44))
		end
	end
	local scale = if tier > 0 then elite.Scale else 1
	pcall(function()
		model:ScaleTo(scale)
	end)
	humanoid.HipHeight = hip0 * scale
	model:SetAttribute("WE_EliteKind", elite.Kind)
	model:SetAttribute("WE_EliteTier", tier)
	model:SetAttribute("WE_EliteDmg", if elite.Untrained then (if elite.Kind == "SpecialForces" then El.SpecialForcesDmgMult else 1) else elite.Dmg)
	model:SetAttribute("WE_EliteScale", scale)
	model:SetAttribute("WE_EliteUntrained", if elite.Untrained then true else nil)
end

-- ── phase 4: the FIELD HOSPITAL (the player's own health; the ONE place new code writes a player's Health) ───────────
local healAt: { [number]: number } = {}
local diedAt: { [number]: { At: number, CF: CFrame } } = {} -- where / when the player last fell (the revive window)
local healing: { [number]: boolean } = {}

function EndgameService.MedicineLevel(profile: any): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	return if typeof(e) == "table" then math.min(nonNeg(e.Medicine), #EndgameConfig.Hospital.Medicine.Costs) else 0
end

-- ArmourService: the Combat Medicine max-HP bonus (0 while the Hospital part is not live for him)
function EndgameService.MedicineBonus(player: Player): number
	if not EndgameConfig.LiveFor(player.UserId, "Hospital") then
		return 0
	end
	return EndgameConfig.MedicineHp(EndgameService.MedicineLevel(getProfile(player)))
end

local function humOf(player: Player): Humanoid?
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

-- the Med Kit heal: HealPerKit over Seconds, in 6 steps; stops when he dies or is full
local function healOverTime(player: Player, amount: number, seconds: number)
	if healing[player.UserId] then
		return
	end
	healing[player.UserId] = true
	task.spawn(function()
		local steps = 6
		for _ = 1, steps do
			local h = humOf(player)
			if h == nil or h.Health >= h.MaxHealth then
				break
			end
			h.Health = math.min(h.MaxHealth, h.Health + amount / steps)
			task.wait(seconds / steps)
		end
		healing[player.UserId] = nil
	end)
end

-- is `pos` inside ANOTHER player's plot (a revive is refused there: the siege rule)
local function inEnemyPlot(player: Player, pos: Vector3): boolean
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local profile = getProfile(player)
	local own = if profile then tonumber(profile.BasePlotId) else nil
	for _, f in ipairs(if bases then bases:GetChildren() else {}) do
		local pad = f:FindFirstChild("PlotPad")
		if pad and pad:IsA("BasePart") and f.Name ~= ("Plot" .. tostring(own)) then
			local lp = pad.CFrame:PointToObjectSpace(pos)
			if math.abs(lp.X) <= pad.Size.X * 0.5 and math.abs(lp.Z) <= pad.Size.Z * 0.5 then
				return true
			end
		end
	end
	return false
end

--[[ The Field Surgeon: get up where you fell. The ONLY move in the endgame code, and it is not travel: the new body is
	placed back on the spot the old one fell (Hospital.Revive.WithinSeconds after death), never anywhere else. ]]
function EndgameService.Revive(player: Player): (boolean, string)
	local d = diedAt[player.UserId]
	local R = EndgameConfig.Hospital.Revive
	if d == nil or clock() - d.At > R.WithinSeconds then
		return false, "Too late to revive"
	end
	if inEnemyPlot(player, d.CF.Position) then
		return false, "No revive inside an enemy base"
	end
	diedAt[player.UserId] = nil
	local fell = d.CF
	task.spawn(function()
		local ok = pcall(function()
			(player :: any):LoadCharacter()
		end)
		local c = player.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if ok and c and h then
			c:PivotTo(fell + Vector3.new(0, 3, 0)) -- the spot he fell on (not travel: WithinSeconds of his death, same place)
			h.Health = h.MaxHealth * R.HpFraction
		end
	end)
	return true, "Back on your feet"
end

-- phase 4: the army medic (Combat Medicine L3+): each sweep (5 s) a soldier not hurt since the last sweep gets back
-- 1 HP a second of it. Soldiers only (never a player).
local unitLastHp: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
function EndgameService.MedicTick(player: Player, seconds: number)
	if not EndgameConfig.LiveFor(player.UserId, "Hospital") then
		return
	end
	if EndgameService.MedicineLevel(getProfile(player)) < EndgameConfig.Hospital.Medicine.MedicLevel then
		return
	end
	local sq = deps.SquadOrdersService
	local st = if sq and sq.StateOf then sq.StateOf(player) else nil
	if st == nil then
		return
	end
	for _, u in ipairs(st.Units) do
		local h = u.Humanoid
		if u.Alive and h and h.Health > 0 then
			local prev = unitLastHp[u]
			if prev ~= nil and h.Health >= prev and h.Health < h.MaxHealth then
				h.Health = math.min(h.MaxHealth, h.Health + seconds)
			end
			unitLastHp[u] = h.Health
		end
	end
end

-- ── phase 4: the ARMORY WORKSHOP (mastery, attachments, camos) and the VEHICLE WORKSHOP ──────────────────────────
local gunCache: { [number]: { [string]: { Sig: string, Def: any } } } = {}

local function endgameMap(profile: any, key: string): { [string]: any }
	local e = EndgameService.Data(profile)
	if typeof(e[key]) ~= "table" then
		e[key] = {}
	end
	return e[key]
end

function EndgameService.MasteryLevel(profile: any, weaponId: string): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	local m = if typeof(e) == "table" and typeof(e.Mastery) == "table" then e.Mastery else nil
	return if m then math.min(nonNeg(m[weaponId]), EndgameConfig.Mastery.MaxLevel) else 0
end

function EndgameService.Attachments(profile: any, weaponId: string): { [string]: boolean }
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	local a = if typeof(e) == "table" and typeof(e.Attachments) == "table" then e.Attachments[weaponId] else nil
	return if typeof(a) == "table" then a else {}
end

-- the owned guns (CombatService writes WE_Weapons = the sorted comma list of owned ids)
local function ownedGuns(player: Player): { string }
	local out: { string } = {}
	local s = player:GetAttribute("WE_Weapons")
	if typeof(s) == "string" then
		for id in string.gmatch(s, "[^,]+") do
			if WeaponConfig.Weapons[id] ~= nil then
				table.insert(out, id)
			end
		end
	end
	return out
end

--[[ CombatService: the weapon row this player's shots / reload / magazine use. The WeaponConfig row itself while the
	Mastery part is not live or the gun has no mastery / attachment (OFF = old); else a copy with GunStats applied
	(cached until the level / attachments change), marked __eg so it is never applied twice. ]]
function EndgameService.PlayerGunDef(player: Player?, def: any): any
	if player == nil or typeof(def) ~= "table" or def.__eg == true or typeof(def.Id) ~= "string" then
		return def
	end
	if not EndgameConfig.LiveFor(player.UserId, "Mastery") then
		return def
	end
	local profile = getProfile(player)
	if profile == nil then
		return def
	end
	local L = EndgameService.MasteryLevel(profile, def.Id)
	local att = EndgameService.Attachments(profile, def.Id)
	local sig = tostring(L)
	for _, slot in ipairs(EndgameConfig.Mastery.AttachOrder) do
		sig ..= if att[slot] then "1" else "0"
	end
	if sig == "00000" then
		return def
	end
	local byGun = gunCache[player.UserId]
	if byGun == nil then
		byGun = {}
		gunCache[player.UserId] = byGun
	end
	local hit = byGun[def.Id]
	if hit and hit.Sig == sig then
		return hit.Def
	end
	local out = table.clone(def)
	for k, v in pairs(EndgameConfig.GunStats(def, L, att)) do
		out[k] = v
	end
	out.__eg = true
	byGun[def.Id] = { Sig = sig, Def = out }
	return out
end

-- WE_GunMods for the client's local fire rate / range / reload / reticle: "Id=rate,range,reload,spread;..." (the
-- multipliers vs the WeaponConfig row; only guns that differ). nil while nothing is upgraded.
function EndgameService.GunModsString(player: Player): string?
	if not EndgameConfig.LiveFor(player.UserId, "Mastery") then
		return nil
	end
	local parts: { string } = {}
	for _, id in ipairs(ownedGuns(player)) do
		local def: any = WeaponConfig.Weapons[id]
		local g = EndgameService.PlayerGunDef(player, def)
		if g ~= def then
			local function r(a: any, b: any): number
				local x, y = tonumber(a) or 0, tonumber(b) or 0
				return if y > 0 then x / y else 1
			end
			table.insert(parts, string.format("%s=%.3f,%.3f,%.3f,%.3f", id, r(g.FireRate, def.FireRate), r(g.Range, def.Range), r(g.ReloadTime, def.ReloadTime), r(g.Spread, def.Spread)))
		end
	end
	return if #parts > 0 then table.concat(parts, ";") else nil
end

-- the camo on a gun (nil = none / not live): CombatService sets the character's WE_GunCamo with the drawn gun.
-- v157: live with the Armory (Mastery) OR the Black Market; without the Armory only the Black Market's camos show.
function EndgameService.CamoFor(player: Player, weaponId: string?): string?
	if weaponId == nil or not EndgameConfig.CamoLiveFor(player.UserId) then
		return nil
	end
	local profile = getProfile(player)
	local e = if profile then profile.Endgame else nil
	local c = if typeof(e) == "table" and typeof(e.Camos) == "table" then e.Camos else nil
	local eq = if c and typeof(c.Equip) == "table" then c.Equip[weaponId] else nil
	if typeof(eq) ~= "string" or c == nil or c[eq] ~= true then
		return nil
	end
	if not EndgameConfig.LiveFor(player.UserId, "Mastery") and EndgameConfig.MarketCamos()[eq] == nil then
		return nil
	end
	return eq
end

-- VehicleService: the Vehicle Workshop factors for a spawn (1, 1 while the part is not live)
function EndgameService.WorkshopFor(userId: number, category: string?): (number, number, number)
	if not EndgameConfig.LiveFor(userId, "Workshop") then
		return 1, 1, 0
	end
	local profile = profileOf(userId)
	local e = if profile then profile.Endgame else nil
	local w = if typeof(e) == "table" and typeof(e.Workshop) == "table" then e.Workshop else nil
	local L = if w then math.min(nonNeg(w[category or "Ground"]), EndgameConfig.Workshop.MaxLevel) else 0
	local hp, sp = EndgameConfig.WorkshopMults(L)
	return hp, sp, L
end

-- VehicleService: the Workshop look on a spawned vehicle: L3 bolt-on armour plates on both flanks (+ a skirt), L5 a
-- gold nameplate trim on the nose. Welded to the vehicle's PrimaryPart, massless, never colliding.
function EndgameService.DressVehicle(model: Model, L: number)
	local W = EndgameConfig.Workshop
	local base = model.PrimaryPart
	if L < W.PlateLevel or base == nil then
		return
	end
	local cf, size = model:GetBoundingBox()
	local function plate(name: string, sz: Vector3, at: CFrame, color: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = sz
		p.CFrame = at
		p.Color = color
		p.Material = mat
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p:SetAttribute("WE_WorkshopPiece", true)
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = base
		w.Part1 = p
		w.Parent = p
	end
	local armour = Color3.fromRGB(70, 74, 64)
	local len = math.max(size.Z * 0.55, 2)
	local h = math.max(size.Y * 0.28, 0.6)
	for _, s in ipairs({ -1, 1 }) do
		plate("WorkshopPlate", Vector3.new(0.25, h, len), cf * CFrame.new(s * (size.X * 0.5 + 0.12), -size.Y * 0.12, 0), armour, Enum.Material.DiamondPlate)
		plate("WorkshopBolts", Vector3.new(0.12, 0.2, len * 0.9), cf * CFrame.new(s * (size.X * 0.5 + 0.3), -size.Y * 0.12 + h * 0.3, 0), Color3.fromRGB(40, 42, 40), Enum.Material.Metal)
	end
	if L >= W.TrimLevel then
		plate("WorkshopNameplate", Vector3.new(math.max(size.X * 0.4, 0.8), 0.3, 0.12), cf * CFrame.new(0, size.Y * 0.1, -size.Z * 0.5 - 0.08), Color3.fromRGB(214, 178, 64), Enum.Material.Metal)
	end
end

-- ── phase 5: the BLACK MARKET (cosmetics), the rebirth UNLOCKS, the INTEL OFFICE (contracts / scouting / raided-by) ──
local scoutReport: { [number]: { [string]: any } } = {}
local pendingScoutCard: { [number]: { [string]: any } } = {} -- Code Bot v171: the result card to push after a scout buy

local function nowUnix(): number
	return os.time()
end

function EndgameService.MarketStock(): { [string]: any }
	local week = EndgameConfig.WeekIndex(nowUnix())
	local s = EndgameConfig.BlackMarketStock(week)
	local nextMonday = EndgameConfig.BlackMarket.EpochMondayUnix + (week + 1) * 604800
	return { Week = week, Cash = s.Cash, Gold = s.Gold, GoldPrice = s.GoldPrice, EndsIn = math.max(0, nextMonday - nowUnix()) }
end

local function marketData(profile: any): { [string]: any }
	local bm = endgameMap(profile, "BlackMarket")
	if typeof(bm.Bought) ~= "table" then
		bm.Bought = {}
	end
	if typeof(bm.Equip) ~= "table" then
		bm.Equip = {}
	end
	return bm
end

-- the equipped Black Market item of a kind for a base owner (nil = none / not live)
local function equipped(userId: number, kind: string): any
	if not EndgameConfig.LiveFor(userId, "BlackMarket") then
		return nil
	end
	local profile = profileOf(userId)
	if profile == nil then
		return nil
	end
	local id = marketData(profile).Equip[kind]
	local item = if typeof(id) == "string" then EndgameConfig.BlackMarket.Items[id] else nil
	return if item and marketData(profile).Bought[id] == true then item else nil
end

function EndgameService.BannerColor(userId: number): Color3?
	local it = equipped(userId, "Banner")
	return if it then it.Color else nil
end
function EndgameService.BeretColor(userId: number): Color3?
	local it = equipped(userId, "Beret")
	return if it then it.Color else nil
end
function EndgameService.PaintColor(userId: number): Color3?
	local it = equipped(userId, "Paint")
	return if it then it.Color else nil
end
function EndgameService.HasTrophy(userId: number): boolean
	return equipped(userId, "Trophy") ~= nil
end

-- the endgame rebirth unlocks this player holds (granted by SyncUnlocks while the Rebirth part is live)
function EndgameService.HasUnlock(userId: number, flag: string): boolean
	if not EndgameConfig.LiveFor(userId, "Rebirth") then
		return false
	end
	local profile = profileOf(userId)
	local e = if profile then profile.Endgame else nil
	return typeof(e) == "table" and typeof(e.Unlocks) == "table" and e.Unlocks[flag] == true
end

function EndgameService.SyncUnlocks(player: Player)
	if not EndgameConfig.LiveFor(player.UserId, "Rebirth") then
		return
	end
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	local u = endgameMap(profile, "Unlocks")
	for _, row in ipairs(EndgameConfig.RebirthUnlocks) do
		if nonNeg(profile.Prestige) >= row.At and u[row.Flag] ~= true then
			u[row.Flag] = true
			notify(player, "Rebirth unlock: " .. row.Name, "Success")
			if deps.DataService and deps.DataService.MarkDirty then
				deps.DataService.MarkDirty(player)
			end
		end
	end
end

-- a soldier's beret in the owner's Black Market colour (SquadOrdersService.spawnUnit; nothing while not live)
function EndgameService.CosmeticUnit(owner: Player, model: Model)
	local c = EndgameService.BeretColor(owner.UserId)
	if c == nil then
		return
	end
	local beret = model:FindFirstChild("Beret", true) or model:FindFirstChild("Helmet", true)
	if beret and beret:IsA("BasePart") then
		beret.Color = c
		local sm = beret:FindFirstChildOfClass("SpecialMesh")
		if sm and sm.TextureId ~= "" then
			sm.VertexColor = Vector3.new(c.R, c.G, c.B) * 1.6 -- a textured hat takes the colour as a tint
		end
	end
end

-- a vehicle in the owner's Black Market paint (VehicleService spawn): the biggest body parts take the paint
function EndgameService.PaintVehicle(model: Model, userId: number)
	local c = EndgameService.PaintColor(userId)
	if c == nil then
		return
	end
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.5 and d:GetAttribute("WE_WorkshopPiece") ~= true and d.Size.Magnitude > 3 then
			table.insert(parts, d)
		end
	end
	table.sort(parts, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	for i = 1, math.min(#parts, 6) do
		parts[i].Color = c
	end
end

-- ── phase 5: WARHEADS (the silo; NukeService asks), the HEIST kits (BankRaidService asks), the bounty scale ──
function EndgameService.HeavyWarheadMults(player: Player): (number, number, boolean)
	if not EndgameConfig.LiveFor(player.UserId, "Warheads") then
		return 1, 1, false
	end
	local profile = getProfile(player)
	local w = if profile and typeof(profile.Endgame) == "table" and typeof(profile.Endgame.Warheads) == "table" then profile.Endgame.Warheads else nil
	if w == nil or nonNeg(w.Heavy) < 1 then
		return 1, 1, false
	end
	local H = EndgameConfig.Warheads.Heavy
	return H.RadiusMult, H.DamageMult, true
end

-- NukeService.Launch spent a Heavy warhead (it rode on this launch)
function EndgameService.SpendHeavy(player: Player)
	local profile = getProfile(player)
	if profile then
		local w = endgameMap(profile, "Warheads")
		w.Heavy = math.max(0, nonNeg(w.Heavy) - 1)
		if deps.DataService and deps.DataService.MarkDirty then
			deps.DataService.MarkDirty(player)
		end
	end
end

function EndgameService.HeistKit(player: Player): number
	if not EndgameConfig.LiveFor(player.UserId, "Heist") then
		return 0
	end
	local profile = getProfile(player)
	local e = if profile then profile.Endgame else nil
	return if typeof(e) == "table" then math.min(nonNeg(e.HeistKit), #EndgameConfig.Heist.Kits) else 0
end

-- BankRaidService: the vault the raider's kit opens: (hold seconds, payout, cooldown, extra guards); the old
-- numbers without a kit / while not live
function EndgameService.HeistRules(player: Player, hold: number, cash: number, cooldown: number): (number, number, number, number)
	local k = EndgameService.HeistKit(player)
	local row: any = EndgameConfig.Heist.Kits[k]
	if row == nil then
		return hold, cash, cooldown, 0
	end
	local pay = EndgameConfig.IncomeMinutesPrice(row.Floor, row.Minutes, incomePerSec(player))
	return row.Hold, pay, (tonumber(row.Cooldown) or cooldown), row.Guards
end

-- PlazaBounty: the bounty grows to 3 min of the claimer's income (the reason is multiplied, so the cash
-- multiplier is divided back out; 1 = the config's $15,000 while not live)
function EndgameService.BountyScale(player: Player, base: number): number
	if not EndgameConfig.LiveFor(player.UserId, "RewardScaling") or base <= 0 then
		return 1
	end
	local eco = deps.EconomyService
	local okM, m = pcall(function()
		return eco and eco.GetCashMult and eco.GetCashMult(player, "plaza_bounty")
	end)
	local mult = if okM and typeof(m) == "number" and m > 0 then m else 1
	local target = EndgameConfig.IncomeMinutesPrice(EndgameConfig.Heist.BountyFloor, EndgameConfig.Heist.BountyMinutes, incomePerSec(player)) / mult
	return math.max(1, target / base)
end

-- ── the Intel Office's contracts ──
local function dayIndex(): number
	return math.floor(nowUnix() / 86400)
end

local function contractsOf(player: Player, profile: any): { [string]: any }
	local c = endgameMap(profile, "Contracts")
	local day = dayIndex()
	if c.Day ~= day or typeof(c.Rows) ~= "table" then
		c.Day = day
		local rows = {}
		for _, def in ipairs(EndgameConfig.DailyContracts(player.UserId, day)) do
			table.insert(rows, { Kind = def.Kind, Need = def.Need, Have = 0, Paid = false, Text = string.format(def.Text, def.Need) })
		end
		c.Rows = rows
	end
	local week = EndgameConfig.WeekIndex(nowUnix())
	if c.Week ~= week or typeof(c.Hvt) ~= "table" then
		c.Week = week
		local h = EndgameConfig.WeeklyHvt(week)
		c.Hvt = { Kind = h.Kind, Need = h.Need, Have = 0, Paid = false, Text = string.format(h.Text, h.Need) }
	end
	if typeof(c.RaidedBy) ~= "table" then
		c.RaidedBy = {}
	end
	return c
end

-- an event that counts for contracts (the game's own hooks call this; nothing while not live)
function EndgameService.NoteContract(player: Player?, kind: string, n: number?)
	if player == nil or not EndgameConfig.LiveFor(player.UserId, "Contracts") then
		return
	end
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	local c = contractsOf(player, profile)
	local add = math.max(1, math.floor(tonumber(n) or 1))
	local changed = false
	for _, r in ipairs(c.Rows) do
		if r.Kind == kind and r.Have < r.Need then
			r.Have = math.min(r.Need, r.Have + add)
			changed = true
			if r.Have >= r.Need then
				notify(player, "Contract done: claim it at the Intel Office", "Success")
			end
		end
	end
	local h = c.Hvt
	if h and h.Kind == kind and h.Have < h.Need then
		h.Have = math.min(h.Need, h.Have + add)
		changed = true
		if h.Have >= h.Need then
			notify(player, "Weekly target done: claim it at the Intel Office", "Success") -- Code Bot v168
		end
	end
	if changed and deps.DataService and deps.DataService.MarkDirty then
		deps.DataService.MarkDirty(player)
	end
	if changed then
		-- Code Bot v168: the Intel Office guidance (WE_IntelGuide) appears with the toast, not on the next 5 s sweep
		pcall(EndgameService.SyncIntelGuide, player)
	end
end

--[[ Code Bot v168 (Shaun 2026-10-01: after "Contract done: claim it at the Intel Office" the game should guide him
	there). READ ONLY (never resets the day / week like contractsOf): true while today's daily rows or this week's HVT
	hold a done-but-unpaid contract. ]]
function EndgameService.IntelClaimable(profile: any): boolean
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	local c = if typeof(e) == "table" then e.Contracts else nil
	if typeof(c) ~= "table" then
		return false
	end
	if c.Day == dayIndex() and typeof(c.Rows) == "table" then
		for _, r in ipairs(c.Rows) do
			if typeof(r) == "table" and r.Paid ~= true and nonNeg(r.Have) >= math.max(1, nonNeg(r.Need)) then
				return true
			end
		end
	end
	local h = c.Hvt
	if c.Week == EndgameConfig.WeekIndex(nowUnix()) and typeof(h) == "table" and h.Paid ~= true and nonNeg(h.Have) >= math.max(1, nonNeg(h.Need)) then
		return true
	end
	return false
end

--[[ Code Bot v168: the player attribute WE_IntelGuide = the Intel Office's NPC point (the world has ONE Intel Office,
	PlazaServicesConfig.Stations.Intel in NW_W1, so it is the nearest) while a contract waits to be claimed, else nil.
	The client (Modules/IntelGuide) points the ONE tracker (ObjectiveMarker: the compass pill + the world marker, the
	same system as BASE / AIRDROP) at it. Set on completion (NoteContract), cleared after the claim (Purchase ->
	SyncAttributes), kept right by the 5 s SyncAttributes sweep (a new day, a rejoin). ]]
function EndgameService.SyncIntelGuide(player: Player)
	local profile = getProfile(player)
	local at: Vector3? = nil
	if profile ~= nil and EndgameConfig.LiveFor(player.UserId, "Contracts") and EndgameService.IntelClaimable(profile) then
		at = EndgameService.StationPoint("Intel")
	end
	if player:GetAttribute("WE_IntelGuide") ~= at then
		player:SetAttribute("WE_IntelGuide", at)
	end
end

--[[ Code Bot v168: PrestigeService.AdminSetRebirth (the owner's /setrebirth): the endgame side of a rebirth count
	change, at once instead of on the next sweep. Lowering the count clears only the endgame unlock FLAGS above it. ]]
function EndgameService.AdminSyncRebirth(player: Player, prestige: number)
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	local e = if typeof(profile.Endgame) == "table" then profile.Endgame else nil
	local u = if e and typeof(e.Unlocks) == "table" then e.Unlocks else nil
	if u then
		for _, row in ipairs(EndgameConfig.RebirthUnlocks) do
			if prestige < row.At then
				u[row.Flag] = nil
			end
		end
	end
	pcall(EndgameService.SyncUnlocks, player)
	pcall(EndgameService.SyncAttributes, player)
	pcall(EndgameService.SyncBaseTier, player)
	local bss = deps.BaseSignService
	if bss and bss.Refresh then
		pcall(bss.Refresh, profile.BasePlotId)
	end
end

-- a raid on `victim` by `attacker` (the in-person ATM raid and the SEND raid): the victim's "Raided by" list, and a
-- DefendRaid contract step for the defender when a raid on him FAILED (called with defended = true)
function EndgameService.NoteRaidedBy(victim: Player, attacker: Player)
	if not EndgameConfig.LiveFor(victim.UserId, "Contracts") then
		return
	end
	local profile = getProfile(victim)
	local ap = getProfile(attacker)
	if profile == nil then
		return
	end
	local c = contractsOf(victim, profile)
	table.insert(c.RaidedBy, 1, { UserId = attacker.UserId, Name = attacker.DisplayName, At = nowUnix(), PlotId = if ap then tonumber(ap.BasePlotId) else nil })
	while #c.RaidedBy > EndgameConfig.Contracts.RaidedByKeep do
		table.remove(c.RaidedBy)
	end
	if deps.DataService and deps.DataService.MarkDirty then
		deps.DataService.MarkDirty(victim)
	end
end

function EndgameService.ContractReward(player: Player, hvt: boolean): number
	local Ct = EndgameConfig.Contracts
	return EndgameConfig.IncomeMinutesPrice(Ct.Floor, if hvt then Ct.HvtMinutes else Ct.Minutes, incomePerSec(player))
end

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- display attributes: WE_EndgameLive (the client builds stations / panels), WE_EmpireLevel, WE_BaseCostScale,
-- WE_PlotId (the HQ console the client puts its prompt on), WE_BaseTier
function EndgameService.SyncAttributes(player: Player)
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	profileOwner[profile] = player.UserId
	local anyLive = EndgameConfig.AnyLiveFor(player.UserId)
	setAttr(player, "WE_EndgameLive", if anyLive then true else nil)
	local empire = if EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then EndgameService.EmpireLevel(profile) else 0
	setAttr(player, "WE_EmpireLevel", if empire > 0 then empire else nil)
	local scale = EndgameService.CostScale(player.UserId, profile)
	setAttr(player, "WE_BaseCostScale", if scale > 1 then scale else nil)
	setAttr(player, "WE_PlotId", if anyLive then tonumber(profile.BasePlotId) else nil)
	local tier = tierOf(player.UserId)
	setAttr(player, "WE_BaseTier", if tier > 0 then tier else nil)
	-- phase 4: the Med Kit / revive counts (the client's MED KIT and GET UP buttons)
	local hosp = EndgameConfig.LiveFor(player.UserId, "Hospital")
	local eg = if typeof(profile.Endgame) == "table" then profile.Endgame else {}
	setAttr(player, "WE_MedKits", if hosp and nonNeg(eg.MedKits) > 0 then nonNeg(eg.MedKits) else nil)
	setAttr(player, "WE_Revive", if hosp and nonNeg(eg.Revive) > 0 then true else nil)
	setAttr(player, "WE_GunMods", EndgameService.GunModsString(player))
	-- phase 5: the R40 Legend Parade (clients build 6 honour-guard figures on his parade ground; the frame is published)
	local parade: CFrame? = nil
	if EndgameService.HasUnlock(player.UserId, "LegendParade") then
		local setup = Workspace:FindFirstChild("WarEmpireSetup")
		local bases = setup and setup:FindFirstChild("Bases")
		local f = bases and bases:FindFirstChild("Plot" .. tostring(profile.BasePlotId))
		local pad = f and f:FindFirstChild("PlotPad")
		if pad and pad:IsA("BasePart") then
			local okL, BL = pcall(function(): any
				return require(script.Parent.Parent.Modules.BaseLayout)
			end)
			if okL and BL then
				parade = BL.PlotCFrame(pad.Position) * CFrame.new(0, pad.Size.Y * 0.5, 14)
			end
		end
	end
	setAttr(player, "WE_ParadeCF", parade)
	pcall(EndgameService.SyncIntelGuide, player) -- Code Bot v168: the Intel Office guidance (after a claim / a new day)
end

-- the station frame for a station kind, or nil until the world registered it
function EndgameService.StationFrame(kind: string): CFrame?
	return stationCF[kind]
end

-- the NPC's world position for a station kind
function EndgameService.StationPoint(kind: string): Vector3?
	local cf = stationCF[kind]
	local st = PlazaServicesConfig.Stations[kind]
	if cf == nil or st == nil then
		return nil
	end
	return (cf * CFrame.new(st.NpcAt)).Position
end

-- (true) when the player stands within BuyRange of the station's NPC
function EndgameService.AtStation(player: Player, kind: string): boolean
	if kind == "Recruits" then
		-- claude-bud JOB A: the Recruitment Office's second interaction point: the DRILL kiosk on HIS own built Elite
		-- Barracks zone (JOB 46). Without this a buy from the kiosk was refused even with the panel open.
		local okK, kp = pcall(function(): any
			return (require :: any)(script.Parent.RebirthZoneService).KioskPoint(player, "drill")
		end)
		local c0 = player.Character
		local r0 = c0 and c0:FindFirstChild("HumanoidRootPart")
		if okK and typeof(kp) == "Vector3" and r0 and r0:IsA("BasePart") and (r0.Position - kp).Magnitude <= EndgameConfig.Station.BuyRange then
			return true
		end
	end
	local p = EndgameService.StationPoint(kind)
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if p == nil or r == nil or not r:IsA("BasePart") then
		return false
	end
	return (r.Position - p).Magnitude <= EndgameConfig.Station.BuyRange
end

-- at the player's own Command Center console (the HQ console): BaseService's console rule
function EndgameService.AtHQ(player: Player): boolean
	local bs = deps.BaseService
	if bs == nil or bs.IsAtConsole == nil then
		return false
	end
	local ok, at = pcall(bs.IsAtConsole, player, "CommandCenter")
	return ok and at == true
end

function EndgameService.RecentlyHurt(player: Player): boolean
	local t = hurtAt[player.UserId]
	return t ~= nil and clock() - t < EndgameConfig.Station.HurtLockSeconds
end

local function short(n: number): string
	if n >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.0fK", n / 1e3)
	end
	return tostring(math.floor(n))
end


function EndgameService.RebuildPrice(player: Player): number
	local D = EndgameConfig.Defence
	return EndgameConfig.IncomeMinutesPrice(D.InstantRebuildMin, D.InstantRebuildSeconds / 60, incomePerSec(player))
end

local function plotId(profile: any): number?
	return tonumber(profile.BasePlotId)
end

local function needsRebuild(profile: any): boolean
	local gd = deps.GateDefenseService
	local pid = plotId(profile)
	if gd == nil or gd.NeedsRebuild == nil or pid == nil then
		return false
	end
	local ok, v = pcall(gd.NeedsRebuild, pid)
	return ok and v == true
end

-- the next Base Tier's row (nil at max): { Tier, Name, Cost, Need (text or nil) }
function EndgameService.NextTier(profile: any): { [string]: any }?
	local t = EndgameService.Tier(profile) + 1
	local row: any = EndgameConfig.BaseTier.Tiers[t]
	if row == nil then
		return nil
	end
	local T = EndgameConfig.Text
	local need: string? = nil
	if nonNeg(profile.Prestige) < (tonumber(row.NeedRebirths) or 0) then
		need = string.format(T.NeedRebirths, row.NeedRebirths)
	elseif row.NeedCC and nonNeg(typeof(profile.BaseUpgrades) == "table" and profile.BaseUpgrades.CommandCenter or 0) < row.NeedCC then
		need = string.format(T.NeedCC, row.NeedCC)
	end
	return { Tier = t, Name = row.Name, Cost = row.Cost, Need = need }
end

-- the next level of a Defence track (nil at max): { Level, Cost, Need }
function EndgameService.NextDefence(profile: any, track: string, uid: number?): { [string]: any }?
	local L = EndgameService.DefenceLevel(profile, track) + 1
	local cost = EndgameConfig.DefenceCost(L)
	if cost == nil then
		return nil
	end
	local needT = EndgameConfig.DefenceNeedTier(L)
	local need = if EndgameService.Tier(profile) < needT then string.format(EndgameConfig.Text.NeedTier, needT) else nil
	-- claude-bud JOB 55: no turrets before Walls L4, so Turret Plating would buy nothing (owner-first)
	if need == nil and track == "Plating" and uid and EndgameConfig.DefenceFixLive(uid) then
		local minW = tonumber((require(Shared.Configs.GateDefenseConfig) :: any).AutoGunMinWallsLevel) or 4
		local walls = if typeof(profile.BaseUpgrades) == "table" then tonumber(profile.BaseUpgrades.DefensiveWalls) or 0 else 0
		if walls < minW then
			need = string.format(EndgameConfig.Text.NeedWalls, minW)
		end
	end
	return { Level = L, Cost = cost, Need = need }
end

-- claude-bud JOB 55: the track's display name (Gate & Walls -> Gate Armour while the fix is live)
local function defName(track: string, uid: number?): string
	if track == "Gate" and uid and EndgameConfig.DefenceFixLive(uid) then
		return EndgameConfig.Text.GateName
	end
	return DEF_NAMES[track] or track
end

local function defEffect(track: string, L: number, uid: number?): string
	if uid and EndgameConfig.DefenceFixLive(uid) then
		return EndgameConfig.DefenceText(track, L, EndgameConfig.TierTextLive(uid)) -- claude-bud JOB 55: the honest text (+ item 3: the turret Mk)
	end
	local D = EndgameConfig.Defence
	if track == "Plating" then
		return string.format("+%d%% turret HP", D.PlatingPct * L)
	elseif track == "Guns" then
		return string.format("+%d%% turret damage", D.GunsPct * L)
	elseif track == "Gate" then
		return string.format("+%d%% gate HP, -%d s rebuild", D.GatePct * L, D.GateRebuildPerLevel * L)
	end
	return string.format("-%d%% raid loot", math.floor(D.VaultAtmPerLevel * L * 100 + 0.5))
end

-- what the client's panels show (display only; Purchase re-checks everything)
function EndgameService.State(player: Player): { [string]: any }
	local profile = getProfile(player)
	local uid = player.UserId
	local out: { [string]: any } = { Live = EndgameConfig.AnyLiveFor(uid) }
	if profile == nil then
		return out
	end
	if EndgameConfig.LiveFor(uid, "EmpireLevel") then
		local L = EndgameService.EmpireLevel(profile)
		out.Empire = {
			Level = L,
			Max = EndgameConfig.Empire.MaxLevel,
			Pct = math.floor((EndgameConfig.EmpireMult(L) - 1) * 100 + 0.5),
			NextCost = EndgameConfig.EmpireCost(L + 1),
			NextPct = EndgameConfig.Empire.CashPctPerLevel,
			Milestone = EndgameConfig.Empire.Milestones[L + 1],
		}
	end
	if EndgameConfig.LiveFor(uid, "Rebirth") then
		local p = nonNeg(profile.Prestige)
		out.Rebirth = {
			Scale = EndgameConfig.RebirthCostScale(p),
			NextScale = EndgameConfig.RebirthCostScale(p + 1),
			NextBase = EndgameConfig.LifeCost(EndgameConfig.RebirthCostScale(p + 1)),
			Next = PrestigeConfig.NextRebirths(p, 1, nil)[1],
		}
	end
	if EndgameConfig.LiveFor(uid, "BaseTier") then
		local t = EndgameService.Tier(profile)
		out.Tier = { Level = t, Max = #EndgameConfig.BaseTier.Tiers, Name = if t > 0 then (EndgameConfig.BaseTier.Tiers :: any)[t].Name else nil, Next = EndgameService.NextTier(profile) }
	end
	if EndgameConfig.LiveFor(uid, "Defence") then
		local rows = {}
		for _, track in ipairs(EndgameConfig.Defence.Tracks) do
			local L = EndgameService.DefenceLevel(profile, track)
			local nx = EndgameService.NextDefence(profile, track, uid)
			table.insert(rows, {
				Id = track,
				Name = defName(track, uid),
				Level = L,
				Max = EndgameConfig.Defence.MaxLevel,
				Now = if L > 0 then defEffect(track, L, uid) else "none yet",
				Next = if nx then defEffect(track, nx.Level, uid) else nil,
				NextCost = if nx then nx.Cost else nil,
				Need = if nx then nx.Need else nil,
			})
		end
		out.Defence = rows
		out.Rebuild = { Need = needsRebuild(profile), Price = EndgameService.RebuildPrice(player) }
	end
	if EndgameConfig.LiveFor(uid, "Warheads") then
		local W = EndgameConfig.Warheads
		local w = endgameMap(profile, "Warheads")
		out.Warheads = {
			TacticalCost = W.Tactical.Cost,
			TacticalNeed = if nonNeg(profile.Prestige) < W.Tactical.NeedRebirths then string.format(EndgameConfig.Text.NeedRebirths, W.Tactical.NeedRebirths) else nil,
			HeavyCost = W.Heavy.Cost,
			HeavyNeed = if EndgameService.HasUnlock(uid, "HeavyWarhead") then nil else string.format(EndgameConfig.Text.NeedRebirths, W.Heavy.NeedRebirths),
			Heavy = nonNeg(w.Heavy),
		}
	end
	if EndgameConfig.LiveFor(uid, "Heist") then
		local k = math.min(nonNeg(EndgameService.Data(profile).HeistKit), #EndgameConfig.Heist.Kits)
		local nextRow: any = EndgameConfig.Heist.Kits[k + 1]
		local cur: any = EndgameConfig.Heist.Kits[k]
		out.Heist = {
			Kit = k,
			KitName = if cur then cur.Name else nil,
			Next = if nextRow then { Name = nextRow.Name, Cost = nextRow.Cost, Minutes = nextRow.Minutes, Guards = nextRow.Guards, Hold = nextRow.Hold } else nil,
		}
	end
	if EndgameConfig.LiveFor(uid, "BlackMarket") then
		local stock = EndgameService.MarketStock()
		local B = EndgameConfig.BlackMarket
		local bm = marketData(profile)
		local camos = endgameMap(profile, "Camos")
		local rows = {}
		local function row(id: string, price: number, gold: boolean)
			local it = B.Items[id]
			if it then
				local owned = if it.Kind == "Camo" then camos[it.Camo] == true else bm.Bought[id] == true
				table.insert(rows, { Id = id, Name = it.Name, Kind = it.Kind, Price = price, Gold = gold, Owned = owned, On = bm.Equip[it.Kind] == id })
			end
		end
		for i, id in ipairs(stock.Cash) do
			row(id, EndgameConfig.IncomeMinutesPrice(B.Slots[i].Floor, B.Slots[i].Minutes, incomePerSec(player)), false)
		end
		row(stock.Gold, stock.GoldPrice, true)
		local owned = {}
		for id, yes in pairs(bm.Bought) do
			local it = B.Items[id]
			if yes == true and it and table.find(stock.Cash, id) == nil and id ~= stock.Gold then
				table.insert(owned, { Id = id, Name = it.Name, Kind = it.Kind, On = bm.Equip[it.Kind] == id })
			end
		end
		-- v157: the Black Market camos he owns, to put on / take off the gun in his hand (no Armory needed)
		local heldRaw = player:GetAttribute("WE_EquippedWeapon")
		local held: string? = if typeof(heldRaw) == "string" and table.find(ownedGuns(player), heldRaw) ~= nil then heldRaw else nil
		local camoRows = {}
		local mc = EndgameConfig.MarketCamos()
		local on = if held then EndgameService.CamoFor(player, held) else nil
		for _, cm in ipairs(EndgameConfig.Mastery.CamoOrder) do
			local itemId = mc[cm]
			if itemId and camos[cm] == true then
				table.insert(camoRows, { Id = cm, Name = B.Items[itemId].Name, On = on == cm })
			end
		end
		out.Market = { Rows = rows, Owned = owned, EndsIn = stock.EndsIn, Gold = nonNeg(profile.Gold), Held = held, HeldName = if held then tostring((WeaponConfig.Weapons :: any)[held].ShortName or (WeaponConfig.Weapons :: any)[held].DisplayName or held) else nil, Camos = camoRows }
	end
	if EndgameConfig.LiveFor(uid, "Contracts") then
		local c = contractsOf(player, profile)
		local bases = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local pp = getProfile(p)
			if p ~= player and pp and tonumber(pp.BasePlotId) then
				table.insert(bases, { Name = p.DisplayName, PlotId = tonumber(pp.BasePlotId) })
			end
		end
		out.Intel = {
			Rows = c.Rows,
			Hvt = c.Hvt,
			Reward = EndgameService.ContractReward(player, false),
			HvtReward = EndgameService.ContractReward(player, true),
			RaidedBy = c.RaidedBy,
			Bases = bases,
			ScoutPrice = EndgameConfig.IncomeMinutesPrice(EndgameConfig.Contracts.ScoutFloor, EndgameConfig.Contracts.ScoutMinutes, incomePerSec(player)),
			Report = scoutReport[uid] or (if typeof(profile.Endgame) == "table" and typeof(profile.Endgame.ScoutReport) == "table" then profile.Endgame.ScoutReport else nil), -- Code Bot v171: saved too
		}
	end
	if EndgameConfig.LiveFor(uid, "Mastery") then
		local Ma = EndgameConfig.Mastery
		local guns = {}
		for _, gid in ipairs(ownedGuns(player)) do
			local def: any = WeaponConfig.Weapons[gid]
			local L = EndgameService.MasteryLevel(profile, gid)
			table.insert(guns, { Id = gid, Name = tostring(def.DisplayName or gid), Mastery = L, Max = Ma.MaxLevel, NextCost = EndgameConfig.MasteryCost(EndgameConfig.MasteryBase(def), L + 1) })
		end
		local eqRaw = player:GetAttribute("WE_EquippedWeapon")
		local eq: string? = if typeof(eqRaw) == "string" then eqRaw else nil
		local att = if typeof(eq) == "string" then EndgameService.Attachments(profile, eq) else {}
		local attRows = {}
		for _, slot in ipairs(Ma.AttachOrder) do
			table.insert(attRows, { Id = slot, Name = Ma.SlotNames[slot], Owned = att[slot] == true, Cost = Ma.Attachments[slot].Cost, Soon = slot == "Suppressor" })
		end
		local camos = {}
		local c = endgameMap(profile, "Camos")
		for _, cm in ipairs(Ma.CamoOrder) do
			table.insert(camos, { Id = cm, Gold = Ma.Camos[cm], Owned = c[cm] == true, On = typeof(eq) == "string" and EndgameService.CamoFor(player, eq) == cm })
		end
		out.Armory = { Guns = guns, Equipped = eq, Attach = attRows, Camos = camos, Gold = nonNeg(profile.Gold) }
	end
	if EndgameConfig.LiveFor(uid, "Workshop") then
		local rows = {}
		local w = endgameMap(profile, "Workshop")
		for _, cl in ipairs(EndgameConfig.Workshop.Classes) do
			local L = math.min(nonNeg(w[cl]), EndgameConfig.Workshop.MaxLevel)
			local hp, sp = EndgameConfig.WorkshopMults(L)
			table.insert(rows, { Id = cl, Level = L, Max = EndgameConfig.Workshop.MaxLevel, NextCost = EndgameConfig.WorkshopCost(L + 1), Hp = math.floor((hp - 1) * 100 + 0.5), Speed = math.floor((sp - 1) * 100 + 0.5) })
		end
		out.Workshop = rows
	end
	if EndgameConfig.LiveFor(uid, "Hospital") then
		local H = EndgameConfig.Hospital
		local e = EndgameService.Data(profile)
		local L = EndgameService.MedicineLevel(profile)
		local last = healAt[uid]
		out.Hospital = {
			HealIn = if last then math.max(0, math.ceil(H.HealCooldown - (clock() - last))) else 0,
			MedKits = nonNeg(e.MedKits),
			MedKitMax = H.MedKit.Max,
			MedKitPrice = EndgameConfig.IncomeMinutesPrice(H.MedKit.Floor, H.MedKit.IncomeSeconds / 60, incomePerSec(player)),
			Medicine = L,
			MedicineMax = #H.Medicine.Costs,
			MedicineNext = H.Medicine.Costs[L + 1],
			Revive = nonNeg(e.Revive),
			RevivePrice = EndgameConfig.IncomeMinutesPrice(H.Revive.Floor, H.Revive.IncomeSeconds / 60, incomePerSec(player)),
		}
	end
	if EndgameConfig.LiveFor(uid, "Elite") then
		local rows = {}
		for _, k in ipairs(EndgameConfig.Elite.Types) do
			local t = EndgameService.EliteTier(profile, k)
			local nextRow: any = EndgameConfig.Elite.Tiers[t + 1]
			local need = if nextRow and nextRow.NeedRebirths and nonNeg(profile.Prestige) < nextRow.NeedRebirths then string.format(EndgameConfig.Text.NeedRebirths, nextRow.NeedRebirths) else nil
			table.insert(rows, {
				Id = k,
				Name = EndgameConfig.Elite.Names[k] or k,
				Tier = t,
				TierName = if t > 0 then (EndgameConfig.Elite.Tiers :: any)[t].Name else "Recruit",
				NextName = if nextRow then nextRow.Name else nil,
				NextCost = if nextRow then nextRow.Cost else nil,
				Pct = EndgameConfig.Elite.PctPerTier * t,
				Need = need,
			})
		end
		out.Elite = rows
		local n, fee = EndgameService.UntrainedNow(player, profile)
		out.Retrain = { Count = n, Price = fee, Free = nonNeg(EndgameService.Data(profile).FreeRetrains) }
	end
	local points: { [string]: any } = {}
	for kind, st in pairs(PlazaServicesConfig.Stations) do
		local pt = EndgameService.StationPoint(kind)
		if pt and EndgameConfig.LiveFor(uid, st.Part) then
			points[kind] = { X = pt.X, Y = pt.Y, Z = pt.Z }
		end
	end
	out.Stations = points
	return out
end

function EndgameService.Push(player: Player)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "EndgameState", EndgameService.State(player))
	end
end

-- Code Bot v171: after a scout purchase, the result card (FeaturePush "ScoutReport"); a no-op otherwise
function EndgameService.PushScoutCard(player: Player)
	local rep = pendingScoutCard[player.UserId]
	if rep == nil then
		return
	end
	pendingScoutCard[player.UserId] = nil
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "ScoutReport", rep)
	end
end

type Plan = { Key: string, Price: number, Apply: (profile: any) -> string, Log: string, Gold: boolean? }

-- Code Bot v171: the Intel Office scouting report on an online player's base (pure read; never yields). Built before
-- the charge (see _Plan "Scout"). Fields: Name, PlotId, At, Turrets, Guards, GateHp, GateMax, Tier, Defence, Verdict.
function EndgameService.BuildScoutReport(player: Player, tgt: Player, pid: number): { [string]: any }
	local rep: { [string]: any } = { Name = tgt.DisplayName, PlotId = pid, At = nowUnix() }
	local gd = deps.GateDefenseService
	local okI, info = pcall(function()
		return gd and gd.SiegeInfo and gd.SiegeInfo(pid)
	end)
	if okI and typeof(info) == "table" then
		rep.Turrets = if typeof(info.TurretPower) == "table" then #info.TurretPower else 0
		rep.Guards = if typeof(info.GuardPower) == "table" then #info.GuardPower else 0
		rep.GateHp = if typeof(info.GateHp) == "number" and info.GateHp == info.GateHp then math.floor(info.GateHp) else nil
		rep.GateMax = if typeof(info.GateMax) == "number" and info.GateMax == info.GateMax then math.floor(info.GateMax) else nil
	end
	local tp = getProfile(tgt)
	if tp then
		rep.Tier = EndgameService.Tier(tp)
		rep.Defence = {}
		for _, tr in ipairs(EndgameConfig.Defence.Tracks) do
			rep.Defence[tr] = EndgameService.DefenceLevel(tp, tr)
		end
	end
	local okP, AP = pcall(function(): any
		return require(script.Parent.Parent.Modules.ArmyPlan)
	end)
	if okP and AP and AP.CheckSend then
		local okV, v = pcall(AP.CheckSend, player, pid)
		if okV and typeof(v) == "table" and typeof(v.Text) == "string" then
			rep.Verdict = v.Text
		end
	end
	return rep
end

--[[ What a purchase would do: (plan) or (nil, why). Every rule the client might skip is checked here: the part is
	live, the place (station / HQ console), not hurt, the requirement, the level cap. The price is config's. ]]
function EndgameService._Plan(player: Player, profile: any, kind: string, id: string?, auto: boolean?): (Plan?, string?)
	local T = EndgameConfig.Text
	local uid = player.UserId
	if kind == "Elite" then
		local k = id
		if not EndgameConfig.LiveFor(uid, "Elite") then
			return nil, T.NotLive
		end
		if typeof(k) ~= "string" or EndgameConfig.Elite.Names[k] == nil then
			return nil, "Unknown"
		end
		if not EndgameService.AtStation(player, "Recruits") then
			return nil, "Go to the Recruitment Office"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local kk: string = k
		local t = EndgameService.EliteTier(profile, kk) + 1
		local row: any = EndgameConfig.Elite.Tiers[t]
		if row == nil then
			return nil, EndgameConfig.Elite.Names[kk] .. " maxed"
		end
		if row.NeedRebirths and nonNeg(profile.Prestige) < row.NeedRebirths then
			return nil, string.format(T.NeedRebirths, row.NeedRebirths)
		end
		return {
			Key = "elite",
			Price = row.Cost,
			Log = string.format("Recruits %s ok T=%d price=%d", kk, t, row.Cost),
			Apply = function(p: any): string
				local e = EndgameService.Data(p)
				if typeof(e.Elite) ~= "table" then
					e.Elite = {}
				end
				e.Elite[kk] = t
				return string.format(T.EliteBought, EndgameConfig.Elite.Names[kk], row.Name)
			end,
		}
	elseif kind == "Mastery" or kind == "Attach" or kind == "Camo" or kind == "EquipCamo" then
		local Ma = EndgameConfig.Mastery
		-- v157: putting on / taking off a camo you own is live with the Black Market too; buying stays Armory-only
		local masteryLive = EndgameConfig.LiveFor(uid, "Mastery")
		if not masteryLive and not (kind == "EquipCamo" and EndgameConfig.CamoLiveFor(uid)) then
			return nil, T.NotLive
		end
		if typeof(id) ~= "string" then
			return nil, "Unknown"
		end
		local sid: string = id
		local gm1, gm2 = string.match(sid, "^([%w_]+):?([%w_]*)$")
		local gunId: string? = gm1
		local extra: string = gm2 or ""
		local def: any = if gunId then WeaponConfig.Weapons[gunId] else nil
		if def == nil then
			return nil, "Unknown gun"
		end
		local owned = false
		for _, g in ipairs(ownedGuns(player)) do
			if g == gunId then
				owned = true
			end
		end
		if kind ~= "Camo" and not owned then
			return nil, "You don't own that gun"
		end
		if kind ~= "EquipCamo" then
			if not EndgameService.AtStation(player, "Armory") then
				return nil, "Go to the Armory Workshop"
			end
			if EndgameService.RecentlyHurt(player) then
				return nil, T.Hurt
			end
		end
		local gid: string = gunId :: string
		if kind == "Mastery" then
			local L = EndgameService.MasteryLevel(profile, gid) + 1
			local cost = EndgameConfig.MasteryCost(EndgameConfig.MasteryBase(def), L)
			if cost == nil then
				return nil, "Mastery maxed"
			end
			return {
				Key = "mastery",
				Price = cost,
				Log = string.format("Armory mastery %s ok L=%d price=%d", gid, L, cost),
				Apply = function(p: any): string
					endgameMap(p, "Mastery")[gid] = L
					gunCache[uid] = nil
					return string.format("%s mastery %d", tostring(def.ShortName or gid), L)
				end,
			}
		elseif kind == "Attach" then
			local slot = extra
			local a: any = Ma.Attachments[slot]
			if a == nil or slot == "Suppressor" then -- the Suppressor waits for a firing ping to hide (none exists yet)
				return nil, "Not available"
			end
			if EndgameService.Attachments(profile, gid)[slot] then
				return nil, "Already fitted"
			end
			return {
				Key = "attach",
				Price = a.Cost,
				Log = string.format("Armory attach %s:%s ok price=%d", gid, slot, a.Cost),
				Apply = function(p: any): string
					local m = endgameMap(p, "Attachments")
					if typeof(m[gid]) ~= "table" then
						m[gid] = {}
					end
					m[gid][slot] = true
					gunCache[uid] = nil
					return string.format("%s fitted", Ma.SlotNames[slot] or slot)
				end,
			}
		elseif kind == "Camo" then
			local camo = extra
			local gold = Ma.Camos[camo]
			if gold == nil then
				return nil, "Unknown camo"
			end
			local c = endgameMap(profile, "Camos")
			if c[camo] == true then
				return nil, "Owned"
			end
			return {
				Key = "camo",
				Price = gold,
				Gold = true,
				Log = string.format("Armory camo %s ok gold=%d", camo, gold),
				Apply = function(p: any): string
					local cc = endgameMap(p, "Camos")
					cc[camo] = true
					if typeof(cc.Equip) ~= "table" then
						cc.Equip = {}
					end
					cc.Equip[gid] = camo
					return camo .. " camo on your " .. tostring(def.ShortName or gid)
				end,
			}
		end
		-- EquipCamo: free, anywhere ("None" takes it off)
		local camo = extra
		local c = endgameMap(profile, "Camos")
		if camo ~= "None" and c[camo] ~= true then
			return nil, "Buy that camo first"
		end
		if camo ~= "None" and not masteryLive and EndgameConfig.MarketCamos()[camo] == nil then
			return nil, T.NotLive
		end
		return {
			Key = "camo_equip",
			Price = 0,
			Log = string.format("Armory camo equip %s:%s", gid, camo),
			Apply = function(p: any): string
				local cc = endgameMap(p, "Camos")
				if typeof(cc.Equip) ~= "table" then
					cc.Equip = {}
				end
				cc.Equip[gid] = if camo == "None" then nil else camo
				return if camo == "None" then "Camo off" else camo .. " camo on"
			end,
		}
	elseif kind == "Workshop" then
		if not EndgameConfig.LiveFor(uid, "Workshop") then
			return nil, T.NotLive
		end
		local cls = id
		if typeof(cls) ~= "string" or table.find(EndgameConfig.Workshop.Classes, cls) == nil then
			return nil, "Unknown"
		end
		local bs = deps.BaseService
		local okC, at = pcall(function()
			return bs and bs.IsAtConsole and bs.IsAtConsole(player, "VehicleDepot")
		end)
		if not (okC and at == true) then
			return nil, "Use the Workshop at your Vehicle Depot"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local cl: string = cls
		local w = endgameMap(profile, "Workshop")
		local L = math.min(nonNeg(w[cl]), EndgameConfig.Workshop.MaxLevel) + 1
		local cost = EndgameConfig.WorkshopCost(L)
		if cost == nil then
			return nil, cl .. " workshop maxed"
		end
		return {
			Key = "workshop",
			Price = cost,
			Log = string.format("Depot workshop %s ok L=%d price=%d", cl, L, cost),
			Apply = function(p: any): string
				endgameMap(p, "Workshop")[cl] = L
				local hp, sp = EndgameConfig.WorkshopMults(L)
				return string.format("%s vehicles: +%d%% HP, +%d%% speed (next spawn)", cl, math.floor((hp - 1) * 100 + 0.5), math.floor((sp - 1) * 100 + 0.5))
			end,
		}
	elseif kind == "Warhead" then
		local W = EndgameConfig.Warheads
		if not EndgameConfig.LiveFor(uid, "Warheads") then
			return nil, T.NotLive
		end
		if not EndgameService.AtHQ(player) then
			return nil, T.NotAtHQ
		end
		local okN, NS = pcall(function(): any
			return (require :: any)(script.Parent:FindFirstChild("NukeService")) -- lazy (NukeService requires this module too)
		end)
		if id == "Tactical" then
			if nonNeg(profile.Prestige) < W.Tactical.NeedRebirths then
				return nil, string.format(T.NeedRebirths, W.Tactical.NeedRebirths)
			end
			if not (okN and NS and NS.CanFillSlot and NS.CanFillSlot(player)) then
				return nil, "Your silo is full (or not built)"
			end
			return {
				Key = "warhead",
				Price = W.Tactical.Cost,
				Log = string.format("HQ warhead Tactical ok price=%d", W.Tactical.Cost),
				Apply = function(_p: any): string
					if NS.FillSlot then
						NS.FillSlot(player)
					end
					return "Tactical Warhead loaded: one silo slot is ready"
				end,
			}
		elseif id == "Heavy" then
			if not EndgameService.HasUnlock(uid, "HeavyWarhead") then
				return nil, string.format(T.NeedRebirths, W.Heavy.NeedRebirths)
			end
			local w = endgameMap(profile, "Warheads")
			if nonNeg(w.Heavy) >= W.Heavy.Hold then
				return nil, "You hold a Heavy Warhead already"
			end
			return {
				Key = "warhead",
				Price = W.Heavy.Cost,
				Log = string.format("HQ warhead Heavy ok price=%d", W.Heavy.Cost),
				Apply = function(p: any): string
					endgameMap(p, "Warheads").Heavy = 1
					return "Heavy Warhead ready: your next launch hits bigger and harder"
				end,
			}
		end
		return nil, "Unknown"
	elseif kind == "Heist" then
		local Hk = EndgameConfig.Heist.Kits
		if not EndgameConfig.LiveFor(uid, "Heist") then
			return nil, T.NotLive
		end
		if not EndgameService.AtStation(player, "Heist") then
			return nil, "Go to the Fixer at the bank"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local e = EndgameService.Data(profile)
		local L = math.min(nonNeg(e.HeistKit), #Hk) + 1
		local row: any = Hk[L]
		if row == nil then
			return nil, "You have every kit"
		end
		return {
			Key = "heist",
			Price = row.Cost,
			Log = string.format("Bank heist kit %s ok price=%d", row.Name, row.Cost),
			Apply = function(p: any): string
				EndgameService.Data(p).HeistKit = L
				return row.Name .. ": a bigger vault opens for you"
			end,
		}
	elseif kind == "Market" or kind == "MarketEquip" then
		local B = EndgameConfig.BlackMarket
		if not EndgameConfig.LiveFor(uid, "BlackMarket") then
			return nil, T.NotLive
		end
		if typeof(id) ~= "string" then
			return nil, "Unknown"
		end
		local sid: string = id
		if kind == "MarketEquip" then
			-- free, anywhere: "None:<Kind>" takes that kind off
			local offKind = string.match(sid, "^None:(%a+)$")
			local item = B.Items[sid]
			if offKind == nil and (item == nil or marketData(profile).Bought[sid] ~= true or item.Kind == "Camo") then
				return nil, "You don't own that"
			end
			return {
				Key = "market_equip",
				Price = 0,
				Log = "Market equip " .. sid,
				Apply = function(p: any): string
					local bm = marketData(p)
					if offKind then
						bm.Equip[offKind] = nil
						return "Taken off"
					end
					bm.Equip[item.Kind] = sid
					return item.Name .. " on"
				end,
			}
		end
		local item = B.Items[sid]
		if item == nil then
			return nil, "Unknown item"
		end
		if not EndgameService.AtStation(player, "BlackMarket") then
			return nil, "Go to the Black Market"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local stock = EndgameService.MarketStock()
		local slot = table.find(stock.Cash, sid)
		local isGold = stock.Gold == sid
		if slot == nil and not isGold then
			return nil, "Not in stock this week"
		end
		local owned = if item.Kind == "Camo" then endgameMap(profile, "Camos")[item.Camo] == true else marketData(profile).Bought[sid] == true
		if owned then
			return nil, "Owned"
		end
		local si: number = slot or 1
		local price = if isGold then stock.GoldPrice else EndgameConfig.IncomeMinutesPrice(B.Slots[si].Floor, B.Slots[si].Minutes, incomePerSec(player))
		return {
			Key = "market",
			Price = price,
			Gold = isGold,
			Log = string.format("Market %s ok price=%d gold=%s", sid, price, tostring(isGold)),
			Apply = function(p: any): string
				if item.Kind == "Camo" then
					local cc = endgameMap(p, "Camos")
					cc[item.Camo] = true
					-- v157: the new camo goes straight onto the gun in his hand (an owned gun; server attribute)
					local held = player:GetAttribute("WE_EquippedWeapon")
					if typeof(held) == "string" and table.find(ownedGuns(player), held) ~= nil then
						if typeof(cc.Equip) ~= "table" then
							cc.Equip = {}
						end
						cc.Equip[held] = item.Camo
						return item.Name .. " bought: on your " .. tostring((WeaponConfig.Weapons :: any)[held].ShortName or held)
					end
				else
					local bm = marketData(p)
					bm.Bought[sid] = true
					bm.Equip[item.Kind] = sid
				end
				return item.Name .. " bought"
			end,
		}
	elseif kind == "Claim" or kind == "Scout" then
		local Ct = EndgameConfig.Contracts
		if not EndgameConfig.LiveFor(uid, "Contracts") then
			return nil, T.NotLive
		end
		if not EndgameService.AtStation(player, "Intel") then
			return nil, "Go to the Intel Office"
		end
		local c = contractsOf(player, profile)
		if kind == "Claim" then
			local row = if id == "HVT" then c.Hvt else c.Rows[tonumber(string.match(tostring(id), "^D(%d)$")) or 0]
			if row == nil then
				return nil, "Unknown"
			end
			if row.Paid then
				return nil, "Claimed"
			end
			if row.Have < row.Need then
				return nil, string.format("%d/%d done", row.Have, row.Need)
			end
			local hvt = id == "HVT"
			local reward = EndgameService.ContractReward(player, hvt)
			return {
				Key = "claim",
				Price = 0,
				Log = string.format("Intel claim %s reward=%d", tostring(id), reward),
				Apply = function(_p: any): string
					row.Paid = true
					local eco = deps.EconomyService
					if eco and eco.AddCash then
						eco.AddCash(player, reward, "endgame_reward")
					end
					if hvt and eco and eco.AddGold then
						eco.AddGold(player, Ct.HvtGold, "endgame_reward")
					end
					return string.format("Contract paid: +$%s%s", short(reward), if hvt then string.format(" +%d Gold", Ct.HvtGold) else "")
				end,
			}
		end
		-- Scout: a report on an ONLINE player's base (offline bases cannot be raided, so they are never shown)
		local pid = tonumber(id)
		local target: Player? = nil
		for _, p in ipairs(Players:GetPlayers()) do
			local pp = getProfile(p)
			if p ~= player and pp and tonumber(pp.BasePlotId) == pid then
				target = p
			end
		end
		if pid == nil or target == nil then
			return nil, "Nobody holds that base now"
		end
		local price = EndgameConfig.IncomeMinutesPrice(Ct.ScoutFloor, Ct.ScoutMinutes, incomePerSec(player))
		local tgt: Player = target
		-- Code Bot v171 (Shaun 2026-10-01 12:08: "the scout report I paid for did nothing"): the report is built HERE,
		-- before Purchase spends a dollar (it was built inside Apply, after SpendCash: a failure there kept his cash).
		-- If it cannot be built, nothing is charged. Apply only stores it: this server's table + profile.Endgame
		-- (it survives a rejoin / a server move) and pushes the "ScoutReport" result card (EndgameController).
		local okR, built = pcall(EndgameService.BuildScoutReport, player, tgt, pid :: number)
		if not okR or typeof(built) ~= "table" then
			warn("[Station] Intel scout report failed (nothing charged): " .. tostring(built))
			return nil, "Scouting failed, try again (nothing charged)"
		end
		local rep: { [string]: any } = built
		return {
			Key = "scout",
			Price = price,
			Log = string.format("Intel scout plot=%d price=%d", pid, price),
			Apply = function(prof: any): string
				rep.Price = price
				scoutReport[uid] = rep
				if typeof(prof) == "table" then
					EndgameService.Data(prof).ScoutReport = rep
				end
				pendingScoutCard[uid] = rep
				return "Scouting report ready: " .. tgt.DisplayName
			end,
		}
	elseif kind == "Heal" or kind == "MedKit" or kind == "Medicine" or kind == "Revive" or kind == "UseMedKit" or kind == "UseRevive" then
		local H = EndgameConfig.Hospital
		if not EndgameConfig.LiveFor(uid, "Hospital") then
			return nil, T.NotLive
		end
		local e = EndgameService.Data(profile)
		if kind == "UseMedKit" then
			local h = humOf(player)
			if nonNeg(e.MedKits) <= 0 then
				return nil, "No Med Kits"
			end
			if h == nil or h.Health >= h.MaxHealth then
				return nil, "Already at full health"
			end
			return {
				Key = "medkit_use",
				Price = 0,
				Log = "Medic kit used",
				Apply = function(p: any): string
					local d = EndgameService.Data(p)
					d.MedKits = math.max(0, nonNeg(d.MedKits) - 1)
					healOverTime(player, H.MedKit.Heal, H.MedKit.Seconds)
					return string.format("Med Kit: +%d HP", H.MedKit.Heal)
				end,
			}
		elseif kind == "UseRevive" then
			if nonNeg(e.Revive) <= 0 then
				return nil, "No revive token"
			end
			return {
				Key = "revive_use",
				Price = 0,
				Log = "Medic revive used",
				Apply = function(p: any): string
					local ok, msg = EndgameService.Revive(player)
					if ok then
						local d = EndgameService.Data(p)
						d.Revive = math.max(0, nonNeg(d.Revive) - 1)
					end
					return msg
				end,
			}
		end
		if not EndgameService.AtStation(player, "Hospital") then
			return nil, "Go to the Field Hospital"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		if kind == "Heal" then
			local h = humOf(player)
			local last = healAt[uid]
			if last and clock() - last < H.HealCooldown then
				return nil, string.format("Next free heal in %d s", math.ceil(H.HealCooldown - (clock() - last)))
			end
			if h == nil or h.Health >= h.MaxHealth then
				return nil, "Already at full health"
			end
			return {
				Key = "heal",
				Price = 0,
				Log = "Hospital heal ok",
				Apply = function(_p: any): string
					healAt[uid] = clock()
					local hh = humOf(player)
					if hh then
						hh.Health = hh.MaxHealth -- the free heal (not in combat: RecentlyHurt checked above)
					end
					return "Healed"
				end,
			}
		elseif kind == "MedKit" then
			if nonNeg(e.MedKits) >= H.MedKit.Max then
				return nil, string.format("You carry %d already", H.MedKit.Max)
			end
			local price = EndgameConfig.IncomeMinutesPrice(H.MedKit.Floor, H.MedKit.IncomeSeconds / 60, incomePerSec(player))
			return {
				Key = "medkit",
				Price = price,
				Log = string.format("Hospital medkit ok price=%d", price),
				Apply = function(p: any): string
					local d = EndgameService.Data(p)
					d.MedKits = math.min(H.MedKit.Max, nonNeg(d.MedKits) + 1)
					return string.format("Med Kit %d/%d", d.MedKits, H.MedKit.Max)
				end,
			}
		elseif kind == "Revive" then
			if nonNeg(e.Revive) >= 1 then
				return nil, "You carry a revive already"
			end
			local price = EndgameConfig.IncomeMinutesPrice(H.Revive.Floor, H.Revive.IncomeSeconds / 60, incomePerSec(player))
			return {
				Key = "revive",
				Price = price,
				Log = string.format("Hospital revive ok price=%d", price),
				Apply = function(p: any): string
					EndgameService.Data(p).Revive = 1
					return "Field Surgeon ready: get up where you fall"
				end,
			}
		end
		local L = EndgameService.MedicineLevel(profile) + 1
		local cost = H.Medicine.Costs[L]
		if cost == nil then
			return nil, "Combat Medicine maxed"
		end
		return {
			Key = "medicine",
			Price = cost,
			Log = string.format("Hospital medicine ok L=%d price=%d", L, cost),
			Apply = function(p: any): string
				EndgameService.Data(p).Medicine = L
				local arm = deps.ArmourService
				if arm and arm.Apply then
					pcall(arm.Apply, player)
				end
				return string.format("Combat Medicine %d: +%d max HP", L, EndgameConfig.MedicineHp(L))
			end,
		}
	elseif kind == "Retrain" then
		if not EndgameConfig.LiveFor(uid, "Elite") then
			return nil, T.NotLive
		end
		local e = EndgameService.Data(profile)
		if auto == true then
			-- one respawning soldier of type `id` (called by UnitElite, never by the remote)
			local k = if typeof(id) == "string" then id else "Infantry"
			local fee = EndgameService.RetrainFee(EndgameService.EliteTier(profile, k))
			local free = nonNeg(e.FreeRetrains) > 0
			return {
				Key = "retrain",
				Price = if free then 0 else fee,
				Log = string.format("Retrain auto %s fee=%d free=%s", k, fee, tostring(free)),
				Apply = function(p: any): string
					if free then
						local d = EndgameService.Data(p)
						d.FreeRetrains = math.max(0, nonNeg(d.FreeRetrains) - 1)
					end
					return T.Retrained
				end,
			}
		end
		if not EndgameService.AtStation(player, "Recruits") then
			return nil, "Go to the Recruitment Office"
		end
		local n, fee = EndgameService.UntrainedNow(player, profile)
		if n <= 0 then
			return nil, "Every soldier is trained"
		end
		return {
			Key = "retrain",
			Price = fee,
			Log = string.format("Recruits retrain ok n=%d price=%d", n, fee),
			Apply = function(_p: any): string
				untrained[uid] = nil
				return T.Retrained
			end,
		}
	elseif kind == "Empire" then
		if not EndgameConfig.LiveFor(uid, "EmpireLevel") then
			return nil, T.NotLive
		end
		if not EndgameService.AtStation(player, "Command") then
			return nil, T.NotHere
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local L = EndgameService.EmpireLevel(profile)
		local price = EndgameConfig.EmpireCost(L + 1)
		if price == nil then
			return nil, T.Max
		end
		return {
			Key = "empire",
			Price = price,
			Log = string.format("Command empire ok L=%d price=%d mult=%.2f", L + 1, price, EndgameConfig.EmpireMult(L + 1)),
			Apply = function(p: any): string
				EndgameService.Data(p).EmpireLevel = L + 1
				return string.format(T.EmpireBought, L + 1, math.floor((EndgameConfig.EmpireMult(L + 1) - 1) * 100 + 0.5))
			end,
		}
	elseif kind == "Tier" then
		if not EndgameConfig.LiveFor(uid, "BaseTier") then
			return nil, T.NotLive
		end
		if not EndgameService.AtHQ(player) then
			return nil, T.NotAtHQ
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local nx = EndgameService.NextTier(profile)
		if nx == nil then
			return nil, "Base Tier maxed"
		end
		if nx.Need then
			return nil, nx.Need
		end
		return {
			Key = "tier",
			Price = nx.Cost,
			Log = string.format("HQ tier ok T=%d price=%d", nx.Tier, nx.Cost),
			Apply = function(p: any): string
				EndgameService.Data(p).BaseTier = nx.Tier
				return string.format(T.TierBought, nx.Tier, string.upper(nx.Name))
			end,
		}
	elseif kind == "Defence" then
		local track = id
		if not EndgameConfig.LiveFor(uid, "Defence") then
			return nil, T.NotLive
		end
		if typeof(track) ~= "string" or DEF_NAMES[track] == nil then
			return nil, "Unknown"
		end
		if not EndgameService.AtStation(player, "Engineers") then
			return nil, "Go to the Engineering Bureau"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local tr: string = track
		local nx = EndgameService.NextDefence(profile, tr, uid) -- claude-bud JOB 55: the walls need too
		if nx == nil then
			return nil, DEF_NAMES[tr] .. " maxed"
		end
		if nx.Need then
			return nil, nx.Need
		end
		return {
			Key = "defence",
			Price = nx.Cost,
			Log = string.format("Engineers %s ok L=%d price=%d", tr, nx.Level, nx.Cost),
			Apply = function(p: any): string
				local e = EndgameService.Data(p)
				if typeof(e.Defence) ~= "table" then
					e.Defence = {}
				end
				e.Defence[tr] = nx.Level
				-- claude-bud JOB 53: a new visual tier says what changed on his base (owner-first with DefenceVisuals)
				local tNow = EndgameConfig.DefenceVisualTier(nx.Level)
				if EndgameConfig.DefenceVisualsLive(uid) and tNow > EndgameConfig.DefenceVisualTier(nx.Level - 1) then
					local look = (T.DefenceLook :: any)[tr]
					if look then
						return string.format(T.DefenceBought, defName(tr, uid), nx.Level) .. " " .. string.format(T.DefenceNewLook, look[tNow] or "")
					end
				end
				return string.format(T.DefenceBought, defName(tr, uid), nx.Level)
			end,
		}
	elseif kind == "Rebuild" then
		if not EndgameConfig.LiveFor(uid, "Defence") then
			return nil, T.NotLive
		end
		if not EndgameService.AtHQ(player) then
			return nil, T.NotAtHQ
		end
		if not needsRebuild(profile) then
			return nil, T.NothingDown
		end
		local price = EndgameService.RebuildPrice(player)
		local pid = plotId(profile)
		return {
			Key = "rebuild",
			Price = price,
			Log = string.format("HQ rebuild ok price=%d", price),
			Apply = function(_p: any): string
				local gd = deps.GateDefenseService
				if gd and gd.InstantRebuild and pid then
					pcall(gd.InstantRebuild, pid)
				end
				return T.Rebuilt
			end,
		}
	end
	return nil, "Unknown"
end

--[[ THE one purchase path. kind: "Empire" | "Tier" | "Defence" (id = the track) | "Rebuild". The client sends only
	kind / id. Returns (ok, message). ]]
function EndgameService.Purchase(player: Player, kind: string, id: string?, auto: boolean?): (boolean, string)
	local profile = getProfile(player)
	if profile == nil then
		return false, "Loading"
	end
	local plan, why = EndgameService._Plan(player, profile, kind, id, auto)
	if plan == nil then
		return false, why or "Unknown"
	end
	local eco = deps.EconomyService
	if eco == nil or eco.SpendCash == nil then
		return false, "Not ready"
	end
	local price = plan.Price
	local key = plan.Key
	if plan.Gold == true then
		-- camos are the first Gold sink (§2.9): Gold only, never Cash
		if nonNeg(profile.Gold) < price then
			return false, string.format("Need %d Gold", price - nonNeg(profile.Gold))
		end
		local okG, errG = eco.SpendGold(player, price, "endgame_" .. key)
		if not okG then
			return false, tostring(errG or "SpendFailed")
		end
		price = 0
	end
	local cash = nonNeg(profile.Cash)
	if cash < price then
		return false, string.format(EndgameConfig.Text.Short, short(price - cash))
	end
	if price > 0 then -- a free re-train (the Instant Army Refill), a heal or a Gold camo spends no Cash
		local ok, err = eco.SpendCash(player, price, "endgame_" .. key)
		if not ok then
			return false, tostring(err or "SpendFailed")
		end
	end
	profile = getProfile(player) or profile
	local msg = plan.Apply(profile)
	if deps.DataService and deps.DataService.MarkDirty then
		deps.DataService.MarkDirty(player)
	end
	print("[Station] " .. plan.Log)
	pcall(EndgameService.SyncAttributes, player)
	local bss = deps.BaseSignService
	if bss and bss.Refresh then
		pcall(bss.Refresh, profile.BasePlotId)
	end
	if key == "tier" or key == "defence" then
		-- the gate HP / turret HP / nests follow at once; the look follows on the next sweep (or now)
		local gd = deps.GateDefenseService
		local pid = plotId(profile)
		if gd and gd.SyncPlot and pid then
			-- claude-bud JOB 55: a Defence buy refreshes the numbers IN PLACE (the damage taken stays; the old full
			-- SyncPlot rebuilt a breached / damaged gate at full HP mid-raid). OFF / a tier buy = the old resync.
			local inPlace = key == "defence" and EndgameConfig.DefenceFixLive(player.UserId) and gd.RefreshDefence ~= nil
			task.defer(function()
				if inPlace then
					pcall(gd.RefreshDefence, pid)
				else
					pcall(gd.SyncPlot, pid)
				end
				task.wait(0.5)
				pcall(EndgameService.SyncBaseTier, player)
			end)
		end
		local ss = deps.SoldierService
		if key == "tier" and ss and ss.PushState then
			pcall(ss.PushState, player)
		end
	end
	if key == "mastery" or key == "attach" or key == "camo" or key == "camo_equip" or key == "market" then
		-- the drawn gun's camo and the client's fire-rate / range multipliers follow at once
		local cs = deps.CombatService
		if cs and cs.SyncWeapons then
			pcall(cs.SyncWeapons, player)
		end
		local c = player.Character
		if c then
			local out = c:GetAttribute("WE_GunOut")
			c:SetAttribute("WE_GunCamo", EndgameService.CamoFor(player, if typeof(out) == "string" then out else nil))
		end
	end
	if (key == "elite" or key == "retrain") and auto ~= true then
		-- the living soldiers take the new tier in place (HP ratio kept, look re-dressed)
		local sq = deps.SquadOrdersService
		if sq and sq._ReapplyElite then
			task.defer(function()
				pcall(sq._ReapplyElite, player)
			end)
		end
	end
	return true, msg
end

-- ── the Base Tier look (server-built, shared: everyone sees a base's tier) ────────────────────────────────────────
local function basesFolder(): Instance?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	return setup and setup:FindFirstChild("Bases")
end

local function plotContext(pid: number, plotFolder: Instance): any?
	local pad = plotFolder:FindFirstChild("PlotPad")
	if pad == nil or not pad:IsA("BasePart") then
		return nil
	end
	local okL, BaseLayout = pcall(function(): any
		return require(script.Parent.Parent.Modules.BaseLayout)
	end)
	if not okL or BaseLayout == nil then
		return nil
	end
	local groundY = pad.Position.Y + pad.Size.Y * 0.5
	local ground = BaseLayout.PlotCFrame(pad.Position) * CFrame.new(0, pad.Size.Y * 0.5, 0)
	local wallTop = groundY + 10
	local walls = plotFolder:FindFirstChild("WE_PerimeterWalls")
	local wallBoxes = {} -- Code Bot v171: the wall segments' boxes (the Recruit Pack's gold trim caps each one)
	if walls then
		for _, w in ipairs(walls:GetChildren()) do
			if w:IsA("BasePart") then
				wallTop = math.max(wallTop, w.Position.Y + w.Size.Y * 0.5)
				if w:GetAttribute("WE_WallLevel") ~= nil then -- the wall bodies only (not the caps / wire / gate posts / arch)
					table.insert(wallBoxes, { CFrame = w.CFrame, Size = w.Size })
				end
			end
		end
	end
	local hq: any = nil
	for _, c in ipairs(plotFolder:GetChildren()) do
		if c:GetAttribute("StructureId") == "CommandCenter" and c:GetAttribute("WE_Console") ~= true then
			for _, b in ipairs(c:GetChildren()) do
				if b:IsA("Model") and b:GetAttribute("StructureId") == "CommandCenter" then
					local cf, size = b:GetBoundingBox()
					hq = { CFrame = cf, Size = size }
				end
			end
		end
	end
	local gd = deps.GateDefenseService
	local posts = {}
	local rawPosts = if gd and gd._Posts then gd._Posts[pid] else nil
	for _, p in ipairs(rawPosts or {}) do
		if p.Parent then
			table.insert(posts, { CFrame = p.CFrame, Size = p.Size })
		end
	end
	local gate = if gd and gd.GetGateCFrame then gd.GetGateCFrame(pid) else nil
	return {
		Ground = ground,
		PadCentre = pad.Position,
		HalfX = pad.Size.X * 0.5 - 1.5,
		HalfZ = pad.Size.Z * 0.5 - 1.5,
		WallTop = wallTop,
		GroundY = groundY,
		Posts = posts,
		Gate = gate,
		Nests = (if gd and gd._Nests then gd._Nests[pid] else nil) or {},
		HQ = hq,
		Walls = wallBoxes,
	}
end

-- Code Bot v171: the Recruit Pack's gold base trim is owned (the saved entitlement, so it is back on every join) and
-- the pack is live for him
function EndgameService.HasRecruitTrim(player: Player, profile: any): boolean
	local okM, MC = pcall(function(): any
		return require(ReplicatedStorage.Shared.Configs.MonetizationConfig)
	end)
	if not okM or MC == nil or MC.RecruitPackLiveFor == nil or MC.RecruitPackLiveFor(player.UserId) ~= true then
		return false
	end
	return typeof(profile) == "table" and typeof(profile.Entitlements) == "table" and profile.Entitlements.RecruitPack == true
end

-- build / rebuild / drop one player's WE_BaseTier model (the key: tier, HQ level, walls, nests)
function EndgameService.SyncBaseTier(player: Player)
	local profile = getProfile(player)
	local pid = if profile then plotId(profile) else nil
	local bases = basesFolder()
	if profile == nil or pid == nil or bases == nil then
		return
	end
	local plotFolder = bases:FindFirstChild("Plot" .. tostring(pid))
	if plotFolder == nil then
		return
	end
	local existing = plotFolder:FindFirstChild("WE_BaseTier")
	local tier = tierOf(player.UserId)
	local crest = EndgameService.HasUnlock(player.UserId, "BastionCrest")
	local trophy = EndgameService.HasTrophy(player.UserId)
	local banner = EndgameService.BannerColor(player.UserId)
	local recruit = EndgameService.HasRecruitTrim(player, profile) -- Code Bot v171
	if tier <= 0 and not crest and not trophy and banner == nil and not recruit then
		if existing then
			existing:Destroy()
		end
		return
	end
	local ctx = plotContext(pid :: number, plotFolder)
	if ctx == nil then
		return
	end
	-- the key: the owner, the tier, the Command Center level (its building is rebuilt on a level change), the walls
	local cc = if typeof(profile.BaseUpgrades) == "table" then tonumber(profile.BaseUpgrades.CommandCenter) or 0 else 0
	ctx.Crest = crest
	ctx.Trophy = trophy
	ctx.BannerColor = banner
	ctx.RecruitTrim = recruit
	local key = string.format("%d|%d|%d|%s|%.1f|%d|%d|%s|%s|%s|%s|%d", player.UserId, tier, cc, tostring(ctx.HQ ~= nil), ctx.WallTop, #ctx.Nests, #ctx.Posts, tostring(crest), tostring(trophy), tostring(banner), tostring(recruit), #ctx.Walls)
	if existing and existing:GetAttribute("WE_TierKey") == key then
		return
	end
	local okB, BTB = pcall(function(): any
		return require(script.Parent.Parent.Modules.BaseTierBuilder)
	end)
	if not okB or BTB == nil then
		return
	end
	local model, parts, lights = BTB.Build(ctx, tier)
	model:SetAttribute("WE_TierKey", key)
	model:SetAttribute("OwnerUserId", player.UserId)
	if existing then
		existing:Destroy()
	end
	model.Parent = plotFolder
	print(string.format("[BaseTier] plot=%d tier=%d parts=%d lights=%d", pid, tier, parts, lights))
end

-- drop a WE_BaseTier model whose owner no longer holds that plot (the plot is free for the next player)
local function sweepOrphans()
	local bases = basesFolder()
	if bases == nil then
		return
	end
	for _, f in ipairs(bases:GetChildren()) do
		local m = f:FindFirstChild("WE_BaseTier")
		if m then
			local uid = tonumber(m:GetAttribute("OwnerUserId"))
			local owner = if uid then Players:GetPlayerByUserId(uid) else nil
			local prof = if owner then getProfile(owner) else nil
			if prof == nil or ("Plot" .. tostring(prof.BasePlotId)) ~= f.Name then
				m:Destroy()
			end
		end
	end
end

local function watchCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum == nil or not hum:IsA("Humanoid") then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h: number)
		if h < last then
			hurtAt[player.UserId] = clock()
		end
		last = h
	end)
	-- phase 4: where he fell (the Field Surgeon's revive window)
	hum.Died:Connect(function()
		local r = char:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			diedAt[player.UserId] = { At = clock(), CF = r.CFrame }
		end
	end)
end

-- a store prop's forecourt: ForecourtStuds out of the box face nearest the plaza, local -Z pointing away from it
local function forecourtFrame(model: Model, toward: Vector3, out: number): CFrame
	local cf, size = model:GetBoundingBox()
	local best: CFrame? = nil
	local bestD = math.huge
	for _, dir in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local wdir = cf:VectorToWorldSpace(dir)
		local flat = Vector3.new(wdir.X, 0, wdir.Z)
		if flat.Magnitude > 0.5 then
			flat = flat.Unit
			local half = math.abs(dir.X) * size.X * 0.5 + math.abs(dir.Z) * size.Z * 0.5
			local p = cf.Position + flat * (half + out)
			local ground = Vector3.new(p.X, cf.Position.Y - size.Y * 0.5, p.Z)
			local d = (Vector3.new(toward.X, 0, toward.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
			if d < bestD then
				bestD = d
				best = CFrame.lookAt(ground, ground + flat)
			end
		end
	end
	return best or cf
end

-- publish the live stations' frames once their buildings exist (the world builds at start; store props later)
local function publishStations()
	local folder = ReplicatedStorage:FindFirstChild(PlazaServicesConfig.FolderName)
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = PlazaServicesConfig.FolderName
		f.Parent = ReplicatedStorage
		folder = f
	end
	local okE, Ent = pcall(function(): any
		return require(script.Parent.Parent.Modules.Enterables)
	end)
	if not okE or Ent == nil then
		return
	end
	local function house(row: string): CFrame?
		for _, e in ipairs(Ent.List()) do
			if e.Id == row then
				return e.CF
			end
		end
		return nil
	end
	local function publish(kind: string, cf: CFrame, how: string)
		stationCF[kind] = cf
		local v = Instance.new("CFrameValue")
		v.Name = kind
		v.Value = cf
		v.Parent = folder
		print(string.format("[Station] %s published at %s (%s)", kind, tostring(cf.Position), how))
	end
	local tries = 90
	for i = 1, tries do
		local missing = false
		for kind, st in pairs(PlazaServicesConfig.Stations) do
			if (EndgameConfig.Parts :: any)[st.Part] == true and stationCF[kind] == nil then
				if st.Row then
					local cf = house(st.Row)
					if cf then
						publish(kind, cf, st.Row)
					else
						missing = true
					end
				elseif st.WorldAt then
					publish(kind, CFrame.lookAt(st.WorldAt, st.WorldAt + st.Face), "world anchor")
				elseif st.StoreProp then
					local wf = Workspace:FindFirstChild("WorldFill")
					local sp = wf and wf:FindFirstChild("StoreProps")
					local prop = sp and sp:FindFirstChild("Store_" .. tostring(st.StoreProp))
					local toward = house("NE_N1") or CFrame.new()
					if prop and prop:IsA("Model") then
						publish(kind, forecourtFrame(prop, toward.Position, st.ForecourtStuds or 7), "store prop " .. tostring(st.StoreProp))
					elseif i == tries or (i >= 30 and house(st.FallbackRow) ~= nil) then
						local hcf = house(st.FallbackRow)
						if hcf then
							publish(kind, hcf * CFrame.new(st.FallbackOffset), "fallback beside " .. st.FallbackRow)
						else
							missing = true
						end
					else
						missing = true
					end
				end
			end
		end
		if not missing then
			return
		end
		task.wait(2)
	end
	warn("[Station] some plaza stations never found their building (PlazaBuildingsConfig rows / store props)")
end

-- test hooks
function EndgameService._SetStation(kind: string, cf: CFrame?)
	stationCF[kind] = cf
end
function EndgameService._SetClock(fn: () -> number)
	clock = fn
end
function EndgameService._Hurt(uid: number, t: number?)
	hurtAt[uid] = t
end
function EndgameService._Own(profile: any, uid: number)
	profileOwner[profile] = uid
end
function EndgameService._Untrained(uid: number): { [string]: number }?
	return untrained[uid]
end
function EndgameService._Deaths(uid: number): { [string]: number }?
	return deaths[uid]
end

function EndgameService.Init(d: { [string]: any })
	deps = d
	if EndgameConfig.Live.Enabled ~= true then
		return
	end
	task.spawn(publishStations)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(c: Model)
			task.spawn(watchCharacter, player, c)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
		-- Code Bot v171: the Recruit Pack's gold base trim goes on the moment the entitlement is granted (the receipt
		-- sets WE_Ent_RecruitPack), not up to 5 s later; the trim itself is built only from the SAVED entitlement
		player:GetAttributeChangedSignal("WE_Ent_RecruitPack"):Connect(function()
			task.defer(function()
				pcall(EndgameService.SyncBaseTier, player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		hurtAt[p.UserId] = nil
		deaths[p.UserId] = nil
		untrained[p.UserId] = nil
		healAt[p.UserId] = nil
		gunCache[p.UserId] = nil
		scoutReport[p.UserId] = nil
		pendingScoutCard[p.UserId] = nil
		diedAt[p.UserId] = nil
		healing[p.UserId] = nil
		feeToast[p.UserId] = nil
	end)
	if d.DataService and d.DataService.OnProfileLoaded then
		d.DataService.OnProfileLoaded(function(player: Player)
			pcall(EndgameService.SyncAttributes, player)
		end)
	end
	-- the rebirth count / live state / the base look change rarely: a slow sweep (1 per 5 s) keeps them right
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(EndgameService.SyncAttributes, p)
				pcall(EndgameService.SyncBaseTier, p)
				pcall(EndgameService.MedicTick, p, 5)
				pcall(EndgameService.SyncUnlocks, p)
			end
			pcall(sweepOrphans)
		end
	end)
	local rs = d.RemoteSetup
	local buy = rs and rs.Get(Constants.RemoteNames.RequestEndgameBuy)
	if buy and buy:IsA("RemoteEvent") then
		(buy :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any, id: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameBuy", kind, id) then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "endgame_buy", EndgameConfig.Station.RatePerSec, EndgameConfig.Station.Burst) then
				return
			end
			if typeof(kind) ~= "string" or not EndgameConfig.AnyLiveFor(player.UserId) then
				return
			end
			local ok, msg = EndgameService.Purchase(player, kind, if typeof(id) == "string" then id else nil)
			notify(player, msg, if ok then "Success" else "Warn")
			EndgameService.Push(player)
			EndgameService.PushScoutCard(player) -- Code Bot v171: the paid scouting report opens as its own result card
		end)
	end
	local ask = rs and rs.Get(Constants.RemoteNames.RequestEndgameState)
	if ask and ask:IsA("RemoteEvent") then
		(ask :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameState") then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "endgame_state", 2, 4) then
				return
			end
			if EndgameConfig.AnyLiveFor(player.UserId) then
				EndgameService.Push(player)
			end
		end)
	end
	print("[WAR EMPIRE] EndgameService Init")
end

return EndgameService
