--!strict
--[[ claude-bud JOB 69 C: the ONE lookup for the "how to play" text (pure; client + tests).

	Every registered activity / mission / daily op / job / zone run carries an inline
	HowTo = { What, Steps, TimeLimit, Reward } in its own config row (MissionConfig, DailyOpsConfig, SiteActivityConfig,
	OpsConfig, RebirthZonesConfig.Info; tools/checks/claude_bud_job69.py fails on a row without one).
	  * HowTo.Find(id)            the HowTo table of that id (nil when none)
	  * HowTo.Line(id, fallback)  the one-line "what to do" for a menu row
	  * HowTo.Card(id, title)     the card data the how-to card shows (ZoneRunController.ShowIntro's shape)
	  * HowTo.Live(userId)        RebirthZonesConfig.Rebuild "HowTo" (owner-first; OFF = the old rows / instant START)
	The index is built once on first use (no per-frame work). ]]

local Configs = script.Parent.Parent:WaitForChild("Configs", 10) :: Instance

local HowTo = {}

local index: { [string]: any }? = nil

local function walk(t: any, depth: number, out: { [string]: any }, seen: { [any]: boolean })
	if type(t) ~= "table" or depth > 4 or seen[t] then
		return
	end
	seen[t] = true
	if type(t.Id) == "string" and type(t.HowTo) == "table" and out[t.Id] == nil then
		out[t.Id] = t.HowTo
	end
	for k, v in pairs(t) do
		if type(v) == "table" and k ~= "HowTo" then
			walk(v, depth + 1, out, seen)
		end
	end
end

local function build(): { [string]: any }
	local out: { [string]: any } = {}
	local seen: { [any]: boolean } = {}
	for _, name in ipairs({ "MissionConfig", "DailyOpsConfig", "SiteActivityConfig", "OpsConfig" }) do
		local m = Configs and Configs:FindFirstChild(name)
		if m then
			local ok, cfg = pcall(require, m :: any)
			if ok then
				walk(cfg, 0, out, seen)
			end
		end
	end
	local rz = Configs and Configs:FindFirstChild("RebirthZonesConfig")
	if rz then
		local ok, cfg: any = pcall(require, rz :: any)
		if ok and type(cfg.Info) == "table" then
			for zoneId, info in pairs(cfg.Info) do
				if type(info) == "table" and type(info.HowTo) == "table" and out[zoneId] == nil then
					out[zoneId] = info.HowTo
				end
			end
		end
	end
	return out
end

function HowTo.Find(id: any): any
	if type(id) ~= "string" then
		return nil
	end
	if index == nil then
		index = build()
	end
	return (index :: { [string]: any })[id]
end

function HowTo.Line(id: any, fallback: string): string
	local h = HowTo.Find(id)
	if h and type(h.What) == "string" and h.What ~= "" then
		return h.What
	end
	return fallback
end

function HowTo.Card(id: any, title: string): any
	local h = HowTo.Find(id)
	if h == nil then
		return nil
	end
	return {
		Zone = id,
		Title = title,
		Goal = h.What,
		Steps = h.Steps,
		Reward = h.Reward,
		Seconds = tonumber(h.TimeLimit) or 0,
		CooldownLeft = 0,
		Compact = false,
	}
end

function HowTo.Live(userId: any): boolean
	local rz = Configs and Configs:FindFirstChild("RebirthZonesConfig")
	if rz == nil then
		return false
	end
	local ok, cfg: any = pcall(require, rz :: any)
	return ok and type(cfg.RebuildLive) == "function" and cfg.RebuildLive(userId, "HowTo") == true
end

-- test hook: drop the cached index (the sims swap configs)
function HowTo._Reset()
	index = nil
end

return HowTo
