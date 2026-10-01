# claude-bud JOB 55 (2026-10-01): honest Defence text + the exploit fixes (Plating needs Walls L4, Turret Guns arms the
# gate / tower guards, the 0.12 in BaseGuards -> Defence.GatePct, a mid-raid Defence buy never repairs the gate).
# Executed inside tools/BuyPathStatic.py (ok / bad).
from pathlib import Path as _J55P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j55_src(p):
    q = _J55P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_EC = _j55_src("src/ReplicatedStorage/Shared/Configs/EndgameConfig.luau")
_fx = _EC.split("DefenceFix = {")[1].split("\n\t},")[0] if "DefenceFix = {" in _EC else ""
(ok if ("Enabled = true," in _fx and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _fx) else bad)("CLAUDE-BUD J55: EndgameConfig.DefenceFix is owner-first")
_dt = _EC.split("function EndgameConfig.DefenceText")[1].split("\nend\n")[0] if "function EndgameConfig.DefenceText" in _EC else ""
(ok if ("turret + guard dmg" in _dt and "gate + guard HP" in _dt and "ATM" in _dt and "army raid loot" in _dt and "wall" not in _dt.lower()) else bad)(
    "CLAUDE-BUD J55: the Defence text names what each track really does (both Vault cuts; no wall HP promise)")
_ES = _j55_src("src/ServerScriptService/Server/Services/EndgameService.luau")
_nd = _ES.split("function EndgameService.NextDefence")[1].split("\nend\n")[0] if "function EndgameService.NextDefence" in _ES else ""
(ok if ('track == "Plating"' in _nd and "AutoGunMinWallsLevel" in _nd and "EndgameConfig.Text.NeedWalls" in _nd and "DefenceFixLive(uid)" in _nd) else bad)(
    "CLAUDE-BUD J55: Turret Plating needs Walls L4 (no turrets before), shown in the row and refused at purchase")
(ok if "EndgameService.NextDefence(profile, tr, uid)" in _ES else bad)("CLAUDE-BUD J55: the purchase path checks the same walls need as the row")
_rs = _ES.split('if key == "tier" or key == "defence" then')[1].split("\n\tend\n")[0] if 'if key == "tier" or key == "defence" then' in _ES else ""
(ok if ('key == "defence" and EndgameConfig.DefenceFixLive(player.UserId)' in _rs and "gd.RefreshDefence, pid" in _rs and "pcall(gd.SyncPlot, pid)" in _rs) else bad)(
    "CLAUDE-BUD J55: a Defence buy refreshes in place (no full SyncPlot repair mid-raid); OFF / a tier buy = the old resync")
_G = _j55_src("src/ServerScriptService/Server/Services/GateDefenseService.luau")
_rd = _G.split("function GateDefenseService.RefreshDefence")[1].split("\nfunction GateDefenseService.SyncPlot")[0] if "function GateDefenseService.RefreshDefence" in _G else ""
(ok if ("EndgameConfigMod.KeepDamage(oldMax, oldHp, newMax)" in _rd and "if not def.GateBreached then" in _rd and "[DefenseUpgrade]" in _rd and "breachGate" not in _rd and "rebuildGate" not in _rd) else bad)(
    "CLAUDE-BUD J55: RefreshDefence keeps the damage taken, a breached gate stays breached, logs [DefenseUpgrade]")
_BG = _j55_src("src/ServerScriptService/Server/Modules/BaseGuards.luau")
(ok if ("0.12 * L" not in _BG and "Defence.GatePct / 100" in _BG) else bad)("CLAUDE-BUD J55: the post guard HP reads EndgameConfig.Defence.GatePct (the 0.12 is gone)")
(ok if (_BG.count("BaseGuards.GuardDamageMult(def.OwnerUserId, H)") == 2 and '"BaseGuard", H)' in _BG and '"TowerGuard", H)' in _BG) else bad)(
    "CLAUDE-BUD J55: the gate and tower guards fire with GuardDamageMult (Turret Guns while the fix is live)")
