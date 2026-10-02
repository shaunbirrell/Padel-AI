--!strict
--[[
	claude-bud JOB 26: personal armour the player buys at his base (Server/Services/ArmourService, Client/Controllers/
	ArmourController: Army menu -> MY ARMOUR).
	  * Effect: damage reduction, delivered as BONUS MAX HEALTH (MaxHealth = PlayerMaxHealth / (1 - Reduction)), so it
	    works against EVERY damage source (guns, soldiers, guards, defenders, vehicles, missiles, blasts) whatever code
	    path hurts the Humanoid: 20 % less damage = 125 HP. The HUD shows the bonus as a blue bar above the health bar
	    (spent first). Capped at MaxReduction.
	  * Tiers bought in order, Cash only, each needs a Command Center level (base progress); bought only inside his own
	    plot (InBaseOnly). Saved in profile.Armour.Tier, kept after death and through rebirth (KeepThroughRebirth).
	  * Look: a vest (every tier) and a helmet (from HelmetFromTier) welded to the character (simple parts, no store
	    assets); Settings "Armour look" hides the look, the stats stay.
	  * Robux: CommanderArmourRobux stays OFF (a suggestion only: the owner must approve any Robux item).
	Enabled = false: no armour (100 HP for everyone, as v118).
]]

export type Tier = { Id: string, Name: string, Cost: number, Reduction: number, NeedCommandCenter: number, Color: Color3 }

local ArmourConfig = {
	Enabled = true,
	MaxReduction = 0.5,
	InBaseOnly = true,
	KeepThroughRebirth = true,
	HelmetFromTier = 3,
	Tiers = {
		{ Id = "LightVest", Name = "Light Vest", Cost = 12000, Reduction = 0.10, NeedCommandCenter = 1, Color = Color3.fromRGB(96, 104, 78) },
		{ Id = "CombatArmour", Name = "Combat Armour", Cost = 45000, Reduction = 0.20, NeedCommandCenter = 2, Color = Color3.fromRGB(78, 86, 62) },
		{ Id = "HeavyArmour", Name = "Heavy Armour", Cost = 150000, Reduction = 0.30, NeedCommandCenter = 3, Color = Color3.fromRGB(62, 68, 52) },
		{ Id = "EliteArmour", Name = "Elite Armour", Cost = 450000, Reduction = 0.40, NeedCommandCenter = 4, Color = Color3.fromRGB(48, 52, 44) },
		{ Id = "TitanArmour", Name = "Titan Armour", Cost = 1200000, Reduction = 0.50, NeedCommandCenter = 5, Color = Color3.fromRGB(36, 38, 34) },
	} :: { Tier },
	-- suggestion only (docs / handoff): a "Commander Armour" look + the Titan tier early for Robux; OFF
	CommanderArmourRobux = false,
}

return ArmourConfig
