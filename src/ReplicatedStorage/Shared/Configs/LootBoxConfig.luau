--!strict
--[[ POLICY-PENDING: random loot boxes are NOT enabled.
	This stub exists so shop/UI can show "coming soon" without grant paths. ]]

local LootBoxConfig = {
	PolicyPending = true,
	Enabled = false,
	Boxes = {
		-- Placeholder only — never grant from client; never ProcessReceipt until policy cleared
		StarterCrate = {
			Id = 0,
			DisplayName = "Supply Crate (policy-pending)",
			Description = "Random rewards disabled until compliance review.",
		},
	},
}

return LootBoxConfig
