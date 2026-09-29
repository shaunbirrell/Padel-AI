--!strict
--[[ Server-authoritative XP / Level
	XP rebalance (spec_xp.md, lane X1):
	  - OnSpend: one-time purchase XP. EconomyService.SpendCash defers it after a successful spend; only the paying
	    reason prefixes pay (upgrade_ / research_ / vehicle_ / weapon_), and only for a save with a BuildXP block.
	  - settle: the level loop. Rewards and LEVEL_UP analytics per level; ONE merged toast, VIP offer check, rebirth
	    nudge and LevelUp push per grant (CLAUDE.md: one message at a time). A run orphaned by a leave / rejoin or a
	    rebirth while a reward waited stops before it pays anything more (v4). A grant made inside a running level
	    loop (a level's cash reward -> the Level10 achievement's XP) is quiet and pushes no LevelUp: the outer run's
	    one toast covers its levels (4.1).
	  - Push: pays the one-time backfill snapshot (quiet, one toast; ships OFF: XP-L1; season bonus only: XP-L2; only
	    in the life it was taken in: H1), then settles a bar that is over-full on the cheaper curve (one merged toast),
	    then pushes. Both steps run in a pcall on a sanitised Level / XP, so the join push always goes out; a Push that
	    lands while they still run skips them (H4: one toast per join).
	XPBalanceConfig comes only from ProfileSchema.XPBalance(), the one validated copy (H2): a broken edit turns purchase
	XP, the snapshot and the backfill off in both modules together, nothing else.
	No remote is added: nothing here is reachable from a client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local LevelConfig = require(Shared.Configs.LevelConfig)
local Types = require(Shared.Types)

-- XP rebalance config (the owner edits XPBalanceConfig by hand to turn the backfill on). Fallback: everything off (no
-- purchase XP, no backfill); kill / mission / daily XP and levels work as before.
local XP_OFF: any = {
	Enabled = false,
	Build = { Enabled = false, Reason = "build", RebirthRebuildMult = 1, ReasonPrefixes = {} },
	Backfill = { Enabled = false, Reason = "build_backfill", Toast = "★ LEVEL %d!" },
	NoBattlePassMirror = { build = true, build_backfill = true },
	BuildXP = function(_price: number): number
		return 0
	end,
	IsBuildReason = function(_reason: string?): boolean
		return false
	end,
}
-- ProfileSchema: the validated XPBalanceConfig (H2) and BuildXPPool, the backfill cap (G5). In a pcall; without it
-- everything here is OFF (and DataService, which requires it directly, could not load a profile anyway).
local schemaOk, schemaMod = pcall(function()
	return require(script.Parent.Parent.Modules.ProfileSchema) :: any
end)
local ProfileSchema: any = if schemaOk and typeof(schemaMod) == "table" then schemaMod else nil
local sharedCfg: any, cfgProblem: any = nil, "ProfileSchema did not load"
if ProfileSchema and typeof(ProfileSchema.XPBalance) == "function" then
	sharedCfg, cfgProblem = ProfileSchema.XPBalance()
end
local XPBalanceConfig: any = if sharedCfg ~= nil then sharedCfg else XP_OFF
if XPBalanceConfig == XP_OFF then
	warn("[XPService] XPBalanceConfig did not load or failed its check (" .. tostring(cfgProblem) .. "): purchase XP and the backfill are OFF")
end

local XPService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RemoteSetup: any = nil
local TerritoryService: any = nil
local _MissionService: any = nil
local MonetizationService: any = nil
local BattlePassService: any = nil
local SeasonService: any = nil
local NotificationService: any = nil
local PrestigeService: any = nil

local function pushXP(player: Player, profile: Types.PlayerProfile, unlockMessage: string?, leveledUp: boolean?)
	local remote = RemoteSetup.Get(Constants.RemoteNames.XPUpdate) :: RemoteEvent
	local hudGoal = LevelConfig.GetHudGoal(profile.Level)
	remote:FireClient(player, {
		Level = profile.Level,
		XP = profile.XP,
		XPToNext = LevelConfig.GetXPRequiredForLevel(profile.Level),
		HudGoal = hudGoal,
		UnlockMessage = unlockMessage,
		LevelUp = leveledUp == true,
	} :: Types.XPUpdatePayload)
end

function XPService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RemoteSetup = deps.RemoteSetup
	TerritoryService = deps.TerritoryService
	_MissionService = deps.MissionService
	MonetizationService = deps.MonetizationService
	BattlePassService = deps.BattlePassService
	SeasonService = deps.SeasonService
	NotificationService = deps.NotificationService
	PrestigeService = deps.PrestigeService
end

--[[ G3: the level loop. Per level crossed: the cash / gold reward and one LEVEL_UP analytics row. Once, after the
	loop and only if the player levelled: one merged "★ LEVEL n!" toast (with the unlock text of the highest level
	crossed that has one, levels a nested grant settled included: 4.1), one VIP soft-offer check and one rebirth nudge
	(all three skipped when quiet), and one pushXP with LevelUp = true (skipped when nested: the outer run pushes it).
	Adds no XP. Returns the number of levels gained. Called only through settle below.
	v4 orphaned run: a level's cash reward can wait on the join-time game-pass check (EconomyService.AddCash reads the
	pass cache). That wait is taken once, up front (GetCashMult reads the same multiplier and fills the cache), before
	any level changes; then every iteration first checks that the run still owns the save: the same profile table
	(a same-server rejoin loads a new one, and AddCash / AddGold look the profile up by UserId, so an orphaned run
	would pay the new session for levels it settles itself) and the same life (a rebirth in the wait must not get the
	old life's rewards). An orphaned run stops there and returns 0: no reward, toast or push. ]]
local function settleLevels(player: Player, profile: Types.PlayerProfile, reason: string?, quiet: boolean, nested: boolean): number
	local life = profile.Prestige
	if profile.Level < LevelConfig.MaxLevel and profile.XP >= LevelConfig.GetXPRequiredForLevel(profile.Level)
		and EconomyService and EconomyService.GetCashMult
	then
		pcall(EconomyService.GetCashMult, player, "level_up")
	end
	local gained = 0
	local unlockMsg: string? = nil
	local fromLevel = profile.Level
	while profile.Level < LevelConfig.MaxLevel do
		if DataService.GetProfile(player) ~= profile or profile.Prestige ~= life then
			return 0 -- orphaned (left / rejoined, or rebirthed) while a reward waited: stop, pay nothing more
		end
		local need = LevelConfig.GetXPRequiredForLevel(profile.Level)
		if profile.XP < need then
			break
		end
		profile.XP -= need
		profile.Level += 1
		gained += 1
		local reward = LevelConfig.GetLevelUpReward(profile.Level)
		if reward.Cash > 0 then
			EconomyService.AddCash(player, reward.Cash, "level_up")
		end
		if reward.Gold > 0 then
			EconomyService.AddGold(player, reward.Gold, "level_up")
		end
		if AnalyticsService then
			AnalyticsService.Log("LEVEL_UP", player.UserId, { level = profile.Level, reason = reason })
		end
	end
	if gained <= 0 then
		return 0
	end
	-- the unlock text of the highest level this run ends above that has one (a nested grant's levels included)
	for lv = profile.Level, fromLevel + 1, -1 do
		unlockMsg = LevelConfig.GetUnlockMessage(lv)
		if unlockMsg then
			break
		end
	end
	if not quiet then
		-- v37: high-contrast level-up celebration toast (client also plays SFX on LevelUp flag); one per grant
		if NotificationService and NotificationService.Notify then
			local celeb = string.format("★ LEVEL %d!", profile.Level)
			if unlockMsg then
				celeb = celeb .. " — " .. unlockMsg
			end
			NotificationService.Notify(player, celeb, "Success", 5)
		end
		-- v35: mid-game VIP soft offer (level≥10)
		if MonetizationService and MonetizationService.TrySoftOfferVIP then
			pcall(function()
				MonetizationService.TrySoftOfferVIP(player, "level")
			end)
		end
		-- v38: soft rebirth CTA when near MinLevelToPrestige
		if PrestigeService and PrestigeService.MaybeNearPrestigeToast then
			pcall(function()
				PrestigeService.MaybeNearPrestigeToast(player)
			end)
		end
	end
	-- one push so the HUD goal / level chip refresh immediately (the client's LevelUp chip pop has no text); a nested
	-- run leaves it to the outer run (one chip pop and one level-up sound per grant)
	if not nested then
		pushXP(player, profile, unlockMsg, true)
	end
	return gained
end

--[[ 4.1: the threads running a level loop, with their depth. A grant made inside a running loop is quiet whatever it
	asked for: EconomyService.AddCash(level reward) -> MissionService.TrackProgress -> CheckAchievements -> GrantAchievement
	-> XPService.AddXP(100, "achievement") runs in the same thread while the loop waits for AddCash to return, and its
	own settle would otherwise use up the rest of a quiet backfill (or of an over-full bar) with a second "★ LEVEL n!"
	toast, VIP check and rebirth nudge. Nested: it still adds the levels and pays their rewards, but shows nothing and
	pushes no LevelUp; the outer run's one toast (or the one Backfill.Toast) names the final level. Keyed by the running
	thread (weak keys), so a grant from another thread (a kill while the join routine waits on the pass check) keeps its
	own toast; restored after a pcall, so a throw can never leave a thread marked. ]]
local settlingThreads: { [thread]: number? } = setmetatable({}, { __mode = "k" }) :: any

local function settle(player: Player, profile: Types.PlayerProfile, reason: string?, quiet: boolean): number
	local me = coroutine.running()
	local depth = settlingThreads[me] or 0
	settlingThreads[me] = depth + 1
	local ok, gained = pcall(settleLevels, player, profile, reason, quiet or depth > 0, depth > 0)
	settlingThreads[me] = if depth > 0 then depth else nil
	if not ok then
		error(gained, 0)
	end
	return gained
end

--[[ Backfill (XPBalanceConfig.Backfill; ships OFF, XP-L1): pay, once, the snapshot ProfileSchema.Migrate stored for
	a save that predates the rebalance (BuildXP.Owed; purchases after the snapshot were paid live by OnSpend, so they
	are not in it). H1: only in the life it was taken in (BuildXP.AtPrestige == Prestige). A snapshot from an earlier
	life (a rebirth since, on a new or an old server) or with no valid stamp is dropped: Owed = 0, nothing paid, as if
	the switch had shipped ON (the grant would have been reset by the rebirth). Capped again at the catalogue pool,
	computed with the bare formula (G5 holds whatever the purchase-XP switches say). Owed is zeroed and the save
	marked dirty BEFORE the grant, so a throw or a second Push cannot pay the snapshot again. Quiet: no per-level
	toasts; one Backfill.Toast if the level rose. XP-L2: AddXP gives this reason the season bonus only (no territory,
	no DoubleXP), so nothing here waits on a game-pass check. ]]
local function grantBackfill(player: Player, profile: Types.PlayerProfile): number
	local bx = (profile :: any).BuildXP
	if not (XPBalanceConfig.Enabled and XPBalanceConfig.Backfill.Enabled) or typeof(bx) ~= "table" then
		return 0
	end
	local owed = tonumber(bx.Owed) or 0
	if owed ~= owed or owed == math.huge then
		owed = 0
	end
	owed = math.floor(owed)
	if owed <= 0 then
		return 0
	end
	local life = tonumber(profile.Prestige) or 0 -- ProfileSchema's nonNegInt: junk -> 0, else a whole number >= 0
	if life ~= life or life == math.huge or life == -math.huge then
		life = 0
	end
	life = math.clamp(math.floor(life), 0, 1e15)
	if bx.AtPrestige ~= life then
		bx.Owed = 0 -- H1: a snapshot from another life (or unstamped) is dropped unpaid
		DataService.MarkDirty(player)
		return 0
	end
	local pool = if ProfileSchema and ProfileSchema.BuildXPPool then ProfileSchema.BuildXPPool() else nil
	if typeof(pool) ~= "number" then
		return 0 -- the cap cannot be computed (a config did not load): keep Owed, pay it on a later join
	end
	owed = math.min(owed, pool)
	bx.Owed = 0
	DataService.MarkDirty(player)
	local before = profile.Level
	XPService.AddXP(player, owed, XPBalanceConfig.Backfill.Reason, { Quiet = true })
	if profile.Level > before and NotificationService and NotificationService.Notify then
		NotificationService.Notify(player, string.format(XPBalanceConfig.Backfill.Toast, profile.Level), "Success", 5)
	end
	return owed -- base XP granted (before the season bonus)
end

-- Level / XP read from a save are plain numbers from here on: a corrupt value (a string, NaN, inf) must never throw
-- (or loop) inside the join routine. XP: not a finite number -> 0. Level: not a number -> 1, else a whole number in
-- 1..MaxLevel (SetLevel's clamp). Returns true when something was repaired.
local function sanitizeLevelXP(profile: any): boolean
	local changed = false
	local xp = tonumber(profile.XP)
	if xp == nil or xp ~= xp or xp == math.huge or xp == -math.huge then
		xp = 0
	end
	if profile.XP ~= xp then
		profile.XP = xp
		changed = true
	end
	local lv = tonumber(profile.Level)
	if lv == nil or lv ~= lv then
		lv = 1
	end
	lv = math.clamp(math.floor(lv :: number), 1, LevelConfig.MaxLevel)
	if profile.Level ~= lv then
		profile.Level = lv
		changed = true
	end
	return changed
end

-- H4: Players whose join steps are running. A Push that lands meanwhile (CharacterAdded, the 12 s loop, a rebirth)
-- skips steps 1 and 2: the running thread settles every level itself, so a join shows one toast. Keyed by the Player
-- object (weak), so a thread left over from an earlier session can never block a rejoin.
local joinStepsRunning: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Push steps 1 and 2. Each runs in a pcall: Owed is zeroed before the grant, so a throw loses at most that grant
-- and never pays it again, and a throw in either step never stops the HUD push. The flag is cleared after both
-- pcalls (they cannot throw past it).
local function joinLevelSteps(player: Player, profile: Types.PlayerProfile)
	if joinStepsRunning[player] then
		return
	end
	joinStepsRunning[player] = true
	-- 1. one-time backfill (no-op unless the switch is on and the save still has BuildXP.Owed > 0)
	local okGrant, grantErr = pcall(grantBackfill, player, profile)
	if not okGrant then
		warn("[XPService] backfill grant failed (Owed already zeroed):", grantErr)
	end
	-- 2. a veteran whose saved XP already covers the cheaper XP-to-next levels up here, with one merged toast
	local okSettle, gained = pcall(settle, player, profile, "curve_settle", false)
	if not okSettle then
		warn("[XPService] curve settle failed:", gained)
	elseif gained > 0 then
		DataService.MarkDirty(player)
	end
	joinStepsRunning[player] = nil
end

function XPService.Push(player: Player)
	local profile = DataService.GetProfile(player)
	if profile then
		if sanitizeLevelXP(profile) then
			DataService.MarkDirty(player)
		end
		-- Steps 1 and 2 run in their own thread. The XP they add never waits on anything (XP-L2), but each level
		-- they cross pays its cash reward through EconomyService.AddCash, which reads the game-pass cache and can
		-- wait for it on a join; the join routine (BaseService.OnProfileLoaded) must not wait with it. When nothing
		-- waits, the thread has finished before task.spawn returns, so the order below is unchanged.
		task.spawn(joinLevelSteps, player, profile)
		-- 3. the normal HUD refresh (always runs)
		pushXP(player, profile)
	end
end

--[[ One-time purchase XP (deferred by EconomyService.SpendCash after a successful spend; the item is already
	written). Only the paying reasons pay, and only for a save with a BuildXP block (every new save, and every old save
	once it has been snapshotted, whatever the backfill switch says: XP-L1). A save with no block was loaded while
	purchase XP was off: what it buys now is paid nothing here and counted, once, by its snapshot on its next load with
	purchase XP on (at Prestige > 0 base levels only). A save WITH a block buying while purchase XP is off: lost. ]]
function XPService.OnSpend(player: Player, amount: number, reason: string?)
	if not XPBalanceConfig.IsBuildReason(reason) then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile or typeof((profile :: any).BuildXP) ~= "table" then
		return
	end
	local base = XPBalanceConfig.BuildXP(amount)
	if (tonumber(profile.Prestige) or 0) > 0 and string.sub(reason :: string, 1, 8) == "upgrade_" then
		base = math.floor(base * XPBalanceConfig.Build.RebirthRebuildMult)
	end
	if base > 0 then
		XPService.AddXP(player, base, XPBalanceConfig.Build.Reason)
	end
end

function XPService.AddXP(player: Player, amount: number, reason: string?, opts: { Quiet: boolean? }?): boolean
	local quiet = opts ~= nil and opts.Quiet == true
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	if SeasonService and SeasonService.GetXPMult and reason ~= "admin" and reason ~= "battlepass" and reason ~= "daily" then
		amount = math.max(1, math.floor(amount * SeasonService.GetXPMult()))
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end

	if profile.Level >= LevelConfig.MaxLevel then
		return false
	end

	local reasonKey = reason or ""
	-- XP-L2: the one-time backfill takes the season bonus only: no territory bonus (like achievements) and no DoubleXP
	-- (MonetizationConfig.XPMultExemptReasons lists build_backfill), so the join routine never waits on a pass check.
	if TerritoryService and TerritoryService.GetXPMult and reason ~= "achievement" and reasonKey ~= XPBalanceConfig.Backfill.Reason then
		amount = math.max(1, math.floor(amount * TerritoryService.GetXPMult(player)))
	end

	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local xpExempt = MonetizationConfig.XPMultExemptReasons
	if MonetizationService and MonetizationService.GetXPMultiplier and not (xpExempt and xpExempt[reasonKey]) then
		amount = math.max(1, math.floor(amount * MonetizationService.GetXPMultiplier(player)))
	end

	profile.XP += amount
	-- G3: one merged toast per grant (rewards + analytics still per level)
	settle(player, profile, reason, quiet)

	DataService.MarkDirty(player)
	pushXP(player, profile, nil)
	if BattlePassService and BattlePassService.AddXP and reason ~= "battlepass"
		and not XPBalanceConfig.NoBattlePassMirror[reasonKey]
		and reasonKey ~= "income" -- claude-bud JOB 10: BalanceConfig income XP never feeds the battle pass
	then
		-- Mirror a portion of gameplay XP into the battle pass track (never the one-time build / backfill XP)
		BattlePassService.AddXP(player, amount, reason)
	end
	return true
end

function XPService.SetLevel(player: Player, level: number)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.Level = math.clamp(math.floor(level), 1, LevelConfig.MaxLevel)
	profile.XP = 0
	DataService.MarkDirty(player)
	pushXP(player, profile)
end

function XPService.GetXPToNext(player: Player): number
	local profile = DataService.GetProfile(player)
	if not profile then
		return 0
	end
	return LevelConfig.GetXPRequiredForLevel(profile.Level)
end

return XPService
