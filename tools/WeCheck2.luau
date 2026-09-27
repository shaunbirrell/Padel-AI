-- WE_CHECK2: WAR EMPIRE second model check (read-only). Run it in the live place through Open Cloud Luau Execution.
-- Each id is loaded, measured and destroyed; the lines print at the end. Nothing is parented, saved or published,
-- and every step runs inside pcall. Copy back every line that starts with WE_CHECK2. The last line says DONE.
-- The ids are the 11 owner picks the first check (WE_CHECK, 2026-09-25) passed but did not settle; no refused id.
local IDS = {
	3553891209, -- FighterJet family (vehicles)
	2474869838, -- LightScoutHeli + UtilityHeli (vehicles)
	9076240315, -- APC family (vehicles)
	8546141386, -- ArmoredTruck family (vehicles, owner yes/no #2)
	4954987035, -- ReconPlane (vehicles, owner yes/no #4)
	15838664806, -- Gunboat family (vehicles, the 2,048-stud part)
	6980242709, -- Buildings.DefensiveWalls (walls)
	13183571527, -- Buildings.Dock (walls, not blocking)
	5318635087, -- FuelTanker (trim)
	8455894899, -- FlatbedHauler (trim)
	11357157285, -- RescueHeli + MedevacHeli (trim)
}
local MAX_PARTS = 80 -- part lines per model, biggest first
local MAX_ROWS = { SEAT = 6, CAM = 3, FX = 6, BRAND = 8, SUB = 10, HINT = 8 } -- other lines per model, most useful first
local MAX_LINES, MAX_BYTES = 400, 300000 -- other lines share what part lines leave (Open Cloud keeps 450 KB of log)

local IS, AS = game:GetService("InsertService"), game:GetService("AssetService")
-- the game's loader deletes these (and everything inside them) before it counts parts
local STRIP = { Humanoid = true, Tool = true, Seat = true, VehicleSeat = true, SpawnLocation = true, ProximityPrompt = true,
	ClickDetector = true, DragDetector = true, Sound = true, ForceField = true, WeldConstraint = true, NoCollisionConstraint = true }
local STRIP_BASES = { "Constraint", "BodyMover", "JointInstance", "LuaSourceContainer" }
local FXC = { ParticleEmitter = true, Fire = true, Smoke = true, Sparkles = true, Beam = true, Trail = true }
local LIGHTS = { PointLight = true, SpotLight = true, SurfaceLight = true }
local JOINTS = { Weld = true, Motor6D = true, Motor = true, Snap = true, ManualWeld = true, Glue = true, ManualGlue = true,
	Rotate = true, RotateP = true, RotateV = true, VelocityMotor = true }
local UNIONS = { UnionOperation = true, IntersectOperation = true, NegateOperation = true }
local MESHES = { SpecialMesh = true, FileMesh = true, BlockMesh = true, CylinderMesh = true }
local TEXTS = { TextLabel = true, TextButton = true, TextBox = true }
local IMAGES = { ImageLabel = true, ImageButton = true }
local KW = { "light", "lamp", "wind", "glass", "front", "nose", "cockpit", "canopy", "rear", "back", "tail", "exhaust", "head",
	"bow", "stern", "hull", "deck", "water", "sea", "ocean", "wave", "rotor", "blade", "prop", "wheel", "tire", "tyre", "track",
	"cab", "gun", "barrel", "turret", "wing", "logo", "flag", "sign", "text", "label", "decal", "brand" }
local SKIP = { sea = "seat", tail = "detail", cab = "cable", bow = "elbow", back = "backg", text = "texture", prop = "propert",
	head = "overhead", sign = "design" }

local PRIORITY = { SEAT = 1, CAM = 2, FX = 3, BRAND = 4, SUB = 5, HINT = 6 }
type Row = { kind: string, body: string, detail: boolean, keep: boolean, seq: number }
type Rec = { id: number, rows: { Row }, used: { [string]: number }, cut: { [string]: number } }
local total = { lines = 0, bytes = 0, ok = 0, fail = 0, err = 0 }
local recs: { Rec } = {}
local cur: Rec = { id = 0, rows = {}, used = {}, cut = {} }

local function out(id: number, kind: string, body: string)
	local line = string.format("WE_CHECK2 %d %s", id, kind) .. (if body ~= "" then " " .. body else "")
	total.lines += 1
	total.bytes += #line + 1
	print(line)
end
-- collects a line for the current model; detail lines past their per-model cap are counted as cut
local function emit(kind: string, body: string, detail: boolean?)
	if detail then
		local cap = if kind == "P" then MAX_PARTS else (MAX_ROWS[kind] or 0)
		cur.used[kind] = (cur.used[kind] or 0) + 1
		if cur.used[kind] > cap then
			cur.cut[kind] = (cur.cut[kind] or 0) + 1
			return
		end
	end
	table.insert(cur.rows, { kind = kind, body = body, detail = detail == true, keep = true, seq = #cur.rows + 1 })
end

local function n(x: number): string
	if x ~= x then
		return "nan"
	elseif math.abs(x) == math.huge then
		return if x > 0 then "inf" else "-inf"
	end
	local s = string.format("%.2f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return if s == "-0" then "0" else s
end
local function v3(v: Vector3): string
	return n(v.X) .. "," .. n(v.Y) .. "," .. n(v.Z)
end
local function eul(cf: CFrame): string
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	return n(math.deg(rx)) .. "," .. n(math.deg(ry)) .. "," .. n(math.deg(rz))
end
local function axis(d: Vector3): string
	local ax, ay, az = math.abs(d.X), math.abs(d.Y), math.abs(d.Z)
	if ax >= ay and ax >= az then
		return if d.X >= 0 then "+X" else "-X"
	elseif ay >= az then
		return if d.Y >= 0 then "+Y" else "-Y"
	end
	return if d.Z >= 0 then "+Z" else "-Z"
end
local function clean(s: any, max: number): string
	local t = string.gsub(tostring(s), "%c", " ")
	if #t > max then
		t = string.gsub(string.sub(t, 1, max - 2), "[\192-\255][\128-\191]*$", "") .. ".."
	end
	return t
end
local function q(s: any, max: number): string
	local t = string.gsub(clean(s, max), "\\", "\\\\")
	t = string.gsub(t, '"', '\\"')
	return '"' .. t .. '"'
end
-- names from just below the container down to d, joined by "/" (left part cut when long)
local function qpath(d: Instance?, top: Instance, max: number): string
	local names = {}
	local x = d
	while x and x ~= top do
		table.insert(names, 1, x.Name)
		x = x.Parent
	end
	local s = string.gsub(table.concat(names, "/"), "%c", " ")
	if #s > max then
		s = ".." .. string.gsub(string.sub(s, -(max - 2)), "^[\128-\191]+", "")
	end
	return q(s, max + 2)
end
local function getp(o: Instance, k: string): any
	local ok, v = pcall(function()
		return (o :: any)[k]
	end)
	return if ok then v else nil
end
-- a content id as its number, or the last part of its path when it has no number (a built-in file)
local function cid(v: any): string
	local s = tostring(v or "")
	local num = string.match(s, "%d%d%d+")
	if num then
		return num
	end
	return if s == "" then "-" else q(string.match(s, "([^/]*)$") or s, 20)
end
local function kw(name: string): string?
	local l = string.lower(name)
	local hit = {}
	for _, w in ipairs(KW) do
		if #hit < 3 and string.find(l, w, 1, true) and not (SKIP[w] and string.find(l, SKIP[w], 1, true)) then
			table.insert(hit, w)
		end
	end
	return if #hit > 0 then table.concat(hit, ",") else nil
end
local function strips(x: Instance): boolean
	if STRIP[x.ClassName] then
		return true
	end
	for _, b in ipairs(STRIP_BASES) do
		if x:IsA(b) then
			return true
		end
	end
	return false
end
local function loaderDrops(d: Instance, top: Instance): boolean
	local x: Instance? = d
	while x and x ~= top do
		if strips(x) then
			return true
		end
		x = x.Parent
	end
	return false
end
-- world-axis box of one part (the same sums the game's vehicle fit uses)
local function pbox(p: BasePart): (Vector3, Vector3)
	local cf, h = p.CFrame, p.Size * 0.5
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local e = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
	return cf.Position - e, cf.Position + e
end
local function hex(c: Color3): string
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function check(m: Instance, via: string): boolean
	local all = m:GetDescendants()
	local c = { parts = 0, loader = 0, mesh = 0, union = 0, sm = 0, neon = 0, seats = 0, lights = 0, fx = 0, scripts = 0,
		hum = 0, tools = 0, snd = 0, dec = 0, tex = 0, sgui = 0, bgui = 0, txt = 0, img = 0, sa = 0, att = 0, cons = 0, joints = 0,
		cams = 0, prompts = 0 }
	local plist, keep, seats, others = {}, {}, {}, {}
	for i, d in ipairs(all) do
		local cls = d.ClassName
		if d:IsA("BasePart") then
			local p = d :: BasePart
			local drop = loaderDrops(p, m)
			c.parts += 1
			if not drop then
				c.loader += 1
				table.insert(keep, p)
			end
			if cls == "MeshPart" then c.mesh += 1 end
			if UNIONS[cls] or p:IsA("PartOperation") then c.union += 1 end
			if p.Material == Enum.Material.Neon then c.neon += 1 end
			if cls == "Seat" or cls == "VehicleSeat" then
				c.seats += 1
				table.insert(seats, p)
			end
			table.insert(plist, { p = p, i = i, v = p.Size.X * p.Size.Y * p.Size.Z, drop = drop })
		else
			table.insert(others, d)
			if MESHES[cls] or d:IsA("DataModelMesh") then c.sm += 1 end
			if LIGHTS[cls] or d:IsA("Light") then c.lights += 1 end
			if FXC[cls] then c.fx += 1 end
			if d:IsA("LuaSourceContainer") then c.scripts += 1 end
			if cls == "Humanoid" then c.hum += 1 end
			if cls == "Tool" then c.tools += 1 end
			if cls == "Sound" then c.snd += 1 end
			if cls == "Decal" then c.dec += 1 end
			if cls == "Texture" then c.tex += 1 end
			if cls == "SurfaceGui" then c.sgui += 1 end
			if cls == "BillboardGui" then c.bgui += 1 end
			if TEXTS[cls] then c.txt += 1 end
			if IMAGES[cls] then c.img += 1 end
			if cls == "SurfaceAppearance" then c.sa += 1 end
			if cls == "Attachment" then c.att += 1 end
			if d:IsA("Constraint") or string.find(cls, "Constraint$") then c.cons += 1 end
			if JOINTS[cls] or d:IsA("JointInstance") then c.joints += 1 end
			if cls == "Camera" then c.cams += 1 end
			if cls == "ProximityPrompt" or cls == "ClickDetector" or cls == "DragDetector" then c.prompts += 1 end
		end
	end
	emit("HEAD", string.format("via=%s parts=%d loader=%d mesh=%d union=%d spm=%d neon=%d seats=%d lights=%d fx=%d scripts=%d hum=%d tools=%d snd=%d dec=%d tex=%d sgui=%d bgui=%d txt=%d img=%d sa=%d att=%d cons=%d joints=%d cams=%d prompts=%d desc=%d",
		via, c.parts, c.loader, c.mesh, c.union, c.sm, c.neon, c.seats, c.lights, c.fx, c.scripts, c.hum, c.tools, c.snd, c.dec,
		c.tex, c.sgui, c.bgui, c.txt, c.img, c.sa, c.att, c.cons, c.joints, c.cams, c.prompts, #all))

	-- the box of the parts the game keeps (the box it fits and scales); at= and top= below are measured from it
	local function boxOf(list: { BasePart }): (Vector3, Vector3)
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		for _, p in ipairs(list) do
			local a, b = pbox(p)
			lo, hi = lo:Min(a), hi:Max(b)
		end
		return lo, hi
	end
	local allParts = {}
	for _, r in ipairs(plist) do
		table.insert(allParts, r.p)
	end
	local lo, hi = boxOf(if #keep > 0 then keep else allParts)
	local ctr = Vector3.zero
	if #allParts == 0 then
		emit("BOX", "none=1")
	else
		ctr = (lo + hi) * 0.5
		local alo, ahi = boxOf(allParts)
		local sz = hi - lo
		emit("BOX", "size=" .. v3(sz) .. " min=" .. v3(lo) .. " max=" .. v3(hi) .. " long=" .. string.sub(axis(sz), 2)
			.. " all=" .. v3(ahi - alo) .. " kept=" .. (if #keep > 0 then "loader" else "all"))
	end

	-- the container and the model inside it: pivot, PrimaryPart, bounding box, extents
	local kids = m:GetChildren()
	local main: Instance = m
	if #kids == 1 and kids[1]:IsA("Model") then
		main = kids[1]
	end
	local mainPivot: CFrame? = nil
	local shown: { Instance } = if main ~= m then { m, main } else { m }
	for _, x in ipairs(shown) do
		local names = {}
		for i, k in ipairs(x:GetChildren()) do
			if i <= 6 then
				table.insert(names, k.ClassName .. ":" .. clean(k.Name, 24))
			end
		end
		local okP, piv = pcall(function()
			return (x :: any):GetPivot()
		end)
		local okB, bcf, bsz = pcall(function()
			return (x :: any):GetBoundingBox()
		end)
		local okE, ext = pcall(function()
			return (x :: any):GetExtentsSize()
		end)
		local pp = getp(x, "PrimaryPart")
		local body = q(if x == m then "container" else "main", 12) .. " path=" .. qpath(x, m, 40) .. " c=" .. x.ClassName
			.. " kids=" .. #x:GetChildren() .. " names=" .. q(table.concat(names, "|"), 90)
			.. " pp=" .. (if typeof(pp) == "Instance" then q(pp.Name, 30) else "-")
		if okP and typeof(piv) == "CFrame" then
			body ..= " piv=" .. v3(piv.Position - ctr) .. " pivr=" .. eul(piv)
			if x == main then
				mainPivot = piv
			end
		end
		if okB and typeof(bcf) == "CFrame" and typeof(bsz) == "Vector3" then
			local off = if okP and typeof(piv) == "CFrame" then bcf.Position - piv.Position else bcf.Position - ctr
			body ..= " bbo=" .. v3(off) .. " bbr=" .. eul(bcf) .. " bbs=" .. v3(bsz)
		end
		if okE and typeof(ext) == "Vector3" then
			body ..= " ext=" .. v3(ext)
		end
		emit("MODEL", body)
	end

	-- one line per part, biggest volume first
	table.sort(plist, function(a, b)
		if a.v ~= b.v then
			return a.v > b.v
		end
		return a.i < b.i
	end)
	local late = {}
	for rank, r in ipairs(plist) do
		local p = r.p
		local cls = p.ClassName
		local _, b = pbox(p)
		local name = p.Name
		local body = rank .. " " .. q(name, 36) .. " c=" .. cls .. " s=" .. v3(p.Size) .. " at=" .. v3(p.Position - ctr)
			.. " top=" .. n(b.Y - lo.Y) .. " r=" .. v3(p.Orientation) .. " lk=" .. axis(p.CFrame.LookVector)
			.. " up=" .. axis(p.CFrame.UpVector) .. " m=" .. p.Material.Name .. " col=" .. hex(p.Color) .. " t=" .. n(p.Transparency)
			.. " in=" .. qpath(p.Parent, m, 40)
		if r.drop then
			body ..= " x=1"
		end
		if cls == "Part" then
			local sh = getp(p, "Shape")
			if typeof(sh) == "EnumItem" and sh.Name ~= "Block" then
				body ..= " sh=" .. sh.Name
			end
		end
		local k = kw(name)
		if k then
			body ..= " kw=" .. k
		end
		if cls == "MeshPart" then
			local ms = getp(p, "MeshSize")
			if typeof(ms) == "Vector3" then
				body ..= " ms=" .. v3(ms)
			end
			body ..= " mesh=" .. cid(getp(p, "MeshId")) .. " tex=" .. cid(getp(p, "TextureID"))
		end
		for _, ch in ipairs(p:GetChildren()) do
			if MESHES[ch.ClassName] or ch:IsA("DataModelMesh") then
				local mt = getp(ch, "MeshType")
				local sc = getp(ch, "Scale")
				body ..= " sm=" .. (if typeof(mt) == "EnumItem" then mt.Name else ch.ClassName) .. " mesh=" .. cid(getp(ch, "MeshId"))
					.. " tex=" .. cid(getp(ch, "TextureId")) .. (if typeof(sc) == "Vector3" then " sc=" .. v3(sc) else "")
				break
			end
		end
		if rank > MAX_PARTS and k then
			table.insert(late, { p = p, k = k })
		end
		emit("P", body, true)
	end

	-- seats: where the driver sits and which way they face (world axes, and in the inner model's pivot frame)
	for _, p in ipairs(seats) do
		local _, b = pbox(p)
		local look = p.CFrame.LookVector
		local body = q(p.Name, 36) .. " c=" .. p.ClassName .. " at=" .. v3(p.Position - ctr) .. " top=" .. n(b.Y - lo.Y)
			.. " lv=" .. v3(look) .. " ax=" .. axis(look) .. " up=" .. axis(p.CFrame.UpVector)
		if mainPivot then
			body ..= " pv=" .. v3(mainPivot:PointToObjectSpace(p.Position)) .. " lvp=" .. v3(mainPivot:VectorToObjectSpace(look))
		end
		emit("SEAT", body .. " in=" .. qpath(p.Parent, m, 40), true)
	end

	-- sub-models and folders with 2+ kept parts (what a ChildName / SubModel could pick)
	local subs: { [Instance]: any }, order = {}, {}
	for _, p in ipairs(keep) do
		local a, b = pbox(p)
		local x = p.Parent
		while x and x ~= m do
			if x:IsA("Model") or x:IsA("Folder") then
				local s = subs[x]
				if not s then
					s = { n = 0, lo = a, hi = b, x = x }
					subs[x] = s
					table.insert(order, s)
				end
				s.n += 1
				s.lo, s.hi = s.lo:Min(a), s.hi:Max(b)
			end
			x = x.Parent
		end
	end
	table.sort(order, function(a, b)
		if a.n ~= b.n then
			return a.n > b.n
		end
		return a.x:GetFullName() < b.x:GetFullName()
	end)
	for _, s in ipairs(order) do
		if s.n >= 2 then
			local k = kw(s.x.Name)
			emit("SUB", qpath(s.x, m, 50) .. " c=" .. s.x.ClassName .. " n=" .. s.n .. " ext=" .. v3(s.hi - s.lo)
				.. " at=" .. v3((s.lo + s.hi) * 0.5 - ctr) .. (if k then " kw=" .. k else ""), true)
		end
	end

	-- other objects whose names hint at a side (front, tail, light...), plus keyword parts past the part-line cap
	for _, x in ipairs(late) do
		emit("HINT", q(x.p.Name, 36) .. " c=" .. x.p.ClassName .. " kw=" .. x.k .. " at=" .. v3(x.p.Position - ctr)
			.. " in=" .. qpath(x.p.Parent, m, 40), true)
	end
	for _, d in ipairs(others) do
		local k = kw(d.Name)
		local s = subs[d]
		if k and not (s and s.n >= 2) then
			local pos: Vector3? = nil
			if s then
				pos = (s.lo + s.hi) * 0.5
			elseif d:IsA("Attachment") then
				local wp = getp(d, "WorldPosition")
				if typeof(wp) == "Vector3" then
					pos = wp
				end
			end
			emit("HINT", q(d.Name, 36) .. " c=" .. d.ClassName .. " kw=" .. k .. (if pos then " at=" .. v3(pos - ctr) else "")
				.. " in=" .. qpath(d.Parent, m, 40), true)
		end
	end

	-- effects and lights, grouped by class and holder; brand check: decals, textures, gui text and images
	local fx, fxOrder, br, brOrder = {}, {}, {}, {}
	for _, d in ipairs(others) do
		local cls = d.ClassName
		if FXC[cls] or LIGHTS[cls] or d:IsA("Light") then
			local par = d.Parent
			local key = cls .. "|" .. (if par then par:GetFullName() else "")
			if not fx[key] then
				fx[key] = { n = 0, d = d }
				table.insert(fxOrder, key)
			end
			fx[key].n += 1
		end
		local val: string? = nil
		if cls == "Decal" or cls == "Texture" then
			local face = getp(d, "Face")
			val = "tex=" .. cid(getp(d, "Texture")) .. (if typeof(face) == "EnumItem" then " face=" .. face.Name else "")
		elseif cls == "SurfaceAppearance" then
			val = "tex=" .. cid(getp(d, "ColorMap"))
		elseif TEXTS[cls] then
			val = "text=" .. q(getp(d, "Text") or "", 60)
		elseif IMAGES[cls] then
			val = "img=" .. cid(getp(d, "Image"))
		elseif cls == "SurfaceGui" or cls == "BillboardGui" then
			local face = getp(d, "Face")
			val = "kids=" .. #d:GetDescendants() .. (if typeof(face) == "EnumItem" then " face=" .. face.Name else "")
		end
		if val then
			local key = cls .. "|" .. val
			if not br[key] then
				br[key] = { n = 0, d = d, val = val }
				table.insert(brOrder, key)
			end
			br[key].n += 1
		end
	end
	for _, key in ipairs(fxOrder) do
		local e = fx[key]
		emit("FX", "c=" .. e.d.ClassName .. " n=" .. e.n .. " on=" .. qpath(e.d.Parent, m, 60), true)
	end
	for _, key in ipairs(brOrder) do
		local e = br[key]
		emit("BRAND", "c=" .. e.d.ClassName .. " n=" .. e.n .. " " .. e.val .. " on=" .. qpath(e.d.Parent, m, 60), true)
	end
	for _, d in ipairs(others) do
		if d.ClassName == "Camera" then
			local cf = getp(d, "CFrame")
			if typeof(cf) == "CFrame" then
				emit("CAM", q(d.Name, 36) .. " lv=" .. v3(cf.LookVector) .. " ax=" .. axis(cf.LookVector) .. " at=" .. v3(cf.Position - ctr), true)
			else
				emit("CAM", q(d.Name, 36), true)
			end
		end
	end
	return true
end

local function load(id: number): (Instance?, string, string)
	local ok, m = pcall(function()
		return IS:LoadAsset(id)
	end)
	if ok and typeof(m) == "Instance" then
		return m, "InsertService", ""
	end
	local ok2, m2 = pcall(function()
		return (AS :: any):LoadAssetAsync(id)
	end)
	if ok2 and typeof(m2) == "Instance" then
		return m2, "AssetService", ""
	end
	return nil, "", tostring(m) .. " / " .. tostring(m2)
end

local function try(f: () -> any): string
	local ok, v = pcall(f)
	return if ok then tostring(v) else "?"
end
-- printed at once, so a run that stops early still shows where it ran
out(0, "ENV", "v=1 studio=" .. try(function()
	return game:GetService("RunService"):IsStudio()
end) .. " server=" .. try(function()
	return game:GetService("RunService"):IsServer()
end) .. " creator=" .. try(function()
	return game.CreatorType.Name .. ":" .. string.format("%d", game.CreatorId)
end) .. " place=" .. try(function()
	return string.format("%d", game.PlaceId)
end) .. " ver=" .. try(function()
	return game.PlaceVersion
end) .. " job=" .. q(try(function()
	return game.JobId
end), 40) .. " ids=" .. #IDS)

for _, id in ipairs(IDS) do
	cur = { id = id, rows = {}, used = {}, cut = {} }
	table.insert(recs, cur)
	local loaded: Instance? = nil
	local okAll, eAll = pcall(function()
		local m, via, err = load(id)
		loaded = m
		if m then
			local ok, e = pcall(check, m, via)
			if ok then
				total.ok += 1
			else
				total.err += 1
				emit("ERR", "err=" .. q(e, 200))
			end
		else
			total.fail += 1
			emit("FAIL", "err=" .. q(err, 200))
		end
	end)
	-- the copy is destroyed whatever happened above (it was never parented)
	local toDestroy = loaded
	if toDestroy then
		pcall(function()
			toDestroy:Destroy()
		end)
	end
	if not okAll then
		total.err += 1
		pcall(emit, "ERR", "err=" .. q(eAll, 200))
	end
end

-- part lines and summary lines always print; the other lines share what is left of MAX_LINES, one per model per round
local function flush()
	local base = total.lines + 1
	local extra: { { Row } } = {}
	for i, rec in ipairs(recs) do
		base += 1
		local list: { Row } = {}
		for _, row in ipairs(rec.rows) do
			if row.detail and row.kind ~= "P" then
				row.keep = false
				table.insert(list, row)
			else
				base += 1
			end
		end
		table.sort(list, function(a, b)
			local pa, pb = PRIORITY[a.kind] or 9, PRIORITY[b.kind] or 9
			if pa ~= pb then
				return pa < pb
			end
			return a.seq < b.seq
		end)
		extra[i] = list
	end
	local left, round, more = MAX_LINES - base, 1, true
	while left > 0 and more do
		more = false
		for i = 1, #recs do
			local row = extra[i][round]
			if row and left > 0 then
				row.keep = true
				left -= 1
				more = true
			end
		end
		round += 1
	end
	for _, rec in ipairs(recs) do
		local printed = 0
		for _, row in ipairs(rec.rows) do
			if not row.keep or (row.detail and total.bytes >= MAX_BYTES) then
				rec.cut[row.kind] = (rec.cut[row.kind] or 0) + 1
			else
				out(rec.id, row.kind, row.body)
				printed += 1
			end
		end
		local cuts = {}
		for k, v in pairs(rec.cut) do
			table.insert(cuts, k .. ":" .. v)
		end
		table.sort(cuts)
		out(rec.id, "END", "lines=" .. printed .. " cut=" .. (if #cuts > 0 then table.concat(cuts, ",") else "0"))
	end
	return true
end
local okF, eF = pcall(flush)
if not okF then
	total.err += 1
	print("WE_CHECK2 0 ERR err=" .. q(eF, 200))
end
out(0, "DONE", string.format("ids=%d ok=%d fail=%d err=%d lines=%d bytes=%d", #IDS, total.ok, total.fail, total.err, total.lines, total.bytes))
