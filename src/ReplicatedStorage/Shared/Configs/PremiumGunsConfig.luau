--!strict
--[[
	claude-bud JOB 35 (2026-09-30): the PREMIUM GUNS ARMORY. Six Robux guns (WeaponConfig, Premium = true, CostCash 0)
	sold by game passes (MonetizationConfig PG_*, prices there only; Id 0 = SOON, never prompted), shown in glass cases
	in every base next to the Supply Depot, and as gold rows in Shop > WEAPONS.
	  * Owning PG_<gun> or PG_ArmoryPass sets profile.Weapons[id] = true (PremiumGunService: join + OnPassOwned).
	  * Cash purchase refuses Premium guns (CombatService.PurchaseWeapon "RobuxOnly"); equip refuses unowned ones.
	  * New server-side gun mechanics (Shared/Util/GunMechanics): Burst, SpinUp, ChargeSeconds, Pierce, HeadshotMult.
	  * The Longshot has a real scope (client: Modules/Scope).
	Kill switch: Live (RetentionConfig.Live rule: OwnerFirst = UserId 470626172 + Studio). Off = no armory, no grants,
	no gold rows (the guns stay in WeaponConfig, unowned and unsold, like the rebirth guns before their rebirth).
]]

export type Gun = { WeaponId: string, PassKey: string }

local PremiumGunsConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v136 launch (owner 2026-09-30 14:17): everyone
	},
	-- the playtest owner gets the six guns while live and the passes are Id 0 (so he can test them); off = passes only
	OwnerTestGrant = true,
	BundleKey = "PG_ArmoryPass",

	-- case order (left to right as you face the row)
	Guns = {
		{ WeaponId = "SovereignPistol", PassKey = "PG_Sovereign" },
		{ WeaponId = "QuakeLauncher", PassKey = "PG_Quake" },
		{ WeaponId = "LongshotSniper", PassKey = "PG_Longshot" },
		{ WeaponId = "HavocRotary", PassKey = "PG_Havoc" },
		{ WeaponId = "ThunderheadLauncher", PassKey = "PG_Thunderhead" },
		{ WeaponId = "TempestRailgun", PassKey = "PG_Tempest" },
	} :: { Gun },

	--[[ The armory row (plot-local studs, like MonetizationConfig.PremiumPads.Depot): 7 cases in one line west of the
		Supply Depot (X -78 .. -54 at Z 146), the 7th = the Armory Pass (all six guns on a rack). Cases face the plot
		(front = -Z). One sign behind, one light for the whole row (Shadows off). ]]
	Armory = {
		X0 = -92,
		Step = -6.5,
		Z = 146,
		SignZ = 152,
		Sign = "ARMORY",
		FolderName = "WE_Armories",
		Plinth = Vector3.new(4, 1.2, 4),
		Glass = Vector3.new(3.4, 4.2, 3.4),
		GlassTransparency = 0.6,
		OwnedGlassTransparency = 0.92, -- "once owned the glass fades"
		Trim = Color3.fromRGB(212, 175, 55),
		LightRange = 26,
		LightBrightness = 1.2,
		PromptDistance = 10,
		LabelMaxDistance = 40, -- WorldLabel cap; the LabelGovernor shows at most 3 base labels at once
		SpinDegPerSecond = 40, -- client spins the gun template in each case
		ShowDistance = 70, -- client builds the spinning guns only within this distance
		GunLength = 2.6, -- the displayed gun is scaled to this length inside the case
	},

	-- the Longshot scope (client, Modules/Scope)
	Scope = {
		BaseFov = 70,
		Levels = { 20, 12 }, -- first press, then again (wheel / second SCOPE tap); a third tap exits
		SwayDeg = 0.35, -- while moving
		SwayIdleDeg = 0.06,
		RecoilMult = 0.5, -- the phone SCOPE button reuses RELOAD's validated size, straight above it
	},
}

local RetentionConfig = require(script.Parent.RetentionConfig)

function PremiumGunsConfig.LiveFor(userId: any): boolean
	return RetentionConfig.Live(PremiumGunsConfig.Live, userId)
end

-- the premium gun for a pass key ("PG_Sovereign" -> "SovereignPistol"); nil for the bundle / anything else
function PremiumGunsConfig.GunForPass(passKey: string): string?
	for _, g in ipairs(PremiumGunsConfig.Guns) do
		if g.PassKey == passKey then
			return g.WeaponId
		end
	end
	return nil
end

-- the pass for a premium gun ("SovereignPistol" -> "PG_Sovereign")
function PremiumGunsConfig.PassFor(weaponId: string): string?
	for _, g in ipairs(PremiumGunsConfig.Guns) do
		if g.WeaponId == weaponId then
			return g.PassKey
		end
	end
	return nil
end

--[[ The weapons a set of owned pass keys unlocks (the single passes + the bundle). owned: { [passKey]: boolean }. ]]
function PremiumGunsConfig.UnlockedBy(owned: { [string]: boolean }): { string }
	local out: { string } = {}
	local all = owned[PremiumGunsConfig.BundleKey] == true
	for _, g in ipairs(PremiumGunsConfig.Guns) do
		if all or owned[g.PassKey] == true then
			table.insert(out, g.WeaponId)
		end
	end
	return out
end

-- the bundle hides once all six single passes are owned
function PremiumGunsConfig.BundleHidden(owned: { [string]: boolean }): boolean
	for _, g in ipairs(PremiumGunsConfig.Guns) do
		if owned[g.PassKey] ~= true then
			return false
		end
	end
	return true
end

return PremiumGunsConfig
