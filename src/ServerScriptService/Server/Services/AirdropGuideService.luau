--!strict
--[[ Code Bot board-text (Shaun: "let me turn the yellow airdrop guide line off"). Server side of Settings ->
	"Airdrop guide line: ON / OFF" (SupplyDropConfig.GuideHide, PUBLIC. Saved per player in the NEW key
	profile.Settings.AirdropGuideOff (true | nil: no other save key is read or written), mirrored as the player attribute
	GuideHide.Attr, which the client's FeatureController (no automatic AIRDROP line) and SettingsController (the row's
	label) read. Validated (RemoteGate boolean schema), rate-limited, refused only when the public switch is disabled.
	Display only: the airdrop itself, its claim and its cash are unchanged (SupplyDropService). ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local SupplyDropConfig = require(Shared.Configs.SupplyDropConfig)
local Constants = require(Shared.Constants)

local AirdropGuideService = {}

function AirdropGuideService.Init(deps: { [string]: any })
	local G: any = SupplyDropConfig.GuideHide
	local DataService = deps.DataService
	local RemoteSetup = deps.RemoteSetup
	local RateLimitService = deps.RateLimitService
	if typeof(G) ~= "table" or G.Enabled ~= true or DataService == nil or RemoteSetup == nil then
		return
	end
	local function push(player: Player, profile: any)
		local st = if typeof(profile.Settings) == "table" then profile.Settings else nil
		player:SetAttribute(G.Attr, if st and st[G.SettingKey] == true then true else nil)
	end
	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestAirdropGuideSetting) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, off: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestAirdropGuideSetting", off) then
			return
		end
		if typeof(off) ~= "boolean" or not SupplyDropConfig.GuideHideLiveFor(player.UserId) then
			return
		end
		if RateLimitService and not RateLimitService.Allow(player, "airdrop_guide_setting", 1, 3) then
			return
		end
		local profile = DataService.GetProfile(player)
		if profile == nil then
			return
		end
		if typeof(profile.Settings) ~= "table" then
			profile.Settings = {}
		end
		profile.Settings[G.SettingKey] = if off then true else nil
		DataService.MarkDirty(player)
		push(player, profile)
	end)
	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if SupplyDropConfig.GuideHideLiveFor(player.UserId) then
			pcall(push, player, profile)
		end
	end)
end

return AirdropGuideService
