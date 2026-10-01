--!strict
--[[
	claude-bud JOB 41 part C (2026-10-01): RIVAL BASES WORTH RAIDING (owner change 19:05: replaces "smaller servers";
	servers stay at 10 players). A separate config (not an ArmyOrdersConfig block) so the JOB 38 SEND config keeps its
	pins; it only SURFACES targets, every rule stays JOB 38's.
	  * the SERVER (Services/RivalService) lists, for each viewer, the other occupied bases ArmySendRules ALLOWS right now
	    (ArmyPlan.CheckSend: the same verdict, the same facts; no second rule), sorted by the loot estimate then the
	    distance, top MaxShown. Loot is a BUCKET, never the exact balance. One FeaturePush "RivalTargets" per viewer
	    every RefreshSeconds, from ONE shared tick.
	  * the CLIENT (Controllers/RivalController) shows a TARGETS pill (count badge) and a small list: name, army size,
	    the loot bucket, the verdict chip, SEND ARMY (the same JOB 38 remote; the server re-checks) and VIEW (the map on
	    that base card; tap-to-pin, no travel).
	OFF (Enabled = false or not live for the viewer): no pill, no push; the map SEND ARMY is unchanged.
]]

local RivalConfig = {
	Enabled = true,
	OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone
	RefreshSeconds = 10,
	MaxShown = 3,
	MinLootToShow = 1000,
	-- the loot estimate as a bucket (largest first): "$1M+", "$100k+", "$10k+", "$1k+"
	LootBuckets = {
		{ Min = 1000000, Text = "$1M+" },
		{ Min = 100000, Text = "$100k+" },
		{ Min = 10000, Text = "$10k+" },
		{ Min = 1000, Text = "$1k+" },
	},
	-- the verdict chip from the SEND ratio (ArmyOrdersConfig.Fairness): bully -> easy (half loot), < RiskyRatio -> risky
	VerdictText = { Easy = "easy", Even = "even", Risky = "risky" },
	-- the optional "new rich target" toast: at most once per this many seconds, never in combat / the Guided hold
	ToastEverySeconds = 300,
	ToastText = "A rich target is nearby: TARGETS",
	-- the pill (real px): top-right under the top-bar pills (the Army tile is in the left rail's thumbstick band)
	Pill = { Width = 128, Height = 48, Top = 64, Right = 16 },
	-- Code Bot v163: the pill is ALWAYS shown for a live player; with 0 targets it is dimmed and the list says this,
	-- plus the server's one-line reason (Why) under it
	EmptyText = "No targets right now — rivals appear when other players have cash to raid",
	EmptyHeight = 96, -- px of the empty-state text block (up to 5 lines at 15 px in the 330 px list)
	WhyText = {
		Held = "Finish the guided first minutes first.",
		Alone = "No other players with a base in this server yet.",
		NoArmy = "Recruit soldiers to send an army.",
		Protected = "Everyone here is shielded or new-player protected right now.",
		Busy = "Your army is out or resting.",
		Poor = "Nobody here has $10k+ in their ATM yet.",
		Strong = "Their defences are too strong for your army right now.",
	},
}

function RivalConfig.LiveFor(userId: any): boolean
	return (require(script.Parent.RetentionConfig) :: any).Live(RivalConfig, userId)
end

-- the bucket text for a loot estimate; nil below MinLootToShow (never the exact number)
function RivalConfig.Bucket(loot: number): string?
	local n = tonumber(loot) or 0
	if n ~= n or n < RivalConfig.MinLootToShow then
		return nil
	end
	for _, b in ipairs(RivalConfig.LootBuckets) do
		if n >= b.Min then
			return b.Text
		end
	end
	return nil
end

-- the verdict chip from an allowed SEND verdict { Bully, Ratio } and the JOB 38 fairness ratios
function RivalConfig.VerdictWord(bully: boolean, ratio: number, riskyRatio: number): string
	if bully then
		return RivalConfig.VerdictText.Easy
	elseif ratio < riskyRatio then
		return RivalConfig.VerdictText.Risky
	end
	return RivalConfig.VerdictText.Even
end

--[[ Pure: candidate rows { PlotId, Loot, Dist, ... } -> the shown list: Loot >= MinLootToShow, sorted by Loot (desc)
	then Dist (asc), at most MaxShown; each row gets its Bucket and loses the exact Loot. ]]
function RivalConfig.Pick(rows: { any }): { any }
	local list = {}
	for _, r in ipairs(rows) do
		if (tonumber(r.Loot) or 0) >= RivalConfig.MinLootToShow then
			table.insert(list, r)
		end
	end
	table.sort(list, function(a, b)
		if a.Loot ~= b.Loot then
			return a.Loot > b.Loot
		end
		return a.Dist < b.Dist
	end)
	local out = {}
	for i = 1, math.min(RivalConfig.MaxShown, #list) do
		local r = list[i]
		table.insert(out, {
			PlotId = r.PlotId,
			Name = r.Name,
			Army = r.Army,
			Verdict = r.Verdict,
			Loot = RivalConfig.Bucket(r.Loot),
			Dist = math.floor((tonumber(r.Dist) or 0) + 0.5),
		})
	end
	return out
end

return RivalConfig
