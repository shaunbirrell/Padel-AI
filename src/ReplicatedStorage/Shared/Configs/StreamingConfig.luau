--!strict
--[[
	StreamingConfig (streaming2, lane S1): tunables for the code that has to behave under instance streaming.

	THE SWITCH IS NOT HERE. Workspace.StreamingEnabled, the two radii and the integrity mode live in
	default.project.json (Workspace $properties): the engine does not let a script set StreamingEnabled, so the project
	file is the flag. Every reader of this config is a no-op while Workspace.StreamingEnabled is false
	(StreamPrefetch.Enabled()), so it ships before the switch and a rollback of the switch restores the old behaviour.
]]

local StreamingConfig = {
	-- Player:RequestStreamAroundAsync timeout (seconds) before a cross-map move (StreamPrefetch.PivotTo). The move
	-- happens when the request returns or gives up, so a slow phone waits at most this long.
	PrefetchTimeout = 5,
	-- A move shorter than this needs no pre-fetch: the client always holds StreamingMinRadius round its character.
	-- Keep it <= Workspace.StreamingMinRadius in default.project.json (64).
	NearStuds = 64,
	-- One check this long after a pre-fetched move: when the character is back where it started (the spawn or its
	-- physics undid the pivot), it is moved once more. Replaces the stacked 0.35 s / 1.0 s blind re-applies.
	SettleCheckSeconds = 0.6,
	-- The first spawn of a session is random (the save loads after it). The own PlayerSpawn is an extra replication
	-- focus from the plot assignment until the pre-fetched move home lands, and never longer than this (seconds).
	JoinFocusMaxSeconds = 40,
	-- FallSafety: at most one "Rescued from fall" toast per player in this many seconds.
	FallToastCooldown = 8,
}

return StreamingConfig
