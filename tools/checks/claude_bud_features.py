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

# 4.2 daily login reward: auto-claimed through the existing server claim (once per UTC day, saved in DailyLogin)
_cbf_drc = "src/ReplicatedStorage/Shared/Configs/DailyRewardConfig.luau"
_cbf_ms = "src/ServerScriptService/Server/Services/MissionService.luau"
must_contain(_cbf_drc, '\tAutoClaim = {\n\t\tRollout = "owner",', "CLAUDE-BUD daily: auto-claim owner-only first")
must_contain(_cbf_drc, "\t\treturn AdminConfig.IsPlaytestOwner(userId)\n\tend\n\treturn false\nend", "CLAUDE-BUD daily: AutoClaimLiveFor fails closed")
_cbf_days = [int(x) for x in re.findall(r"\{ Day = \d+, Cash = (\d+),", read(_cbf_drc) or "")]
(ok if len(_cbf_days) == 7 and all(b > a for a, b in zip(_cbf_days, _cbf_days[1:])) else bad)(f"CLAUDE-BUD daily: 7-day streak with rising cash {_cbf_days}")
must_contain(_cbf_ms, "if DailyRewardConfig.AutoClaimLiveFor(player.UserId) then", "CLAUDE-BUD daily: auto-claim gated per player")
must_contain(_cbf_ms, "local okClaim = MissionService.ClaimDailyLogin(player)", "CLAUDE-BUD daily: auto-claim reuses the server claim (idempotent per day)")
must_contain(_cbf_ms, "\tif daily.LastClaimDay == today then", "CLAUDE-BUD daily: one claim per UTC day")
must_contain(_cbf_ms, "\tdaily.LastClaimDay = today\n\tdaily.LastClaimUnix = os.time()", "CLAUDE-BUD daily: the streak day is saved in the profile")
must_contain(_cbf_ms, "\tDataService.MarkDirty(player)\n\tMissionService.Push(player)\n\treturn true, nil\nend\n\nfunction MissionService.Start", "CLAUDE-BUD daily: the claim marks the save dirty")
