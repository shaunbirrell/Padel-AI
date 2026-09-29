--!strict
--[[
	claude-bud JOB 4/5 (2026-09-29): client side of the server's FeaturePush cues (Constants.RemoteNames.FeaturePush,
	server -> this client only; the server fires it only to players a feature is live for, so nothing here gates).
	Display only: every reward is decided on the server.
	  "Airdrop"  { Show = true, X, Y, Z, Cash } -> the one objective marker ("AIRDROP") to the landing spot
	             { Show = false }               -> clears it if it is still the airdrop
	  "Bounty"   { Show = true, X, Y, Z }       -> the objective marker ("BOUNTY") on the Central Plaza
	             { Show = false }               -> clears it if it is still the bounty
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Remotes = require(Shared.Remotes)
local Constants = require(Shared.Constants)

local FeatureController = {}

local LABELS = { Airdrop = "AIRDROP", Bounty = "BOUNTY" }

local function marker(kind: string, data: any)
	local label = LABELS[kind]
	if label == nil or typeof(data) ~= "table" then
		return
	end
	if data.Show == true then
		local x, y, z = tonumber(data.X), tonumber(data.Y), tonumber(data.Z)
		if x and y and z then
			ObjectiveMarker.ShowWith({ Short = label, X = x, Y = y, Z = z }, { TimeoutSeconds = 300 })
		end
	else
		local cur = ObjectiveMarker.Current()
		if cur and cur.Short == label then
			ObjectiveMarker.Clear()
		end
	end
end

function FeatureController.Init()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if typeof(kind) ~= "string" then
			return
		end
		if LABELS[kind] then
			marker(kind, data)
		end
	end)
end

return FeatureController
