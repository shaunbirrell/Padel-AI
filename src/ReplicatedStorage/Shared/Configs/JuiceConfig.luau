--!strict
--[[
	claude-bud JOB 11 (2026-09-29): juice (Client/Modules/Juice). Already in the game and kept: purchase / collect / level-up
	sounds (SoundConfig.Hooks), the HUD "+$N" cash floats (HudLayout.CashFloat), toasts. Added, owner-only first:
	  * Purchase / unlock burst: on a successful base purchase (PurchaseResult Ok) a gold ring expands at the player's
	    feet (he stands at the console) with a short spark burst; the ring is 1 client part, the sparks one Emit.
	    Low FX (ProductionFx.IsLowFx / the JOB 8 low tier): ring only, no particles.
	  * Rebirth celebration: the server's FeaturePush "Rebirth" (after a saved rebirth) shows a gold banner in the HUD's
	    top stack ("REBIRTH P3!" + what it gives) and a light confetti fall, BannerSeconds long; never covers the controls.
	All client-only (nothing replicates), no per-frame work outside the short tweens. Rollout "owner" / "all" / off.
]]

local JuiceConfig = {
	Rollout = "owner",
	Burst = {
		Seconds = 1.1,
		RingStuds = 12,
		Particles = 18,
		Color = Color3.fromRGB(255, 205, 60),
	},
	Rebirth = {
		BannerSeconds = 3.5,
		Confetti = 26,
		Colors = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 200, 90) } :: { Color3 },
	},
}

function JuiceConfig.LiveFor(userId: any): boolean
	local mode = JuiceConfig.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
	end
	return false
end

return JuiceConfig
