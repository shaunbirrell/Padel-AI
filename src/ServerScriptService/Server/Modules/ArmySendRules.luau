--!strict
--[[
	claude-bud JOB 38 (2026-09-30): the SEND fairness verdict and the power numbers (ArmyOrdersConfig.Fairness; DECIDED by the
	owner 2026-09-30). Pure functions: ArmyPlan gathers the facts on the server, this decides; the tests call it directly.
	Order of the checks (the first that fails is the reason; nothing marches):
	  self -> offline ("Player left") -> no base -> ally -> PvP off -> shield -> new player -> novice shield -> the victim's
	  army protection -> the sender's cooldown -> one active SEND -> no soldiers -> too weak (< MinPowerRatio x defences).
	An allowed SEND carries the power text ("Your army 820 vs defences 1,240: risky") and the bully flag (> BullyRatio x
	defences: half loot). The verdict is computed at the send and kept for that siege.
]]

local ArmyOrdersConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Configs.ArmyOrdersConfig)

local ArmySendRules = {}

export type Facts = {
	Self: boolean,
	VictimOnline: boolean,
	VictimHasBase: boolean,
	Ally: boolean,
	PvpOff: boolean,
	ShieldLeft: number, -- seconds
	NewPlayerLeft: number,
	Novice: boolean,
	ProtectLeft: number, -- the victim's army protection
	CooldownLeft: number, -- the sender's SEND cooldown
	ActiveSend: boolean,
	Units: number,
	ArmyPower: number,
	DefencePower: number,
}
export type Verdict = { Ok: boolean, Reason: string, Text: string, Bully: boolean, Ratio: number }

function ArmySendRules.Clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function ArmySendRules.Commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- units x unit HP x unit DPS (research-scaled numbers come from the caller)
function ArmySendRules.ArmyPower(units: number, unitHp: number, unitDps: number): number
	return math.max(0, units) * math.max(0, unitHp) * math.max(0, unitDps)
end

-- gate HP + each guard's HP x DPS + each live turret's HP x DPS
function ArmySendRules.DefencePower(gateHp: number, guards: { { Hp: number, Dps: number } }, turrets: { { Hp: number, Dps: number } }): number
	local p = math.max(0, gateHp)
	for _, g in ipairs(guards) do
		p += math.max(0, g.Hp) * math.max(0, g.Dps)
	end
	for _, t in ipairs(turrets) do
		p += math.max(0, t.Hp) * math.max(0, t.Dps)
	end
	return p
end

function ArmySendRules.Verdict(f: Facts): Verdict
	local F = ArmyOrdersConfig.Fairness
	local function no(reason: string, text: string): Verdict
		return { Ok = false, Reason = reason, Text = text, Bully = false, Ratio = 0 }
	end
	if f.Self then
		return no("Self", "That is your base")
	end
	if not f.VictimOnline then
		return no("Offline", "Player left")
	end
	if not f.VictimHasBase then
		return no("NoBase", "No base to attack")
	end
	if f.Ally then
		return no("Ally", "Clan ally")
	end
	if f.PvpOff then
		return no("PvpOff", "PvP is off in this server")
	end
	if f.ShieldLeft > 0 then
		return no("Shielded", "🛡 Shielded " .. ArmySendRules.Clock(f.ShieldLeft))
	end
	if f.NewPlayerLeft > 0 then
		return no("NewPlayer", "New player protected " .. ArmySendRules.Clock(f.NewPlayerLeft))
	end
	if f.Novice then
		return no("Novice", "New player protected")
	end
	if f.ProtectLeft > 0 then
		return no("Protected", "Just raided: protected " .. ArmySendRules.Clock(f.ProtectLeft))
	end
	if f.CooldownLeft > 0 then
		return no("Cooldown", "Army resting " .. ArmySendRules.Clock(f.CooldownLeft))
	end
	if f.ActiveSend then
		return no("Active", "Your army is already out")
	end
	if f.Units <= 0 then
		return no("NoArmy", "No soldiers to send")
	end
	local def = math.max(1, f.DefencePower)
	local ratio = f.ArmyPower / def
	local vs = string.format("Your army %s vs defences %s", ArmySendRules.Commas(f.ArmyPower), ArmySendRules.Commas(f.DefencePower))
	if ratio < F.MinPowerRatio then
		local v = no("TooWeak", vs .. ": too weak")
		v.Ratio = ratio
		return v
	end
	local bully = ratio > F.BullyRatio
	local word = if bully then "much stronger: half loot" elseif ratio < F.RiskyRatio then "risky" else "good odds"
	return { Ok = true, Reason = "Ok", Text = vs .. ": " .. word, Bully = bully, Ratio = ratio }
end

return ArmySendRules
