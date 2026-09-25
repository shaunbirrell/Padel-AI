--!strict
--[[
	OpsJobs — the JOBS resolver (W3 step 2 Phase B, lane U). Pure functions over plain tables: no Instances, no
	services, no clock reads (every function that ages a timer takes `now`), so the headless tests call it directly.
	Contract: scratchpad w3s2/buildB/KB/contract.md §6. Spec: w3s2/spec_w3s2.md + activities §1.1-1.4.

	The client never decides anything here: states, pay, cooldowns and every point come from the server's OpsState /
	OpsPing payloads (OpsConfig exported types). This module only caches them, ages the "seconds left" timers and
	picks what the JOBS board and the GO button show.

	  OpsJobs.NewCache() -> Cache
	  OpsJobs.Merge(cache, payload, now) -> boolean       OpsState: Full replaces the site cache, a delta merges into
	                                                        it, State "Off" drops a site; Carrying / Bags every payload
	  OpsJobs.AddPing(cache, payload, now, userId) -> bool OpsPing {U, X, Z}: a carrier seen now (never the local player)
	  OpsJobs.Rows(cache, me, trackedId, userId, now?) -> { Row }   at most Ui.Jobs.Rows (3):
	      1. the carried job (GO = your own Home) or the tracked job
	      2. the nearest open job to `me` (the caller passes Home while the player stands in their own plot)
	      3. somebody else's dropped / pinged bag ("Steal the Bag"), else the bank if it is open, else the next-nearest
	         open job; when nothing else is open the bank still fills the row with its countdown
	    A row never offers GO to a Quiet, Closed, Held or on-your-cooldown site (only the bank is listed then, with its
	    countdown and no GO).
	  OpsJobs.GoFor(cache, id, me, userId, now) -> Point?  the CURRENT point of a tracked id: a site's Target anchor, your
	                                                        own Home ("@home") or a bag / carrier ("@bag:<UserId>")
	  OpsJobs.NearestLike(cache, id, me, now) -> string?   the nearest open site with the same job Title (GO re-resolves
	                                                        there when the tracked site closes under you)
	  OpsJobs.Sub(site, def, distStuds, now?) -> string    "OPEN · 620m · $36K" / "RAID ON" / "CLOSED 4:10" /
	                                                        "YOURS IN 7:30" / "HELD" (OpsConfig.Text.Row)

	Every GO point is per player: the nearest valid site, your own plot's Home, or the last position of a bag. Never a
	fixed world marker. Points without a height (Home, bags, pings) stand on WorldConfig.Activity.FloorY.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local OpsConfig = require(Shared.Configs.OpsConfig)
local WorldConfig = require(Shared.Configs.WorldConfig)

local OpsJobs = {}

export type Point = { Short: string, X: number, Y: number, Z: number }
export type Row = {
	Id: string, -- a site id, OpsJobs.HomeId or "@bag:<UserId>"
	Title: string,
	Sub: string,
	Hard: boolean,
	Go: Point?, -- nil = no GO (a closed bank row); a Tracked row shows STOP instead
	Tracked: boolean,
	Steal: boolean?,
	Kind: string, -- an OpsConfig.Kinds key, or "Steal" / "Home"
	Dist: number?, -- studs from `me` (XZ)
}
export type SiteEntry = {
	Id: string,
	State: string,
	X: number?,
	Y: number?,
	Z: number?,
	Left: number?,
	Pay: number?,
	MyCd: number?,
	Guards: number?,
	HeldBy: number?,
	At: number, -- `now` when Left / MyCd arrived (they are seconds left at that moment)
}
export type PingEntry = { X: number, Z: number, At: number }
export type Cache = {
	Sites: { [string]: SiteEntry },
	Home: { X: number, Z: number }?,
	Carrying: OpsConfig.OpsCarrySnap?,
	CarryAt: number,
	Bags: { OpsConfig.OpsBagSnap },
	Pings: { [number]: PingEntry },
	Full: boolean, -- a Full snapshot has arrived (before it, the board shows nothing)
	Version: number, -- bumps on every accepted payload / ping (the board rebuilds only when it changed)
}
export type Me = { X: number, Z: number }

local TEXT = OpsConfig.Text
local ROW = TEXT.Row
local UI = OpsConfig.Ui
local MAX_ROWS = math.max(1, UI.Jobs.Rows)
local FLOOR_Y = WorldConfig.Activity.FloorY
local SEP = " · "
local OPEN_STATES: { [string]: boolean } = { Dormant = true, Open = true, Active = true }
local MAX_SITES = 64 -- a payload never carries more (32 sites today); junk beyond is ignored
local MAX_BAGS = 8

-- Fields lane O may add to OpsConfig (pending edit, buildB/U/pending_edits.md); read defensively so this works before
local ROW_ANY: any = ROW
local UI_ANY: any = UI
OpsJobs.HomeShort = if type(ROW_ANY.HomeShort) == "string" then ROW_ANY.HomeShort else "BASE"
local STEAL_SUB: string? = if type(ROW_ANY.Steal) == "string" then ROW_ANY.Steal else nil -- "BAG · %s" (distance)
OpsJobs.EmptyText = if type(ROW_ANY.Empty) == "string" then ROW_ANY.Empty else nil
OpsJobs.PingTtl = if type(UI_ANY.PingTtlSeconds) == "number" then UI_ANY.PingTtlSeconds else OpsConfig.Remote.PingSeconds * 2.5

OpsJobs.HomeId = "@home"
OpsJobs.BagPrefix = "@bag:"

---------------------------------------------------------------------------------------------------------------
-- formatting
---------------------------------------------------------------------------------------------------------------

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -1e7 and n < 1e7
end

--[[ "$36K" / "$1.2M" / "$900" (whole dollars; the JOBS sub-line). ]]
function OpsJobs.Money(n: number): string
	local a = math.abs(n)
	if a >= 1e6 then
		local s = string.format("%.1f", n / 1e6)
		if string.sub(s, -2) == ".0" then
			s = string.sub(s, 1, -3)
		end
		return "$" .. s .. "M"
	elseif a >= 1e3 then
		local s = string.format("%.1f", n / 1e3)
		if string.sub(s, -2) == ".0" then
			s = string.sub(s, 1, -3)
		end
		return "$" .. s .. "K"
	end
	return "$" .. tostring(math.floor(n))
end

--[[ "4:10" (m:ss), "1:02:03" past an hour. ]]
function OpsJobs.Clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

--[[ "95m" under 1 km, "1.2km" above (the compass chip's format; 1 stud reads as 1 m). ]]
function OpsJobs.Dist(studs: number): string
	if studs < 1000 then
		return string.format("%dm", math.floor(studs))
	end
	return string.format("%.1fkm", studs / 1000)
end

-- seconds still left of a timer that had `secs` left at `at`
function OpsJobs.Remaining(secs: number?, at: number, now: number?): number
	if secs == nil or not finite(secs) then
		return 0
	end
	if now == nil then
		return math.max(0, secs)
	end
	return math.max(0, secs - math.max(0, now - at))
end
local remaining = OpsJobs.Remaining

local function dropSep(s: string): string
	if string.sub(s, -#SEP) == SEP then
		return string.sub(s, 1, -#SEP - 1)
	end
	return s
end

--[[ The JOBS row sub-line for one site (OpsConfig.Text.Row). distStuds < 0 = unknown distance. ]]
function OpsJobs.Sub(site: SiteEntry, def: OpsConfig.SiteDef, distStuds: number, now: number?): string
	local at = site.At or 0
	local mine = remaining(site.MyCd, at, now)
	if mine > 0 then
		return string.format(ROW.Mine, OpsJobs.Clock(mine))
	end
	local st = site.State
	if st == "Cooling" or st == "Closed" then
		local left = remaining(site.Left, at, now)
		if left > 0 then
			return string.format(ROW.Closed, OpsJobs.Clock(left))
		end
		return TEXT.LabelSub.Closed
	elseif st == "Held" then
		return ROW.Held
	elseif st == "Quiet" then
		return TEXT.LabelSub.Quiet
	elseif st == "Active" then
		return ROW.Active
	end
	local d = if distStuds >= 0 then OpsJobs.Dist(distStuds) else ""
	local pay = if site.Pay ~= nil and finite(site.Pay) and site.Pay > 0 then OpsJobs.Money(site.Pay) else ""
	local s = string.format(ROW.Open, d, pay)
	s = string.gsub(s, SEP .. SEP, SEP) -- no distance: "OPEN · $36K", never "OPEN ·  · $36K"
	s = dropSep(s)
	if d == "" then
		s = dropSep(s)
	end
	return s
end

---------------------------------------------------------------------------------------------------------------
-- cache
---------------------------------------------------------------------------------------------------------------

function OpsJobs.NewCache(): Cache
	return {
		Sites = {},
		Home = nil,
		Carrying = nil,
		CarryAt = 0,
		Bags = {},
		Pings = {},
		Full = false,
		Version = 0,
	}
end

local function num(v: any): number?
	if finite(v) then
		return v
	end
	return nil
end

--[[ Merge one OpsState payload (shape checked field by field: a client never trusts a payload's shape). Unknown
	site ids (not in OpsConfig) are ignored. false = rejected (not a table / no Sites list). ]]
function OpsJobs.Merge(cache: Cache, payload: any, now: number): boolean
	if type(payload) ~= "table" or type(payload.Sites) ~= "table" then
		return false
	end
	local full = payload.Full == true
	if full then
		cache.Sites = {}
		cache.Full = true
		local h = payload.Home
		if type(h) == "table" and finite(h.X) and finite(h.Z) then
			cache.Home = { X = h.X, Z = h.Z }
		end
	end
	local sites = cache.Sites
	for i, s in ipairs(payload.Sites) do
		if i > MAX_SITES then
			break
		end
		if type(s) == "table" and type(s.Id) == "string" and type(s.State) == "string" and OpsConfig.Get(s.Id) ~= nil then
			if s.State == "Off" then
				sites[s.Id] = nil
			else
				local old = sites[s.Id]
				local e: SiteEntry = {
					Id = s.Id,
					State = s.State,
					X = num(s.X) or (old and old.X),
					Y = num(s.Y) or (old and old.Y),
					Z = num(s.Z) or (old and old.Z),
					Left = num(s.Left),
					Pay = num(s.Pay),
					MyCd = num(s.MyCd),
					Guards = num(s.Guards),
					HeldBy = num(s.HeldBy),
					At = now,
				}
				sites[s.Id] = e
			end
		end
	end
	-- Carrying and Bags ride on EVERY payload (nil Carrying = not carrying)
	local c = payload.Carrying
	if type(c) == "table" and type(c.Site) == "string" and finite(c.Left) then
		cache.Carrying = {
			Site = c.Site,
			Kind = if type(c.Kind) == "string" then c.Kind else "",
			Value = num(c.Value) or 0,
			Left = c.Left,
			Picked = c.Picked == true,
		}
		cache.CarryAt = now
	else
		cache.Carrying = nil
	end
	local bags: { OpsConfig.OpsBagSnap } = {}
	if type(payload.Bags) == "table" then
		for i, b in ipairs(payload.Bags) do
			if i > MAX_BAGS then
				break
			end
			if type(b) == "table" and finite(b.U) and finite(b.X) and finite(b.Z) then
				table.insert(bags, {
					U = b.U,
					X = b.X,
					Z = b.Z,
					Age = num(b.Age) or 0,
					Site = if type(b.Site) == "string" then b.Site else "",
				})
			end
		end
	end
	cache.Bags = bags
	cache.Version += 1
	return true
end

--[[ One OpsPing (a bag carrier's position; the server sends it only to non-allies). Old pings expire after PingTtl. ]]
function OpsJobs.AddPing(cache: Cache, payload: any, now: number, userId: number): boolean
	if type(payload) ~= "table" or not (finite(payload.U) and finite(payload.X) and finite(payload.Z)) then
		return false
	end
	if payload.U == userId then
		return false
	end
	for u, p in pairs(cache.Pings) do
		if now - p.At > OpsJobs.PingTtl then
			cache.Pings[u] = nil
		end
	end
	cache.Pings[payload.U] = { X = payload.X, Z = payload.Z, At = now }
	cache.Version += 1
	return true
end

--[[ Drop pings older than PingTtl; true when one went (the board changes). ]]
function OpsJobs.ExpirePings(cache: Cache, now: number): boolean
	local any = false
	for u, p in pairs(cache.Pings) do
		if now - p.At > OpsJobs.PingTtl then
			cache.Pings[u] = nil
			any = true
		end
	end
	if any then
		cache.Version += 1
	end
	return any
end

---------------------------------------------------------------------------------------------------------------
-- resolving
---------------------------------------------------------------------------------------------------------------

--[[ A job you can go and do now: open (Dormant / Open / Active: RAID ON may be joined), not on your own cooldown and
	with a known point. Held / Cooling / Closed / Quiet never are. ]]
function OpsJobs.Available(e: SiteEntry, now: number?): boolean
	return OPEN_STATES[e.State] == true and remaining(e.MyCd, e.At, now) <= 0 and e.X ~= nil and e.Z ~= nil
end
local available = OpsJobs.Available

local function dist2(me: Me?, x: number, z: number): number
	if me == nil then
		return 0
	end
	local dx, dz = x - me.X, z - me.Z
	return dx * dx + dz * dz
end

function OpsJobs.SiteGo(e: SiteEntry, def: OpsConfig.SiteDef): Point?
	if e.X == nil or e.Z == nil then
		return nil
	end
	return { Short = def.Short, X = e.X :: number, Y = e.Y or FLOOR_Y, Z = e.Z :: number }
end

--[[ Your own delivery point (server: your plot's centre moved toward the front gate; Pool_Town with no plot). ]]
function OpsJobs.HomeGo(cache: Cache): Point?
	local h = cache.Home
	if h == nil then
		return nil
	end
	return { Short = OpsJobs.HomeShort, X = h.X, Y = FLOOR_Y, Z = h.Z }
end

local function carryShort(siteId: string): string
	local def = OpsConfig.Get(siteId)
	local k = def and OpsConfig.Kinds[def.Kind]
	local label = k and k.CarryLabel
	if type(label) == "string" and string.match(label, "^[A-Z]+$") and #label <= 7 then
		return label
	end
	return "BAG"
end

type Steal = { U: number, X: number, Z: number, Short: string }

-- somebody else's bags: dropped ones (from OpsState) and carriers seen on OpsPing, nearest first
local function steals(cache: Cache, userId: number, me: Me?, now: number?): { Steal }
	local out: { Steal } = {}
	local seen: { [number]: boolean } = {}
	for _, b in ipairs(cache.Bags) do
		if b.U ~= userId and not seen[b.U] then
			seen[b.U] = true
			table.insert(out, { U = b.U, X = b.X, Z = b.Z, Short = carryShort(b.Site) })
		end
	end
	for u, p in pairs(cache.Pings) do
		if u ~= userId and not seen[u] and (now == nil or now - p.At <= OpsJobs.PingTtl) then
			seen[u] = true
			table.insert(out, { U = u, X = p.X, Z = p.Z, Short = "BAG" })
		end
	end
	table.sort(out, function(a: Steal, b: Steal): boolean
		local da, db = dist2(me, a.X, a.Z), dist2(me, b.X, b.Z)
		if da ~= db then
			return da < db
		end
		return a.U < b.U
	end)
	return out
end

--[[ The current point of a tracked id (nil = it is gone / not available now). ]]
function OpsJobs.GoFor(cache: Cache, id: string, me: Me?, userId: number, now: number?): Point?
	if id == OpsJobs.HomeId then
		if cache.Carrying == nil then
			return nil
		end
		return OpsJobs.HomeGo(cache)
	end
	if string.sub(id, 1, #OpsJobs.BagPrefix) == OpsJobs.BagPrefix then
		local u = tonumber(string.sub(id, #OpsJobs.BagPrefix + 1))
		if u == nil then
			return nil
		end
		for _, s in ipairs(steals(cache, userId, me, now)) do
			if s.U == u then
				return { Short = s.Short, X = s.X, Y = FLOOR_Y, Z = s.Z }
			end
		end
		return nil
	end
	local e = cache.Sites[id]
	local def = OpsConfig.Get(id)
	if e == nil or def == nil or not available(e, now) then
		return nil
	end
	return OpsJobs.SiteGo(e, def)
end

--[[ The nearest OTHER open site doing the same job (same Title: "Take Checkpoint" at any of the 12 posts). ]]
function OpsJobs.NearestLike(cache: Cache, id: string, me: Me?, now: number?): string?
	local def = OpsConfig.Get(id)
	if def == nil then
		return nil
	end
	local best: string? = nil
	local bestD = math.huge
	for sid, e in pairs(cache.Sites) do
		if sid ~= id and available(e, now) then
			local d2 = OpsConfig.Get(sid)
			if d2 and d2.Title == def.Title then
				local d = dist2(me, e.X :: number, e.Z :: number)
				if d < bestD or (d == bestD and best ~= nil and sid < best) then
					best, bestD = sid, d
				end
			end
		end
	end
	return best
end

local function siteRow(e: SiteEntry, def: OpsConfig.SiteDef, me: Me?, trackedId: string?, now: number?): Row
	local d = if me and e.X and e.Z then math.sqrt(dist2(me, e.X :: number, e.Z :: number)) else -1
	return {
		Id = e.Id,
		Title = def.Title,
		Sub = OpsJobs.Sub(e, def, d, now),
		Hard = def.Hard,
		Go = if available(e, now) then OpsJobs.SiteGo(e, def) else nil,
		Tracked = trackedId == e.Id,
		Kind = def.Kind,
		Dist = if d >= 0 then d else nil,
	}
end

local function stealRow(s: Steal, me: Me?, trackedId: string?): Row
	local id = OpsJobs.BagPrefix .. tostring(s.U)
	local d = if me then math.sqrt(dist2(me, s.X, s.Z)) else -1
	local dt = if d >= 0 then OpsJobs.Dist(d) else ""
	return {
		Id = id,
		Title = ROW.StealTitle,
		Sub = if STEAL_SUB then string.format(STEAL_SUB, dt) else dt,
		Hard = true,
		Go = { Short = s.Short, X = s.X, Y = FLOOR_Y, Z = s.Z },
		Tracked = trackedId == id,
		Steal = true,
		Kind = "Steal",
		Dist = if d >= 0 then d else nil,
	}
end

type Cand = { E: SiteEntry, Def: OpsConfig.SiteDef, D: number }

--[[ The JOBS rows (at most Ui.Jobs.Rows). `me`: where distances are measured from (nil: unknown). ]]
function OpsJobs.Rows(cache: Cache, me: Me?, trackedId: string?, userId: number, now: number?): { Row }
	local rows: { Row } = {}
	if not cache.Full then
		return rows
	end
	local used: { [string]: boolean } = {}

	-- open sites, nearest first (ties by id: stable)
	local open: { Cand } = {}
	local bank: Cand? = nil
	for id, e in pairs(cache.Sites) do
		local def = OpsConfig.Get(id)
		if def then
			local d = if e.X and e.Z then dist2(me, e.X :: number, e.Z :: number) else math.huge
			if def.Pinned == true then
				bank = { E = e, Def = def, D = d }
			end
			if available(e, now) then
				table.insert(open, { E = e, Def = def, D = d })
			end
		end
	end
	table.sort(open, function(a: Cand, b: Cand): boolean
		if a.D ~= b.D then
			return a.D < b.D
		end
		return a.E.Id < b.E.Id
	end)

	-- 1. the carried job (GO = your own Home) or the tracked job
	local carry = cache.Carrying
	if carry then
		local def = OpsConfig.Get(carry.Site)
		local h = cache.Home
		local d = if me and h then math.sqrt(dist2(me, h.X, h.Z)) else -1
		local left = remaining(carry.Left, cache.CarryAt, now)
		table.insert(rows, {
			Id = OpsJobs.HomeId,
			Title = if def then def.Title else TEXT.Card.Carry,
			Sub = string.format(TEXT.Card.CarryHint, OpsJobs.Clock(left)),
			Hard = if def then def.Hard else true,
			Go = OpsJobs.HomeGo(cache),
			Tracked = trackedId == OpsJobs.HomeId,
			Kind = "Home",
			Dist = if d >= 0 then d else nil,
		})
		used[OpsJobs.HomeId] = true
		used[carry.Site] = true
	elseif trackedId ~= nil then
		if string.sub(trackedId, 1, #OpsJobs.BagPrefix) == OpsJobs.BagPrefix then
			for _, s in ipairs(steals(cache, userId, me, now)) do
				if OpsJobs.BagPrefix .. tostring(s.U) == trackedId then
					table.insert(rows, stealRow(s, me, trackedId))
					used[trackedId] = true
					break
				end
			end
		else
			local e = cache.Sites[trackedId]
			local def = OpsConfig.Get(trackedId)
			if e and def then
				table.insert(rows, siteRow(e, def, me, trackedId, now))
				used[trackedId] = true
			end
		end
	end

	-- 2. the nearest open job
	local nextOpen = 1
	local function takeOpen(): Row?
		while nextOpen <= #open do
			local c = open[nextOpen]
			nextOpen += 1
			if not used[c.E.Id] then
				used[c.E.Id] = true
				return siteRow(c.E, c.Def, me, trackedId, now)
			end
		end
		return nil
	end
	-- the bank with its countdown: only when nothing else is open to fill the row
	local function bankCountdown(): Row?
		local b = bank
		if b and not used[b.E.Id] then
			used[b.E.Id] = true
			return siteRow(b.E, b.Def, me, trackedId, now)
		end
		return nil
	end
	if #rows < MAX_ROWS then
		local r = takeOpen()
		if r then
			table.insert(rows, r)
		end
	end

	-- 3. ONE row: somebody else's bag > the open bank > the next-nearest open job > the bank's countdown
	if #rows < MAX_ROWS then
		local r: Row? = nil
		for _, s in ipairs(steals(cache, userId, me, now)) do
			local id = OpsJobs.BagPrefix .. tostring(s.U)
			if not used[id] then
				used[id] = true
				r = stealRow(s, me, trackedId)
				break
			end
		end
		local b = bank
		if r == nil and b and not used[b.E.Id] and available(b.E, now) then
			used[b.E.Id] = true
			r = siteRow(b.E, b.Def, me, trackedId, now)
		end
		if r == nil then
			r = takeOpen() or bankCountdown()
		end
		if r then
			table.insert(rows, r)
		end
	end

	-- no tracked / carried job: the free row is the next-nearest open job
	while #rows < MAX_ROWS do
		local r = takeOpen() or bankCountdown()
		if r == nil then
			break
		end
		table.insert(rows, r)
	end
	return rows
end

return OpsJobs
