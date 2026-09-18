--!strict
--[[ Battle Pass track preview rebuild (extracted from ProgressionController). ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local ProgressionUI = require(script.Parent.ProgressionUI)

local ProgressionBattlePass = {}

function ProgressionBattlePass.RebuildTrackPreview(trackList: ScrollingFrame?, bpState: any)
	if not trackList or typeof(bpState) ~= "table" then
		return
	end
	for _, child in ipairs(trackList:GetChildren()) do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyState") then
			child:Destroy()
		end
	end

	local level = tonumber(bpState.Level) or 0
	local freeTrack = bpState.FreeTrack or {}
	local premTrack = bpState.PremiumTrack or {}
	local claimedFree = bpState.ClaimedFree or {}
	local claimedPrem = bpState.ClaimedPremium or {}
	local premium = bpState.Premium == true

	local tiers: { number } = {}
	local seen: { [number]: boolean } = {}
	for t in pairs(freeTrack) do
		local n = tonumber(t)
		if n and not seen[n] then
			seen[n] = true
			table.insert(tiers, n)
		end
	end
	for t in pairs(premTrack) do
		local n = tonumber(t)
		if n and not seen[n] then
			seen[n] = true
			table.insert(tiers, n)
		end
	end
	table.sort(tiers)

	local rows = 0
	local maxRows = 14
	for _, tier in ipairs(tiers) do
		if rows >= maxRows then
			break
		end
		local freeR = freeTrack[tier] or freeTrack[tostring(tier)]
		local premR = premTrack[tier] or premTrack[tostring(tier)]
		local freeClaimed = claimedFree[tostring(tier)] == true
		local premClaimed = claimedPrem[tostring(tier)] == true
		local reached = tier <= level
		local freeReady = reached and freeR ~= nil and not freeClaimed
		local premReady = reached and premium and premR ~= nil and not premClaimed
		local interesting = freeReady
			or premReady
			or (reached and ((freeR ~= nil and not freeClaimed) or (premR ~= nil and not premClaimed)))
			or (not reached and tier <= level + 6)
		local skip = (not interesting) and (rows > 0 or tier > level + 3)
		if not skip then
			rows += 1
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -6, 0, 28)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = tier
			row.Parent = trackList
			UIUtil.Corner(row, 4)

			local status = "locked"
			if freeReady or premReady then
				status = "READY"
			elseif reached then
				status = "claimed"
				if (freeR and not freeClaimed) or (premR and not premClaimed and not premium) then
					status = if premium then "partial" else "free done / need Prem"
				end
			end

			local freeTxt = ProgressionUI.FormatReward(freeR)
			local premTxt = ProgressionUI.FormatReward(premR)
			local lab = Instance.new("TextLabel")
			lab.BackgroundTransparency = 1
			lab.Position = UDim2.fromOffset(6, 0)
			lab.Size = UDim2.new(1, -70, 1, 0)
			lab.Font = Enum.Font.Gotham
			lab.TextSize = 11
			lab.TextXAlignment = Enum.TextXAlignment.Left
			lab.TextColor3 = if (freeReady or premReady) then Constants.Colors.Cash else Constants.Colors.Muted
			lab.Text = string.format(
				"L%d  Free:%s  Prem:%s  [%s]",
				tier,
				if freeTxt ~= "" then freeTxt else "-",
				if premTxt ~= "" then premTxt else "-",
				status
			)
			lab.Parent = row

			if freeReady then
				local claimBtn = Instance.new("TextButton")
				claimBtn.AnchorPoint = Vector2.new(1, 0.5)
				claimBtn.Position = UDim2.new(1, -4, 0.5, 0)
				claimBtn.Size = UDim2.fromOffset(52, 22)
				claimBtn.BackgroundColor3 = Constants.Colors.Accent
				claimBtn.Font = Enum.Font.GothamBold
				claimBtn.TextSize = 10
				claimBtn.TextColor3 = Constants.Colors.Text
				claimBtn.Text = "CLAIM"
				claimBtn.BorderSizePixel = 0
				UIUtil.Corner(claimBtn, 4)
				claimBtn.Parent = row
				local claimTier = tier
				claimBtn.MouseButton1Click:Connect(function()
					Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(claimTier, "free")
				end)
			elseif premReady then
				local claimBtn = Instance.new("TextButton")
				claimBtn.AnchorPoint = Vector2.new(1, 0.5)
				claimBtn.Position = UDim2.new(1, -4, 0.5, 0)
				claimBtn.Size = UDim2.fromOffset(52, 22)
				claimBtn.BackgroundColor3 = Constants.Colors.Gold
				claimBtn.Font = Enum.Font.GothamBold
				claimBtn.TextSize = 10
				claimBtn.TextColor3 = Constants.Colors.Background
				claimBtn.Text = "CLAIM"
				claimBtn.BorderSizePixel = 0
				UIUtil.Corner(claimBtn, 4)
				claimBtn.Parent = row
				local claimTier = tier
				claimBtn.MouseButton1Click:Connect(function()
					Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(claimTier, "premium")
				end)
			end
		end
	end

	if rows == 0 then
		UIUtil.EmptyState(
			trackList,
			"No battle pass rows yet — earn XP from gameplay to unlock Free/Premium track rewards.",
			0
		)
	end
end


return ProgressionBattlePass
