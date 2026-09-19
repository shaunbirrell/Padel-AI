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
	RaidHoldSeconds = 8,
	CooldownSeconds = 300, -- 5 min per player after successful raid
	CashMin = 15000,
	CashMax = 35000,
	GuardNPCType = "BankGuard",
	GuardCount = 5,
	GuardRingRadius = 18,
	NotifyOnRaid = true,
}

return BankRaidConfig
