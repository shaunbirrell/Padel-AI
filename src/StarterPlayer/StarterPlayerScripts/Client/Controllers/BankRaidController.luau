--!strict
--[[
	Empire Bank raid HUD — v70 "clean screen": the vault hold bar is a top-centre stack item (spec §3.4, slot
	"Progress"; was a 340×78 card at (0.5, 0, 1, -330) in the middle of the screen). One ProgressPill:
	  in the vault, nothing held yet  "STAND TO LOOT $15K–$35K"   0%
	  holding                         "RAIDING EMPIRE BANK"       62%   gold bar
	  under fire                      "UNDER FIRE · CLEAR GUARDS" 62%   red bar + red edge
	  seated on the vault             "LEAVE VEHICLE"             62%   amber bar + amber edge (W3 step 2, lane F)
	  cooldown (standing on the vault) "EMPIRE BANK COOLDOWN"      4m    grey
	Shows while InVault / HoldProgress > 0 / UnderFire (BankRaidStateUpdate), hidden while Dead.

	W3 step 2, lane F: the bank's world label (server: "Empire Bank" / "OPEN · rob the vault" / "RAID ON") shows
	"CLOSED 4m" on THIS client while this player's own saved cooldown runs (the server label is public, the cooldown
	is not). Refreshed at 1 Hz only while a cooldown runs or has just ended; the label is found through the vault's
	CollectionService tag (streaming-safe: no label streamed in → nothing to draw). Display only: the server decides
	every payout.

	streaming2 lane C4 (F22): the kept label counts as live only while it IsDescendantOf(Workspace). When the vault
	streams out, the engine parents the top of what left (the vault, or the bank Model above it) to nil, so the
	label's own Parent stays set; the old `bb.Parent` test kept writing into a label that was not in the world. Now it
	is dropped and found again through the tag once it is back (the LabelGovernor pattern). With streaming off the
	two tests agree: a destroyed label has no Parent.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local HudConfig = require(Shared.Configs.HudConfig)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local Remotes = require(Shared.Remotes)
local WorldLabel = require(Shared.Util.WorldLabel)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local ProgressPill = require(script.Parent.Parent.Modules.ProgressPill)

local BankRaidController = {}

local player = Players.LocalPlayer

local _gui: ScreenGui? = nil
local pill: ProgressPill.Pill? = nil
local active = false -- the server says the local player is at / in the vault (see Apply)

local UNDER_FIRE = Color3.fromRGB(255, 96, 72)
local VEHICLE = Color3.fromRGB(255, 176, 48)
local HOLD_FILL = HudConfig.Colors.Gold
local LABEL = BankRaidConfig.Label

-- this player's own cooldown for the world label's CLOSED line (os.clock deadline; 0 = none)
local closedUntil = 0
local labelOverridden = false
local labelRef: BillboardGui? = nil
local labelLoop = false

export type BankRaidStatePayload = {
	BankId: string?,
	DisplayName: string?,
	Enabled: boolean?,
	CooldownRemaining: number?,
	RaidHoldSeconds: number?,
	HoldNeed: number?,
	HoldProgress: number?,
	InVault: boolean?,
	UnderFire: boolean?,
	Blocked: string?, -- "Vehicle": seated on the vault (no progress until on foot)
	CashHintMin: number?,
	CashHintMax: number?,
}

local function setVisible(visible: boolean)
	if active == visible then
		return
	end
	active = visible
	local p = pill
	if p then
		HudLayout.RefreshVisibility(p.Frame)
	end
end

-- "$15K" / "$1.2M" / "$900" — keeps the loot hint short enough for the 320 v pill
local function shortCash(n: number): string
	local a = math.abs(n)
	if a >= 1e6 then
		local s = string.format("%.1f", n / 1e6):gsub("%.0$", "")
		return "$" .. s .. "M"
	elseif a >= 1e3 then
		local s = string.format("%.1f", n / 1e3):gsub("%.0$", "")
		return "$" .. s .. "K"
	end
	return "$" .. tostring(math.floor(n))
end

-- ── the bank's world label: this player's CLOSED line ───────────────────────────────────────────────────────
local function findLabel(): BillboardGui?
	local bb = labelRef
	if bb and bb:IsDescendantOf(Workspace) then -- F22: Parent stays set when the vault streams out
		return bb
	end
	labelRef = nil
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BankVault)) do
		local g = inst:FindFirstChild(LABEL.Name)
		if g and g:IsA("BillboardGui") then
			labelRef = g
			return g
		end
	end
	return nil
end

-- The line this client shows: CLOSED <m>m while its own cooldown runs, else the server's public state (read back
-- from the label's WE_BankState attribute). Pure: exported for the headless tests.
function BankRaidController.LabelLine(secondsLeft: number, publicState: any): (string, Color3)
	if secondsLeft > 0 then
		return string.format(LABEL.ClosedSub, math.max(1, math.ceil(secondsLeft / 60))), LABEL.ClosedColor
	end
	if publicState == "raid" then
		return LABEL.RaidingSub, LABEL.RaidingColor
	end
	return LABEL.OpenSub, LABEL.OpenColor
end

local function refreshLabel()
	local left = closedUntil - os.clock()
	if left <= 0 and not labelOverridden then
		return
	end
	local bb = findLabel()
	if not bb then
		return -- not streamed in (or no bank): drawn when it is
	end
	local sub, color = BankRaidController.LabelLine(left, bb:GetAttribute(LABEL.StateAttribute))
	labelOverridden = left > 0
	-- SetText writes only what differs; a server change to the label overwrites ours and is redrawn within 1 s
	WorldLabel.SetText(bb, LABEL.Title, sub, color)
end

local function startLabelLoop()
	if labelLoop then
		return
	end
	labelLoop = true
	task.spawn(function()
		while true do
			task.wait(1)
			refreshLabel()
		end
	end)
end

function BankRaidController.Apply(payload: BankRaidStatePayload)
	if payload.Enabled == false then
		setVisible(false)
		return
	end

	local cd = math.max(0, math.floor(tonumber(payload.CooldownRemaining) or 0))
	-- every push carries the authoritative remaining seconds (join, save loaded, loot, in the vault)
	closedUntil = if cd > 0 then os.clock() + cd else 0
	refreshLabel()

	local inVault = payload.InVault == true
	local underFire = payload.UnderFire == true
	local seated = payload.Blocked == "Vehicle"
	local hold = tonumber(payload.HoldProgress) or 0
	local need = tonumber(payload.HoldNeed) or tonumber(payload.RaidHoldSeconds) or 8
	if need <= 0 then
		need = 8
	end
	local name = payload.DisplayName or "Empire Bank"

	local show = inVault or hold > 0 or underFire
	if not show then
		setVisible(false)
		return
	end

	local p = pill
	if p then
		local frac = math.clamp(hold / need, 0, 1)
		if cd > 0 then
			p.Title.Text = string.upper(name) .. " COOLDOWN"
			p.Title.TextColor3 = ProgressPill.Colors.Title
			p.Value.Text = string.format("%dm", math.max(1, math.ceil(cd / 60)))
			p.Fill.BackgroundColor3 = ProgressPill.Colors.Idle
			ProgressPill.SetFraction(p, 0)
			ProgressPill.ResetStroke(p)
		elseif seated then
			p.Title.Text = "LEAVE VEHICLE"
			p.Title.TextColor3 = VEHICLE
			p.Value.Text = ProgressPill.Percent(frac)
			p.Fill.BackgroundColor3 = VEHICLE
			ProgressPill.SetFraction(p, frac)
			ProgressPill.AccentStroke(p, VEHICLE)
		elseif underFire then
			p.Title.Text = "UNDER FIRE · CLEAR GUARDS"
			p.Title.TextColor3 = UNDER_FIRE
			p.Value.Text = ProgressPill.Percent(frac)
			p.Fill.BackgroundColor3 = UNDER_FIRE
			ProgressPill.SetFraction(p, frac)
			ProgressPill.AccentStroke(p, UNDER_FIRE)
		else
			if hold > 0 then
				p.Title.Text = "RAIDING " .. string.upper(name)
			else
				local cashMin = tonumber(payload.CashHintMin) or 15000
				local cashMax = tonumber(payload.CashHintMax) or 35000
				p.Title.Text = string.format("STAND TO LOOT %s–%s", shortCash(cashMin), shortCash(cashMax))
			end
			p.Title.TextColor3 = ProgressPill.Colors.Title
			p.Value.Text = ProgressPill.Percent(frac)
			p.Fill.BackgroundColor3 = HOLD_FILL
			ProgressPill.SetFraction(p, frac)
			ProgressPill.ResetStroke(p)
		end
	end
	setVisible(true)
end

local function playerGui(): PlayerGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	local waited = player:WaitForChild("PlayerGui", 30)
	if waited and waited:IsA("PlayerGui") then
		return waited
	end
	return nil
end

function BankRaidController.Init()
	local pg = playerGui()
	if not pg then
		warn("[WAR EMPIRE] BankRaidController: no PlayerGui after 30 s; bank HUD off")
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireBankRaid"
	-- Core safe insets + the one HUD UIScale; DisplayOrder from HudConfig (32: above the capture bar's gui)
	HudLayout.ApplyScreen(screen, { Insets = "Core" })
	screen.Parent = pg
	_gui = screen

	local p = ProgressPill.Build(screen, "BankRaidProgress")
	pill = p
	HudLayout.BindVisibility(p.Frame, { HideWhen = { "Dead" } }, function(): boolean
		return active
	end)
	HudLayout.RegisterTopStack("BankRaid", p.Frame, HudConfig.TopStack.Order.Progress, { Space = "Hud" })

	startLabelLoop()
	Remotes.BindEvent(Constants.RemoteNames.BankRaidStateUpdate, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		BankRaidController.Apply(payload :: BankRaidStatePayload)
	end)

	print("[WAR EMPIRE] BankRaidController ready")
end

return BankRaidController
