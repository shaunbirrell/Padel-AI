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
]]

local RetentionConfig = require(script.Parent.RetentionConfig)

local BaseMarkerConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) sees markers until Code Bot sets false = everyone
	},
	FolderName = "WE_BaseMarkers", -- ReplicatedStorage (streaming-safe: never a workspace lookup on the client)
	RefreshSeconds = 5, -- the server's fallback refresh (claims / leaves / nation / rebirth also push at once)
	HeightStuds = 70, -- above the plot centre (the v123 sign is at 26 over the gate)
	MaxDistance = 5000, -- the whole map
	AlwaysOnTop = true,
	HideInsideStuds = 60, -- hidden this close (the v123 sign takes over) ...
	FadeInsideStuds = 90, -- ... fading in to full at this distance
	ShowOpenBases = true, -- "OPEN BASE" in grey, smaller, 60 % opacity
	OpenOpacity = 0.6,
	-- size (real px on the screen; BillboardGui offsets are not under the HUD UIScale)
	MaxPx = Vector2.new(230, 58), -- near
	MinPx = Vector2.new(150, 42), -- far (still legible on an 800x360 phone)
	NearStuds = 150, -- MaxPx at or under this ...
	FarStuds = 1500, -- ... MinPx at or past this
	CompactFarStuds = 1800, -- past this the marker is compact (flag + rank)
	OverlapPx = 90, -- two markers closer than this on screen: the farther one goes compact
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

-- 0 (hidden) .. 1 (full) by the viewer's distance to the plot centre
function BaseMarkerConfig.Fade(dist: number): number
	local lo, hi = BaseMarkerConfig.HideInsideStuds, BaseMarkerConfig.FadeInsideStuds
	if dist <= lo then
		return 0
	elseif dist >= hi then
		return 1
	end
	return (dist - lo) / (hi - lo)
end

-- the marker's pixel size at a distance (MaxPx near .. MinPx far, linear between)
function BaseMarkerConfig.SizeAt(dist: number): Vector2
	local a = math.clamp((dist - BaseMarkerConfig.NearStuds) / (BaseMarkerConfig.FarStuds - BaseMarkerConfig.NearStuds), 0, 1)
	local mx, mn = BaseMarkerConfig.MaxPx, BaseMarkerConfig.MinPx
	return Vector2.new(mx.X + (mn.X - mx.X) * a, mx.Y + (mn.Y - mx.Y) * a)
end

-- the rank chip text: "COMMANDER R3"; nil at R0 (hidden)
function BaseMarkerConfig.RankText(prestige: number, titleFor: (number) -> string?): string?
	local p = math.max(0, math.floor(tonumber(prestige) or 0))
	if p <= 0 then
		return nil
	end
	local t = titleFor(p)
	return if t then string.format("%s R%d", string.upper(t), p) else string.format("R%d", p)
end

--[[ the far-compact rule: markers = { { Key, Dist, X, Y } } (screen px); returns { [Key] = true } for the compact
	ones: past CompactFarStuds, or the farther of two closer than OverlapPx on screen ]]
function BaseMarkerConfig.CompactSet(markers: { { Key: any, Dist: number, X: number, Y: number } }): { [any]: boolean }
	local out: { [any]: boolean } = {}
	for _, m in ipairs(markers) do
		if m.Dist > BaseMarkerConfig.CompactFarStuds then
			out[m.Key] = true
		end
	end
	for i = 1, #markers do
		for j = i + 1, #markers do
			local a, b = markers[i], markers[j]
			local dx, dy = a.X - b.X, a.Y - b.Y
			if dx * dx + dy * dy < BaseMarkerConfig.OverlapPx * BaseMarkerConfig.OverlapPx then
				out[if a.Dist >= b.Dist then a.Key else b.Key] = true
			end
		end
	end
	return out
end

return BaseMarkerConfig
