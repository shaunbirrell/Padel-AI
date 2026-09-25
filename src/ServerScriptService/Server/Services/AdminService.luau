--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")
local AdminConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AdminConfig)
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local AdminService = {}

local EconomyService: any = nil
local XPService: any = nil
local DataService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil

function AdminService.IsAdmin(player: Player): boolean
	local uid = tonumber(player.UserId)
	if typeof(uid) ~= "number" then
		return false
	end
	-- Belt: shaunie6 always admin
	if uid == 470626172 then
		return true
	end
	local list = AdminConfig.UserIds
	if typeof(list) ~= "table" then
		return false
	end
	for _, id in ipairs(list) do
		if tonumber(id) == uid then
			return true
		end
	end
	for k, v in pairs(list) do
		if tonumber(k) == uid or tonumber(v) == uid then
			return true
		end
	end
	return false
end

--[[ v71 money (M2): test commands for the money workflows (AdminConfig.MoneyCommands). Allowed for the admin
	allowlist, and for any player in Studio (Local Server tests use Player1 / Player2). Each one is logged as
	ADMIN_COMMAND and calls its service when that service exists; until then it replies "not built yet".
	None of them touches Cash, and each acts only on the caller. ]]
local MONEY_COMMANDS: { [string]: boolean } = {}
for _, name in ipairs((AdminConfig :: any).MoneyCommands or {}) do
	if typeof(name) == "string" then
		MONEY_COMMANDS[string.lower(name)] = true
	end
end

local function isMoneyCommand(command: any): boolean
	return RemoteGuard.IsCommandString(command) and MONEY_COMMANDS[string.lower(command :: string)] == true
end

local function adminReply(deps: { [string]: any }, player: Player, text: string, kind: string)
	local notify = deps.NotificationService
	if notify and notify.Notify then
		pcall(notify.Notify, player, text, kind)
	end
	print("[AdminService] " .. player.Name .. ": " .. text)
end

-- An entitlement key the game knows: a MonetizationConfig GamePasses key or a DevProduct GrantEntitlement value.
local function isKnownEntitlementKey(key: string): boolean
	local MonetizationConfig = require(ReplicatedStorage.Shared.Configs.MonetizationConfig)
	if (MonetizationConfig.GamePasses :: any)[key] ~= nil then
		return true
	end
	for _, def in pairs(MonetizationConfig.DevProducts :: any) do
		if typeof(def) == "table" and def.GrantEntitlement == key then
			return true
		end
	end
	return false
end

-- Whole number in [minN, maxN] from a number or a numeric string; nil otherwise.
local function argInt(value: any, minN: number, maxN: number): number?
	local n = if typeof(value) == "string" then tonumber(value) else value
	return RemoteGuard.ClampInt(n, minN, maxN)
end

-- Runs one money command; returns a short result for the ADMIN_COMMAND log.
local function runMoneyCommand(deps: { [string]: any }, player: Player, cmd: string, arg1: any, arg2: any): string
	local function serviceFn(serviceName: string, fnName: string): any
		local svc = deps[serviceName]
		if typeof(svc) == "table" and typeof(svc[fnName]) == "function" then
			return svc[fnName]
		end
		return nil
	end
	local function notBuilt(): string
		adminReply(deps, player, cmd .. ": not built yet", "Warn")
		return "not_built"
	end
	local function badArgs(usage: string): string
		adminReply(deps, player, "Usage: " .. usage, "Warn")
		return "bad_args"
	end
	local function call(fn: any, okText: string, ...: any): string
		local ok, res, err = pcall(fn, ...)
		if not ok then
			warn("[AdminService] " .. cmd .. " failed:", res)
			adminReply(deps, player, cmd .. " failed (see Output)", "Warn")
			return "error"
		end
		if res == false then
			adminReply(deps, player, cmd .. " refused: " .. tostring(err), "Warn")
			return "refused"
		end
		adminReply(deps, player, okText, "Success")
		return "ok"
	end

	if cmd == "grantent" then
		if not RemoteGuard.IsKeyString(arg1) or not isKnownEntitlementKey(arg1 :: string) then
			return badArgs("grantent <key> (a MonetizationConfig pass key or GrantEntitlement)")
		end
		local fn = serviceFn("MonetizationService", "GrantEntitlement")
		if not fn then
			return notBuilt()
		end
		return call(fn, "Entitlement granted: " .. (arg1 :: string), player, arg1 :: string)
	elseif cmd == "givenuke" then
		local n = argInt(arg1, 1, 100)
		if not n then
			return badArgs("givenuke <1-100> [tactical]")
		end
		local kind = if typeof(arg2) == "string" and string.lower(arg2) == "tactical" then "TacticalNuke" else "Nuke"
		local fn = serviceFn("NukeService", "Grant")
		if not fn then
			return notBuilt()
		end
		return call(fn, string.format("Granted %d %s", n, kind), player, kind, n, "admin")
	elseif cmd == "nukecd" then
		local fn = serviceFn("NukeService", "AdminResetCooldowns")
		if not fn then
			return notBuilt()
		end
		return call(fn, "Nuke cooldowns reset")
	elseif cmd == "vhp" then
		local pct = argInt(arg1, 0, 100)
		if not pct then
			return badArgs("vhp <0-100>")
		end
		local fn = serviceFn("VehicleService", "AdminSetHP")
		if not fn then
			return notBuilt()
		end
		return call(fn, string.format("Vehicle HP set to %d%%", pct), player, pct)
	elseif cmd == "setprestige" then
		local n = argInt(arg1, 0, 100)
		if not n then
			return badArgs("setprestige <0-100>")
		end
		local fn = serviceFn("RebirthExpansionService", "AdminSetPrestige")
		if not fn then
			return notBuilt()
		end
		return call(fn, "Prestige set to " .. tostring(n), player, n)
	elseif cmd == "openzone" then
		if not RemoteGuard.IsIdString(arg1, 32) then
			return badArgs("openzone <zoneId>")
		end
		local fn = serviceFn("RebirthExpansionService", "AdminOpenZone")
		if not fn then
			return notBuilt()
		end
		return call(fn, "Zone opened: " .. (arg1 :: string), player, arg1 :: string)
	elseif cmd == "resetrebirth" then
		local fn = serviceFn("RebirthExpansionService", "AdminResetRebirth")
		if not fn then
			return notBuilt()
		end
		return call(fn, "Rebirth progress reset", player)
	end
	return "unknown"
end

--[[ F7 test (owner's 11 features, lane P): give yourself n (1-5) Keep-Base Rebirth tokens so the keep-base path
	("USE SAVED" in the Rebirth modal) can be tested on a phone before the product Id is pasted. Admin allowlist
	ONLY (never the Studio-open money commands, never another player). Returns the reply text. ]]
local function giveKeepBaseTokens(deps: { [string]: any }, player: Player, n: number?): string
	local prestige = deps.PrestigeService
	if not (prestige and typeof(prestige.AdminGiveKeepBase) == "function") then
		return "givekeepbase: not built yet"
	end
	local ok, res, err = pcall(prestige.AdminGiveKeepBase, player, n or 1)
	if not ok then
		warn("[AdminService] givekeepbase failed:", res)
		return "givekeepbase failed (see Output)"
	end
	if res ~= true then
		return "givekeepbase refused: " .. tostring(err)
	end
	return string.format("Admin: Keep-Base Rebirths saved %d", prestige.KeepBaseTokens(player))
end

--[[ Nations test (lane B): clear the CALLER's own nation fields (NationId, NationSetAt, NationFreeUntil,
	NationFreeChanges, NationPrompts) so the join picker and the free first pick can be tested again. Admin allowlist
	ONLY (the remote handler and the chat hook both return for anyone else); it never takes a target player.
	Returns the reply text. ]]
local function nationReset(deps: { [string]: any }, player: Player): string
	local svc = deps.NationColorService
	if not (svc and typeof(svc.AdminReset) == "function") then
		return "nationreset: not built yet"
	end
	local ok, res = pcall(svc.AdminReset, player)
	if not ok then
		warn("[AdminService] nationreset failed:", res)
		return "nationreset failed (see Output)"
	end
	return if res == true then "Admin: flag choice reset" else "nationreset: still loading"
end

--- Force Cash = AdminPlaytestCash for allowlisted admins (mid-session recovery).
local function grantAdminPlaytestCashFloor(player: Player): (boolean, number)
	local target = math.floor(tonumber(AdminConfig.AdminPlaytestCash) or 0)
	if target <= 0 then
		return false, 0
	end
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return false, 0
	end
	local before = math.floor(tonumber(profile.Cash) or 0)
	profile.Cash = target
	if DataService.MarkDirty then
		DataService.MarkDirty(player)
	end
	if EconomyService and EconomyService.Push then
		EconomyService.Push(player)
	end
	print(
		string.format(
			"[AdminCash] CHAT/CMD grant userId=%s before=%s after=%s matched=true",
			tostring(player.UserId),
			tostring(before),
			tostring(target)
		)
	)
	return true, target
end

function AdminService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	DataService = deps.DataService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService

	local RemoteSetup = deps.RemoteSetup
	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestAdminCommand) :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, command: any, arg1: any, arg2: any)
		if not RateLimitService.Allow(player, "admin", 2, 4) then
			return
		end
		-- v71 money (M2): the money test commands are also open to any player in Studio (never on live servers)
		local moneyCmd = isMoneyCommand(command)
		local isAdmin = AdminService.IsAdmin(player)
		if not isAdmin and not (moneyCmd and RunService:IsStudio()) then
			warn("[AdminService] Unauthorized admin attempt:", player.UserId)
			return
		end
		if not RemoteGuard.IsCommandString(command) then
			return
		end
		-- Admin still requires a loaded profile for mutating commands
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end

		local cmd = string.lower(command :: string)
		local ADMIN_GRANT_MAX = 1_000_000_000
		if moneyCmd then
			local result = runMoneyCommand(deps, player, cmd, arg1, arg2)
			local argText = if typeof(arg1) == "string" or typeof(arg1) == "number" then string.sub(tostring(arg1), 1, 40) else nil
			AnalyticsService.Log("ADMIN_COMMAND", player.UserId, {
				command = cmd,
				arg = argText,
				result = result,
				admin = isAdmin,
			})
			return
		end
		AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = cmd })

		if cmd == "cash" or cmd == "givecash" then
			-- No amount (or cash alias): instantly floor to AdminPlaytestCash for mid-session recovery
			local explicit = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if not explicit then
				local okGrant, granted = grantAdminPlaytestCashFloor(player)
				if okGrant and deps.NotificationService then
					deps.NotificationService.Notify(player, string.format("Admin cash set to $%s", tostring(granted)), "Success")
				elseif not okGrant and deps.NotificationService then
					deps.NotificationService.Notify(player, "Admin cash grant failed (no profile?)", "Warn")
				end
			else
				EconomyService.AddCash(player, explicit, "admin")
			end
		elseif cmd == "givegold" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt then
				EconomyService.AddGold(player, amt, "admin")
			end
		elseif cmd == "givexp" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt then
				XPService.AddXP(player, amt, "admin")
			end
		elseif cmd == "setlevel" then
			local lvl = RemoteGuard.ClampPositiveInt(arg1, 1000)
			if lvl then
				XPService.SetLevel(player, lvl)
			end
		elseif cmd == "unlockall" then
			local profile = DataService.GetProfile(player)
			if profile then
				local VehicleConfig = require(ReplicatedStorage.Shared.Configs.VehicleConfig)
				local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
				for id in pairs(VehicleConfig.Vehicles) do
					profile.Vehicles[id] = true
				end
				for id in pairs(WeaponConfig.Weapons) do
					profile.Weapons[id] = true
				end
				DataService.MarkDirty(player)
			end
		elseif cmd == "resetbase" then
			local profile = DataService.GetProfile(player)
			if profile then
				for id in pairs(profile.BaseUpgrades) do
					profile.BaseUpgrades[id] = 0
				end
				DataService.MarkDirty(player)
				if deps.BaseService then
					deps.BaseService.PushState(player)
					if deps.BaseService.RefreshAllVisuals then
						deps.BaseService.RefreshAllVisuals(player)
					end
				end
			end
		elseif cmd == "wipeprofile" then
			-- Delete DataStore key, clear memory (so PlayerRemoving cannot re-save), kick to rejoin fresh
			local userId = player.UserId
			local okWipe, wipeErr = DataService.RemovePersistedProfile(userId)
			if not okWipe then
				warn("[AdminService] wipeprofile RemoveAsync failed:", wipeErr)
			end
			DataService.ClearInMemoryProfile(userId)
			pcall(function()
				local SessionLock = require(script.Parent.Parent.Modules.SessionLock)
				SessionLock.Release(userId)
			end)
			player:Kick("Progress wiped — please rejoin")
			return
		elseif cmd == "resettutorial" then
			if deps.TutorialService and deps.TutorialService.Reset then
				deps.TutorialService.Reset(player)
			end
		elseif cmd == "givekeepbase" then
			-- F7 test tokens: reached only by the admin allowlist (not a MoneyCommands entry, so no Studio opening)
			local reply = giveKeepBaseTokens(deps, player, RemoteGuard.ClampPositiveInt(arg1, 5))
			if deps.NotificationService then
				deps.NotificationService.Notify(player, reply, "Success")
			end
		elseif cmd == "nationreset" then
			-- nations test: the caller's own nation fields only (admin allowlist; not a MoneyCommands entry)
			local reply = nationReset(deps, player)
			if deps.NotificationService then
				deps.NotificationService.Notify(player, reply, "Success")
			end
		elseif cmd == "prestige" or cmd == "forceprestige" then
			if deps.PrestigeService and deps.PrestigeService.DoPrestige then
				-- force: temporarily ignore level gate via SetLevel first if needed
				if cmd == "forceprestige" and deps.XPService then
					local PrestigeConfig = require(ReplicatedStorage.Shared.Configs.PrestigeConfig)
					deps.XPService.SetLevel(player, PrestigeConfig.MinLevelToPrestige)
				end
				local ok, err = deps.PrestigeService.DoPrestige(player)
				if deps.NotificationService then
					deps.NotificationService.Notify(player, if ok then "Prestige OK" else ("Prestige failed: " .. tostring(err)), if ok then "Success" else "Warn")
				end
			end
		elseif cmd == "createclan" and RemoteGuard.IsIdString(arg1, 32) then
			if deps.ClanService and deps.ClanService.CreateClan then
				local tagArg = if RemoteGuard.IsIdString(arg2, 8) then arg2 :: string else nil
				local ok, err = deps.ClanService.CreateClan(player, arg1 :: string, tagArg)
				if not ok and deps.NotificationService then
					deps.NotificationService.Notify(player, "Clan create failed: " .. tostring(err), "Warn")
				end
			end
		elseif cmd == "joinclan" and RemoteGuard.IsIdString(arg1) then
			if deps.ClanService then
				deps.ClanService.JoinClan(player, arg1 :: string)
			end
		elseif cmd == "leaveclan" then
			if deps.ClanService then
				deps.ClanService.LeaveClan(player)
			end
		elseif cmd == "bpxp" then
			local amt = RemoteGuard.ClampPositiveInt(arg1, ADMIN_GRANT_MAX)
			if amt and deps.BattlePassService and deps.BattlePassService.AddXP then
				deps.BattlePassService.AddXP(player, amt, "admin")
			end
		elseif cmd == "grantpremium" then
			if deps.BattlePassService and deps.BattlePassService.SetPremium then
				deps.BattlePassService.SetPremium(player, true)
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Battle Pass Premium granted", "Success")
				end
			end
		elseif cmd == "grantpass" and RemoteGuard.IsKeyString(arg1) then
			-- Studio mock GamePass ownership (Ids may still be 0)
			if deps.MonetizationService and deps.MonetizationService.SetMockGamePassOwned then
				deps.MonetizationService.SetMockGamePassOwned(player, arg1 :: string, true)
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Mock GamePass owned: " .. arg1, "Success")
				end
			end
		elseif cmd == "endseason" then
			if deps.SeasonService and deps.SeasonService.EndSeason then
				deps.SeasonService.EndSeason("admin:" .. tostring(player.UserId))
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Season ended (admin)", "Info")
				end
			end
		elseif cmd == "resumeseason" then
			if deps.SeasonService and deps.SeasonService.ClearEndOverride then
				deps.SeasonService.ClearEndOverride("admin:" .. tostring(player.UserId))
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "Season resumed (admin)", "Success")
				end
			end
		elseif cmd == "resetmap" then
			-- Studio: destroy WarEmpireSetup and rebuild via MapSetup
			if not RunService:IsStudio() then
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "resetmap is Studio-only", "Warn")
				end
				return
			end
			local existing = Workspace:FindFirstChild("WarEmpireSetup")
			if existing then
				existing:Destroy()
			end
			local voidFb = Workspace:FindFirstChild("WE_VoidFallback")
			if voidFb then
				voidFb:Destroy()
			end
			local MapSetup = require(script.Parent.Parent.Modules.MapSetup)
			local ok, err = pcall(function()
				MapSetup.Run()
			end)
			if not ok then
				warn("[WAR EMPIRE] resetmap MapSetup failed: " .. tostring(err))
				if deps.NotificationService then
					deps.NotificationService.Notify(player, "MapSetup failed — check Output", "Error")
				end
				return
			end
			if deps.NotificationService then
				deps.NotificationService.Notify(player, "Map regenerated (MapSetup)", "Success")
			end
		end
	end)

	-- Server chat: /cash or /givecash (no client remote wiring required)
	local lastAdminChat: { [number]: { Text: string, At: number } } = {}
	local ADMIN_DEFAULT_LEVEL = 25 -- every helicopter unlocks by Lv 20 (VehicleConfig Air)
	local ADMIN_DEFAULT_XP = 10_000
	Players.PlayerRemoving:Connect(function(p: Player)
		lastAdminChat[p.UserId] = nil
	end)

	local function onAdminChat(player: Player, message: string)
		if typeof(message) ~= "string" or message == "" then
			return
		end
		if not AdminService.IsAdmin(player) then
			return
		end
		local text = string.lower((string.gsub(message, "^%s+", "")))
		text = string.gsub(text, "^/", "")
		local cmd, rest = string.match(text, "^([%w_]+)%s*(.-)%s*$")
		if not cmd then
			return
		end
		local isLevelCmd = cmd == "level" or cmd == "setlevel"
		local isXpCmd = cmd == "xp" or cmd == "givexp"
		local isKeepBaseCmd = cmd == "givekeepbase"
		local isNationResetCmd = cmd == "nationreset"
		if cmd ~= "cash" and cmd ~= "givecash" and not isLevelCmd and not isXpCmd and not isKeepBaseCmd and not isNationResetCmd then
			return
		end
		-- v71: one chat line can arrive via Player.Chatted, TextChatCommand and MessageReceived — run it once
		local nowClock = os.clock()
		local last = lastAdminChat[player.UserId]
		if last and last.Text == text and nowClock - last.At < 1.0 then
			return
		end
		lastAdminChat[player.UserId] = { Text = text, At = nowClock }
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		-- F7: owner playtest — /givekeepbase [1-5] (Keep-Base Rebirth tokens; admin allowlist only, see above)
		if isKeepBaseCmd then
			local reply = giveKeepBaseTokens(deps, player, RemoteGuard.ClampPositiveInt(tonumber(rest), 5))
			if deps.NotificationService then
				deps.NotificationService.Notify(player, reply, "Success")
			end
			AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = "chat_givekeepbase", arg = string.sub(tostring(rest), 1, 8) })
			return
		end
		-- nations: owner playtest on a phone — /nationreset clears the caller's own flag choice (allowlist only)
		if isNationResetCmd then
			local reply = nationReset(deps, player)
			if deps.NotificationService then
				deps.NotificationService.Notify(player, reply, "Success")
			end
			AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = "chat_nationreset" })
			return
		end
		-- v71: owner playtest — /level <n> (default ADMIN_DEFAULT_LEVEL) and /xp <n> (default ADMIN_DEFAULT_XP).
		-- Allowlist only (AdminService.IsAdmin above); server-side; no remote grants XP.
		if isLevelCmd or isXpCmd then
			local num = tonumber(rest)
			local valid = typeof(num) == "number" and num == num and num > 0
			if isLevelCmd then
				local lvl = if valid then math.clamp(math.floor(num :: number), 1, 1000) else ADMIN_DEFAULT_LEVEL
				XPService.SetLevel(player, lvl)
				local profile = DataService.GetProfile(player)
				local now = if profile then profile.Level else lvl
				if deps.NotificationService then
					deps.NotificationService.Notify(player, string.format("Admin: level set to %d", now), "Success")
				end
				AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = "chat_level", arg = tostring(lvl) })
			else
				local amt = if valid then math.clamp(math.floor(num :: number), 1, 1_000_000_000) else ADMIN_DEFAULT_XP
				local ok = XPService.AddXP(player, amt, "admin")
				if deps.NotificationService then
					deps.NotificationService.Notify(player, if ok then string.format("Admin: +%d XP", amt) else "Admin: XP not added (max level?)", if ok then "Success" else "Warn")
				end
				AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = "chat_xp", arg = tostring(amt) })
			end
			return
		end
		local explicit: number? = nil
		local n = tonumber(rest)
		if typeof(n) == "number" and n == n and n > 0 then
			explicit = math.clamp(math.floor(n), 1, 1_000_000_000)
		end
		if cmd == "cash" or not explicit then
			local okGrant, granted = grantAdminPlaytestCashFloor(player)
			if deps.NotificationService then
				if okGrant then
					deps.NotificationService.Notify(player, string.format("Admin cash set to $%s", tostring(granted)), "Success")
				else
					deps.NotificationService.Notify(player, "Admin cash grant failed", "Warn")
				end
			end
		elseif explicit and EconomyService then
			EconomyService.AddCash(player, explicit, "admin")
			if deps.NotificationService then
				deps.NotificationService.Notify(player, string.format("Gave $%s", tostring(explicit)), "Success")
			end
		end
	end

	AdminService._OnAdminChat = onAdminChat -- test hook (headless sim has no Player.Chatted)

	local function hookPlayerChat(player: Player)
		player.Chatted:Connect(function(message: string)
			onAdminChat(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hookPlayerChat)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(hookPlayerChat, p)
	end

	-- v54: TextChatService backup — modern chat often does NOT fire Player.Chatted
	-- Optional mid-session admin recovery (main cash path is LoadProfile CreateDefault + DS v2).
	local function wireTextChatCommands()
		local okCmd, errCmd = pcall(function()
			local parent = TextChatService:FindFirstChild("WE_AdminCommands")
			if not parent then
				parent = Instance.new("Folder")
				parent.Name = "WE_AdminCommands"
				parent.Parent = TextChatService
			end
			local function ensureCommand(name: string, primary: string, secondary: string?)
				local existing = parent:FindFirstChild(name)
				if existing and existing:IsA("TextChatCommand") then
					return existing :: TextChatCommand
				end
				local cmd = Instance.new("TextChatCommand")
				cmd.Name = name
				cmd.PrimaryAlias = primary
				if secondary then
					cmd.SecondaryAlias = secondary
				end
				cmd.Parent = parent
				return cmd
			end
			local cashCmd = ensureCommand("WE_Cash", "/cash", "/givecash")
			cashCmd.Triggered:Connect(function(textSource: TextSource, unfilteredText: string)
				local player = Players:GetPlayerByUserId(textSource.UserId)
				if player then
					onAdminChat(player, unfilteredText)
				end
			end)
			-- v71: owner playtest level / XP (admin allowlist only; see onAdminChat)
			for _, spec in ipairs({ { "WE_Level", "/level", "/setlevel" }, { "WE_XP", "/xp", "/givexp" }, { "WE_KeepBase", "/givekeepbase" }, { "WE_NationReset", "/nationreset" } }) do
				local c = ensureCommand(spec[1], spec[2], spec[3])
				if spec[1] == "WE_NationReset" then
					-- nations: never offered in chat autocomplete (lead decision 6: nothing of the feature shows for
					-- non-admins before the flag art is live); the admin still types it
					local cmdAny: any = c
					pcall(function()
						cmdAny.AutocompleteVisible = false
					end)
				end
				c.Triggered:Connect(function(textSource: TextSource, unfilteredText: string)
					local player = Players:GetPlayerByUserId(textSource.UserId)
					if player then
						onAdminChat(player, unfilteredText)
					end
				end)
			end
		end)
		if not okCmd then
			warn("[AdminService] TextChatCommand wire failed:", errCmd)
		end
		-- Also listen on MessageReceived (covers typed /cash when TextChatCommand unavailable)
		local okMsg, errMsg = pcall(function()
			TextChatService.MessageReceived:Connect(function(message: TextChatMessage)
				local text = message.Text
				if typeof(text) ~= "string" then
					return
				end
				local lower = string.lower((string.gsub(text, "^%s+", "")))
				local isAdminLine = string.sub(lower, 1, 5) == "/cash"
					or string.sub(lower, 1, 9) == "/givecash"
					or string.sub(lower, 1, 6) == "/level"
					or string.sub(lower, 1, 9) == "/setlevel"
					or string.sub(lower, 1, 3) == "/xp"
					or string.sub(lower, 1, 7) == "/givexp"
					or string.sub(lower, 1, 13) == "/givekeepbase"
					or string.sub(lower, 1, 12) == "/nationreset"
				if not isAdminLine then
					return
				end
				local src = message.TextSource
				if not src then
					return
				end
				local player = Players:GetPlayerByUserId(src.UserId)
				if player then
					onAdminChat(player, text)
				end
			end)
		end)
		if not okMsg then
			warn("[AdminService] TextChat MessageReceived wire failed:", errMsg)
		end
	end
	task.defer(wireTextChatCommands)
end

return AdminService
