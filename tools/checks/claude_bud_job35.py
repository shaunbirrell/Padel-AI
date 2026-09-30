# claude-bud JOB 35 (2026-09-30): the PREMIUM GUNS ARMORY, owner-first (PremiumGunsConfig.Live): six Robux guns
# (WeaponConfig Premium defs, MonetizationConfig PG_* passes at Id 0), GunMechanics (burst / spin / charge / pierce /
# headshot mult) in CombatService.RequestFire, WeaponAssetLoader plain models, the scope, the base armory cases and the
# Shop WEAPONS gold rows. Static pins + the real-code test (tools/sim/run_armory_test.py).
import os as _j35_os
import subprocess as _j35_sp
import sys as _j35_sys
from pathlib import Path as _J35P

if "ok" not in globals():
    _j35_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j35_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J35P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j35(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J35: " + msg)


def _j35_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j35_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j35_src(path).splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_PGC = _j35_src("src/ReplicatedStorage/Shared/Configs/PremiumGunsConfig.luau")
_MCF = _j35_src("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
_WC = _j35_src("src/ReplicatedStorage/Shared/Configs/WeaponConfig.luau")
_CS = _j35_code(_SV + "Services/CombatService/init.luau")
_PGS = _j35_code(_SV + "Services/PremiumGunService.luau")
_WAL = _j35_code(_SV + "Modules/WeaponAssetLoader.luau")
_CC = _j35_code(_CL + "Controllers/CombatController.luau")
_SC = _j35_code(_CL + "Controllers/ShopController.luau")
_SCO = _j35_code(_CL + "Modules/Scope.luau")

# gate + no Robux changes elsewhere: every new pass Id 0, prices in MonetizationConfig only, not in RolloutKeys
_j35("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false, -- codebot_v136 launch" in _PGC and "RetentionConfig.Live(PremiumGunsConfig.Live, userId)" in _PGC,
     "one kill switch (PremiumGunsConfig.Live; v136: OwnerFirst=false, everyone; superseded in codebot_v136.py)")
for _k, _p, _id in (("PG_Sovereign", 99, 2002154652), ("PG_Quake", 249, 2003492417), ("PG_Longshot", 299, 2003180431), ("PG_Havoc", 349, 2002250646), ("PG_Thunderhead", 399, 1999305818), ("PG_Tempest", 499, 2002682646), ("PG_ArmoryPass", 1299, 2002868467)):
    _j35(("\t\t%s = {\n\t\t\tId = %d,\n" % (_k, _id)) in _MCF and ("RobuxPrice = %d," % _p) in _MCF, "%s: live Id %d, R$ %d in MonetizationConfig" % (_k, _id, _p))
_j35('"PG_' not in _MCF.split("RolloutKeys", 1)[1].split("\n", 1)[0], "PG_* passes are not in RolloutKeys (they use their live Ids directly)")
_j35("RobuxPrice" not in _PGC and "RobuxPrice" not in _PGS.replace("d.RobuxPrice", ""), "no price typed outside MonetizationConfig")
# guns: premium, never sold for Cash; ownership only from the pass
_j35(_WC.count("premiumGun({") == 6 and "d.Premium = true" in _WC and "d.CostCash = 0" in _WC, "six WeaponConfig premium guns (Premium, CostCash 0)")
_j35('return false, "RobuxOnly"' in _CS and "(def :: any).Premium == true" in _CS, "Cash purchase refuses premium guns")
_j35("if not owns(profile, weaponId) then\n\t\treturn false, \"NotOwned\"" in _CS, "equip still refuses unowned guns")
_j35("ms.OnPassOwned(function(player: Player, passKey: string, reason: string)" in _PGS and "PremiumGunsConfig.UnlockedBy({ [passKey] = true })" in _PGS
     and "profile.Weapons[id] = true" in _PGS, "owning a PG_* pass (join + purchase, via OnPassOwned) sets profile.Weapons[id] = true")
_j35("MarketplaceService:PromptGamePassPurchase(player, id)" in _PGS and "if id == 0 then\n\t\treturn" in _PGS, "the armory prompts only a real pass Id (Id 0 = SOON, never prompted)")
# mechanics: server-authoritative, nil = unchanged
_j35("GunMechanics.Prime(def, mech, clock(), payload.Prime)" in _CS and "if not GunMechanics.Ready(def, mech, clock()) then" in _CS
     and "minInterval = GunMechanics.Interval(def, mech, clock(), minInterval)" in _CS and "GunMechanics.OnShot(def, mech, clock())" in _CS,
     "RequestFire: spin / charge primes, burst interval, all decided on the server")
_j35("pierceOn(player, def, state.WeaponId, damage, origin, direction, range, shotFilter, body)" in _CS and "local hit = CombatService.ApplyHit(player, r.Instance" in _CS,
     "Pierce re-casts past each body and every extra hit goes through ApplyHit (the one PvP rule)")
_j35("(tonumber(opts.HeadshotMult) or CombatFeelConfig.HeadshotMult)" in _CS, "per-gun HeadshotMult (nil = the global one)")
# loader: plain models, scripts stripped, part cap kept
_j35("if tool == nil and o.VisualPlain == true then" in _WAL and "if d:IsA(\"LuaSourceContainer\") or d:IsA(\"Sound\") then" in _WAL
     and "local MAX_PARTS = 16" in _WAL and 'sw.Name = "WE_SpinWeld"' in _WAL, "loader: plain Model / MeshPart guns, scripts stripped, 16-part cap, spinning barrel")
# client: scope + touch
_j35("Scope.Set(1)" in _CC and "Scope.Cycle()" in _CC and 'HudLayout.AssertTouchTarget(sc, "SCOPE")' in _CC and "Scope.Start(function(): boolean" in _CC,
     "scope: hold RMB / L2, the phone SCOPE button (touch target), auto-exit")
_j35("S.Levels[math.min(n, #S.Levels)]" in _SCO and "UserInputService.MouseDeltaSensitivity = savedSens * fov / S.BaseFov" in _SCO
     and "Enum.RenderPriority.Last.Value + 1" in _SCO and "Enum.RenderPriority.Camera.Value - 2" in _SCO,
     "scope: FOV levels, sensitivity x FOV/70, sway applied after the shake and undone before CameraFx")
_j35("Levels = { 20, 12 }" in _PGC and "BaseFov = 70" in _PGC and "RecoilMult = 0.5" in _PGC, "scope numbers: FOV 70 -> 20 -> 12, recoil x0.5")
_j35("pcall(cf.Kick, wid, Scope.RecoilMult())" in _CC, "recoil x0.5 while scoped")
# armory: parts, light, labels
_j35(_PGS.count("Instance.new(\"PointLight\")") == 1 and "light.Shadows = false" in _PGS and "CastShadow = false" in _PGS.replace("p.CastShadow = false", "CastShadow = false"),
     "armory: one light for the row, Shadows off, no part shadows")
_j35("BaseLabel = true" in _PGS and "MaxDistance = A.LabelMaxDistance" in _PGS and "LabelMaxDistance = 40" in _PGC, "armory boards: base labels (the governor shows the 3 nearest), MaxDistance 40")
_j35("GlassTransparency = 0.6" in _PGC and "if stateName == \"Owned\" then A.OwnedGlassTransparency" in _PGS, "glass 0.6; once owned the glass fades and the prompt says Equip")
# shop
_j35("premiumKey and premiumSold" in _SC and "PremiumGunsConfig.LiveFor(player.UserId)" in _SC and 'promptGamePass(tostring((def :: any).PassKey), "shop")' in _SC,
     "Shop WEAPONS: gold premium rows, only while live and the pass has an Id")

_luau = _j35_os.environ.get("LUAU")
if _luau is None and _j35_os.environ.get("LUAU_COMPILE"):
    _cand = _j35_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j35_os.path.isfile(_cand) else None
if _luau:
    _r = _j35_sp.run([_j35_sys.executable, "tools/sim/run_armory_test.py"], capture_output=True, text=True, env=dict(_j35_os.environ, LUAU=_luau))
    _j35(_r.returncode == 0 and "ARMORY TEST: 0 failed" in _r.stdout, "run_armory_test.py (real mechanics / configs / service / loader)")
else:
    print("SKIP CLAUDE-BUD J35: Luau CLI test (set LUAU)")
