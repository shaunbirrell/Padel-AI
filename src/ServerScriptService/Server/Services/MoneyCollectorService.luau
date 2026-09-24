--!strict
--[[
	Money Collector — passive income accrues to PendingCash until the player
	touches their plot's WE_MoneyCollector (or owns AutoCollect entitlement).
	Server-authoritative only.

	v69 ATM raids (RaidConfig.Raid, owner rule): stand at another player's ATM — inside their base — for
	HoldSeconds, on foot, alive and without taking damage, to steal 10% of their ATM balance into your own ATM.
	The victim is then shielded for 10 minutes (profile.Raid.ShieldUntil) and the thief waits a minute
	(profile.Raid.RaidCooldownUntil); both are os.time() values on the saved profile, so leaving / rejoining /
	server hopping does not reset them. The hold runs on the server's view of the character (StepRaids) —
	there is no raid remote. Defenses are physical: any damage cancels the hold (GateDefenseService guards /
	AutoGuns, or the owner shooting back).

	v71 (HUD v70 spec §4.2 / §5): no floating ATM card — the ATM's own screen (WE_ATMScreen) carries the balance
	and a status line, the lime CollectCircle is the "stand here" cue. A collect is a "+$N" float at the cash pill
	(Notification type Collect + Amount, no lane line); walking over the ATM is silent for AutoCollect owners. No
	upsell companion lines (the client's offer toast carries the offer). A raid victim gets one Error line plus a
	red spend float (the HUD shield chip reads WE_ShieldUntil); the thief gets a Success line plus a float.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local RaidConfig = require(Shared.Configs.RaidConfig)
local CombatFairnessConfig = require(Shared.Configs.CombatFairnessConfig) -- P0-6 new-thief protection
local ServerModules = script.Parent.Parent.Modules
local RemoteSetup = require(ServerModules.RemoteSetup)

local MoneyCollectorService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local MonetizationService: any = nil
local TutorialService: any = nil
local RateLimitService: any = nil
-- v69: Init runs before these services' own Init (Bootstrap order) — only called from heartbeat / handlers
local BaseService: any = nil
local ClanService: any = nil
local GateDefenseService: any = nil
local AnalyticsService: any = nil

local TAG = Constants.Tags.MoneyCollector
local OVERLAP_MARGIN = 3.5
local COLLECT_RADIUS = 10 -- horizontal studs from ATM body (covers CollectCircle pad)
local SPATIAL_INTERVAL = 0.25
local MAX_RAID_STEP = 0.5 -- a server hitch never advances a raid hold by more than this per tick
local AUTO_COLLECT_INTERVAL = 2.0
local emptyCollectToastAt: { [number]: number } = {}

local lastOverlap: { [string]: boolean } = {}
local attached: { [BasePart]: boolean } = {}

type RaidHold = {
	VictimUserId: number,
	VictimName: string,
	PlotId: number,
	Part: BasePart,
	Progress: number,
	LastHealth: number,
	LastPushAt: number,
	LastAlarmAt: number,
	StartedAt: number,
	Hrp: BasePart,
}

type IncomeEntry = { t: number, amount: number }

-- thiefUserId → running hold (memory only; a hold never survives the thief leaving)
local holds: { [number]: RaidHold } = {}
-- thiefUserId → last Blocked reason pushed (throttle, spec §1.7)
local blockedPush: { [number]: { Reason: string, At: number } } = {}
-- teleport guard (spec §1.8), all os.clock
local lastPos: { [number]: Vector3 } = {}
local lastHrp: { [number]: BasePart } = {}
local teleportLockUntil: { [number]: number } = {}
-- AutoCollect income of the last AutoCollectWindowSeconds (memory only, spec §1.5); os.time stamps
local recentAuto: { [number]: { IncomeEntry } } = {}
-- non-yielding "owns AutoCollect" flag, refreshed by the AutoCollect loop (entitlement checks can yield on a cold
-- game-pass cache; the raid path must never yield)
local autoCollectFlag: { [number]: boolean } = {}

local function hasAutoCollect(player: Player): boolean
	if MonetizationService and MonetizationService.PlayerOwnsEntitlement then
		if MonetizationService.PlayerOwnsEntitlement(player, "AutoCollect") then
			return true
		end
	end
	if MonetizationService and MonetizationService.PlayerOwnsGamePass then
		if MonetizationService.PlayerOwnsGamePass(player, "AutoCollect") then
			return true
		end
	end
	local profile = DataService.GetProfile(player)
	if profile and typeof(profile.Entitlements) == "table" and profile.Entitlements.AutoCollect == true then
		return true
	end
	return false
end

local function hasDoubleCash(player: Player): boolean
	if MonetizationService and MonetizationService.PlayerOwnsEntitlement then
		if MonetizationService.PlayerOwnsEntitlement(player, "DoubleCash") then
			return true
		end
	end
	if MonetizationService and MonetizationService.PlayerOwnsGamePass then
		if MonetizationService.PlayerOwnsGamePass(player, "DoubleCash") then
			return true
		end
	end
	local profile = DataService.GetProfile(player)
	if profile and typeof(profile.Entitlements) == "table" and profile.Entitlements.DoubleCash == true then
		return true
	end
	return false
end

-- ── small helpers ───────────────────────────────────────────────────────────

local function profileOf(player: Player): any
	if not DataService then
		return nil
	end
	return DataService.GetProfile(player)
end

-- v67 contract: true only for a save read from the DataStore (never for a session-only profile)
local function isLoaded(player: Player): boolean
	if not DataService then
		return false
	end
	if DataService.IsLoaded then
		return DataService.IsLoaded(player) == true
	end
	return DataService.GetProfile(player) ~= nil
end

local function markDirty(player: Player)
	if DataService and DataService.MarkDirty then
		DataService.MarkDirty(player)
	end
end

local function raidNum(profile: any, key: string): number
	local raid = profile and profile.Raid
	if typeof(raid) ~= "table" then
		return 0
	end
	return tonumber(raid[key]) or 0
end

local function raidOf(profile: any): { [string]: any }
	local raid = profile.Raid
	if typeof(raid) ~= "table" then
		raid = { ShieldUntil = 0, StrikeCooldownUntil = 0, DefensesDownUntil = 0 }
		profile.Raid = raid
	end
	return raid
end

local function formatCash(n: number): string
	local s = string.format("%d", math.floor(math.abs(n)))
	local out = (string.reverse(s):gsub("(%d%d%d)", "%1,"))
	out = string.reverse(out)
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if n < 0 then "-" else "") .. out
end

local function plotIdOf(part: BasePart): number?
	local raw = part:GetAttribute("PlotId")
	if typeof(raw) == "number" then
		return raw
	end
	local n = tonumber(raw)
	if typeof(n) == "number" then
		return n
	end
	return nil
end

-- Server truth for plot ownership (BaseService); profile scan only when BaseService is missing.
local function ownerUserIdOfPlot(plotId: number): number?
	if BaseService and BaseService.GetOwnerUserId then
		local uid = BaseService.GetOwnerUserId(plotId)
		if typeof(uid) == "number" then
			return uid
		end
		return nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = profileOf(player)
		if profile and profile.BasePlotId == plotId then
			return player.UserId
		end
	end
	return nil
end

local function findOwnerByPlot(plotId: number): Player?
	local uid = ownerUserIdOfPlot(plotId)
	if uid == nil then
		return nil
	end
	return Players:GetPlayerByUserId(uid)
end

local function ownedPlotOf(player: Player): number?
	if BaseService and BaseService.GetOwnedPlotId then
		local pid = BaseService.GetOwnedPlotId(player)
		if typeof(pid) == "number" then
			return pid
		end
		return nil
	end
	local profile = profileOf(player)
	local pid = if profile then tonumber(profile.BasePlotId) else nil
	return pid
end

local function isAlly(ownerUserId: number, player: Player): boolean
	if player.UserId == ownerUserId then
		return true
	end
	if GateDefenseService and GateDefenseService.IsAlly then
		return GateDefenseService.IsAlly(ownerUserId, player) == true
	end
	-- Fallback (no GateDefenseService): same non-empty clan id
	if not (ClanService and ClanService.GetClanId) then
		return false
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return false
	end
	local okA, a = pcall(ClanService.GetClanId, owner)
	local okB, b = pcall(ClanService.GetClanId, player)
	return okA and okB and typeof(a) == "string" and a ~= "" and a == b
end

local function newPlayerSecondsLeft(profile: any): number
	local R = RaidConfig.Raid
	if RunService:IsStudio() and not R.ProtectNewPlayersInStudio then
		return 0
	end
	local first = tonumber(profile.FirstJoinUnix) or 0
	if first <= 0 then
		return 0
	end
	return math.max(0, first + R.NewPlayerProtectionSeconds - os.time())
end

--[[ P0-6 (mobile plan): mirror of the victim's protection for the THIEF — a player still in the tutorial, or inside
	their first CombatFairnessConfig.ThiefProtectMinutes, cannot rob an ATM (the tutorial's guide line must never
	turn into a raid on someone else's base). Returns (reason?, secondsLeft?). ]]
local function newThiefBlock(profile: any): (string?, number?)
	local C = CombatFairnessConfig
	if not C.ThiefProtectEnabled then
		return nil, nil
	end
	if RunService:IsStudio() and not C.ThiefProtectInStudio then
		return nil, nil
	end
	if C.ThiefRequireTutorialDone and profile.TutorialComplete ~= true then
		return "ThiefTutorial", nil
	end
	local first = tonumber(profile.FirstJoinUnix) or 0
	if first > 0 then
		local left = first + C.ThiefProtectMinutes * 60 - os.time()
		if left > 0 then
			return "ThiefNew", left
		end
	end
	return nil, nil
end

-- ── AutoCollect income window (spec §1.5) ──────────────────────────────────

local function pruneRecent(userId: number): { IncomeEntry }?
	local list = recentAuto[userId]
	if not list then
		return nil
	end
	local window = RaidConfig.Raid.AutoCollectWindowSeconds
	local nowUnix = os.time()
	local kept: { IncomeEntry } = {}
	for _, e in ipairs(list) do
		if nowUnix - e.t <= window then
			table.insert(kept, e)
		end
	end
	if #kept == 0 then
		recentAuto[userId] = nil
		return nil
	end
	recentAuto[userId] = kept
	return kept
end

local function recordAutoIncome(userId: number, amount: number)
	if amount <= 0 then
		return
	end
	local list = pruneRecent(userId) or {}
	table.insert(list, { t = os.time(), amount = math.floor(amount) })
	recentAuto[userId] = list
end

local function recentAutoSum(userId: number): number
	local list = pruneRecent(userId)
	if not list then
		return 0
	end
	local total = 0
	for _, e in ipairs(list) do
		total += e.amount
	end
	return total
end

-- What "10% of their ATM" is taken from: PendingCash, plus the last 10 min of auto-collected income for
-- AutoCollect owners (otherwise AutoCollect would be raid immunity — its loop empties the ATM every 2 s).
function MoneyCollectorService.GetRaidableBalance(victim: Player): number
	local profile = profileOf(victim)
	if not profile then
		return 0
	end
	local balance = math.max(0, math.floor(tonumber(profile.PendingCash) or 0))
	if RaidConfig.Raid.AutoCollectCountsRecentIncome and autoCollectFlag[victim.UserId] == true then
		-- capped at the Cash they still hold: auto income already spent cannot be stolen (completeRaid takes the
		-- rest out of Cash), so the ATM never shows / promises more than a raid can actually take
		local cash = math.max(0, math.floor(tonumber(profile.Cash) or 0))
		balance += math.min(recentAutoSum(victim.UserId), cash)
	end
	return balance
end

-- ── ATM screen (no floating card: spec §5 "WE_CollectorBillboard … REMOVE") ──────────────────────────────

-- v71: the old floating "ATM · WALK IN TO COLLECT" card (WE_CollectorBillboard: AlwaysOnTop, 100 studs, a card
-- with a backdrop) is gone. Remove one left by an older server build or a resetmap.
local function dropLegacyBillboard(part: BasePart)
	local oldBb = part:FindFirstChild("WE_CollectorBillboard")
	if oldBb then
		oldBb:Destroy()
	end
end

-- The status line sits on the painted ATM screen (MapSetup's WE_ATMScreen SurfaceGui): top third, the digits
-- below it. Built once per screen; later refreshes only write changed text.
local function ensureScreenStatus(sg: Instance, digits: TextLabel): TextLabel?
	local st = sg:FindFirstChild("Status")
	if st and st:IsA("TextLabel") then
		return st
	end
	digits.AnchorPoint = Vector2.new(0.5, 1)
	digits.Position = UDim2.fromScale(0.5, 1)
	digits.Size = UDim2.fromScale(1, 0.68)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Status"
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.Position = UDim2.fromScale(0.5, 0)
	lbl.Size = UDim2.fromScale(1, 0.32)
	lbl.BackgroundColor3 = Color3.fromRGB(6, 26, 12)
	lbl.BackgroundTransparency = 0.1
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(200, 230, 200)
	lbl.Text = ""
	lbl.Parent = sg
	return lbl
end

local function syncAtmScreen(part: BasePart, pending: number, title: string?)
	local folder = part.Parent
	if not folder then
		return
	end
	local screen = folder:FindFirstChild("CollectorScreen")
	if not (screen and screen:IsA("BasePart")) then
		return
	end
	local sg = screen:FindFirstChild("WE_ATMScreen")
	local digits = sg and sg:FindFirstChild("Digits")
	if sg and digits and digits:IsA("TextLabel") then
		local text = string.format("$%s", tostring(math.floor(pending)))
		if digits.Text ~= text then
			digits.Text = text
			digits.TextColor3 = if pending > 0 then Color3.fromRGB(70, 255, 120) else Color3.fromRGB(40, 120, 70)
		end
		if title then
			local st = ensureScreenStatus(sg, digits)
			if st and st.Text ~= title then
				st.Text = title
			end
		end
	end
	local light = part:FindFirstChild("ATMGlow")
	if light and light:IsA("PointLight") then
		light.Color = Color3.fromRGB(120, 255, 90)
		if pending >= 500 then
			light.Brightness = 1.4
			light.Range = 18
		elseif pending > 0 then
			light.Brightness = 0.9
			light.Range = 14
		else
			light.Brightness = 0.35
			light.Range = 10
		end
	end
end

local function isBeingRobbed(plotId: number): boolean
	for _, hold in pairs(holds) do
		if hold.PlotId == plotId then
			return true
		end
	end
	return false
end

-- ATM screen status line (raid spec §1.10): shield > being robbed > AutoCollect > walk-in. Painted on the ATM's
-- own screen (v71), so it reads only up close and never floats over the HUD.
local function atmTitle(owner: Player?, plotId: number?): string
	if owner then
		local profile = profileOf(owner)
		local shield = raidNum(profile, "ShieldUntil")
		local nowUnix = os.time()
		if shield > nowUnix then
			return "ATM · SHIELD " .. RaidConfig.FormatTime(shield - nowUnix)
		end
		if plotId ~= nil and isBeingRobbed(plotId) then
			return "ATM BEING ROBBED!"
		end
		if autoCollectFlag[owner.UserId] == true then
			return "ATM · AUTO-COLLECT"
		end
	end
	return "ATM · WALK IN TO COLLECT"
end

local function refreshBillboard(part: BasePart, pending: number, title: string?)
	syncAtmScreen(part, pending, title)
end

local function pointInPart(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 4
		and localPos.Y <= half.Y + 10
end

local function nearCollector(hrpPos: Vector3, part: BasePart): boolean
	-- Prefer generous ground radius so standing on CollectCircle / black base works
	local delta = hrpPos - part.Position
	local horiz = Vector3.new(delta.X, 0, delta.Z).Magnitude
	if horiz <= COLLECT_RADIUS then
		return math.abs(delta.Y) <= 14
	end
	return pointInPart(hrpPos, part)
end

-- Raid range: horizontal RadiusStuds and |dy| <= MaxHeightDelta from the ATM body
local function inRaidRange(hrpPos: Vector3, part: BasePart): boolean
	local R = RaidConfig.Raid
	local delta = hrpPos - part.Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= R.RadiusStuds and math.abs(delta.Y) <= R.MaxHeightDelta
end

-- ── raid feedback ──────────────────────────────────────────────────────────

local function pushAtmRaidState(player: Player, payload: { [string]: any })
	local remote = RemoteSetup.Get(Constants.RemoteNames.AtmRaidStateUpdate)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent):FireClient(player, payload)
	end
end

local function reasonText(reason: string, secs: number?, balance: number?): string
	local T = RaidConfig.Text
	if reason == "Hit" then
		return T.RaidHit
	elseif reason == "LeftRange" then
		return T.RaidLeft
	elseif reason == "VictimLeft" then
		return T.RaidVictimLeft
	elseif reason == "Emptied" then
		return T.RaidEmptied
	elseif reason == "Dead" then
		return T.RaidDead
	end
	if reason == "ThiefTutorial" then -- P0-6 (texts in CombatFairnessConfig; device-neutral)
		return CombatFairnessConfig.ThiefTutorialText
	elseif reason == "ThiefNew" then
		return string.format(CombatFairnessConfig.ThiefNewText, RaidConfig.FormatTime(secs or 0))
	end
	local tpl = T.Blocked[reason]
	if not tpl then
		return reason
	end
	if string.find(tpl, "%s", 1, true) then
		if reason == "LowBalance" then
			return string.format(tpl, formatCash(balance or 0))
		end
		return string.format(tpl, RaidConfig.FormatTime(secs or 0))
	end
	return tpl
end

-- CanRaid reason while a hold was running → the Interrupted reason the thief sees
local function interruptReason(reason: string): string
	if reason == "LowBalance" then
		return "Emptied"
	elseif reason == "VictimLoading" then
		return "VictimLeft"
	end
	return reason
end

-- Reasons shown as Phase "Interrupted"; any other cause of a cancel is shown as Phase "Blocked" with its code
local INTERRUPT_REASONS: { [string]: boolean } = { Hit = true, LeftRange = true, VictimLeft = true, Emptied = true, Dead = true }

local function holdingPayload(hold: RaidHold): { [string]: any }
	local need = RaidConfig.Raid.HoldSeconds
	local progress = math.min(hold.Progress, need)
	return {
		Phase = "Holding",
		VictimName = hold.VictimName,
		HoldProgress = math.floor(progress * 100 + 0.5) / 100,
		HoldNeed = need,
		Text = string.format(RaidConfig.Text.RaidHolding, hold.VictimName, progress, math.floor(need)),
	}
end

local function pushAlarm(victim: Player, thief: Player, hold: RaidHold, first: boolean)
	local need = RaidConfig.Raid.HoldSeconds
	local text = string.format(RaidConfig.Text.RaidAlarm, thief.DisplayName)
	hold.LastAlarmAt = os.clock()
	pushAtmRaidState(victim, {
		Phase = "Alarm",
		ThiefName = thief.DisplayName,
		HoldProgress = math.floor(math.min(hold.Progress, need) * 100 + 0.5) / 100,
		HoldNeed = need,
		Text = text,
	})
	if first and NotificationService and NotificationService.NotifyThrottled then
		NotificationService.NotifyThrottled(victim, text, "Warn", 4, RaidConfig.Raid.VictimAlarmToastCooldown, "atm_alarm")
	end
end

-- Blocked is re-sent only when the reason changes, or every BlockedPushInterval while standing at the ATM.
local function pushBlocked(thief: Player, victim: Player, reason: string, secs: number?, force: boolean?)
	local nowC = os.clock()
	local rec = blockedPush[thief.UserId]
	if not force and rec and rec.Reason == reason and nowC - rec.At < RaidConfig.Raid.BlockedPushInterval - 1e-6 then
		return
	end
	blockedPush[thief.UserId] = { Reason = reason, At = nowC }
	local balance = if reason == "LowBalance" then MoneyCollectorService.GetRaidableBalance(victim) else nil
	pushAtmRaidState(thief, {
		Phase = "Blocked",
		Reason = reason,
		VictimName = victim.DisplayName,
		CooldownRemaining = if secs then math.max(0, math.ceil(secs)) else nil,
		Text = reasonText(reason, secs, balance),
	})
end

local function clearHold(thief: Player): RaidHold?
	local hold = holds[thief.UserId]
	holds[thief.UserId] = nil
	pcall(function()
		thief:SetAttribute("WE_RaidingPlot", nil)
	end)
	return hold
end

--[[ Cancel a running hold. `reason` is a cancel reason (Hit / LeftRange / VictimLeft / Dead) or the CanRaid code
	that failed mid-hold (LowBalance shows as Emptied, VictimLoading as VictimLeft). Interrupt reasons push
	"Interrupted"; any other rule (Shielded, Seated, Teleport …) pushes "Blocked" with its code instead (one chip,
	not two). The victim gets "Defended" when the hold had reached >= 1 s — unless they were just robbed / left. ]]
local function cancelHold(thief: Player, reason: string, secs: number?, victim: Player?)
	local hold = clearHold(thief)
	if not hold then
		return
	end
	local shown = interruptReason(reason)
	if INTERRUPT_REASONS[shown] or victim == nil then
		pushAtmRaidState(thief, {
			Phase = "Interrupted",
			Reason = shown,
			VictimName = hold.VictimName,
			HoldProgress = math.floor(math.min(hold.Progress, RaidConfig.Raid.HoldSeconds) * 100 + 0.5) / 100,
			HoldNeed = RaidConfig.Raid.HoldSeconds,
			Text = reasonText(shown, secs),
		})
		-- the chip already says why: no Blocked push of the same cause right after it
		blockedPush[thief.UserId] = { Reason = reason, At = os.clock() }
	else
		pushBlocked(thief, victim, reason, secs, true)
	end
	if hold.Progress >= 1 and shown ~= "VictimLeft" then
		local owner = Players:GetPlayerByUserId(hold.VictimUserId)
		if owner and raidNum(profileOf(owner), "ShieldUntil") <= os.time() then
			pushAtmRaidState(owner, {
				Phase = "Defended",
				ThiefName = thief.DisplayName,
				Reason = shown,
				Text = RaidConfig.Text.RaidDefended,
			})
		end
	end
end

-- ── rules (spec §1.1) ──────────────────────────────────────────────────────

--[[ (ok, reason?, secondsLeft?) — first failure wins. reason nil = silent (own ATM). "Dead" / "VictimLeft" are
	cancel-only reasons (never pushed as Blocked). ]]
function MoneyCollectorService.CanRaid(thief: Player, victim: Player): (boolean, string?, number?)
	local R = RaidConfig.Raid
	if not R.Enabled then
		return false, "Disabled"
	end
	if victim == thief or victim.UserId == thief.UserId then
		return false, nil
	end
	if victim.Parent == nil or ownedPlotOf(victim) == nil then
		return false, "VictimLeft"
	end
	local tProfile = profileOf(thief)
	if not tProfile or not isLoaded(thief) then
		return false, "ThiefLoading"
	end
	-- a session-only save would create / destroy money: refuse until the real save is in
	local vProfile = profileOf(victim)
	if not vProfile or not isLoaded(victim) then
		return false, "VictimLoading"
	end
	if ownedPlotOf(thief) == nil then
		return false, "NoBase"
	end
	local thiefBlock, thiefLeft = newThiefBlock(tProfile)
	if thiefBlock then
		return false, thiefBlock, thiefLeft
	end
	if not R.AllowAllies and isAlly(victim.UserId, thief) then
		return false, "Ally"
	end
	local char = thief.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false, "Dead"
	end
	if R.RequireOnFoot and hum.SeatPart ~= nil then
		return false, "Seated"
	end
	local lock = teleportLockUntil[thief.UserId]
	if lock and os.clock() < lock then
		return false, "Teleport", math.ceil(lock - os.clock())
	end
	local nowUnix = os.time()
	local cd = raidNum(tProfile, "RaidCooldownUntil")
	if nowUnix < cd then
		return false, "ThiefCooldown", cd - nowUnix
	end
	local shield = raidNum(vProfile, "ShieldUntil")
	if nowUnix < shield then
		return false, "Shielded", shield - nowUnix
	end
	local newLeft = newPlayerSecondsLeft(vProfile)
	if newLeft > 0 then
		return false, "NewPlayer", newLeft
	end
	local balance = MoneyCollectorService.GetRaidableBalance(victim)
	if balance < R.MinVictimBalance or math.floor(balance * R.StealFraction) < R.MinSteal then
		return false, "LowBalance"
	end
	return true, nil, nil
end

function MoneyCollectorService.GetRaidHold(thief: Player): { VictimUserId: number, Progress: number }?
	local hold = holds[thief.UserId]
	if not hold then
		return nil
	end
	return { VictimUserId = hold.VictimUserId, Progress = hold.Progress }
end

-- ── steal (spec §1.4) — synchronous: nothing here may yield ─────────────────

local function completeRaid(thief: Player, victim: Player, hold: RaidHold): boolean
	local R = RaidConfig.Raid
	-- 1. re-validate at the moment of completion (a second thief finishing on the same tick fails here: Shielded)
	local ok, reason, secs = MoneyCollectorService.CanRaid(thief, victim)
	if not ok then
		cancelHold(thief, reason or "VictimLeft", secs, victim)
		return false
	end
	local vProfile = profileOf(victim)
	local tProfile = profileOf(thief)
	if not vProfile or not tProfile or not EconomyService then
		cancelHold(thief, "VictimLeft")
		return false
	end
	-- 2. 10% of the raidable balance
	local balance = MoneyCollectorService.GetRaidableBalance(victim)
	local steal = math.floor(balance * R.StealFraction)
	-- 3. protection first: a failure below favours the victim
	local vRaid = raidOf(vProfile)
	local tRaid = raidOf(tProfile)
	local oldShield = vRaid.ShieldUntil
	local oldCooldown = tRaid.RaidCooldownUntil
	local nowUnix = os.time()
	vRaid.ShieldUntil = nowUnix + R.ShieldSeconds
	tRaid.RaidCooldownUntil = nowUnix + R.ThiefCooldownSeconds
	-- 4. PendingCash → thief's ATM, 1:1 (existing transfer, no multipliers)
	local moved = 0
	local pending = math.max(0, math.floor(tonumber(EconomyService.GetPendingCash(victim)) or 0))
	local fromPending = math.min(steal, pending)
	if fromPending > 0 then
		moved = math.max(0, math.floor(tonumber(EconomyService.TransferPendingCash(victim, thief, fromPending)) or 0))
	end
	-- 5. AutoCollect owners: the rest comes out of the last 10 min of auto-collected income (now in Cash)
	local rest = steal - moved
	if rest > 0 and R.AutoCollectCountsRecentIncome and autoCollectFlag[victim.UserId] == true then
		local cash = math.max(0, math.floor(tonumber(EconomyService.GetCash(victim)) or 0))
		local cashTake = math.floor(math.min(rest, recentAutoSum(victim.UserId), cash))
		if cashTake > 0 and EconomyService.SpendCash(victim, cashTake, "atm_raid_loss") then
			-- "atm_raid" is NEVER_MULTIPLIED → the thief gets exactly what the victim lost
			if EconomyService.AccruePendingCash(thief, cashTake, "atm_raid") then
				moved += cashTake
			else
				EconomyService.AddCash(victim, cashTake, "purchase_refund")
			end
		end
	end
	-- 6. nothing moved → no shield, no cooldown
	if moved <= 0 then
		vRaid.ShieldUntil = oldShield
		tRaid.RaidCooldownUntil = oldCooldown
		clearHold(thief)
		pushBlocked(thief, victim, "LowBalance", nil, true)
		return false
	end
	-- 7. persist + mirror
	markDirty(victim)
	markDirty(thief)
	pcall(function()
		victim:SetAttribute("WE_ShieldUntil", vRaid.ShieldUntil)
	end)
	recentAuto[victim.UserId] = nil
	clearHold(thief)
	-- keep the 5 s Success chip up: the thief is still on the ATM (now ThiefCooldown) — no Blocked push for 5 s
	blockedPush[thief.UserId] = { Reason = "ThiefCooldown", At = os.clock() + 5 - R.BlockedPushInterval }
	-- 8. feedback
	local T = RaidConfig.Text
	local successText = string.format(T.RaidSuccess, formatCash(moved), victim.DisplayName)
	local robbedText = string.format(T.RaidRobbed, thief.DisplayName, formatCash(moved), RaidConfig.FormatTime(R.ShieldSeconds))
	if NotificationService then
		-- spec §4.2: thief → Success line + "+$N" float; victim → Error line + red spend float (shield chip = HUD)
		NotificationService.Notify(thief, successText, "Success", 5)
		NotificationService.Notify(thief, string.format("+$%s", formatCash(moved)), "Collect", nil, moved)
		NotificationService.Notify(victim, robbedText, "Error", 6)
		NotificationService.Notify(victim, string.format("-$%s", formatCash(moved)), "Collect", nil, -moved)
	end
	pushAtmRaidState(thief, {
		Phase = "Success",
		VictimName = victim.DisplayName,
		Stolen = moved,
		Text = successText,
		CooldownRemaining = R.ThiefCooldownSeconds,
		CooldownTotal = R.ThiefCooldownSeconds,
		Success = true,
	})
	pushAtmRaidState(victim, {
		Phase = "Robbed",
		ThiefName = thief.DisplayName,
		Stolen = moved,
		ShieldRemaining = R.ShieldSeconds,
		Text = robbedText,
		CooldownRemaining = 0,
		CooldownTotal = R.ThiefCooldownSeconds,
		Success = false,
		Raided = true,
	})
	MoneyCollectorService.RefreshForPlayer(victim)
	if AnalyticsService and AnalyticsService.Log then
		local props = { VictimUserId = victim.UserId, Stolen = moved, Balance = balance, PlotId = hold.PlotId }
		task.spawn(function()
			pcall(AnalyticsService.Log, "ATM_RAID", thief.UserId, props)
		end)
	end
	return true
end

-- ── the hold state machine (spec §1.3) ─────────────────────────────────────

-- Foreign ATM (owned by someone else) this position is in raid range of; prefers the running hold's ATM.
local function findForeignAtm(player: Player, pos: Vector3, hold: RaidHold?): (BasePart?, number?, number?)
	if hold and hold.Part.Parent and inRaidRange(pos, hold.Part) then
		local ownerId = ownerUserIdOfPlot(hold.PlotId)
		if ownerId ~= nil and ownerId ~= player.UserId then
			return hold.Part, hold.PlotId, ownerId
		end
	end
	for part in pairs(attached) do
		if part.Parent and inRaidRange(pos, part) then
			local plotId = plotIdOf(part)
			if plotId ~= nil then
				local ownerId = ownerUserIdOfPlot(plotId)
				if ownerId ~= nil and ownerId ~= player.UserId then
					return part, plotId, ownerId
				end
			end
		end
	end
	return nil, nil, nil
end

local function stepPlayer(player: Player, step: number, nowC: number)
	local R = RaidConfig.Raid
	local uid = player.UserId
	local char = player.Character
	local hrpInst = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrpInst and hrpInst:IsA("BasePart")) then
		lastPos[uid] = nil
		lastHrp[uid] = nil
		if holds[uid] then
			cancelHold(player, "Dead")
		end
		return
	end
	local hrp = hrpInst :: BasePart
	local hum = (char :: Model):FindFirstChildOfClass("Humanoid")
	local pos = hrp.Position

	-- 1. teleport bookkeeping (same HRP, on foot, > TeleportStuds in one tick → lockout)
	local seated = hum ~= nil and hum.SeatPart ~= nil
	local prevPos: Vector3? = lastPos[uid]
	if lastHrp[uid] == hrp and prevPos and not seated then
		local limit = R.TeleportStuds * math.max(1, step / SPATIAL_INTERVAL)
		if (pos - prevPos).Magnitude > limit then
			teleportLockUntil[uid] = nowC + R.TeleportLockoutSeconds
		end
	end
	lastPos[uid] = pos
	lastHrp[uid] = hrp

	local hold: RaidHold? = holds[uid]
	if hold and hold.Hrp ~= hrp then
		cancelHold(player, "Dead") -- respawned mid-hold
		hold = nil
	end

	-- 2. a foreign ATM in range
	local part, plotId, ownerId = findForeignAtm(player, pos, hold)
	if not part or plotId == nil or ownerId == nil then
		if hold then
			local stillThere = hold.Part.Parent ~= nil and inRaidRange(pos, hold.Part)
			cancelHold(player, if stillThere then "VictimLeft" else "LeftRange")
		end
		return
	end
	local victim = Players:GetPlayerByUserId(ownerId)
	if not victim then
		if hold then
			cancelHold(player, "VictimLeft")
		end
		return
	end

	-- 3. rules
	local ok, reason, secs = MoneyCollectorService.CanRaid(player, victim)
	if not ok then
		if hold then
			cancelHold(player, reason or "VictimLeft", secs, victim)
		elseif reason ~= nil and reason ~= "Dead" and reason ~= "VictimLeft" then
			pushBlocked(player, victim, reason, secs)
		end
		return
	end
	if not hum then
		return
	end

	-- 4. start (or switch victim)
	if hold and hold.VictimUserId ~= victim.UserId then
		cancelHold(player, "LeftRange")
		hold = nil
	end
	if not hold then
		local newHold: RaidHold = {
			VictimUserId = victim.UserId,
			VictimName = victim.DisplayName,
			PlotId = plotId,
			Part = part,
			Progress = 0,
			LastHealth = hum.Health,
			LastPushAt = -math.huge,
			LastAlarmAt = -math.huge,
			StartedAt = nowC,
			Hrp = hrp,
		}
		holds[uid] = newHold
		hold = newHold
		blockedPush[uid] = nil
		pcall(function()
			player:SetAttribute("WE_RaidingPlot", plotId)
		end)
		pushAlarm(victim, player, newHold, true)
	else
		-- 5. any damage cancels (progress back to 0; restarts next tick while still in range)
		if hum.Health < hold.LastHealth - R.DamageCancelHp then
			cancelHold(player, "Hit")
			return
		end
		hold.LastHealth = hum.Health
	end
	local h = hold :: RaidHold
	h.Progress += step

	-- 6. done
	if h.Progress >= R.HoldSeconds - 1e-6 then
		completeRaid(player, victim, h)
		return
	end
	if nowC - h.LastPushAt >= R.HoldPushInterval - 1e-6 then
		h.LastPushAt = nowC
		pushAtmRaidState(player, holdingPayload(h))
	end
	if nowC - h.LastAlarmAt >= R.AlarmPushInterval - 1e-6 then
		pushAlarm(victim, player, h, false)
	end
end

--[[ One raid tick for every online player (heartbeat calls it every ~0.25 s with the elapsed time; exported so
	tests can drive it with a fake clock). ]]
function MoneyCollectorService.StepRaids(step: number)
	if typeof(step) ~= "number" or step ~= step or step <= 0 then
		return
	end
	step = math.min(step, MAX_RAID_STEP)
	local nowC = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		xpcall(stepPlayer, function(err)
			warn("[MoneyCollector] raid step failed", player.UserId, err)
		end, player, step, nowC)
	end
end

-- ── collect ────────────────────────────────────────────────────────────────

-- silent: the AutoCollect loop collects every few seconds; the cash readout updating is the feedback.
-- v69: silent also skips the money-bag FX and the soft offers (they ran every 2 s for AutoCollect owners).
function MoneyCollectorService.Collect(player: Player, silent: boolean?): (boolean, number)
	if not EconomyService or not EconomyService.CollectPendingCash then
		return false, 0
	end
	local granted = EconomyService.CollectPendingCash(player)
	if granted <= 0 then
		return false, 0
	end
	if TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "PassiveIncome")
	end
	if silent then
		return true, granted
	end
	if NotificationService then
		-- spec §4.2: type Collect + Amount → only the "+$N" float at the cash pill, never a lane line
		NotificationService.Notify(player, string.format("Collected $%d", granted), "Collect", 3, granted)
	end
	-- v33: one-shot soft AutoCollect GamePass offer after first manual collect
	do
		local profile = DataService.GetProfile(player)
		local offerCfg = (MonetizationConfig :: any).AutoCollectOffer
		local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.AutoCollect
		if (
			profile
			and offerCfg
			and gp
			and typeof(gp.Id) == "number"
			and gp.Id ~= 0
			and profile.AutoCollectOffered ~= true
			and not hasAutoCollect(player)
			and (not MonetizationService or not MonetizationService.ClaimSoftOfferSlot or MonetizationService.ClaimSoftOfferSlot(player))
		) then
			profile.AutoCollectOffered = true
			DataService.MarkDirty(player)
			task.delay(tonumber(offerCfg.DelaySeconds) or 1.2, function()
				if not player.Parent then
					return
				end
				if hasAutoCollect(player) then
					return
				end
				local remote = RemoteSetup.Get(Constants.RemoteNames.AutoCollectOffer)
				if remote and remote:IsA("RemoteEvent") then
					(remote :: RemoteEvent):FireClient(player, {
						ProductKey = "AutoCollect",
						GamePassId = gp.Id,
						DisplayName = gp.DisplayName or "Auto Collect",
						RobuxPrice = gp.RobuxPrice,
					})
				end
				-- (no companion Info line: the client's offer toast is the whole offer — spec §4.2)
			end)
		end
	end
	-- v34: one-shot DoubleCash soft offer after meaningful collect (existing Id only; not spammy)
	do
		local profile = DataService.GetProfile(player)
		local offerCfg = (MonetizationConfig :: any).DoubleCashOffer
		local gp = MonetizationConfig.GamePasses and MonetizationConfig.GamePasses.DoubleCash
		local minCash = tonumber(offerCfg and offerCfg.MinCollectCash) or 2500
		-- Prefer after AutoCollect already teased/owned so we don't stack two toasts on first collect
		local acReady = profile and (profile.AutoCollectOffered == true or hasAutoCollect(player))
		if (
			profile
			and offerCfg
			and gp
			and typeof(gp.Id) == "number"
			and gp.Id ~= 0
			and granted >= minCash
			and acReady
			and profile.DoubleCashOffered ~= true
			and not hasDoubleCash(player)
			and (not MonetizationService or not MonetizationService.ClaimSoftOfferSlot or MonetizationService.ClaimSoftOfferSlot(player))
		) then
			profile.DoubleCashOffered = true
			DataService.MarkDirty(player)
			task.delay(tonumber(offerCfg.DelaySeconds) or 1.8, function()
				if not player.Parent then
					return
				end
				if hasDoubleCash(player) then
					return
				end
				local remote = RemoteSetup.Get(Constants.RemoteNames.DoubleCashOffer)
				if remote and remote:IsA("RemoteEvent") then
					(remote :: RemoteEvent):FireClient(player, {
						ProductKey = "DoubleCash",
						GamePassId = gp.Id,
						DisplayName = gp.DisplayName or "2x Cash",
						RobuxPrice = gp.RobuxPrice,
					})
				end
				-- (no companion Info line: the client's offer toast is the whole offer — spec §4.2)
			end)
		end
	end
	-- v37: one-shot CashMega soft offer after high pending collect (existing Id only)
	if MonetizationService and MonetizationService.TrySoftOfferCashMega then
		pcall(function()
			MonetizationService.TrySoftOfferCashMega(player, "pending_collect", granted)
		end)
	end
	-- v69: FX on its own thread (a catalog load can yield; the collect path never does)
	task.spawn(function()
		pcall(function()
			local vas = require(script.Parent.VisualAssetService) :: any
			local plotId = ownedPlotOf(player)
			local pos: Vector3? = nil
			local parent: Instance? = nil
			if plotId ~= nil then
				for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
					if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
						pos = inst.Position + Vector3.new(0, 4, 0)
						parent = inst.Parent
						break
					end
				end
			end
			if not pos then
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					pos = hrp.Position
				end
			end
			if pos and vas and vas.PlayMoneyBagFX then
				vas.PlayMoneyBagFX(pos, parent)
			end
		end)
	end)
	return true, granted
end

function MoneyCollectorService.RefreshAllBillboards()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and inst.Parent then
			local plotId = plotIdOf(inst)
			local owner = if plotId ~= nil then findOwnerByPlot(plotId) else nil
			local amount = if owner then MoneyCollectorService.GetRaidableBalance(owner) else 0
			refreshBillboard(inst, amount, atmTitle(owner, plotId))
		end
	end
end

function MoneyCollectorService.RefreshForPlayer(player: Player)
	local plotId = ownedPlotOf(player)
	if plotId == nil then
		return
	end
	local amount = MoneyCollectorService.GetRaidableBalance(player)
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and plotIdOf(inst) == plotId then
			refreshBillboard(inst, amount, atmTitle(player, plotId))
		end
	end
end

-- Non-owner pressed the ATM prompt: a hint only (rate limited) — the raid itself is the server-side hold.
local function promptHint(player: Player, owner: Player)
	if RateLimitService and not RateLimitService.Allow(player, "atm_prompt", 2, 3) then
		return
	end
	local hold = holds[player.UserId]
	if hold then
		pushAtmRaidState(player, holdingPayload(hold))
		return
	end
	local ok, reason, secs = MoneyCollectorService.CanRaid(player, owner)
	if not ok then
		if reason ~= nil and reason ~= "Dead" and reason ~= "VictimLeft" then
			pushBlocked(player, owner, reason, secs, true)
		end
		return
	end
	pushAtmRaidState(player, {
		Phase = "Blocked",
		Reason = "Hint",
		VictimName = owner.DisplayName,
		Text = string.format(RaidConfig.Text.RaidHint, owner.DisplayName, math.floor(RaidConfig.Raid.HoldSeconds)),
	})
end

function MoneyCollectorService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	MonetizationService = deps.MonetizationService
	TutorialService = deps.TutorialService
	RateLimitService = deps.RateLimitService
	BaseService = deps.BaseService
	ClanService = deps.ClanService
	GateDefenseService = deps.GateDefenseService
	AnalyticsService = deps.AnalyticsService

	-- Touch + spatial + prompt collect (own ATM, or an unowned one during the join race). Foreign ATMs never
	-- collect or raid from here: the raid is the StepRaids hold.
	local function tryCollectFromPart(player: Player, part: BasePart, fromPrompt: boolean?)
		local profile = DataService.GetProfile(player)
		if not profile then
			return
		end
		local plotId = plotIdOf(part)
		if plotId ~= nil then
			local owner = findOwnerByPlot(plotId)
			if owner and owner ~= player then
				if fromPrompt == true then
					promptHint(player, owner)
				end
				return
			end
		end
		local pending = math.floor(tonumber(profile.PendingCash) or 0)
		if pending <= 0 then
			if fromPrompt == true and NotificationService then
				local now = os.clock()
				local last = emptyCollectToastAt[player.UserId] or 0
				if now - last >= 2.5 then
					emptyCollectToastAt[player.UserId] = now
					NotificationService.Notify(
						player,
						"Nothing to collect yet — grab the dropper cash or wait for income",
						"Info",
						3
					)
				end
			end
			return
		end
		-- walking over / standing at the ATM is silent for AutoCollect owners (their loop collects every 2 s;
		-- the number counting up is the feedback) — spec §4.2. The prompt is an explicit tap: it always floats.
		MoneyCollectorService.Collect(player, fromPrompt ~= true and autoCollectFlag[player.UserId] == true)
		MoneyCollectorService.RefreshForPlayer(player)
	end

	local function attach(part: BasePart)
		if attached[part] then
			return
		end
		attached[part] = true
		part.CanTouch = true
		part.CanCollide = true
		dropLegacyBillboard(part)
		-- Mobile-friendly Collect prompt (standing on the pad + the prompt button)
		do
			local existing = part:FindFirstChild("WE_CollectPrompt")
			if existing then
				existing:Destroy()
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "WE_CollectPrompt"
			prompt.ActionText = "Collect"
			prompt.ObjectText = "ATM"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Style = Enum.ProximityPromptStyle.Default
			prompt.Parent = part
			prompt.Triggered:Connect(function(triggerPlayer: Player)
				tryCollectFromPart(triggerPlayer, part, true)
			end)
		end
		task.defer(function()
			pcall(function()
				local vas = require(script.Parent.VisualAssetService) :: any
				if vas and vas.TryAttachCollectorVisual then
					vas.TryAttachCollectorVisual(part)
				end
			end)
		end)
		part.Touched:Connect(function(hit)
			if not hit:IsA("BasePart") then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			if not character then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			local key = tostring(player.UserId) .. "|" .. part:GetFullName()
			if lastOverlap[key] then
				return
			end
			lastOverlap[key] = true
			tryCollectFromPart(player, part)
		end)
		part.TouchEnded:Connect(function(hit)
			if not hit:IsA("BasePart") then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				lastOverlap[tostring(player.UserId) .. "|" .. part:GetFullName()] = false
			end
		end)
	end

	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			attach(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			attach(inst)
		end
	end)

	local acc = 0
	local autoAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		autoAcc += dt
		if acc >= SPATIAL_INTERVAL then
			local elapsed = acc
			acc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local profile = DataService.GetProfile(player)
					if profile then
						for part in pairs(attached) do
							if part.Parent and nearCollector(hrp.Position, part) then
								tryCollectFromPart(player, part, false)
							end
						end
					end
				end
			end
			MoneyCollectorService.StepRaids(elapsed)
			MoneyCollectorService.RefreshAllBillboards()
		end
		if autoAcc >= AUTO_COLLECT_INTERVAL then
			autoAcc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local owns = hasAutoCollect(player)
				autoCollectFlag[player.UserId] = owns
				if owns then
					local profile = DataService.GetProfile(player)
					if profile and (tonumber(profile.PendingCash) or 0) > 0 then
						local ok, granted = MoneyCollectorService.Collect(player, true)
						if ok and granted > 0 then
							recordAutoIncome(player.UserId, granted)
						end
						MoneyCollectorService.RefreshForPlayer(player)
					end
				end
			end
		end
	end)

	-- Mirror the persisted shield for HUDs once the real save is in
	if DataService and DataService.OnProfileLoaded then
		DataService.OnProfileLoaded(function(player: Player, profile: any)
			local shield = raidNum(profile, "ShieldUntil")
			pcall(function()
				player:SetAttribute("WE_ShieldUntil", if shield > 0 then shield else nil)
			end)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		holds[uid] = nil
		blockedPush[uid] = nil
		lastPos[uid] = nil
		lastHrp[uid] = nil
		teleportLockUntil[uid] = nil
		recentAuto[uid] = nil
		autoCollectFlag[uid] = nil
		emptyCollectToastAt[uid] = nil
		-- holds on this player (as victim) are cancelled on the next raid tick (owner gone → VictimLeft)
	end)

	print("[WAR EMPIRE] MoneyCollectorService ready (PendingCash → touch WE_MoneyCollector; ATM raid hold 10%, shield 10 min)")
end

return MoneyCollectorService
