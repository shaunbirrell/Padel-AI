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
	-- Attack-order hits credit the owner too? Off: Attack units roam with no leash and no line of sight, so an idle
	-- owner hidden behind a wall near the bank earned ~$9,150 in 10 min in the verifier sim (HEAD: $0). Escort only.
	UnitKillCreditOnAttack = false,

	-- ── F6 · novice shield (CombatService; owner's 11 features) ──────────────────────────────────────────────────
	-- A brand-new player (tutorial not complete, profile.NoviceShieldDone false) spawns with a visible ForceField
	-- (WE_NoviceShield) and cannot be damaged or targeted (InvulnerableUntil = math.huge, WE_ShieldUntil set). It ends
	-- for good (NoviceShieldDone = true, one Text.Off toast) on the first of: drawing a weapon (EndOnDraw), the first
	-- accepted shot (EndOnFire), an accepted squad order or missile strike (EndOnSquadOrder), contesting a zone
	-- (EndOnContestedCapture), tutorial complete or skip (EndOnTutorialComplete), or MaxSeconds of shielded play.
	-- Never re-granted once it has ended. Text is device-neutral (no keys, no "tap" / "click"), at most 42 characters.
	-- Off until lane Z.
	NoviceShield = {
		Enabled = false,
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
