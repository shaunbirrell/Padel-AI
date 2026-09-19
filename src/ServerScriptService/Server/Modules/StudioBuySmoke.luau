--!strict
--[[
	Studio-only auto BUY smoke.
	After profile + plot assign (~3–5s): teleport to plot, PurchaseUpgrade(CommandCenter),
	print unmistakable [SMOKE] BUY lines, mirror into ServerStorage.SmokeResult,
	and FireAllClients(StudioSmokeLog) so Play Solo client Output also shows the result.

	NEVER runs outside RunService:IsStudio(). Product Ids stay 0 (no Marketplace).
	HttpService / %TEMP% file writes are unreliable from Studio Luau — prefer prints + remote.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudioBuySmoke = {}

local STRUCTURE_ID = "CommandCenter"
local DELAY_SEC = 4.0
local ranFor: { [number]: boolean } = {}

local smokeRemote: RemoteEvent? = nil

local function resolveSmokeRemote(): RemoteEvent?
	if smokeRemote and smokeRemote.Parent then
		return smokeRemote
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		return nil
	end
	local ev = folder:FindFirstChild("StudioSmokeLog")
	if ev and ev:IsA("RemoteEvent") then
		smokeRemote = ev
		return ev
	end
	return nil
end

local function writeResult(line: string)
	local folder = ServerStorage:FindFirstChild("SmokeResult")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SmokeResult"
		folder.Parent = ServerStorage
	end
	local sv = folder:FindFirstChild("LastBuy")
	if not sv then
		sv = Instance.new("StringValue")
		sv.Name = "LastBuy"
		sv.Parent = folder
	end
	sv.Value = line
	local log = folder:FindFirstChild("Log")
	if not log then
		log = Instance.new("StringValue")
		log.Name = "Log"
		log.Parent = folder
	end
	local prev = log.Value
	if #prev > 4000 then
		prev = string.sub(prev, -2000)
	end
	log.Value = prev .. (if prev ~= "" then "\n" else "") .. line
end

local function broadcast(kind: string, line: string)
	local ev = resolveSmokeRemote()
	if ev then
		ev:FireAllClients(kind, line, os.clock())
	end
end

local function smokeLine(kind: string, detail: string)
	local line = string.format("[SMOKE] BUY %s %s", kind, detail)
	-- Louder than a single print: banner + warn on FAIL so Output filter can't miss it
	print("========== " .. line .. " ==========")
	print(line)
	if kind == "FAIL" then
		warn(line)
	elseif kind == "OK" then
		print("[SMOKE] ★★★ BUY PATH OK ★★★")
	end
	writeResult(line)
	broadcast(kind, line)
	return line
end

function StudioBuySmoke.Init(deps: { [string]: any })
	if not RunService:IsStudio() then
		return
	end

	local DataService = deps.DataService
	local BaseService = deps.BaseService
	if not DataService or not BaseService then
		warn("[SMOKE] BUY FAIL deps missing DataService/BaseService")
		broadcast("FAIL", "[SMOKE] BUY FAIL deps missing DataService/BaseService")
		return
	end

	-- Resolve remote early (RemoteSetup runs before this)
	task.defer(function()
		local ev = resolveSmokeRemote()
		if ev then
			print("[SMOKE] StudioSmokeLog remote ready — client Output will mirror BUY lines")
		else
			warn("[SMOKE] StudioSmokeLog remote missing — server prints only")
		end
	end)

	print("[SMOKE] StudioBuySmoke armed (IsStudio=true) — will auto-BUY CommandCenter ~4s after plot assign")
	print("[SMOKE] Watch Output for: [SMOKE] BUY START / OK / FAIL  (also FireAllClients StudioSmokeLog)")

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		if ranFor[player.UserId] then
			return
		end
		ranFor[player.UserId] = true

		task.delay(DELAY_SEC, function()
			if not player.Parent then
				smokeLine("FAIL", "player left before smoke")
				return
			end

			local profile = DataService.GetProfile(player)
			if not profile then
				smokeLine("FAIL", "NoProfile after delay")
				return
			end

			-- Ensure plot + standing on it
			if profile.BasePlotId == nil and BaseService.AssignPlot then
				BaseService.AssignPlot(player)
				profile = DataService.GetProfile(player) or profile
			end
			if BaseService.TeleportToPlot then
				BaseService.TeleportToPlot(player)
			end

			local cashBefore = tonumber(profile.Cash) or 0
			local levelBefore = tonumber(profile.BaseUpgrades and profile.BaseUpgrades[STRUCTURE_ID]) or 0

			-- Studio-only: ensure one upgrade can succeed (cash + not already MaxLevel)
			local EconomyService = deps.EconomyService
			local Shared = ReplicatedStorage:FindFirstChild("Shared")
			if Shared then
				local okCfg, BaseConfig = pcall(function()
					return require(Shared.Configs.BaseConfig)
				end)
				if okCfg and typeof(BaseConfig) == "table" then
					local def = BaseConfig.Structures and BaseConfig.Structures[STRUCTURE_ID]
					local maxLevel = if def then (tonumber(def.MaxLevel) or 5) else 5
					if levelBefore >= maxLevel then
						profile.BaseUpgrades[STRUCTURE_ID] = maxLevel - 1
						levelBefore = maxLevel - 1
						DataService.MarkDirty(player)
					end
					local nextLevel = levelBefore + 1
					local cost = def and def.Costs and def.Costs[nextLevel]
					if typeof(cost) == "number" and cashBefore < cost and EconomyService and EconomyService.AddCash then
						EconomyService.AddCash(player, cost - cashBefore, "studio_smoke_buy")
						profile = DataService.GetProfile(player) or profile
						cashBefore = tonumber(profile.Cash) or cashBefore
					end
				end
			end

			smokeLine("START", string.format(
				"player=%s cash=%d level=%d structure=%s plot=%s",
				player.Name,
				cashBefore,
				levelBefore,
				STRUCTURE_ID,
				tostring(profile.BasePlotId)
			))

			local okCall, resultOrErr = pcall(function()
				return BaseService.PurchaseUpgrade(player, STRUCTURE_ID)
			end)
			if not okCall then
				smokeLine("FAIL", "pcall error: " .. tostring(resultOrErr))
				return
			end

			local result = resultOrErr
			if typeof(result) ~= "table" then
				smokeLine("FAIL", "bad result type=" .. typeof(result))
				return
			end

			profile = DataService.GetProfile(player) or profile
			local cashAfter = tonumber(result.Cash) or tonumber(profile.Cash) or cashBefore
			local levelAfter = tonumber(result.NewLevel)
				or tonumber(profile.BaseUpgrades and profile.BaseUpgrades[STRUCTURE_ID])
				or levelBefore

			if result.Ok == true then
				smokeLine("OK", string.format("newCash=%d level=%d structure=%s", cashAfter, levelAfter, STRUCTURE_ID))
			else
				smokeLine("FAIL", string.format("err=%s cash=%d level=%d", tostring(result.Error), cashAfter, levelAfter))
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		ranFor[player.UserId] = nil
	end)
end

return StudioBuySmoke
