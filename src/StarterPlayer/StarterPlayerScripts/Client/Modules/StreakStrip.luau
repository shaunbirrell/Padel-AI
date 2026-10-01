--!strict
--[[
	claude-bud JOB 29 (2026-09-30): the 7-day login strip, shared by the streak card (RetentionController) and the Missions
	panel (MissionController). Pure UI from the server's Streak7 data:
	  * Days = 7;
	  * Today = the day claimed today, or the one he can claim;
	  * Claimed;
	  * Cash[d];
	  * Big[d] (day 3 and day 7).
	Days before today show a tick, today is lit gold, the big days carry a gold border and a star. No input, no loops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60) :: any -- Bootstrap already waited for it; bounded anyway
local TycoonMath = require(Shared.Util.TycoonMath) -- Code Bot: the shared short money formatter (K/M/B/T)

local StreakStrip = {}

local GOLD = Color3.fromRGB(255, 205, 60)
local DONE = Color3.fromRGB(70, 150, 90)
local DIM = Color3.fromRGB(40, 44, 50)
local TEXT = Color3.fromRGB(235, 235, 235)

--[[ claude-bud JOB 49 A: the REAL time to the next claim day, from the server's clock in the payload (ServerNow /
	NextClaimUnix) and the local clock since it arrived (receivedAt = os.clock() then). nil when the server sent none
	(Calendar off) -> no countdown at all (no fake timer). "Next in 5h 12m" / "Next in 12m". ]]
function StreakStrip.NextText(data: any, receivedAt: number?): string?
	local nowS, nextS = tonumber(data and data.ServerNow), tonumber(data and data.NextClaimUnix)
	if nowS == nil or nextS == nil then
		return nil
	end
	local left = math.max(0, math.floor(nextS - nowS - (os.clock() - (receivedAt or os.clock()))))
	local h, m = left // 3600, (left % 3600) // 60
	return if h > 0 then string.format("Next in %dh %02dm", h, m) else string.format("Next in %dm", math.max(1, m))
end

-- "$750", "$1K", "$3.5K", "$20K", "$125M", "$2.7B": the SHARED short formatter (TycoonMath.ShortCash, tight; K/M/B/T).
-- Code Bot (2026-10-01): was a k-only formatter here ("$624953.3k" on D7 spilled into D6 on phones).
function StreakStrip.ShortCash(n: number): string
	return TycoonMath.ShortCash(tonumber(n) or 0, true)
end

-- a tile label that always fits its tile: TextScaled, capped at the panel's text size (never bigger than before),
-- shrinks down to MIN_TEXT on a narrow phone; no wrapping, so a long value scales instead of spilling
local MIN_TEXT = 6
local function fitText(label: TextLabel, maxSize: number)
	label.TextScaled = true
	label.TextWrapped = false
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.max(MIN_TEXT, math.floor(maxSize))
	c.MinTextSize = MIN_TEXT
	c.Parent = label
end

--[[ A horizontal strip of `data.Days` tiles, each tileW x tileH (in the parent's units), text `textSize`. Returns the
	strip Frame (parented to `parent`). ]]
function StreakStrip.Build(parent: Instance, data: any, tileW: number, tileH: number, textSize: number): Frame
	local days = math.clamp(math.floor(tonumber(data.Days) or 7), 1, 7)
	local today = math.floor(tonumber(data.Today) or 1)
	local claimed = data.Claimed == true
	local gap = 4
	local strip = Instance.new("Frame")
	strip.Name = "StreakStrip"
	strip.BackgroundTransparency = 1
	-- the strip's natural size; a caller may give it a scale width (Missions panel on a phone): the tiles share it
	strip.Size = UDim2.fromOffset(days * tileW + (days - 1) * gap, tileH)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = strip
	for d = 1, days do
		local done = d < today or (d == today and claimed)
		local isToday = d == today
		local big = typeof(data.Big) == "table" and data.Big[d] == true
		local tile = Instance.new("Frame")
		tile.Name = "Day" .. tostring(d)
		tile.LayoutOrder = d
		-- Code Bot (2026-10-01): an equal share of the strip (was a fixed tileW: a narrow panel pushed D7 out) and
		-- ClipsDescendants, so no label can ever draw over the neighbouring tile
		tile.Size = UDim2.new(1 / days, -gap * (days - 1) / days, 1, 0)
		tile.ClipsDescendants = true
		tile.BackgroundColor3 = if isToday then GOLD elseif done then DONE else DIM
		tile.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = tile
		if big then
			local st = Instance.new("UIStroke")
			st.Color = GOLD
			st.Thickness = 2
			st.Parent = tile
		end
		local top = Instance.new("TextLabel")
		top.BackgroundTransparency = 1
		top.Position = UDim2.fromScale(0.04, 0.04)
		top.Size = UDim2.fromScale(0.92, 0.44)
		top.Font = Enum.Font.GothamBlack
		top.TextSize = textSize
		fitText(top, textSize)
		top.TextColor3 = if isToday then Color3.fromRGB(30, 26, 10) else TEXT
		top.Text = (if done and not isToday then "✓" else "D" .. tostring(d)) .. (if big then "★" else "")
		top.Parent = tile
		local bottom = Instance.new("TextLabel")
		bottom.BackgroundTransparency = 1
		bottom.Position = UDim2.fromScale(0.04, 0.52)
		bottom.Size = UDim2.fromScale(0.92, 0.44)
		bottom.Font = Enum.Font.GothamBold
		bottom.TextSize = textSize
		fitText(bottom, textSize)
		bottom.TextColor3 = top.TextColor3
		local cash = if typeof(data.Cash) == "table" then tonumber(data.Cash[d]) or 0 else 0
		bottom.Text = StreakStrip.ShortCash(cash)
		if tonumber(data.GraceDay) == d then
			bottom.Text = "SAVED" -- claude-bud JOB 49 A: the missed day the grace rule kept
		end
		bottom.Parent = tile
		tile.Parent = strip
	end
	strip.Parent = parent
	return strip
end

return StreakStrip
