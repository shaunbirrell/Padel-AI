--!strict
--[[
	Empire Bank raid — stand on vault to loot Cash; per-player cooldown.
	Bank guards are living CombatService NPCs (MoveTo + shoot), not static MapSetup props.
	Pushes HoldProgress / UnderFire / InVault / Blocked to clients for BankRaidController HUD.

	v71 (task #20, bank retune): "under fire" = hit within BankRaidConfig.UnderFireSeconds (was: health below 95 %,
	which froze the hold forever for anyone the guards had ever scratched — no health regen reaches 95 % inside the
	respawn window). The vault label is one stud-scaled WorldLabel, never AlwaysOnTop, MaxDistance <= 40 (HUD v70
	spec §5).

	W3 step 2, lane F "bank findable" (spec w3s2 §6 Phase A; server decides everything, the client only draws):
	- Guards spawn on FIXED posts: the "Town.Bank" npc anchors G1..Gn (ActivityAnchors, stamped on BankPlaza by
	  MapSetup once lane BK lands), else BankRaidConfig.GuardPosts (P0 posts clear of today's building).
	- On foot only: a seated raider (Humanoid.SeatPart) gets Blocked = "Vehicle", no progress and no pay.
	- The cooldown lives on the profile (profile.Raid.BankCooldownUntil, os.time seconds): sanitised here on load
	  (junk → removed, longer than one cooldown → clamped), so it survives a rejoin. No ProfileSchema edit: Migrate
	  keeps unknown Raid keys. A player whose profile has not loaded yet cannot loot (GetProfile is nil).
	- Label: "Empire Bank" + "OPEN · rob the vault" / "RAID ON" (everyone; attribute WE_BankState = open / raid).
	  "CLOSED 4m" is drawn by BankRaidController on the cooling player's own client only.
	- The EMPIRE BANK sign is painted (WorldKits.Sign, inside the world sign budget) only when BankSign has none.
	- Reward toast "Bank job +$23,456" (commas), MissionService.TrackProgress(player, "Heist", 1), and a one-time
	  first-visit tip (profile.Raid.BankSeen) within BankRaidConfig.FirstVisitRadius.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local BankRaidService = {}

local EconomyService: any = nil
local NotificationService: any = nil
local AnalyticsService: any = nil
local RemoteSetup: any = nil
local CombatService: any = nil
local DataService: any = nil
local MissionService: any = nil

local vaultPart: BasePart? = nil
local holdProgress: { [number]: number } = {}
-- only when no DataService is wired (headless drivers); live servers keep the cooldown on the profile
local sessionCooldown: { [number]: number } = {}
local inVaultNow: { [number]: boolean } = {}
local underFireNow: { [number]: boolean } = {}
local blockedNow: { [number]: string } = {}
local lastPushedProgress: { [number]: number } = {}
local firstVisitDone: { [number]: boolean } = {}
local guardsSpawned = false
local vaultLabel: BillboardGui? = nil
local lastRaiding: boolean? = nil
local signTried = false
-- under fire = a health drop seen within UnderFireSeconds (sampled on the 4 Hz tick; regen never counts)
local lastHealth: { [number]: number } = {}
local hurtAt: { [number]: number } = {}

local LABEL = BankRaidConfig.Label
local TEXT = BankRaidConfig.Text
local SIGN = BankRaidConfig.Sign

-- Server modules used lazily (a missing or broken module only means the fallback path)
local function serverModule(name: string): any
	local parent = script.Parent and script.Parent.Parent
	local modules = parent and parent:FindFirstChild("Modules")
	local m = modules and modules:FindFirstChild(name)
	if not (m and m:IsA("ModuleScript")) then
		return nil
	end
	local ok, mod = pcall(require, m)
	return if ok then mod else nil
end

local function formatCash(n: number): string
	local s = string.format("%d", math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function findVault(): BasePart?
	if vaultPart and vaultPart.Parent then
		return vaultPart
	end
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BankVault)) do
		if inst:IsA("BasePart") then
			vaultPart = inst
			return inst
		end
	end
	return nil
end

-- ── profile: Raid.BankCooldownUntil / Raid.BankSeen (no schema edit; Migrate keeps unknown Raid keys) ──────────
local function raidTable(profile: any): { [string]: any }?
	local raid = profile.Raid
	if typeof(raid) ~= "table" then
		return nil
	end
	return raid
end

local function profileOf(player: Player): any
	if DataService == nil then
		return nil
	end
	return DataService.GetProfile(player)
end

-- os.time() until which this player cannot loot; nil = profile not loaded yet (not eligible)
local function cooldownUntil(player: Player): number?
	if DataService == nil then
		return sessionCooldown[player.UserId] or 0
	end
	local profile = profileOf(player)
	if profile == nil then
		return nil
	end
	local raid = raidTable(profile)
	local v = raid and raid.BankCooldownUntil
	if typeof(v) ~= "number" or v ~= v then
		return 0
	end
	return v
end

local function setCooldown(player: Player, untilT: number)
	if DataService == nil then
		sessionCooldown[player.UserId] = untilT
		return
	end
	local profile = profileOf(player)
	if profile == nil then
		return
	end
	local raid = raidTable(profile)
	if raid == nil then
		-- same defaults as ProfileSchema / MoneyCollectorService.raidOf (Migrate always leaves a table here)
		local fresh: { [string]: any } = { ShieldUntil = 0, StrikeCooldownUntil = 0, DefensesDownUntil = 0 }
		profile.Raid = fresh
		raid = fresh
	end
	if raid ~= nil then
		raid.BankCooldownUntil = untilT
	end
	DataService.MarkDirty(player)
end

--[[ Local sanitiser for the saved cooldown (spec w3s2 §6 lane F): not a finite number or <= 0 → removed; longer
	than one cooldown from now (junk or a clock jump) → clamped to now + CooldownSeconds; whole seconds. Returns the
	clean value (nil when absent) and whether it changed. Pure: exported for the headless tests. ]]
function BankRaidService.SanitizeCooldown(value: any, nowUnix: number): (number?, boolean)
	if value == nil then
		return nil, false
	end
	if typeof(value) ~= "number" or value ~= value or value <= 0 then
		return nil, true
	end
	local cap = nowUnix + math.max(0, BankRaidConfig.CooldownSeconds or 300)
	local clean = math.floor(math.min(value, cap))
	return clean, clean ~= value
end

local function sanitizeProfile(player: Player, profile: any)
	local raid = raidTable(profile)
	if raid == nil then
		return
	end
	local changed = false
	local cd, cdChanged = BankRaidService.SanitizeCooldown(raid.BankCooldownUntil, os.time())
	if cdChanged then
		raid.BankCooldownUntil = cd
		changed = true
	end
	local seen = raid.BankSeen
	if seen ~= nil and typeof(seen) ~= "boolean" then
		raid.BankSeen = nil
		changed = true
	end
	if changed and DataService then
		DataService.MarkDirty(player)
	end
end

-- ── world: vault label, EMPIRE BANK sign ────────────────────────────────────────────────────────────────────
local function ensureVaultBillboard(vault: BasePart)
	local existing = vault:FindFirstChild(LABEL.Name)
	if existing and existing:IsA("BillboardGui") and existing:FindFirstChild("Title") then
		vaultLabel = existing
		return
	end
	if existing then
		existing:Destroy()
	end
	-- spec §5 "Bank vault labels ×2 → keep only BankRaidService's": MapSetup's "EMPIRE BANK · Stand to RAID cash"
	-- card ("Label") sits on the same vault at the same height, so the two drew on top of each other. Its how-to
	-- line now lives in this label's state line ("OPEN · rob the vault").
	local legacy = vault:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") then
		legacy:Destroy()
	end
	-- stud-scaled, plain outlined text, MaxDistance <= 40, never through walls (spec §5 "Bank vault labels")
	local bb = WorldLabel.Create(vault, LABEL.Title, {
		Name = LABEL.Name,
		Color = LABEL.Color,
		Sub = LABEL.OpenSub,
		SubColor = LABEL.OpenColor,
		Offset = Vector3.new(0, LABEL.HeightStuds, 0),
		MaxDistance = LABEL.MaxDistance,
	})
	bb:SetAttribute(LABEL.StateAttribute, "open")
	vaultLabel = bb
	lastRaiding = false
end

local FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}

-- the face of `part` whose world normal points most along `dir` (the street side of the sign)
local function faceToward(part: BasePart, dir: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -math.huge
	for _, face in ipairs(FACES) do
		local n = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
		local d = n:Dot(dir)
		if d > bestDot then
			best, bestDot = face, d
		end
	end
	return best
end

-- the bank's own folder (MapSetup's "EmpireBank" = BankId), however deep the vault sits in it
local function bankFolderOf(vault: BasePart): Instance?
	local cur = vault.Parent
	while cur ~= nil and not cur:IsA("Workspace") do
		if cur.Name == BankRaidConfig.BankId then
			return cur
		end
		cur = cur.Parent
	end
	local parent = vault.Parent
	return if parent ~= nil and not parent:IsA("Workspace") then parent else nil -- never search all of Workspace
end

-- EMPIRE BANK on the bank's sign part, only when it has no SurfaceGui yet (idempotent once lane BK paints it)
local function ensureBankSign(vault: BasePart)
	if signTried then
		return
	end
	local folder = bankFolderOf(vault)
	-- a 17-part folder; searched at most a few times (Init, the 4 Hz tick until the 2 s deferred pass)
	local sign = folder and folder:FindFirstChild(SIGN.PartName, true)
	if not (sign and sign:IsA("BasePart")) then
		return -- not built yet (retried on the next tick); nothing to paint on
	end
	signTried = true
	if sign:FindFirstChildWhichIsA("SurfaceGui") then
		return
	end
	local WorldKits = serverModule("WorldKits")
	if WorldKits == nil or WorldKits.Sign == nil then
		warn("[WAR EMPIRE] BankRaidService: WorldKits.Sign missing; EMPIRE BANK sign not painted")
		return
	end
	local ok, gui = pcall(WorldKits.Sign, sign, faceToward(sign, SIGN.Facing), SIGN.Text)
	if not ok or gui == nil then
		warn("[WAR EMPIRE] BankRaidService: EMPIRE BANK sign not painted (" .. tostring(if ok then "world sign budget" else gui) .. ")")
	end
end

local function refreshBillboardHint()
	local bb = vaultLabel
	if not bb or not bb.Parent then
		return
	end
	-- One public line; the per-player hold / cooldown stays on the raider's HUD (BankRaidController), and the
	-- "CLOSED 4m" line is drawn by that player's own client over this one.
	local anyRaiding = false
	for uid, inv in pairs(inVaultNow) do
		if inv and (holdProgress[uid] or 0) > 0 then
			anyRaiding = true
			break
		end
	end
	if anyRaiding == lastRaiding then
		return
	end
	lastRaiding = anyRaiding
	-- attribute first: a client drawing its own CLOSED line reads the public state back from it
	bb:SetAttribute(LABEL.StateAttribute, if anyRaiding then "raid" else "open")
	WorldLabel.SetText(
		bb,
		LABEL.Title,
		if anyRaiding then LABEL.RaidingSub else LABEL.OpenSub,
		if anyRaiding then LABEL.RaidingColor else LABEL.OpenColor
	)
end

-- ── guards on fixed posts ───────────────────────────────────────────────────────────────────────────────────
--[[ Root CFrames for the bank guards: the "Town.Bank" npc anchors whose role is G<n> (sorted by id), else the
	BankRaidConfig.GuardPosts fallback (at most GuardCount). Pure apart from the anchor read: exported for tests. ]]
function BankRaidService.GuardPosts(): ({ CFrame }, string)
	local lift = BankRaidConfig.GuardRootLift or 3
	local out: { CFrame } = {}
	local ActivityAnchors = serverModule("ActivityAnchors")
	if ActivityAnchors and ActivityAnchors.List then
		local ok, list = pcall(ActivityAnchors.List, BankRaidConfig.AnchorSite, "npc")
		if ok and typeof(list) == "table" then
			for _, a in ipairs(list) do
				if typeof(a.Role) == "string" and string.match(a.Role, BankRaidConfig.GuardRolePattern) and typeof(a.CFrame) == "CFrame" then
					table.insert(out, a.CFrame + Vector3.new(0, lift, 0))
				end
			end
		end
	end
	if #out > 0 then
		return out, "anchors"
	end
	local limit = BankRaidConfig.GuardCount or #BankRaidConfig.GuardPosts
	for i, p in ipairs(BankRaidConfig.GuardPosts) do
		if i > limit then
			break
		end
		local cf = CFrame.new(p.X, p.Y + lift, p.Z) * CFrame.Angles(0, math.rad(p.Yaw or 180), 0)
		table.insert(out, cf)
	end
	return out, "config"
end

local function spawnBankGuards()
	if guardsSpawned then
		return
	end
	if not CombatService or not CombatService.SpawnNPC then
		warn("[WAR EMPIRE] BankRaidService: CombatService.SpawnNPC missing")
		return
	end
	guardsSpawned = true

	local posts, source = BankRaidService.GuardPosts()
	local typeId = BankRaidConfig.GuardNPCType or "BankGuard"
	local spawned = 0
	for _, cf in ipairs(posts) do
		local rec = CombatService.SpawnNPC(typeId, cf)
		if rec then
			spawned += 1
		end
	end
	print(string.format("[WAR EMPIRE] BankRaidService: spawned %d %s combat NPCs at bank (%d fixed posts from %s)", spawned, typeId, #posts, source))
	if spawned == 0 then
		warn("[WAR EMPIRE] BankRaidService: ZERO BankGuards — will retry once in 3s")
		guardsSpawned = false
		task.delay(3, function()
			if not guardsSpawned then
				spawnBankGuards()
			end
		end)
	end
end

-- ── HUD payload ────────────────────────────────────────────────────────────────────────────────────────────
local function pushState(player: Player, opts: { InVault: boolean?, UnderFire: boolean? }?)
	if not RemoteSetup then
		return
	end
	local now = os.time()
	local untilT = cooldownUntil(player) or 0
	local remaining = math.max(0, untilT - now)
	local need = BankRaidConfig.RaidHoldSeconds or 8
	local prog = holdProgress[player.UserId] or 0
	local inVault = if opts and opts.InVault ~= nil then opts.InVault else (inVaultNow[player.UserId] == true)
	local underFire = if opts and opts.UnderFire ~= nil then opts.UnderFire else (underFireNow[player.UserId] == true)
	local remote = RemoteSetup.Get(Constants.RemoteNames.BankRaidStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		BankId = BankRaidConfig.BankId,
		DisplayName = BankRaidConfig.DisplayName,
		Enabled = BankRaidConfig.Enabled == true,
		CooldownRemaining = remaining,
		RaidHoldSeconds = need,
		HoldNeed = need,
		HoldProgress = prog,
		InVault = inVault,
		UnderFire = underFire,
		Blocked = if inVault then blockedNow[player.UserId] else nil,
		CashHintMin = BankRaidConfig.CashMin,
		CashHintMax = BankRaidConfig.CashMax,
	})
	lastPushedProgress[player.UserId] = prog
end

local function completeRaid(player: Player)
	local cashMin = BankRaidConfig.CashMin or 15000
	local cashMax = BankRaidConfig.CashMax or 35000
	local cash = math.random(cashMin, cashMax)
	holdProgress[player.UserId] = nil
	inVaultNow[player.UserId] = false
	underFireNow[player.UserId] = false
	blockedNow[player.UserId] = nil
	-- "bank_raid" is exempt from the cash multipliers (MonetizationConfig.CashMultExemptReasons): the toast is exact
	if EconomyService.AddCash(player, cash, "bank_raid") ~= true then
		pushState(player, { InVault = false, UnderFire = false })
		return -- no profile: nothing paid, so no cooldown either
	end
	local cd = BankRaidConfig.CooldownSeconds or 300
	setCooldown(player, os.time() + cd)
	if BankRaidConfig.NotifyOnRaid and NotificationService then
		NotificationService.Notify(player, string.format(TEXT.Reward, formatCash(cash)), "Reward")
	end
	if MissionService and MissionService.TrackProgress then
		local ok, err = pcall(MissionService.TrackProgress, player, "Heist", 1)
		if not ok then
			warn("[WAR EMPIRE] BankRaidService: TrackProgress Heist failed: " .. tostring(err))
		end
	end
	if AnalyticsService then
		local ev = (AnalyticsConfig.Events and AnalyticsConfig.Events.BANK_RAID) or "BANK_RAID"
		AnalyticsService.Log(ev, player.UserId, { cash = cash })
	end
	pushState(player, { InVault = false, UnderFire = false })
end

-- health drops since the last tick → "hit just now" (a respawn or regen raises health and never counts)
local function sampleHurt(uid: number, hum: Humanoid, nowC: number)
	local hp = hum.Health
	local prev = lastHealth[uid]
	if prev ~= nil and hp < prev - 0.01 then
		hurtAt[uid] = nowC
	end
	lastHealth[uid] = hp
end

local function isUnderFire(player: Player, nowC: number): boolean
	local char = player.Character
	if not char then
		return true
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return true
	end
	return nowC - (hurtAt[player.UserId] or -math.huge) < (BankRaidConfig.UnderFireSeconds or 2)
end

-- one-time tip the first time this player comes near the bank (saved; never while being shot at)
local function maybeFirstVisit(player: Player, rootPos: Vector3, nowC: number)
	local uid = player.UserId
	if firstVisitDone[uid] or not NotificationService then
		return
	end
	local center = BankRaidConfig.Position
	local dx, dz = rootPos.X - center.X, rootPos.Z - center.Z
	local r = BankRaidConfig.FirstVisitRadius or 150
	if dx * dx + dz * dz > r * r then
		return
	end
	local profile = profileOf(player)
	if DataService ~= nil and profile == nil then
		return -- not loaded yet: ask again on a later tick
	end
	local raid = if profile ~= nil then raidTable(profile) else nil
	if raid ~= nil and raid.BankSeen == true then
		firstVisitDone[uid] = true
		return
	end
	if nowC - (hurtAt[uid] or -math.huge) < (BankRaidConfig.FirstVisitSkipIfHitSeconds or 5) then
		return
	end
	firstVisitDone[uid] = true
	if raid ~= nil then
		raid.BankSeen = true
		DataService.MarkDirty(player)
	end
	NotificationService.Notify(player, TEXT.FirstVisit, "Info")
end

function BankRaidService.Push(player: Player)
	pushState(player)
end

function BankRaidService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	AnalyticsService = deps.AnalyticsService
	RemoteSetup = deps.RemoteSetup
	CombatService = deps.CombatService
	DataService = deps.DataService
	MissionService = deps.MissionService

	if not BankRaidConfig.Enabled then
		return
	end

	-- the sign first, while the world sign budget still has the bank's slot (MapDressing paints the POI boards a
	-- frame later); retried from the tick if the bank is not built yet
	do
		local vault = findVault()
		if vault then
			ensureBankSign(vault)
		end
	end

	task.defer(function()
		task.wait(2)
		local vault = findVault()
		if vault then
			ensureVaultBillboard(vault)
			ensureBankSign(vault)
			signTried = true -- one more try at most: a bank without a BankSign part has nothing to paint
		end
		spawnBankGuards()
	end)

	if DataService and DataService.OnProfileLoaded then
		-- the saved cooldown reaches the HUD (and the client's CLOSED line) as soon as the save is in
		DataService.OnProfileLoaded(function(player: Player, profile: any)
			sanitizeProfile(player, profile)
			if player.Parent then
				pushState(player)
			end
		end)
	end

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.25 then
			return
		end
		local step = accum
		accum = 0

		local vault = findVault()
		if not vault then
			return
		end
		if not (vaultLabel and vaultLabel.Parent) then
			ensureVaultBillboard(vault)
		end
		if not signTried then
			ensureBankSign(vault)
		end
		local radius = BankRaidConfig.VaultRadius or 12
		local need = BankRaidConfig.RaidHoldSeconds or 8
		local nowUnix = os.time()
		local nowC = os.clock()
		local pos = vault.Position
		local nearby: { [number]: boolean } = {}
		local toPush: { Player } = {}

		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local untilT = cooldownUntil(player) -- nil: profile not loaded → not eligible (treated as away)
			local onCooldown = untilT ~= nil and untilT > nowUnix
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local inside = false
			local fired = false

			if hum then
				sampleHurt(uid, hum, nowC)
			end
			if hrp and hum and hum.Health > 0 then
				inside = untilT ~= nil and (hrp.Position - pos).Magnitude <= radius
				maybeFirstVisit(player, hrp.Position, nowC)
			end

			if inside and not onCooldown and hum and hum.SeatPart ~= nil then
				-- on foot only: a vehicle parked on the vault never loots (progress frozen, "LEAVE VEHICLE")
				nearby[uid] = true
				inVaultNow[uid] = true
				underFireNow[uid] = false
				blockedNow[uid] = "Vehicle"
				table.insert(toPush, player)
			elseif inside and not onCooldown then
				nearby[uid] = true
				blockedNow[uid] = nil
				fired = isUnderFire(player, nowC)
				underFireNow[uid] = fired
				inVaultNow[uid] = true
				if not fired then
					local prog = (holdProgress[uid] or 0) + step
					holdProgress[uid] = prog
					if prog >= need then
						completeRaid(player)
						-- completeRaid already pushed
					else
						table.insert(toPush, player)
					end
				else
					-- Under fire: progress frozen but HUD must show the block
					table.insert(toPush, player)
				end
			elseif inside and onCooldown then
				-- Standing on vault while cooling down — still show cooldown HUD
				inVaultNow[uid] = true
				underFireNow[uid] = false
				blockedNow[uid] = nil
				nearby[uid] = true
				table.insert(toPush, player)
			else
				local wasIn = inVaultNow[uid] == true
				local hadProg = (holdProgress[uid] or 0) > 0
				blockedNow[uid] = nil
				if wasIn or hadProg then
					-- Left vault / progress reset — push once so client hides bar
					inVaultNow[uid] = false
					underFireNow[uid] = false
					holdProgress[uid] = nil
					table.insert(toPush, player)
				else
					inVaultNow[uid] = false
					underFireNow[uid] = false
				end
			end
		end

		for uid in pairs(holdProgress) do
			if not nearby[uid] then
				holdProgress[uid] = nil
			end
		end

		for _, player in ipairs(toPush) do
			pushState(player)
		end

		refreshBillboardHint()
	end)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			pushState(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		holdProgress[uid] = nil
		inVaultNow[uid] = nil
		underFireNow[uid] = nil
		blockedNow[uid] = nil
		lastPushedProgress[uid] = nil
		lastHealth[uid] = nil
		hurtAt[uid] = nil
		firstVisitDone[uid] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			pushState(player)
		end)
	end

	print("[WAR EMPIRE] BankRaidService ready (fixed-post BankGuards, on-foot hold, saved cooldown)")
end

return BankRaidService
