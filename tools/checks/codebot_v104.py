# Code Bot v104 (2026-09-29): JOB 13 engagement live for ALL players (owner: "switch all of JOB 13 on"), with the exploit
# guards for an all-players rollout, + the Bud Studios Discord invite as policy-gated plain text in the Codes panel.
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb104_.
import subprocess as _cb104_sp
import sys as _cb104_sys
_cb104_S = "src/ServerScriptService/Server/"
_cb104_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_cb104_SH = "src/ReplicatedStorage/Shared/"
_cb104_EC = _cb104_SH + "Configs/EngagementConfig.luau"
_cb104_ES = _cb104_S + "Services/EngagementService.luau"

# ── build ──
# v105 (Code Bot): retired build pins, superseded in tools/checks/codebot_v105.py:
#for _f in (_cb104_S + "Services/DataService.luau", _cb104_S + "Services/BaseService.luau", _cb104_S + "EarlyRemotes.server.luau"):
#    must_contain(_f, 'SetAttribute("WE_Build", 104)', "CODEBOT v104: WE_Build=104 " + _f.rsplit("/", 1)[-1])
#must_contain(_cb104_S + "Services/DataService.luau", "WE_Build=104", "CODEBOT v104: DataService profile-loaded log says WE_Build=104")

# ── every JOB 13 rollout is "all" ──
_cb104_e = read(_cb104_EC) or ""
_cb104_ro = re.search(r"\tRollout = \{(.*?)\n\t\}", _cb104_e, re.S)
_cb104_vals = dict(re.findall(r'(\w+) = "(\w+)"', _cb104_ro.group(1))) if _cb104_ro else {}
for _k in ("Events", "Leaderboards", "Invite", "Friends", "Comeback"):
    (ok if _cb104_vals.get(_k) == "all" else bad)(f"CODEBOT v104: EngagementConfig.Rollout.{_k} = all ({_cb104_vals.get(_k)})")

# ── exploit guards (static) ──
must_contain(_cb104_EC, "InviteDailyCap = 5,", "CODEBOT v104: invite daily cap kept (5)")
must_contain(_cb104_EC, "InviteNewPlayerSeconds = 900,", "CODEBOT v104: invite only for a brand-new account")
must_contain(_cb104_ES, "return player:IsFriendsWithAsync(ref)", "CODEBOT v104: invite needs a real Roblox friendship")
must_contain(_cb104_ES, "if not okF or isFriend ~= true or player.Parent == nil or profile.ReferredBy ~= nil then", "CODEBOT v104: a failed friend check pays nothing")
must_contain(_cb104_ES, "saveNow(player) -- v104: ReferredBy is on disk before the inviter is paid", "CODEBOT v104: ReferredBy saved right away")
must_contain(_cb104_ES, "if live(\"Invite\", player) and persistent(player) then", "CODEBOT v104: queued invites only claimed on a saved profile")
must_contain(_cb104_EC, "FriendsDailyCap = 30000,", "CODEBOT v104: friends bonus daily cap")
must_contain(_cb104_ES, "local amount = math.min(room, E.FriendsCashPerTick * n)", "CODEBOT v104: friends bonus paid within the daily cap")
must_contain(_cb104_ES, "n = math.min(n, E.FriendsCap)", "CODEBOT v104: friends bonus still max 3 friends")
must_contain(_cb104_EC, "WriteMinGapSeconds = 60,", "CODEBOT v104: board write gap 60 s")
# v107 BOARDS: throttle moved to LeaderboardConfig.WriteDue; pin kept via claude_bud_boards.py + codebot_v107
# must_contain(_cb104_ES, "return -- v104: throttled (one write per player per WriteMinGapSeconds)", "CODEBOT v104: board writes throttled per player")
must_contain(_cb104_ES, "if not force and not LeaderboardConfig.WriteDue(lastWriteAt[player.UserId], now) then", "CODEBOT v104→BOARDS: board writes throttled per player")
# must_contain(_cb104_ES, "if v and prev[b.Id] ~= v and writeBudgetOk() then", "CODEBOT v104: unchanged scores skipped + write budget respected")
must_contain(_cb104_ES, "if v > 0 and prev[key] ~= v and budgetOk(Enum.DataStoreRequestType.SetIncrementSortedAsync) then", "CODEBOT v104→BOARDS: unchanged/zero scores skipped + write budget")
# must_contain(_cb104_ES, "if uid and not isBoardExcluded(uid) and #rows < E.TopN then", "CODEBOT v104: admin accounts never shown on a board")
must_contain(_cb104_ES, "if uid and not isBoardExcluded(uid) then", "CODEBOT v104→BOARDS: admin accounts never shown on a board")
must_contain(_cb104_ES, "if not persistent(player) or tonumber(profile.ComebackPaidFor) == prev then", "CODEBOT v104: comeback once per absence, saved profile only")
must_contain(_cb104_S + "Modules/ProfileSchema.luau", "profile.ComebackPaidFor = nonNegInt(profile.ComebackPaidFor)", "CODEBOT v104: ComebackPaidFor sanitised in the save")
must_contain(_cb104_S + "Modules/ProfileSchema.luau", "profile.FriendsPaid = nonNegInt(profile.FriendsPaid)", "CODEBOT v104: FriendsPaid sanitised in the save")
_cb104_mc = read(_cb104_SH + "Configs/MonetizationConfig.luau") or ""
_cb104_ex = re.search(r"CashMultExemptReasons = \{(.*?)\n\t\}", _cb104_mc, re.S)
for _r in ("invite_welcome", "invite_reward", "friends_bonus", "comeback"):
    (ok if _cb104_ex and re.search(r"\b" + _r + r" = true", _cb104_ex.group(1)) else bad)(f"CODEBOT v104: {_r} is multiplier-exempt (the caps are the real caps)")
must_contain(_cb104_ES, "econ.AddCash(p, amount, reason)", "CODEBOT v104: every engagement reward is paid by the server (EconomyService.AddCash)")
must_not_contain(_cb104_CL + "Modules/EngagementClient.luau", "FireServer", "CODEBOT v104: the engagement client sends nothing to the server (display only)")

# ── Discord invite: plain text, policy-gated, never a link ──
_cb104_SC = _cb104_SH + "Configs/SocialConfig.luau"
_cb104_CC = _cb104_CL + "Controllers/CodesController.luau"
must_contain(_cb104_SC, '\tDiscordInvite = "https://discord.gg/tkjA2DFBmZ",', "CODEBOT v104: SocialConfig.DiscordInvite = the Bud Studios server")
must_contain(_cb104_SC, '\tDiscordInviteText = "Discord: discord.gg/tkjA2DFBmZ",', "CODEBOT v104: plain-text invite line (no scheme)")
must_contain(_cb104_SC, '\tDiscordText = "Join Bud Studios Discord for free codes!",', "CODEBOT v104: SocialConfig.DiscordText kept")
must_contain(_cb104_CC, 'local inviteLabel = label("DiscordInvite", "", 16,', "CODEBOT v104: invite shown in a TextLabel")
must_contain(_cb104_CC, "PolicyService:GetPolicyInfoForPlayerAsync(player)", "CODEBOT v104: invite line gated by PolicyService")
must_contain(_cb104_CC, 'if ref == "Discord" then', "CODEBOT v104: only when AllowedExternalLinkReferences lists Discord")
must_contain(_cb104_CC, "inviteLabel.Text = inviteText", "CODEBOT v104: the label shows SocialConfig.DiscordInviteText")
_cb104_ct = read(_cb104_CC) or ""
(bad if re.search(r"https?://|discord\.gg|DiscordInvite\b(?!Text)|SetClipboard|OpenBrowserWindow", _cb104_ct.replace('"DiscordInvite"', "")) else ok)(
    "CODEBOT v104: Codes panel has no URL / raw DiscordInvite / clickable-link API")
(bad if re.search(r"DiscordInvite\b(?!Text)", "\n".join(read(p) or "" for p in (_cb104_CL + "Controllers/ShopController.luau", _cb104_CL + "Controllers/SettingsController.luau"))) else ok)(
    "CODEBOT v104: the raw invite URL is not used by other client panels")

# ── untouched ──
must_contain(_cb104_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v104: WE_Building untouched")
must_not_contain(_cb104_SH + "Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v104: PreferMesh stays OFF")

# ── executed: the real EngagementService under the Luau CLI (exploit guards for a non-owner account) ──
try:
    _cb104_r = _cb104_sp.run([_cb104_sys.executable, str(ROOT / "tools/engagement_gate_test.py")], capture_output=True, text=True, timeout=120)
    _cb104_out = _cb104_r.stdout + _cb104_r.stderr
    _cb104_last = [l for l in _cb104_out.splitlines() if l.startswith("engagement_gate_test") or l.startswith("SKIP")]
    (ok if _cb104_r.returncode == 0 else bad)("CODEBOT v104: tools/engagement_gate_test.py " + (_cb104_last[-1] if _cb104_last else _cb104_out[-300:]))
except Exception as _e:
    bad("CODEBOT v104: tools/engagement_gate_test.py did not run: %s" % _e)
