--!strict
--[[
	Combat fairness (mobile plan P0-7, P0-6 server part, P1-2, P1-4). About 80 % of players are on phones, so the
	server never trusts a client-named target, keeps brand-new players out of raids, makes NPCs need line of sight
	and miss sometimes, and makes the default squad order (FOLLOW) protect the player. Server-side numbers only.
]]

local CombatFairnessConfig = {
	-- ── P0-7 · claimed target (CombatService.RequestFire) ─────────────────────────────────────────────────────
	-- When the server's own fire ray misses every player / NPC / gate, the TargetUserId / TargetNpcId the client sent
	-- may still take the hit (lag tolerance: the target moved after the phone's ray hit it), but only if the target
	-- is alive, in front of the fire ray, within weapon range, its torso lies within MissTolerance studs sideways of
	-- the ray, and a server ray from the validated origin to that torso hits the target before any wall, terrain,
	-- vehicle or other player. Fire rate and ammo are spent before this check, exactly as for any shot.
	MissTolerance = 5, -- studs sideways from the fire ray to the target torso (v70: 4 → 5 so phone players on ~250 ms cellular still land 10/12 aim points on a walking target; line of sight is still required)
	ClaimLosPastTorsoStuds = 2, -- the line-of-sight ray runs this far past the torso centre so it can touch the target
	-- The fire ray hit only scenery (usually the ground behind the target): the claim is still checked as above, if
	-- the torso is no further along the ray than that hit + ClaimBeyondHitStuds. false = only rays that hit nothing.
	ClaimAfterSceneryHit = true,
	ClaimBeyondHitStuds = 3,
	RefusalLogSeconds = 10, -- at most one refusal log line per shooter per this many seconds (the rest are counted)

	-- ── P0-6 · new-thief protection (MoneyCollectorService.CanRaid) ───────────────────────────────────────────
	-- Mirrors the victim's new-player protection: a thief who has not finished (or skipped) the tutorial, or who
	-- joined less than ThiefProtectMinutes ago, cannot start or finish an ATM raid. Texts are device-neutral.
	ThiefProtectEnabled = true,
	ThiefProtectMinutes = 10, -- since profile.FirstJoinUnix
	ThiefRequireTutorialDone = true,
	ThiefProtectInStudio = false, -- like RaidConfig.Raid.ProtectNewPlayersInStudio (Studio makes fresh profiles)
	ThiefTutorialText = "Finish or skip the tutorial to start raiding",
	ThiefNewText = "New player — raids unlock in %s", -- %s = m:ss

	-- ── P1-2 · NPC shots (CombatNPC.Think) ───────────────────────────────────────────────────────────────────
	NpcRequireLos = true, -- a ray from the NPC's eyes to the target must not hit anything else first
	NpcLosRespectCanCollide = true, -- non-collidable decor does not block (same rule as the gate guards)
	NpcIgnoreTargetVehicle = true, -- the vehicle the target SITS in never blocks (no free shield until vehicle HP, M4)
	NpcEyeHeight = 1.5, -- studs above the NPC root the shot starts from
	NpcNearStuds = 20, -- at or inside this distance the hit chance is NpcNearHitChance
	NpcNearHitChance = 0.75,
	NpcFarHitChance = 0.30, -- at the NPC type's max Range; linear in between
	NpcFastTargetSpeed = 10, -- studs/s (horizontal, sampled on the server); faster targets are harder to hit
	NpcFastTargetPenalty = 0.15, -- subtracted from the hit chance against fast targets
	NpcMinHitChance = 0.05,
	NpcReactionSeconds = 0.5, -- no shot until the NPC has seen its (new) target this long
	NpcReactionOnLosRegain = true, -- losing sight restarts the reaction delay (peeking from cover is fair)
	NpcChaseWithoutLos = true, -- an NPC in range but without a clear shot keeps closing in

	-- ── P1-4 · squad escort (SquadOrdersService, order "Follow") ─────────────────────────────────────────────
	EscortEngageRadius = 55, -- FOLLOW units shoot hostiles within this distance of their player
	EscortLeash = 20, -- ...while staying within this distance of the player
	EscortRequireLos = true, -- escort shots need line of sight (friendly units and the owner never block)
	UnitKillCashShare = 0.5, -- a kill landed by a squad unit pays the owner this share of the normal kill cash
	UnitKillXPShare = 1, -- ...and this share of the normal kill XP (kills and mission progress count in full)
	-- Attack-order hits credit the owner too? Off: Attack units roam with no leash, so an idle owner hidden behind a
	-- wall near the bank earned ~$9,150 in 10 min in the verifier sim (HEAD: $0; ATTACK shots then went through
	-- walls). squadfair: they need a line of sight now, but the missing leash still makes an idle farm, so escort only.
	UnitKillCreditOnAttack = false,

	-- ── squadfair · every squad unit shot (orders ATTACK and FOLLOW escort; SquadOrdersService.unitShoot) ─────────
	-- A unit shoots like an NPC: it needs a line of sight from its eyes (NpcEyeHeight) to the target (its squad, the
	-- owner and the target never block; the escort's ray) and rolls a hit chance that falls with distance. A miss
	-- spends the fire cooldown like a hit. A hit goes through CombatService's NPC damage path (ApplyUnitHit), so squad
	-- fire provokes a Passive / grouped NPC (bank guards, Ops garrisons) like a player's shot. Units only ever shoot
	-- CombatService NPCs: never a player (novice shield, clan allies), never a statue (a WE_NPC model with no NPCId).
	UnitAttackRequireLos = true, -- ATTACK shots need line of sight too (FOLLOW escort shots: EscortRequireLos)
	-- Another NPC's body never blocks a squad ray (walls, terrain, vehicles and other players still do): two hostiles
	-- standing close hid each other from the whole squad, which then stopped shooting and pressed into them.
	UnitLosIgnoreNPCBodies = true,
	-- The FOLLOW escort (the default order) never opens fire on a calm Passive NPC (bank guards, Ops garrisons before they
	-- are provoked), so walking past a quiet site with a squad never starts a fight. Once the group is provoked (your shot,
	-- a breach, ProvokeRadius, an ATTACK order's hit) the escort defends you. false = the escort shoots calm guards too,
	-- and its first hit provokes the whole group (ASSUMPTIONS SQF-11; reversible here).
	EscortIgnoreCalm = true,
	-- A unit whose nearest hostile is walled off shoots the nearest hostile within its fire range (ATTACK: 85 % of
	-- AttackRange; FOLLOW escort: AttackRange) it CAN see: a check casts at most this many rays (the nearest hostile
	-- first, then the next nearest), and only while the nearest is blocked.
	UnitLosRaysPerCheck = 3,
	-- With nothing in sight in range, an ATTACK unit keeps closing in (like NpcChaseWithoutLos) for at most
	-- UnitBlockedChaseSeconds; so does a unit walking at a hostile out of range that gets no UnitChaseProgressStuds
	-- nearer in that time (a wall in its way: MoveTo walks straight, there is no pathfinding). The blocked timer runs
	-- only while something is in range to check: it starts over when nothing is (the unit is walking in) and when
	-- another hostile out of range becomes its target (a swap between hostiles in range keeps it running). Then it
	-- gives up THAT FIGHT: the hostiles within UnitGiveUpScopeStuds of where the one it chased stood (the last two such
	-- spots are kept). It still attacks any hostile elsewhere in reach (another group, or the walled one once it walks
	-- out of that circle); with only a given-up fight in reach it walks its owner's trail like FOLLOW, still shooting
	-- any hostile it can see in range, so it never walks back to the same wall. A shot into a given-up fight, or the
	-- order given again (tap ATTACK again), ends the give-ups; a given-up fight with nobody left in it is forgotten.
	-- The give-up does not restart the blocked timer: after it, a hostile elsewhere beyond range gets a fresh approach,
	-- but one inside range that it cannot see is given up at once, with no approach, until the timer starts over (so
	-- three or more walled spots never take turns; only two are remembered).
	-- 0 = one give-up covers every hostile until a shot or a new order (the round-3 rule). A blocked line is
	-- re-checked at most once per shot cooldown
	-- (1 / OrdersConfig.AttackFireRate).
	UnitChaseWithoutLos = true,
	UnitBlockedChaseSeconds = 6,
	UnitChaseProgressStuds = 2,
	UnitGiveUpScopeStuds = 30,
	-- The same order again within this many seconds of the last one (a double tap, or a spammed button) changes
	-- nothing: the blocked re-check wait, the chase timers and a give-up all stay. Later, the same order again is a
	-- fresh order (a squad that gave up tries once more).
	UnitRepeatOrderGraceSeconds = 2,
	-- Hit chance: UnitNearHitChance at or inside UnitNearStuds, falling linearly to UnitFarHitChance at
	-- OrdersConfig.AttackRange, never below UnitMinHitChance and never above UnitMaxHitChance (the code clamps to it).
	-- ATTACK units fire only inside 85 % of AttackRange, as before; the FOLLOW escort fires out to AttackRange. Squad
	-- values, higher than the NPC ones (Npc* above): units used to hit every shot, and the FOLLOW escort is the default
	-- protection on live. 0.98 / 0.96 is the middle option of the owner's decision A/B (ASSUMPTIONS SQF-5 / SQF-18;
	-- 0.96 / 0.92 is the lowest that meets the SQF-17 lines, 0.99 / 0.99 the closest to today). Never 1: a squad shot
	-- can always miss (CLAUDE.md: a hit chance must exist); keep 0 < Far <= Near <= Max < 1 (a BuyPathStatic pin
	-- parses these numbers, so a retune inside those bounds is a config-only change).
	UnitNearStuds = 35,
	UnitNearHitChance = 0.98,
	UnitFarHitChance = 0.96,
	UnitMinHitChance = 0.05,
	UnitMaxHitChance = 0.98,
	-- Provoke by proxy: a squad hit on a grouped or stance NPC (bank guards, Ops garrisons: any hit on one provokes its
	-- group and keeps it fighting) is refused unless the owner's living character stands within that NPC type's
	-- AggroRange of it (or within UnitProvokeOwnerStuds when that is above 0), calm or already provoked. The squad's
	-- target pick (ATTACK and FOLLOW) skips such NPCs while the owner is out of reach. So a squad never opens a fight
	-- its owner is not part of, and stops as soon as the owner leaves (the group then calms as usual). Plain Aggressive
	-- NPCs (every live camp and bank NPC while Jobs are off) are not affected. The group's targets are not changed:
	-- they take the nearest player, as before.
	UnitProvokeNeedsOwner = true,
	UnitProvokeOwnerStuds = 0,
	UnitHitErrorLogSeconds = 30, -- a failing CombatService.ApplyUnitHit is logged at most once per this many seconds

	-- ── F6 · novice shield (CombatService; owner's 11 features) ──────────────────────────────────────────────────
	-- A brand-new player (tutorial not complete, profile.NoviceShieldDone false) spawns with a visible ForceField
	-- (WE_NoviceShield) and cannot be damaged or targeted (InvulnerableUntil = math.huge, WE_ShieldUntil set). It ends
	-- for good (NoviceShieldDone = true, one Text.Off toast) on the first of: drawing a weapon (EndOnDraw), the first
	-- accepted shot (EndOnFire), an accepted squad order or missile strike (EndOnSquadOrder), contesting a zone
	-- (EndOnContestedCapture), tutorial complete or skip (EndOnTutorialComplete), or MaxSeconds of shielded play.
	-- Never re-granted once it has ended. Text is device-neutral (no keys, no "tap" / "click"), at most 42 characters.
	-- On since lane Z (reversible).
	NoviceShield = {
		Enabled = true,
		MaxSeconds = 900,
		EndOnDraw = true,
		EndOnFire = true,
		EndOnSquadOrder = true,
		EndOnTutorialComplete = true,
		EndOnContestedCapture = true,
		Text = {
			On = "Shield on until you draw a weapon",
			Off = "Shield off. You can be attacked.",
		},
	},
}

return CombatFairnessConfig
