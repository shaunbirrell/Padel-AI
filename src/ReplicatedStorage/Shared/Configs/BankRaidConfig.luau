--!strict
--[[
	Empire Bank raid stub — high-value contested vault with NPC guards + per-player cooldown.
	Inspired by MT raid/contested high-value buildings; WAR EMPIRE naming only.
]]

local BankRaidConfig = {
	Enabled = true,
	BankId = "EmpireBank",
	DisplayName = "Empire Bank",
	Position = Vector3.new(220, 1, -220),
	VaultRadius = 12,
	RaidHoldSeconds = 6, -- v71: 8 → 6 (task #20 bank retune; guard stats in CombatConfig.NPCTypes.BankGuard)
	CooldownSeconds = 300, -- 5 min per player after successful raid
	CashMin = 15000,
	CashMax = 35000,
	GuardNPCType = "BankGuard",
	GuardCount = 5,
	GuardRingRadius = 18,
	NotifyOnRaid = true,
	-- v71: the hold freezes only while the raider was hit within this many seconds (was: any health below 95 %)
	UnderFireSeconds = 2,
	-- vault label (Shared/Util/WorldLabel): stud-scaled, never AlwaysOnTop, MaxDistance <= 40 (spec §5)
	Label = {
		Title = "Empire Bank",
		RaidingSub = "RAID IN PROGRESS",
		Color = Color3.fromRGB(255, 220, 120),
		RaidingColor = Color3.fromRGB(255, 176, 48),
		HeightStuds = 8, -- above the vault pad centre (clear of a standing raider's head)
		MaxDistance = 40,
	},
}

return BankRaidConfig
