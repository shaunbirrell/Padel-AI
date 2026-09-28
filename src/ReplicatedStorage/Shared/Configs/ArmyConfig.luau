--!strict
--[[
	ArmyConfig — the field army (SquadOrdersService units). SPEC-ARMY-FINAL §10.1. Config-first; server and client read it.

	████ army lane A0 blocks: Rollout · Escort · ShotFx · Text (+ the LiveFor / IsLive helper) ████
	Other army lanes add their own self-contained blocks to this same table (lane FIX: Follow / Recover / Gate; lane A:
	Home / Guard / Hold / Path / Ui; lane C: March). Keep each block self-contained; this file requires only AdminConfig.

	ROLLOUT (owner 2026-09-28, integrator decision): each part is "off" | "owner" | "all".
	  "off"   = today's game (e506c9c) for everyone;
	  "owner" = only the owner's playtest account (AdminConfig.IsPlaytestOwner, UserId 470626172, the same gate as
	            AircraftWeaponConfig.LiveFor); everyone else keeps today's game;
	  "all"   = everyone.
	  Any other value counts as "off" (fail closed). The SERVER decides (ArmyConfig.LiveFor); nothing is read from a client.
	  Parts: Escort (lane A0: the bank fix, defend-when-targeted, focus fire, side-step, visible unit shots), Army (lane A:
	  guard line, follow outside, paths), March (lane C: ATTACK takes checkpoints).

	ESCORT (FOLLOW, lane A0, "I went to the bank and they didn't shoot"): for a live owner the escort's first targets are
	  the NPCs aiming at him within DefendRadius of him (CombatService.NPCsAimingAt / NPCThreat) and the NPCs he hit
	  himself in the last FocusFireSeconds within DefendRadius (focus fire; CombatService stamps the player's own hits);
	  then today's escort targets (CombatFairnessConfig.EscortEngageRadius 55 of him). While such a target exists the
	  escort leash is DefendLeash (today CombatFairnessConfig.EscortLeash 20), so units step out for a sight line. Every
	  shot keeps squadfair's rules: line of sight, the unit hit curve, unitMayHit, no kill pay on ATTACK.
	  Side-step: after SideStepAfterBlocked shot checks in a row with the target in range but out of sight, a unit
	  probes SideStepStuds to each side (at most 4 rays per probe, at most one probe per SideStepMinGap s, only while
	  blocked) and walks to the first spot that sees the target and stays inside its leash, for at most SideStepHoldSeconds.
	  NpcSnapshot is NOT a Rollout part: every army's hostile scan reads one CombatService NPC list per think pass
	  (CombatService.LiveNPCSnapshot) instead of a CollectionService:GetTagged("WE_NPC") per unit; the picks are the same
	  (a2 differential runs). false = the per-unit GetTagged scan of e506c9c.

	SHOTFX (lane A0): a unit shot (hit or miss, every order) of a live owner's army may send one WeaponFx bullet
	  (UnreliableRemoteEvent, CombatFx) with the NPC rifle look (S = 0, W = "NPC": the rig's aim pose plays too).
	  Sampled to one event per army per PerArmyMinGap s, then a per-army shooter bucket, then an army bucket of
	  PerRecipientHz (burst PerRecipientBurst) per recipient, on top of CombatFx's own recipient bucket. A missed shot's
	  tracer lands MissOffsetStuds beside the target (no random numbers: the hit roll sequence is untouched).

	TEXT: device-neutral army strings (no key names, no "click" / "tap"); lanes A and C show them.
]]

local AdminConfig = require(script.Parent.AdminConfig)

local ArmyConfig = {
	-- ── Rollout (lane A0 builds the gate; lanes A / C read it) ─────────────────────────────────────────────────────
	Rollout = {
		Escort = "owner", -- lane A0: bank fix / defend / focus fire / side-step / visible unit shots
		Army = "owner", -- lane A: guard line, follow outside, movement
		March = "owner", -- lane C: ATTACK takes checkpoints
	},

	-- ── Escort (FOLLOW; SPEC-ARMY-FINAL §7.1 / §7.2) ──────────────────────────────────────────────────────────────
	Escort = {
		DefendRadius = 90, -- studs from the owner: NPCs aiming at him / hit by him this close are escort targets first
		DefendLeash = 28, -- escort leash (studs from the owner) while such a target exists (else EscortLeash 20)
		FocusFireSeconds = 6, -- an NPC the owner hit himself within this many seconds is a focus-fire target
		SideStep = true,
		SideStepAfterBlocked = 2, -- shot checks in a row with the target in range but out of sight
		SideStepStuds = { 4, 8 }, -- lateral probe distances (one ring per probe, alternating)
		SideStepMinGap = 1.5, -- seconds between two probes of one unit (<= 4 rays per probe)
		SideStepHoldSeconds = 3, -- a side-step walk ends after this (reached, a shot, or given up)
		NpcSnapshot = true, -- every army (not a Rollout part): one NPC list per think pass, no GetTagged per unit
	},

	-- ── ShotFx (every order; SPEC-ARMY-FINAL §7.1 "Visible shots") ────────────────────────────────────────────────
	ShotFx = {
		Enabled = true,
		PerArmyMinGap = 0.25, -- at most one WeaponFx event per army per this many seconds
		PerRecipientHz = 6, -- army bucket per recipient (events / s), on top of CombatFeelConfig.Fx.PerRecipientHz
		PerRecipientBurst = 2, -- 2 per think pass (armies fire together at 2.5 Hz): <= 6 in any 1 s, 5 / s steady
		MissOffsetStuds = 3, -- a miss tracer lands this far beside the target (alternating sides)
	},

	-- ── Text (device-neutral; no key names, no "click" / "tap") ──────────────────────────────────────────────────
	Text = {
		Status = {
			Guard = "GUARDING BASE",
			Follow = "FOLLOWING",
			Hold = "HOLDING",
			HoldPost = "HOLDING POST",
			March = "TO %s",
			Fight = "FIGHTING",
			Capture = "TAKING POST",
			Wait = "WAITING FOR YOU",
			Return = "RETURNING",
			HoldLine = "AT THE CENTRE",
			Clear = "FIGHTING",
		},
		Tile = { Guard = "GUARD", Follow = "FOLLOW", Attack = "ATTACK", Hold = "HOLD", Return = "RETURN" },
		MovingOut = "Army moving out",
		Waiting = "Army waiting for you",
		TakeCentre = "Take the Centre!",
		Taken = "%s taken",
		UnderAttack = "%s under attack",
		NoBase = "No base to guard",
	},
}

-- army lane A0: the rollout value of one part, normalised ("off" for a missing part or any other value: fail closed)
function ArmyConfig.RolloutOf(part: string): string
	local r = (ArmyConfig :: any).Rollout
	local v = if typeof(r) == "table" then r[part] else nil
	if v == "owner" or v == "all" then
		return v
	end
	return "off"
end

-- army lane A0: is this rollout part live for this UserId? "all" = everyone; "owner" = the owner's playtest account only
-- (AdminConfig.IsPlaytestOwner, as AircraftWeaponConfig.LiveFor); "off" = nobody. Pure; the server evaluates it.
function ArmyConfig.LiveFor(part: string, userId: any): boolean
	local v = ArmyConfig.RolloutOf(part)
	if v == "all" then
		return true
	end
	if v == "owner" then
		return AdminConfig.IsPlaytestOwner(userId) == true
	end
	return false
end

-- army lane A0: LiveFor for a Player (false for anything that is not a Player)
function ArmyConfig.IsLive(part: string, player: any): boolean
	if typeof(player) ~= "Instance" or not (player :: Instance):IsA("Player") then
		return false
	end
	return ArmyConfig.LiveFor(part, (player :: Player).UserId)
end

return ArmyConfig
