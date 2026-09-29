# claude-bud JOB 4 (2026-09-29): new features, each behind its own owner-only flag, server-authoritative.
# Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbf_.
_cbf_sdc = "src/ReplicatedStorage/Shared/Configs/SupplyDropConfig.luau"
_cbf_sds = "src/ServerScriptService/Server/Services/SupplyDropService.luau"
_cbf_fc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/FeatureController.luau"
_cbf_const = "src/ReplicatedStorage/Shared/Constants.luau"
_cbf_rs = "src/ServerScriptService/Server/Modules/RemoteSetup.luau"

# shared: the FeaturePush remote (server -> client only; nobody listens on the server)
must_contain(_cbf_const, 'FeaturePush = "FeaturePush",', "CLAUDE-BUD features: FeaturePush remote name")
must_contain(_cbf_rs, "Constants.RemoteNames.FeaturePush, -- claude-bud JOB 4/5", "CLAUDE-BUD features: FeaturePush is created")
(ok if "FeaturePush" not in "".join((read(p) or "") for p in [
    "src/ServerScriptService/Server/Services/SupplyDropService.luau"]) or "OnServerEvent" not in (read(_cbf_sds) or "") else bad)(
    "CLAUDE-BUD features: no FeaturePush OnServerEvent (display cues only)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau", 'safeInit("FeatureController"', "CLAUDE-BUD features: FeatureController starts")

# 4.1 airdrop
must_contain(_cbf_sdc, '\tAirdrop = {\n\t\tRollout = "owner",', "CLAUDE-BUD airdrop: owner-only first")
must_contain(_cbf_sdc, "\t\tIntervalSeconds = 600,", "CLAUDE-BUD airdrop: every 10 minutes")
must_contain(_cbf_sdc, "\t\treturn AdminConfig.IsPlaytestOwner(userId)\n\tend\n\treturn false\nend", "CLAUDE-BUD airdrop: AirdropLiveFor fails closed")
must_contain(_cbf_sds, "if airdrop and not SupplyDropConfig.AirdropLiveFor(player.UserId) then", "CLAUDE-BUD airdrop: only players it is live for can claim")
must_contain(_cbf_sds, "if airdrop and rec.Landed ~= true then", "CLAUDE-BUD airdrop: no claim while it falls")
must_contain(_cbf_sds, 'EconomyService.AddCash(player, rec.ClaimCash, "supply_drop")', "CLAUDE-BUD airdrop: cash granted on the server (first to hold)")
must_contain(_cbf_sds, "if SupplyDropConfig.AirdropLiveFor(p.UserId) then\n\t\t\tev:FireClient(p, \"Airdrop\", data)", "CLAUDE-BUD airdrop: the marker goes only to players it is live for")
must_contain(_cbf_sds, "if not r.Airdrop then -- claude-bud: the airdrop never takes a crate slot", "CLAUDE-BUD airdrop: the old crates are unchanged (MaxActive 2)")
must_contain(_cbf_fc, 'ObjectiveMarker.ShowWith({ Short = label, X = x, Y = y, Z = z }, { TimeoutSeconds = 300 })', "CLAUDE-BUD airdrop: map marker via the one objective marker")
