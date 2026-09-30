--!strict
-- claude-bud JOB 40 part C: the load / origin probe for StorePropsConfig.Candidates. Run it as Open Cloud Luau
-- execution on the live place (as tools/WeCheck2.luau is), or paste into the Studio command bar. It only reads: it
-- loads each id, counts the pieces, prints a line per id and destroys the copy. It never places anything in the world.
-- A row passes when it loads, has at most 40 BaseParts after the service's trim (scripts / lights stripped), and no
-- name hits the real-world / franchise list. Code Bot runs it (no API key lives in the game), then wires the passing
-- ids into ReplaceRows / BaseRows and runs WE_CHECK2 + tools/wire-asset-ids.py on them.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local okC, Cfg = pcall(function(): any
	return require(ReplicatedStorage:WaitForChild("Shared", 5):WaitForChild("Configs", 5):WaitForChild("StorePropsConfig", 5) :: any)
end)
local list: { any } = if okC and Cfg and typeof(Cfg.Candidates) == "table" then Cfg.Candidates else {}

local BANNED = { "sn%-75", "phoenix", "orly", "f%-16", "apache", "black hawk", "abrams", "leopard", "t%-72", "nasa", "star wars", "halo" }

local out = {}
for _, row in ipairs(list) do
	local ok, model = pcall(InsertService.LoadAsset, InsertService, row.Id)
	if not ok or model == nil then
		table.insert(out, string.format("FAIL  %d %s: load (%s)", row.Id, row.Name, tostring(model)))
		continue
	end
	local parts, meshes, scripts, lights, humanoids, bad = 0, 0, 0, 0, 0, {}
	for _, d in ipairs((model :: Instance):GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			if d:IsA("MeshPart") then
				meshes += 1
			end
		elseif d:IsA("LuaSourceContainer") then
			scripts += 1
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("Humanoid") then
			humanoids += 1
		end
		local n = string.lower(d.Name)
		for _, b in ipairs(BANNED) do
			if string.find(n, b) then
				table.insert(bad, d.Name)
			end
		end
	end
	local sizeTxt = "?"
	local m = (model :: Instance):FindFirstChildWhichIsA("Model") or model
	local okS, size = pcall(function()
		return (m :: Model):GetExtentsSize()
	end)
	if okS then
		sizeTxt = string.format("%.0fx%.0fx%.0f", size.X, size.Y, size.Z)
	end
	local pass = parts > 0 and parts <= 40 and humanoids == 0 and #bad == 0
	table.insert(out, string.format("%s  %d %s: parts=%d meshes=%d scripts=%d(stripped) lights=%d humanoids=%d size=%s%s",
		if pass then "PASS" else "FAIL", row.Id, row.Name, parts, meshes, scripts, lights, humanoids, sizeTxt,
		if #bad > 0 then " names=" .. table.concat(bad, ",") else ""))
	;(model :: Instance):Destroy()
end
print("JOB40 PROPS PROBE (" .. #list .. " ids)\n" .. table.concat(out, "\n"))
return table.concat(out, "\n")
