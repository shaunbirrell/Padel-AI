--!strict
--[[
	claude-bud JOB 37 (2026-09-30): GUARDS at the real road checkpoints (WorldKits Detail.Checkpoint; CheckpointGuardService).
	  * A group of guards (NpcType, CombatConfig.NPCTypes.CheckpointGuard) wakes at a detailed checkpoint when a player the
	    switch is live for comes within WakeStuds, on the booth's posts (WE_GuardPost1..5; the 5th is the tower deck, a
	    Post guard). They sleep again (despawn, no NPC slot) when no live player is within SleepStuds.
	  * They fight through the SAME NPC path as the bank guards: CombatService.SpawnNPC (GroupId / Home / Leash), CombatNPC
	    target pick + line of sight + hit-chance rolls, real shots; the PvP / protection rules and damage caps apply. They
	    target only live players (SpawnNPC TargetFilter); players shoot them through the normal weapon path.
	  * Each kill pays the NPC type's own reward (KillCash / KillXP, paid by CombatService like every NPC).
	  * The LAST guard down: "Checkpoint cleared" for every live player who hurt a guard in the last AssistSeconds (or
	    killed one, his army's kills included): Cleared.XP + max(CashFloor, CashMinutes x passive $/min) capped at
	    CashCap, once per checkpoint per player per cycle and never again within PlayerCooldownSeconds. Private
	    servers pay PrivateMult (OpsRewards' rule). Mission objective "Checkpoint" +1.
	  * The group respawns RespawnSeconds after the last guard died, only while a live player is near and never on top of
	    one (SpawnClearStuds from every player).
	Kill switch: Live (RetentionConfig.Live rule: OwnerFirst = UserId 470626172 + Studio). Off / not live = no guards,
	no rewards, no map / mission changes (the checkpoint is decor).
]]

local CheckpointGuardConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) until Code Bot sets false = everyone
	},
	NpcType = "CheckpointGuard",
	-- the NPC type's per-kill reward (CombatConfig.NPCTypes.CheckpointGuard reads these; CombatService pays them)
	KillCash = 150,
	KillXP = 45,
	Cleared = {
		XP = 250,
		CashFloor = 2500,
		CashMinutes = 2, -- minutes of the player's passive income
		CashCap = 25000,
		PrivateMult = 0.5, -- private servers (game.PrivateServerOwnerId ~= 0), like OpsRewards
	},
	AssistSeconds = 30,
	PlayerCooldownSeconds = 300,
	RespawnSeconds = 180,
	WakeStuds = 220,
	SleepStuds = 340,
	SiteRadius = 30,
	LeashExtra = 20, -- leash = SiteRadius + LeashExtra from each guard's post
	SpawnClearStuds = 6,
	CheckSeconds = 2,
	MaxGuards = 5,
	MapLabel = "CHECKPOINT",
}

local RetentionConfig = require(script.Parent.RetentionConfig)

function CheckpointGuardConfig.LiveFor(userId: any): boolean
	return RetentionConfig.Live(CheckpointGuardConfig.Live, userId)
end

-- live for every player (the daily mission offer is global, so it only lists the checkpoint objective then)
function CheckpointGuardConfig.LiveForAll(): boolean
	local L = CheckpointGuardConfig.Live
	return L.Enabled == true and L.OwnerFirst ~= true
end

-- the cleared bonus cash for a passive income of perMin $/min (private = a private server)
function CheckpointGuardConfig.ClearedCash(perMin: number, private: boolean): number
	local C = CheckpointGuardConfig.Cleared
	local rate = if typeof(perMin) == "number" and perMin == perMin and perMin > 0 and perMin < 1e12 then perMin else 0
	local cash = math.min(C.CashCap, math.max(C.CashFloor, math.floor(C.CashMinutes * rate)))
	return if private then math.floor(cash * C.PrivateMult) else cash
end

return CheckpointGuardConfig
