--!strict
--[[
	WAR EMPIRE W3 step 2 — ActivityAnchors: the one reader (and the one writer) of the activity anchors
	(spec scratchpad w3s2 §1.5–§1.6 / §5; contract scratchpad w3s2/build/L0/contract.md; config WorldConfig.Activity).

	An activity anchor is an invisible Attachment (0 parts) on a static anchored host part, tagged "WE_ActivityAnchor"
	(= WorldConfig.Activity.Tag) and carrying the WorldConfig.Activity.Attr attributes. Ids are "<POI>.<Site>.<Role>"
	(each segment letters, digits or "_"; POI = a WorldConfig.POIs Id); the site id is "<POI>.<Site>". The geometry
	stamps them (WorldPOI: POI layout rows on the POI's ActivityHost part, Activity.CheckpointAnchors on every
	CheckpointBooth, Town rows on a part of the cluster they Require; MapSetup: Town.BankAnchors on BankPlaza); the jobs
	read them (OpsService, BankRaidService).

	SERVER ONLY (it lives in ServerScriptService). Never yields, never waits on the tree, no cache: each List / Get walks the
	tag list once (a few hundred anchors), so callers read at site init and keep the records — never per frame.
	Anchors outside Workspace (e.g. a template kept in ServerStorage) and anchors whose host is not a BasePart are
	ignored. Positions come from host.CFrame * attachment.CFrame (the same as Attachment.WorldCFrame on live).

	PUBLIC API (frozen by lane L0; later changes are additive only):
	  ActivityAnchors.List(site?, kind?) -> { Anchor }
	      every live anchor, sorted by Id. site = "<POI>.<Site>" (one job place) or "<POI>" (the whole place);
	      kind = one of WorldConfig.Activity.Kinds. Duplicated ids warn once; the first by instance path wins.
	  ActivityAnchors.Get(id) -> Anchor?
	      one anchor by its full id, or nil.
	  ActivityAnchors.Parse(id) -> (poi?, site?, role?)
	      splits and checks an id: poi "Port", site "Port.Customs", role "Gate"; nil, nil, nil when malformed.
	  ActivityAnchors.Stamp(host, def) -> Attachment?
	      the one writer: validates def (id, kind, prompt, finite position), replaces any anchor with the same id under
	      host, creates the Attachment at def.Position turned by def.Yaw, sets the attributes and the tag. nil + a
	      warning when def is invalid (an unknown role only warns). host must never move or be replaced by a mesh
	      overlay (ActivityHost, CheckpointBooth, a MarketStall part, BankPlaza).
	  ActivityAnchors.FromRow(row) -> StampDef
	      a WorldConfig.ActivityAnchor row (world X / Z, Y above the floor) as a StampDef.
	  ActivityAnchors.FromTemplate(t, poi, siteSegment, kitFrame) -> StampDef
	      a WorldConfig.AnchorTemplate row (kit-local) placed by the kit's world frame (yaw-only CFrame at the kit's
	      pivot): id "<poi>.<siteSegment>.<t.Role>", yaw = kit yaw + t.Yaw.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)

local A = WorldConfig.Activity
local ATTR = A.Attr
-- BuyPathStatic pins the literal GetTagged("WE_ActivityAnchor") call below; the config value must agree with it
local TAG = "WE_ActivityAnchor"
if A.Tag ~= TAG then
	warn(string.format("[ActivityAnchors] WorldConfig.Activity.Tag is %q but this reader uses %q", tostring(A.Tag), TAG))
end

export type Anchor = {
	Id: string,
	POI: string,
	Site: string, -- "<POI>.<Site>"
	Role: string,
	Kind: string,
	Position: Vector3, -- world, on the standing surface (add your own lift for a prompt or a label)
	Yaw: number, -- degrees, 0 = faces north (-Z)
	CFrame: CFrame, -- Position turned by Yaw
	R: number?,
	Prompt: string?,
	Part: string?,
	BoxW: number?,
	BoxL: number?,
	Probe: boolean,
	Attachment: Attachment,
}

export type StampDef = {
	Id: string,
	Kind: string,
	Position: Vector3, -- world
	Yaw: number?, -- degrees, default 0
	R: number?,
	Prompt: string?,
	Part: string?,
	Box: { number }?, -- { width, length }
	Probe: boolean?,
}

local ActivityAnchors = {}

local function toSet(list: { string }): { [string]: boolean }
	local s: { [string]: boolean } = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

local KINDS = toSet(A.Kinds)
local PROMPTS = toSet(A.Prompts)
local ROLES = toSet(A.Roles)
local POI_IDS: { [string]: boolean } = {}
for _, p in ipairs(WorldConfig.POIs) do
	POI_IDS[p.Id] = true
end

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[ActivityAnchors] " .. msg)
	end
end

local function finite(n: number): boolean
	return n == n and n > -1e7 and n < 1e7
end

function ActivityAnchors.Parse(id: string): (string?, string?, string?)
	if type(id) ~= "string" then
		return nil, nil, nil
	end
	local poi, site, role = string.match(id, "^([%w_]+)%.([%w_]+)%.([%w_]+)$")
	if poi == nil or site == nil or role == nil or not POI_IDS[poi] then
		return nil, nil, nil
	end
	return poi, poi .. "." .. site, role
end

local function knownRole(role: string): boolean
	if ROLES[role] then
		return true
	end
	for _, stem in ipairs(A.NumberedRoles) do
		if string.match(role, "^" .. stem .. "%d+$") then
			return true
		end
	end
	return false
end

function ActivityAnchors.FromRow(row: WorldConfig.ActivityAnchor): StampDef
	return {
		Id = row.Id,
		Kind = row.Kind,
		Position = Vector3.new(row.X, A.FloorY + (row.Y or 0), row.Z),
		Yaw = row.Yaw or 0,
		R = row.R,
		Prompt = row.Prompt,
		Part = row.Part,
		Box = row.Box,
		Probe = row.Probe,
	}
end

function ActivityAnchors.FromTemplate(t: WorldConfig.AnchorTemplate, poi: string, siteSegment: string, kitFrame: CFrame): StampDef
	local p = (kitFrame * CFrame.new(t.X, 0, t.Z)).Position
	local look = kitFrame.LookVector
	local kitYaw = math.deg(math.atan2(-look.X, -look.Z))
	return {
		Id = poi .. "." .. siteSegment .. "." .. t.Role,
		Kind = t.Kind,
		Position = Vector3.new(p.X, A.FloorY + (t.Y or 0), p.Z),
		Yaw = kitYaw + (t.Yaw or 0),
		R = t.R,
		Prompt = t.Prompt,
		Part = t.Part,
		Box = nil,
		Probe = t.Probe,
	}
end

function ActivityAnchors.Stamp(host: BasePart, def: StampDef): Attachment?
	local poi, site, role = ActivityAnchors.Parse(def.Id)
	if poi == nil or site == nil or role == nil then
		warn(string.format("[ActivityAnchors] Stamp: bad id %q (want <POI>.<Site>.<Role>, POI from WorldConfig.POIs)", tostring(def.Id)))
		return nil
	end
	if typeof(host) ~= "Instance" or not host:IsA("BasePart") then
		warn(string.format("[ActivityAnchors] Stamp %s: the host is not a BasePart", def.Id))
		return nil
	end
	if not KINDS[def.Kind] then
		warn(string.format("[ActivityAnchors] Stamp %s: unknown kind %q", def.Id, tostring(def.Kind)))
		return nil
	end
	if def.Prompt ~= nil and not PROMPTS[def.Prompt] then
		warn(string.format("[ActivityAnchors] Stamp %s: unknown prompt %q", def.Id, tostring(def.Prompt)))
		return nil
	end
	local pos = def.Position
	if typeof(pos) ~= "Vector3" or not (finite(pos.X) and finite(pos.Y) and finite(pos.Z)) then
		warn(string.format("[ActivityAnchors] Stamp %s: bad position", def.Id))
		return nil
	end
	local yaw = def.Yaw or 0
	if not finite(yaw) then
		yaw = 0
	end
	if not knownRole(role) then
		warnOnce("role:" .. role, string.format("Stamp %s: role %q is outside WorldConfig.Activity.Roles (stamped anyway)", def.Id, role))
	end

	for _, ch in ipairs(host:GetChildren()) do
		if ch:IsA("Attachment") and ch.Name == def.Id then
			ch:Destroy()
		end
	end
	local att = Instance.new("Attachment")
	att.Name = def.Id
	att.CFrame = host.CFrame:ToObjectSpace(CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0))
	att:SetAttribute(ATTR.Id, def.Id)
	att:SetAttribute(ATTR.Site, site)
	att:SetAttribute(ATTR.POI, poi)
	att:SetAttribute(ATTR.Role, role)
	att:SetAttribute(ATTR.Kind, def.Kind)
	att:SetAttribute(ATTR.Yaw, yaw)
	if def.R ~= nil then
		att:SetAttribute(ATTR.R, def.R)
	end
	if def.Prompt ~= nil then
		att:SetAttribute(ATTR.Prompt, def.Prompt)
	end
	if def.Part ~= nil then
		att:SetAttribute(ATTR.Part, def.Part)
	end
	local box = def.Box
	if box ~= nil and #box >= 2 then
		att:SetAttribute(ATTR.BoxW, box[1])
		att:SetAttribute(ATTR.BoxL, box[2])
	end
	if def.Probe == true then
		att:SetAttribute(ATTR.Probe, true)
	end
	att.Parent = host
	CollectionService:AddTag(att, TAG)
	return att
end

local function num(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if type(v) == "number" then v else nil
end

local function str(inst: Instance, name: string): string?
	local v = inst:GetAttribute(name)
	return if type(v) == "string" then v else nil
end

-- one tagged instance as a record (nil when it is not a live, well-formed anchor)
local function record(inst: Instance): Anchor?
	if not inst:IsA("Attachment") or not inst:IsDescendantOf(Workspace) then
		return nil
	end
	local host = inst.Parent
	if host == nil or not host:IsA("BasePart") then
		warnOnce("host:" .. inst:GetFullName(), inst:GetFullName() .. ": an anchor must sit on a BasePart (ignored)")
		return nil
	end
	local id = str(inst, ATTR.Id)
	local kind = str(inst, ATTR.Kind)
	local poi, site, role
	if id ~= nil then
		poi, site, role = ActivityAnchors.Parse(id)
	end
	if id == nil or kind == nil or poi == nil or site == nil or role == nil then
		warnOnce("bad:" .. inst:GetFullName(), inst:GetFullName() .. ": malformed anchor (id / kind attributes; ignored)")
		return nil
	end
	local yaw = num(inst, ATTR.Yaw) or 0
	local wcf = (host :: BasePart).CFrame * (inst :: Attachment).CFrame
	local p = wcf.Position
	return {
		Id = id,
		POI = poi,
		Site = site,
		Role = role,
		Kind = kind,
		Position = p,
		Yaw = yaw,
		CFrame = CFrame.new(p) * CFrame.Angles(0, math.rad(yaw), 0),
		R = num(inst, ATTR.R),
		Prompt = str(inst, ATTR.Prompt),
		Part = str(inst, ATTR.Part),
		BoxW = num(inst, ATTR.BoxW),
		BoxL = num(inst, ATTR.BoxL),
		Probe = inst:GetAttribute(ATTR.Probe) == true,
		Attachment = inst :: Attachment,
	}
end

-- every live anchor, deduplicated by id (first by instance path), sorted by id
local function all(): { Anchor }
	local tagged = CollectionService:GetTagged("WE_ActivityAnchor")
	local recs: { Anchor } = {}
	for _, inst in ipairs(tagged) do
		local r = record(inst)
		if r ~= nil then
			table.insert(recs, r)
		end
	end
	table.sort(recs, function(a: Anchor, b: Anchor): boolean
		if a.Id ~= b.Id then
			return a.Id < b.Id
		end
		return a.Attachment:GetFullName() < b.Attachment:GetFullName()
	end)
	local out: { Anchor } = {}
	local last: string? = nil
	for _, r in ipairs(recs) do
		if r.Id == last then
			warnOnce("dup:" .. r.Id, "duplicate anchor id " .. r.Id .. " (the first by instance path is used)")
		else
			table.insert(out, r)
			last = r.Id
		end
	end
	return out
end

function ActivityAnchors.List(site: string?, kind: string?): { Anchor }
	local byPOI = site ~= nil and string.find(site, ".", 1, true) == nil
	local out: { Anchor } = {}
	for _, r in ipairs(all()) do
		local siteOk = site == nil or (if byPOI then r.POI == site else r.Site == site)
		if siteOk and (kind == nil or r.Kind == kind) then
			table.insert(out, r)
		end
	end
	return out
end

function ActivityAnchors.Get(id: string): Anchor?
	for _, r in ipairs(all()) do
		if r.Id == id then
			return r
		end
	end
	return nil
end

return ActivityAnchors
