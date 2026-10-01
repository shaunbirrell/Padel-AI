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
	-- Code Bot v168 (Shaun 2026-10-01: "isn't very clear and in depth"; a dark pill with small dim yellow text): a
	-- 64 px CARD instead: a crosshair icon, "TARGETS" + the count, then the suggested rival (the server's top pick:
	-- most loot, then nearest) on two lines: the name, "500m · $100k+"; with no target "No target now" + the short
	-- reason. Placed in the CONTENT rect (below the 58 px topbar row where the compass / BASE pill sits), Top px under
	-- it, Right px from the safe right edge. Its width leaves the centred top stack (toasts / objective card,
	-- HudConfig.TopStack.MaxWidthScale 0.62 of the content width) a StackGap: Width = clamp(content x
	-- (1 - 0.62) / 2 - Right - StackGap, MinWidth, MaxWidth) = 180 px on a 1024 x 471 phone (146 on 844 x 390). From
	-- BigIconMinWidth the crosshair is a 30 px icon left of the three lines; narrower, an 18 px icon in the title row
	-- and the two rival lines use the full width.
	Pill = { Top = 8, Right = 8, Height = 64, MinWidth = 142, MaxWidth = 260, StackGap = 6, TopStackScale = 0.62, Icon = 30, SmallIcon = 18, BigIconMinWidth = 172, Badge = 30 },
	-- the list under the card (real px): one 64 px row per target (name + level / army + verdict chip / loot +
	-- distance, SEND ARMY + VIEW), a 36 px header; on a short screen it slides up over the card (it must end above
	-- the content bottom: asserted by the v168 test)
	List = { Width = 400, Gap = 6, Header = 36, RowHeight = 64, RowGap = 4, SendWidth = 112, ViewWidth = 60, ButtonHeight = 48 },
	-- the card's short empty-state reasons (<= 16 chars at 14 px in the card's 126 px text column); the list keeps the full WhyText
	ShortWhy = {
		Held = "Finish the guide",
		Alone = "No rivals here",
		NoArmy = "Recruit soldiers",
		Protected = "Rivals shielded",
		Busy = "Army busy",
		Poor = "No rich rivals",
		Strong = "Too strong",
	},
	ShortWhyDefault = "Check back soon",
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

-- ── Code Bot v168: the TARGETS card / list text (pure; RivalController draws exactly these strings) ──

-- "95m" under 1 km, "1.2km" above (the compass pill's format; 1 stud = 1 m)
function RivalConfig.DistText(studs: any): string
	local n = math.max(0, tonumber(studs) or 0)
	if n ~= n then
		n = 0
	end
	if n < 1000 then
		return string.format("%dm", math.floor(n + 0.5))
	end
	return string.format("%.1fkm", n / 1000)
end

-- the short reason for the card from the server's full one-line Why (RivalConfig.WhyText value)
function RivalConfig.ShortWhyFor(why: string?): string
	if type(why) == "string" then
		for key, full in pairs(RivalConfig.WhyText) do
			if full == why then
				return RivalConfig.ShortWhy[key] or RivalConfig.ShortWhyDefault
			end
		end
	end
	return RivalConfig.ShortWhyDefault
end

--[[ The card's three lines for the pushed rows (rows[1] = the server's suggested rival) and the empty reason:
	{ Title = "TARGETS", Count = n, Name = line 2, Detail = line 3, Has = n > 0 } ]]
function RivalConfig.PillLines(rows: { any }?, why: string?): { [string]: any }
	local list = rows or {}
	local top = list[1]
	if top == nil then
		return { Title = "TARGETS", Count = 0, Name = "No target now", Detail = RivalConfig.ShortWhyFor(why), Has = false }
	end
	local loot = if type(top.Loot) == "string" then top.Loot else "$1k+"
	local far = tonumber(top.Dist) or 0
	return {
		Title = "TARGETS",
		Count = #list,
		Name = tostring(top.Name or "Rival"),
		Detail = if far > 0 then RivalConfig.DistText(far) .. " · " .. loot else loot .. " loot",
		Has = true,
	}
end

--[[ One list row's text: Name, Level ("Lv 23"), Army ("Army 12"), Loot ("$100k+ loot"), Dist ("500m away"),
	Chip (the verdict, upper case). ]]
function RivalConfig.RowLines(r: any): { [string]: string }
	local lv = math.floor(tonumber(r and r.Level) or 0)
	return {
		Name = tostring(r and r.Name or "Rival"),
		Level = if lv > 0 then "Lv " .. tostring(lv) else "Lv ?",
		Army = "Army " .. tostring(math.floor(tonumber(r and r.Army) or 0)),
		Loot = (if r and type(r.Loot) == "string" then r.Loot else "$1k+") .. " loot",
		Dist = RivalConfig.DistText(r and r.Dist),
		Chip = string.upper(tostring(r and r.Verdict or RivalConfig.VerdictText.Even)),
	}
end

--[[ The card + list rectangles in the content rect's px (x, y = top-left; w, h) for a content size and a row count.
	RivalController places by exactly these numbers; the v168 test checks them against the 1024 x 471 HUD. ]]
function RivalConfig.Layout(contentW: number, contentH: number, nRows: number): { [string]: any }
	local P, L = RivalConfig.Pill, RivalConfig.List
	local side = contentW * (1 - P.TopStackScale) / 2
	local w = math.clamp(math.floor(side - P.Right - P.StackGap), P.MinWidth, P.MaxWidth)
	local big = w >= P.BigIconMinWidth
	local pill = {
		X = contentW - P.Right - w,
		Y = P.Top,
		W = w,
		H = P.Height,
		Icon = if big then P.Icon else P.SmallIcon,
		IconX = 8,
		IconY = if big then math.floor((P.Height - P.Icon) / 2) else 5,
		TitleX = if big then 8 + P.Icon + 8 else 8 + P.SmallIcon + 4,
		TextX = if big then 8 + P.Icon + 8 else 8,
	}
	pill.TextW = w - pill.TextX - 8
	pill.TitleW = w - pill.TitleX - P.Badge
	local body = if nRows <= 0 then RivalConfig.EmptyHeight else nRows * (L.RowHeight + L.RowGap)
	local listH = L.Header + body + 4
	-- under the card; on a short screen as far up as needed (over the card, never above the content top + Top)
	local listTop = math.max(P.Top, math.min(P.Top + P.Height + L.Gap, contentH - P.Right - listH))
	listH = math.min(listH, contentH - listTop - P.Right)
	local lw = math.min(L.Width, contentW - 2 * P.Right)
	return { Pill = pill, List = { X = contentW - P.Right - lw, Y = listTop, W = lw, H = listH } }
end

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
			Level = math.max(0, math.floor(tonumber(r.Level) or 0)), -- Code Bot v168 (display only)
			Verdict = r.Verdict,
			Loot = RivalConfig.Bucket(r.Loot),
			Dist = math.floor((tonumber(r.Dist) or 0) + 0.5),
		})
	end
	return out
end

return RivalConfig
