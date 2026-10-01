--!strict
--[[ Code Bot v185: DOUBLE WEEKEND server side (Shared/Configs/EventConfig). The one place the grants ask "how much
	extra right now". Server only: os.time() is the server's UTC clock; the owner preview switch is a ReplicatedStorage
	attribute only the server writes (a client-side attribute change never replicates to the server). ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("EventConfig")) :: any

local DoubleEvent = {}

function DoubleEvent.PreviewOn(): boolean
	local v = ReplicatedStorage:GetAttribute(EventConfig.PreviewAttr)
	if v == nil then
		return EventConfig.OwnerFirst == true
	end
	return v == true
end

-- owner /eventpreview on|off (AdminService); also published so the owner's client banner follows it
function DoubleEvent.SetPreview(on: boolean)
	ReplicatedStorage:SetAttribute(EventConfig.PreviewAttr, on == true)
end

function DoubleEvent.Init()
	if ReplicatedStorage:GetAttribute(EventConfig.PreviewAttr) == nil then
		ReplicatedStorage:SetAttribute(EventConfig.PreviewAttr, EventConfig.OwnerFirst == true)
	end
end

-- Code Bot v192: the one-time DOUBLE WEEKEND pop-up's "seen" flag. profile.EventPopupSeen = { [EventConfig.Id] = unix }
-- (a NEW profile field; no existing key renamed), replicated as the EventConfig.PopupSeenAttr player attribute
-- (true / false, written once the profile has loaded, so the client waits for it before it decides).
local popupData: any = nil

local function seenIn(profile: any): boolean
	local t = if typeof(profile) == "table" then profile.EventPopupSeen else nil
	return typeof(t) == "table" and (tonumber(t[EventConfig.Id]) or 0) > 0
end

function DoubleEvent.MarkPopupSeen(player: Player)
	pcall(function()
		player:SetAttribute(EventConfig.PopupSeenAttr, true)
	end)
	local profile = popupData and popupData.GetProfile(player)
	if typeof(profile) ~= "table" or seenIn(profile) then
		return
	end
	local t = if typeof(profile.EventPopupSeen) == "table" then profile.EventPopupSeen else {}
	t[EventConfig.Id] = os.time()
	profile.EventPopupSeen = t
	pcall(popupData.MarkDirty, player)
end

-- owner /eventpopup reset: forget his seen flag (so a rejoin shows the real first-time flow again)
function DoubleEvent.ResetPopupSeen(player: Player)
	local profile = popupData and popupData.GetProfile(player)
	if typeof(profile) == "table" and typeof(profile.EventPopupSeen) == "table" then
		profile.EventPopupSeen[EventConfig.Id] = nil
		pcall(popupData.MarkDirty, player)
	end
	pcall(function()
		player:SetAttribute(EventConfig.PopupSeenAttr, false)
	end)
end

-- called from RetentionService.Init (deps: DataService, RemoteSetup, RateLimitService)
function DoubleEvent.InitPopup(deps: { [string]: any })
	popupData = deps.DataService
	if popupData and popupData.OnProfileLoaded then
		popupData.OnProfileLoaded(function(player: Player, profile: any)
			pcall(function()
				player:SetAttribute(EventConfig.PopupSeenAttr, seenIn(profile))
			end)
		end)
	end
	local Constants = require(ReplicatedStorage.Shared.Constants) :: any
	local ev = deps.RemoteSetup and deps.RemoteSetup.Get(Constants.RemoteNames.RequestEventPopupSeen)
	if ev == nil then
		warn("[DoubleEvent] RequestEventPopupSeen remote missing; the pop-up seen flag is session-only")
		return
	end
	ev.OnServerEvent:Connect(function(player: Player, id: any)
		if not require(script.Parent.RemoteGate).Check(player, "RequestEventPopupSeen", id) then
			return
		end
		if id ~= EventConfig.Id then
			return
		end
		if deps.RateLimitService and not deps.RateLimitService.Allow(player, "event_popup_seen", 1, 2) then
			return
		end
		DoubleEvent.MarkPopupSeen(player)
	end)
end

function DoubleEvent.ActiveFor(player: Player?): boolean
	if typeof(player) ~= "Instance" then
		return false
	end
	return EventConfig.ActiveFor((player :: Player).UserId, os.time(), DoubleEvent.PreviewOn())
end

local function clampMult(m: any): number
	local n = tonumber(m) or 1
	if n ~= n or n < 1 then
		return 1
	end
	return math.min(n, 5)
end

function DoubleEvent.IsKillReason(reason: string?): boolean
	return reason ~= nil and EventConfig.KillReasons[reason] == true
end

-- cash x for `reason` (called only inside EconomyService's non-exempt stack): kill reasons -> KillMult
function DoubleEvent.CashMult(player: Player, reason: string?): number
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	local key = reason or ""
	if EventConfig.KillReasons[key] then
		return clampMult(EventConfig.KillMult)
	end
	if EventConfig.CashExemptReasons[key] then
		return 1
	end
	return clampMult(EventConfig.CashMult)
end

-- Code Bot v197: cash x for a 2x-pass-EXEMPT `reason` (EconomyService.cashMultFor's exempt branch): CashMult only for
-- EventConfig.ExtraCashReasons (never a kill / CashExemptReasons reason), else 1
function DoubleEvent.ExtraCashMult(player: Player, reason: string?): number
	local key = reason or ""
	local extra = EventConfig.ExtraCashReasons
	if extra == nil or extra[key] ~= true or EventConfig.CashExemptReasons[key] or EventConfig.KillReasons[key] then
		return 1
	end
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	return clampMult(EventConfig.CashMult)
end

-- XP x for `reason` (XPService.AddXP, after the pass multiplier's own exemptions): kill reasons -> KillMult
function DoubleEvent.XPMult(player: Player, reason: string?): number
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	local key = reason or ""
	if EventConfig.KillReasons[key] then
		return clampMult(EventConfig.KillMult)
	end
	if EventConfig.XPExemptReasons[key] then
		return 1
	end
	return clampMult(EventConfig.XPMult)
end

-- how many a kill counts for (missions KillPlayer / KillNPC, MOST KILLS / ARMY KILLS boards)
function DoubleEvent.KillCount(player: Player): number
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	return math.floor(clampMult(EventConfig.KillMult))
end

-- offline pay factor for a counted span [fromUnix, fromUnix + seconds): only the part inside the window is doubled
function DoubleEvent.OfflineFactor(fromUnix: number, seconds: number): number
	if seconds <= 0 then
		return 1
	end
	local inside = EventConfig.OverlapSeconds(fromUnix, fromUnix + seconds)
	return 1 + (clampMult(EventConfig.CashMult) - 1) * inside / seconds
end

return DoubleEvent
