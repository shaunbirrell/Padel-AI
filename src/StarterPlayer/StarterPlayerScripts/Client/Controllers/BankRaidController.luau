--!strict
--[[
	Empire Bank raid HUD — v70 "clean screen": the vault hold bar is a top-centre stack item (spec §3.4, slot
	"Progress"; was a 340×78 card at (0.5, 0, 1, -330) in the middle of the screen). One ProgressPill:
	  in the vault, nothing held yet  "STAND TO LOOT $15K–$35K"   0%
	  holding                         "RAIDING EMPIRE BANK"       62%   gold bar
	  under fire                      "UNDER FIRE · CLEAR GUARDS" 62%   red bar + red edge
	  cooldown (standing on the vault) "EMPIRE BANK COOLDOWN"      4m    grey
	Shows while InVault / HoldProgress > 0 / UnderFire (BankRaidStateUpdate), hidden while Dead.
	Display only: the server decides every payout.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local HudConfig = require(Shared.Configs.HudConfig)
local Remotes = require(Shared.Remotes)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local ProgressPill = require(script.Parent.Parent.Modules.ProgressPill)

local BankRaidController = {}

local player = Players.LocalPlayer

local _gui: ScreenGui? = nil
local pill: ProgressPill.Pill? = nil
local active = false -- the server says the local player is at / in the vault (see Apply)

local UNDER_FIRE = Color3.fromRGB(255, 96, 72)
local HOLD_FILL = HudConfig.Colors.Gold

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

function BankRaidController.Apply(payload: BankRaidStatePayload)
	if payload.Enabled == false then
		setVisible(false)
		return
	end

	local inVault = payload.InVault == true
	local underFire = payload.UnderFire == true
	local hold = tonumber(payload.HoldProgress) or 0
	local need = tonumber(payload.HoldNeed) or tonumber(payload.RaidHoldSeconds) or 8
	if need <= 0 then
		need = 8
	end
	local cd = math.max(0, math.floor(tonumber(payload.CooldownRemaining) or 0))
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

function BankRaidController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireBankRaid"
	-- Core safe insets + the one HUD UIScale; DisplayOrder from HudConfig (32: above the capture bar's gui)
	HudLayout.ApplyScreen(screen, { Insets = "Core" })
	screen.Parent = player:WaitForChild("PlayerGui")
	_gui = screen

	local p = ProgressPill.Build(screen, "BankRaidProgress")
	pill = p
	HudLayout.BindVisibility(p.Frame, { HideWhen = { "Dead" } }, function(): boolean
		return active
	end)
	HudLayout.RegisterTopStack("BankRaid", p.Frame, HudConfig.TopStack.Order.Progress, { Space = "Hud" })

	Remotes.BindEvent(Constants.RemoteNames.BankRaidStateUpdate, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		BankRaidController.Apply(payload :: BankRaidStatePayload)
	end)

	print("[WAR EMPIRE] BankRaidController ready")
end

return BankRaidController
