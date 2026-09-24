--!strict
--[[
	SERVER-AUTHORITATIVE walk-over upgrade purchase.

	Primary buy path: Touched on WE_UpgradeSlot plinths + spatial HRP check.
	Validates PlotId == profile.BasePlotId (Studio: teleport home instead of silent fail),
	debounces per player+structure, then BaseService.PurchaseUpgrade.
	Client WorldPromptController FireServer remains secondary (B-menu / backup).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local ConsoleBuyConfig = require(Shared.Configs.ConsoleBuyConfig)
local ConsoleLocator = require(Shared.Util.ConsoleLocator)

local UpgradePadService = {}

local DataService: any = nil
local BaseService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil

-- v65: never index nil DataService
local function getDataService(): any
	if DataService ~= nil then
		return DataService
	end
	local ok, mod = pcall(require, script.Parent.DataService)
	if ok and mod ~= nil then
		DataService = mod
		warn("[UpgradePad] getDataService: recovered via require(script.Parent.DataService)")
		return DataService
	end
	warn("[UpgradePad] getDataService: DataService still nil after require fallback")
	return nil
end

local TAG = Constants.Tags.UpgradeSlot
local DEBOUNCE_SEC = 1.0
local OVERLAP_MARGIN = 4.0 -- wide AABB so kits / edges never miss
local SPATIAL_INTERVAL = 0.2

local lastAttempt: { [string]: number } = {}
local attached: { [BasePart]: boolean } = {}
local partConns: { [BasePart]: { RBXScriptConnection } } = {}
local lastOverlap: { [string]: boolean } = {}

local function attemptKey(userId: number, structureId: string): string
	return tostring(userId) .. "|" .. structureId
end

local function padKey(part: BasePart, structureId: string): string
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" then
		return tostring(pid) .. "|" .. structureId
	end
	return structureId
end

local function trackConn(part: BasePart, conn: RBXScriptConnection)
	local list = partConns[part]
	if not list then
		list = {}
		partConns[part] = list
	end
	table.insert(list, conn)
end

local function detach(part: BasePart)
	local list = partConns[part]
	if list then
		for _, c in ipairs(list) do
			c:Disconnect()
		end
		partConns[part] = nil
	end
	attached[part] = nil
end

-- v68: consoles (BaseLayoutConfig) are bought by prompt / BUY tap only — never by walking into them
local function isConsole(part: BasePart): boolean
	return part:GetAttribute("WE_Console") == true
end

local function hardenPad(part: BasePart)
	part.CanTouch = not isConsole(part)
	part.CanCollide = true
	part.CanQuery = true
	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CanTouch = false
			child.CanQuery = false
		end
	end
end

local function pointInPad(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 4
		and localPos.Y <= half.Y + 12
end

local function isSeated(character: Model): boolean
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local seat = hum.SeatPart
	if seat == nil then
		return false
	end
	return seat:IsA("VehicleSeat") or seat:IsA("Seat")
end

local function flashPad(part: BasePart)
	local original = part.Color
	local originalMat = part.Material
	part.Color = Color3.fromRGB(80, 255, 120)
	part.Material = Enum.Material.Neon
	task.delay(0.35, function()
		if part.Parent then
			part.Color = original
			part.Material = originalMat
		end
	end)
end

local function firePurchaseResult(player: Player, structureId: string, result: any)
	-- v63: prefer BaseService.AckBuyResult (attributes + PurchaseResult) so client never times out
	if BaseService and BaseService.AckBuyResult then
		pcall(function()
			BaseService.AckBuyResult(player, structureId, result)
		end)
		return
	end
	pcall(function()
		if not RemoteSetup then
			return
		end
		local ev = RemoteSetup.Get(Constants.RemoteNames.PurchaseResult)
		if ev and ev:IsA("RemoteEvent") then
			(ev :: RemoteEvent):FireClient(player, {
				Ok = result.Ok == true,
				Error = result.Error,
				StructureId = structureId,
				NewLevel = result.NewLevel,
				Cash = result.Cash,
			})
		end
	end)
end

local function notifyPurchaseResult(player: Player, structureId: string, result: any, fromStanding: boolean?)
	firePurchaseResult(player, structureId, result)
	if not NotificationService then
		warn("[UpgradePad] NotificationService nil — toast skipped for", structureId, result.Error)
		return
	end
	local def = BaseConfig.Structures[structureId]
	if result.Ok then
		local name = if def then def.DisplayName else tostring(structureId)
		-- "%s Lv %d": FredokaOne has no "→" (HUD v70 spec §4.2 / risk #5)
		NotificationService.Notify(
			player,
			string.format("Purchase SUCCESSFUL! %s Lv %d", name, result.NewLevel or 0),
			"Success",
			4
		)
	else
		-- v71 (HUD v70 spec §4.1 / §4.2): one failed purchase = one line — the client words every PurchaseResult
		-- error itself (WorldPromptController), so the server only adds what the client cannot see.
		local err = result.Error or "Failed"
		local msg: string? = if err == "NoProfile"
			then "Profile still loading — try BUY again"
			elseif err == "RateLimited"
			then "Buying too fast — wait a moment"
			else nil
		if msg then
			-- Standing on pad must NOT spam every spatial tick (~0.85–1.2s cooldown)
			local cd = if fromStanding then 1.1 else 0.75
			local key = "pad|" .. err .. "|" .. structureId
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, msg, "Warn", 3.5, cd, key)
			else
				NotificationService.Notify(player, msg, "Warn", 3.5)
			end
		end
	end
end

local function tryServerPurchase(player: Player, part: BasePart, structureId: string, fromStanding: boolean?)
	local DS = getDataService()
	if not DS then
		print(string.format("[UpgradePad] BUY FAIL %s %s — NoDataService", player.Name, structureId))
		-- the client words this failure from PurchaseResult (one failed purchase = one line)
		firePurchaseResult(player, structureId, { Ok = false, Error = "NoDataService" })
		return
	end
	local profile = DS.GetProfile(player)
	if not profile and DS.EnsureProfile then
		profile = DS.EnsureProfile(player)
	end
	if not profile then
		print(string.format("[UpgradePad] BUY FAIL %s %s — NoProfile", player.Name, structureId))
		firePurchaseResult(player, structureId, { Ok = false, Error = "NoProfile" })
		if NotificationService then
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, "Profile still loading — try BUY again", "Warn", 3, 2.5, "pad|NoProfile")
			else
				NotificationService.Notify(player, "Profile still loading — try BUY again", "Warn", 3)
			end
		end
		return
	end

	-- Assign a plot if this player has none yet. v68: never fall back to plot 1 — that handed a 7th+ player
	-- another player's base. With no free plot, BaseService.PurchaseUpgrade answers NoPlot (with a toast).
	if profile.BasePlotId == nil then
		if BaseService and BaseService.AssignPlot then
			pcall(function()
				BaseService.AssignPlot(player)
			end)
			profile = getDataService().GetProfile(player) or profile
		end
	end

	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" and profile.BasePlotId ~= nil and pid ~= profile.BasePlotId then
		local key = attemptKey(player.UserId, structureId)
		local now = os.clock()
		local last = lastAttempt[key] or 0
		if now - last >= DEBOUNCE_SEC then
			lastAttempt[key] = now
			-- Always teleport + toast so WrongPlot never silent-fails (esp. Studio)
			if BaseService and BaseService.TeleportToPlot then
				BaseService.TeleportToPlot(player)
			end
			print(string.format("[UpgradePad] WrongPlot %s tried plot=%s own=%s → teleport", player.Name, tostring(pid), tostring(profile.BasePlotId)))
			if NotificationService then
				if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, "Not your base — teleported to YOUR plot", "Warn", 2.5, 1.2, "wrongplot")
			else
				NotificationService.Notify(player, "Not your base — teleported to YOUR plot", "Warn", 2.5)
			end
			end
		end
		return
	end

	local key = attemptKey(player.UserId, structureId)
	local now = os.clock()
	local last = lastAttempt[key] or 0
	if now - last < DEBOUNCE_SEC then
		return
	end

	-- v64: never index nil BaseUpgrades
	if typeof(profile.BaseUpgrades) ~= "table" then
		profile.BaseUpgrades = {}
	end
	if typeof(profile.Stats) ~= "table" then
		profile.Stats = { UpgradesPurchased = 0 }
	end
	local def = BaseConfig.Structures[structureId]
	local current = tonumber(profile.BaseUpgrades[structureId]) or 0
	if def and current >= def.MaxLevel then
		lastAttempt[key] = now
		if not fromStanding then
			notifyPurchaseResult(player, structureId, { Ok = false, Error = "MaxLevel" })
		end
		return
	end

	lastAttempt[key] = now

	if RateLimitService and not RateLimitService.Allow(player, "purchase_upgrade", 6, 8) then
		print(string.format("[UpgradePad] BUY RATE-LIMIT %s %s", player.Name, structureId))
		if NotificationService and not fromStanding then
			NotificationService.Notify(player, "Buying too fast — wait a moment", "Warn", 2.5)
		end
		return
	end

	print(string.format("[UpgradePad] BUY ATTEMPT %s %s plot=%s standing=%s", player.Name, structureId, tostring(profile.BasePlotId), tostring(fromStanding == true)))
	-- v64: pcall so pad path never throws past ack (same ServerError surface as remote)
	local callOk, callResult = pcall(function()
		-- v71: AtPart = this console / pad, so the server checks the character against the part that was used
		return BaseService.PurchaseUpgrade(player, structureId, { AtPart = part, Source = if isConsole(part) then "Prompt" else "Pad" })
	end)
	local result: any
	if not callOk then
		local errStr = tostring(callResult or "unknown")
		if #errStr > 180 then
			errStr = string.sub(errStr, 1, 180)
		end
		warn("[UpgradePad] PurchaseUpgrade threw:", errStr)
		pcall(function()
			player:SetAttribute("WE_BuyErr", errStr)
		end)
		result = { Ok = false, Error = "ServerError" }
	else
		result = callResult
	end
	if result.Ok then
		print(string.format("[UpgradePad] BUY OK %s %s → Lv %s", player.Name, structureId, tostring(result.NewLevel)))
	else
		print(string.format("[UpgradePad] BUY FAIL %s %s → %s", player.Name, structureId, tostring(result.Error)))
	end
	notifyPurchaseResult(player, structureId, result, fromStanding)
	if result.Ok then
		flashPad(part)
	end
end

local function onPadTouched(part: BasePart, hit: BasePart)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	if isSeated(character) then
		return
	end
	local structureId = part:GetAttribute("StructureId")
	if typeof(structureId) ~= "string" then
		return
	end
	local key = padKey(part, structureId) .. "|" .. tostring(player.UserId)
	if lastOverlap[key] then
		return
	end
	lastOverlap[key] = true
	tryServerPurchase(player, part, structureId, false)
end

local function attachSlot(part: BasePart)
	if attached[part] then
		hardenPad(part)
		return
	end
	if not part:IsA("BasePart") then
		return
	end
	local structureId = part:GetAttribute("StructureId")
	if typeof(structureId) ~= "string" then
		return
	end

	attached[part] = true
	hardenPad(part)

	local console = isConsole(part)
	trackConn(part, part.Touched:Connect(function(hit)
		if not console and hit:IsA("BasePart") then
			onPadTouched(part, hit)
		end
	end))

	trackConn(part, part.TouchEnded:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local sid = part:GetAttribute("StructureId")
		if typeof(sid) ~= "string" then
			return
		end
		local key = padKey(part, sid) .. "|" .. tostring(player.UserId)
		task.defer(function()
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and pointInPad(hrp.Position, part) then
				return
			end
			lastOverlap[key] = false
		end)
	end))

	trackConn(part, part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detach(part)
		end
	end))

	-- v62 nuclear backup: server ProximityPrompt.Triggered (no client remotes)
	local existingPrompt = part:FindFirstChild("WE_ServerBuyPrompt")
	if existingPrompt then
		existingPrompt:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WE_ServerBuyPrompt"
	prompt.ActionText = if console then "Build / Upgrade" else "Buy"
	local def = BaseConfig.Structures[structureId]
	prompt.ObjectText = if def then def.DisplayName else structureId
	-- v68: consoles need a short hold so walking past never buys
	prompt.HoldDuration = if console then ConsoleBuyConfig.ConsoleHoldSeconds else ConsoleBuyConfig.PadHoldSeconds
	prompt.MaxActivationDistance = if console then ConsoleBuyConfig.ConsolePromptDistance else ConsoleBuyConfig.PadPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = part
	trackConn(part, prompt.Triggered:Connect(function(who: Player)
		local character = who.Character
		if character and isSeated(character) then
			return
		end
		print(string.format("[UpgradePad] ProximityPrompt BUY %s %s", who.Name, structureId))
		tryServerPurchase(who, part, structureId, false)
	end))
end

local function countAttached(): number
	local n = 0
	for part in pairs(attached) do
		if part.Parent then
			n += 1
		end
	end
	return n
end

local function scanAndTagFromSetup(): number
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local retagged = 0
	local function consider(desc: Instance)
		if not desc:IsA("BasePart") then
			return
		end
		local sid = desc:GetAttribute("StructureId")
		local pid = desc:GetAttribute("PlotId")
		if typeof(sid) == "string" and typeof(pid) == "number" then
			if not CollectionService:HasTag(desc, TAG) then
				CollectionService:AddTag(desc, TAG)
			end
			hardenPad(desc)
			attachSlot(desc)
			retagged += 1
		end
	end
	if setup then
		local bases = setup:FindFirstChild("Bases")
		if bases then
			for _, desc in ipairs(bases:GetDescendants()) do
				consider(desc)
			end
		end
	end
	return retagged
end

-- v63: nuclear Workspace sweep — any BasePart with StructureId (+ optional PlotId)
local function scanEntireWorkspaceForStructureId(): number
	local n = 0
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			local sid = desc:GetAttribute("StructureId")
			if typeof(sid) == "string" and sid ~= "" then
				local pid = desc:GetAttribute("PlotId")
				if typeof(pid) ~= "number" then
					-- default PlotId=1 so first player can buy CommandCenter even without tag
					desc:SetAttribute("PlotId", 1)
					pid = 1
				end
				if not CollectionService:HasTag(desc, TAG) then
					CollectionService:AddTag(desc, TAG)
				end
				hardenPad(desc)
				attachSlot(desc)
				n += 1
			end
		end
	end
	return n
end

local function bindExistingAndFuture()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			attachSlot(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			attachSlot(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			detach(inst)
		end
	end)
end

local function startSpatialLoop()
	local acc = 0
	local rescanAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		rescanAcc += dt
		-- v63: if zero pads, re-sweep Workspace every 5s
		if rescanAcc >= 5 then
			rescanAcc = 0
			if countAttached() == 0 then
				scanAndTagFromSetup()
				if countAttached() == 0 then
					scanEntireWorkspaceForStructureId()
				end
			end
		end
		if acc < SPATIAL_INTERVAL then
			return
		end
		acc = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				if isSeated(character) then
					local uid = tostring(player.UserId)
					local suffix = "|" .. uid
					for key in pairs(lastOverlap) do
						if string.sub(key, -#suffix) == suffix then
							lastOverlap[key] = false
						end
					end
				else
					local hrp = character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						local pos = hrp.Position
						for part in pairs(attached) do
							if part.Parent and not isConsole(part) then
								local structureId = part:GetAttribute("StructureId")
								if typeof(structureId) == "string" then
									local key = padKey(part, structureId) .. "|" .. tostring(player.UserId)
									local inside = pointInPad(pos, part)
									if inside then
										if not lastOverlap[key] then
											lastOverlap[key] = true
											tryServerPurchase(player, part, structureId, false)
										else
											tryServerPurchase(player, part, structureId, true)
										end
									elseif lastOverlap[key] then
										lastOverlap[key] = false
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

function UpgradePadService.Init(deps: { [string]: any })
	assert(deps.DataService, "UpgradePadService.Init missing deps.DataService")
	DataService = deps.DataService
	BaseService = deps.BaseService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup

	bindExistingAndFuture()
	local initCount = countAttached()
	print(string.format("[WAR EMPIRE] UpgradePadService Init: attached=%d tagged=%d", initCount, #CollectionService:GetTagged(TAG)))
	if initCount == 0 then
		local scanned = scanAndTagFromSetup()
		print(string.format("[WAR EMPIRE] UpgradePadService: scanned Bases → attached=%d", scanned))
		if countAttached() == 0 then
			local swept = scanEntireWorkspaceForStructureId()
			warn(string.format("[WAR EMPIRE] UpgradePadService: Init Workspace StructureId sweep attached=%d", swept))
		end
	end

	startSpatialLoop()

	-- v71: stamp each console's world position on its owner (WE_ConsolePos_<StructureId>) so the Base panel GO
	-- waypoint still finds it when StreamingEnabled has streamed the console out on that client. A missing console
	-- means that structure cannot be bought on this plot (console-only buying): say so loudly, once per plot ready.
	if BaseService and BaseService.OnPlotReady then
		BaseService.OnPlotReady(function(player: Player, plotId: number)
			local missing: { string } = {}
			for _, sid in ipairs(BaseConfig.StructureOrder) do
				local part = ConsoleLocator.Find(plotId, sid)
				player:SetAttribute("WE_ConsolePos_" .. sid, if part then part.Position else nil)
				if part == nil then
					table.insert(missing, sid)
				end
			end
			if #missing > 0 then
				warn(string.format("[UpgradePad] plot %d has NO buy point for %s — unbuyable until the map rebuilds", plotId, table.concat(missing, ", ")))
			end
		end)
	end

	task.defer(function()
		task.wait(1)
		for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
			if inst:IsA("BasePart") then
				attachSlot(inst)
			end
		end
		local after = countAttached()
		print(string.format("[WAR EMPIRE] UpgradePadService after-map: attached=%d", after))
		if after == 0 then
			local scanned = scanAndTagFromSetup()
			warn(string.format("[WAR EMPIRE] UpgradePadService: ZERO pads after map — Bases scan attached=%d", scanned))
			if countAttached() == 0 then
				local swept = scanEntireWorkspaceForStructureId()
				warn(string.format("[WAR EMPIRE] UpgradePadService: Workspace StructureId sweep attached=%d", swept))
			end
		end
	end)

	print("[WAR EMPIRE] UpgradePadService ready (server walk-over buy, margin=" .. tostring(OVERLAP_MARGIN) .. ")")
end

return UpgradePadService
