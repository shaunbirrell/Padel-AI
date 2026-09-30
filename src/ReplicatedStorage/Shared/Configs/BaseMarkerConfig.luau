--!strict
--[[
	claude-bud JOB 40 part E (2026-09-30, owner-approved PRIORITY): the BASE OWNER MARKER, visible from anywhere on the
	map (docs/claude-queue/JOB40-guards-speed-props-like-reminder.md part E). Above each occupied base: the owner's
	nation flag, DisplayName, @username and rebirth rank. It is the ONE documented exception to the "world labels within
	40 studs / AlwaysOnTop only for the objective marker" rule (CLAUDE.md world-label bullet, ASSUMPTIONS).
	  * the SERVER only publishes data (Services/BaseMarkerService: ReplicatedStorage.WE_BaseMarkers, one Configuration
	    per plot, attributes written only on change, event-driven + a 5 s refresh; nothing per frame);
	  * the CLIENT builds one BillboardGui per plot (Controllers/BaseMarkerController) and fades / scales / compacts
	    them together at most 10 Hz.
	Owner-first by VIEWER (Live: Enabled + OwnerFirst): off = no marker, the v123 base sign and the map unchanged.

	claude-bud JOB 40E FIX (2026-09-30, the owner's phone screenshots): the tags were too big (150-230 px boxes, a fifth
	of a phone screen each), too low (70 studs: from 1,000+ studs that is ~4 degrees above eye level, across the skyline),
	showed grey empty "OPEN BASE" / "?" tags, and a "VETERAN" title in the view. Now:
	  * HIGH in the sky: HeightAt(dist) = 150 studs + 6 % of the distance (max 260), so a far tag still sits well above
	    the horizon (1,000 studs away: 210 up = ~12 degrees);
	  * a SLIM pill sized to its text: a small flag + the short name (14-17 px real); the @handle and a short "R3" only
	    inside DetailStuds; never the rebirth title;
	  * small far, a little bigger near (ScaleAt: 1.0 far .. 1.2 near, clamped; a far tag is never bigger than a near
	    one); fades out past FarFadeStart .. FarFadeEnd;
	  * at most MaxShown rival tags (the nearest), and never two overlapping on screen (the farther one hides);
	  * no tag for a base without a live owner or a name (never grey / empty); "YOU" on the own base, which still fades
	    out inside HideInsideStuds.
]]

local RetentionConfig = require(script.Parent.RetentionConfig)

local BaseMarkerConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) sees markers until Code Bot sets false = everyone
	},
	FolderName = "WE_BaseMarkers", -- ReplicatedStorage (streaming-safe: never a workspace lookup on the client)
	RefreshSeconds = 5, -- the server's fallback refresh (claims / leaves / nation / rebirth also push at once)
	HeightStuds = 150, -- JOB 40E FIX: the minimum height above the plot centre (was 70; the tallest base kit is < 100)
	HeightPerStud = 0.06, -- + this x the viewer's distance, so a far tag stays in the sky
	MaxHeightStuds = 260,
	MaxDistance = 5000, -- the BillboardGui limit; the tags fade out much sooner (FarFade*)
	AlwaysOnTop = true,
	HideInsideStuds = 60, -- hidden this close (the v123 sign takes over) ...
	FadeInsideStuds = 90, -- ... fading in to full at this distance
	FarFadeStart = 1800, -- JOB 40E FIX: full up to here ...
	FarFadeEnd = 2400, -- ... gone past here
	ShowOpenBases = false, -- JOB 40E FIX: never a grey / empty tag for a base without a live owner
	-- size (real px on the screen; BillboardGui offsets are not under the HUD UIScale)
	PillHeight = 24, -- the slim pill at scale 1 (far)
	DetailHeight = 40, -- inside DetailStuds: a second line with the @handle and "R<n>"
	DetailStuds = 300,
	NameTextSize = 14, -- 14 px real at scale 1 (the CLAUDE.md minimum), up to 16.8 near
	UserTextSize = 12, -- the secondary @handle line (near only)
	MaxNameWidth = 96, -- longer names are cut with "..."
	PadPx = 6,
	MinScale = 1.0, -- far
	MaxScale = 1.2, -- near
	NearStuds = 150, -- MaxScale at or under this ...
	FarStuds = 1500, -- ... MinScale at or past this
	MaxShown = 5, -- rival tags at once (the nearest); the own base is always allowed
	OverlapPadPx = 4, -- two tags whose screen boxes come closer than this: the farther one hides
	UpdateHz = 10,
	Colors = {
		Plate = Color3.fromRGB(24, 26, 21),
		Stroke = Color3.fromRGB(90, 100, 80),
		Name = Color3.fromRGB(245, 245, 240),
		Muted = Color3.fromRGB(176, 184, 170),
		Rank = Color3.fromRGB(214, 178, 64),
		You = Color3.fromRGB(90, 200, 120),
		Ally = Color3.fromRGB(90, 160, 230),
		Open = Color3.fromRGB(150, 150, 150),
		NoFlag = Color3.fromRGB(70, 85, 55),
	},
	Text = { Open = "OPEN BASE", You = "YOU" },
}

function BaseMarkerConfig.LiveFor(userId: any): boolean
	return RetentionConfig.Live(BaseMarkerConfig.Live, userId)
end

-- 0 (hidden) .. 1 (full) by the viewer's distance to the plot centre: fades in past 60..90 (the v123 sign takes over
-- near the base) and out past FarFadeStart..FarFadeEnd
function BaseMarkerConfig.Fade(dist: number): number
	local B = BaseMarkerConfig
	local near = math.clamp((dist - B.HideInsideStuds) / (B.FadeInsideStuds - B.HideInsideStuds), 0, 1)
	local far = 1 - math.clamp((dist - B.FarFadeStart) / (B.FarFadeEnd - B.FarFadeStart), 0, 1)
	return math.min(near, far)
end

-- how high above the plot centre the tag floats for a viewer at `dist` (in the sky, never across the ground view)
function BaseMarkerConfig.HeightAt(dist: number): number
	local B = BaseMarkerConfig
	return math.clamp(B.HeightStuds + B.HeightPerStud * math.max(0, dist), B.HeightStuds, B.MaxHeightStuds)
end

-- the tag's scale at a distance: MaxScale near .. MinScale far (clamped; never bigger far than near)
function BaseMarkerConfig.ScaleAt(dist: number): number
	local B = BaseMarkerConfig
	local a = math.clamp((dist - B.NearStuds) / (B.FarStuds - B.NearStuds), 0, 1)
	return B.MaxScale + (B.MinScale - B.MaxScale) * a
end

-- the short rank for the near line: "R3"; nil at R0 (no rebirth title on the tag any more: JOB 40E FIX)
function BaseMarkerConfig.RankText(prestige: number, _titleFor: any?): string?
	local p = math.max(0, math.floor(tonumber(prestige) or 0))
	return if p > 0 then string.format("R%d", p) else nil
end

-- a tag is drawn only for a base with a live owner AND a name (never grey, never empty)
function BaseMarkerConfig.HasTag(owner: any, name: any): boolean
	return typeof(owner) == "number" and typeof(name) == "string" and string.match(name, "%S") ~= nil
end

--[[ which tags show this step. tags = { { Key, Dist, X, Y, W, H, Mine } } (screen px, centre + size; only tags on
	screen with a fade > 0). The own base first, then the nearest rivals up to MaxShown; a tag whose screen box comes
	within OverlapPadPx of one already shown hides (so the farther of two overlapping tags hides). ]]
function BaseMarkerConfig.VisibleSet(tags: { any }): { [any]: boolean }
	local B = BaseMarkerConfig
	local list = table.clone(tags)
	table.sort(list, function(a, b)
		if (a.Mine == true) ~= (b.Mine == true) then
			return a.Mine == true
		end
		return a.Dist < b.Dist
	end)
	local out: { [any]: boolean } = {}
	local shown: { any } = {}
	local rivals = 0
	for _, t in ipairs(list) do
		if t.Mine == true or rivals < B.MaxShown then
			local clear = true
			for _, s in ipairs(shown) do
				if math.abs(t.X - s.X) * 2 < t.W + s.W + 2 * B.OverlapPadPx and math.abs(t.Y - s.Y) * 2 < t.H + s.H + 2 * B.OverlapPadPx then
					clear = false
					break
				end
			end
			if clear then
				out[t.Key] = true
				table.insert(shown, t)
				if t.Mine ~= true then
					rivals += 1
				end
			end
		end
	end
	return out
end

return BaseMarkerConfig
