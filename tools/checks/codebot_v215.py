# Code Bot Roblox v215 (2026-10-02): Shaun approved the v212 Supply Depot board and
# airdrop-guide controls for every player, not just the playtest owner.
# This check proves both config gates are public, the client paths use those gates,
# and the server accepts the non-owner AirdropGuideOff setting. Prices, IDs and saves
# remain unchanged; no WE_Building*, PreferMesh or Streaming changes.
import os
import re
import subprocess
import tempfile
from pathlib import Path

BUILD = 215
ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V215_PREV", "5172ca2")
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def read(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def old(rel):
    r = subprocess.run(["git", "show", PREV + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond, label):
    tag = "CODEBOT v215: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            raise SystemExit(1)


MC = read(C + "MonetizationConfig.luau")
SDC = read(C + "SupplyDropConfig.luau")
RET = read(C + "RetentionConfig.luau")
AGS = read(S + "Services/AirdropGuideService.luau")
FC = read(CL + "Controllers/FeatureController.luau")
SET = read(CL + "Controllers/SettingsController.luau")

# ---- build / the two public switches ----
for rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
    check(('SetAttribute("WE_Build", 218)' in read(rel)) or (rel.endswith("DataService.luau") and "WE_Build=218" in read(rel)),
          "WE_Build=218 " + rel.rsplit("/", 1)[-1])

big = MC[MC.find("\t\tBigSign = {"):MC.find("\t\t},", MC.find("\t\tBigSign = {"))]
guide = SDC[SDC.find("SupplyDropConfig.GuideHide = {"):SDC.find("\n}", SDC.find("SupplyDropConfig.GuideHide = {"))]
check("Enabled = true," in big and "OwnerFirst = false, -- PUBLIC (Code Bot v215)" in big,
      "PremiumPads.BigSign is enabled and public")
check("Enabled = true," in guide and "OwnerFirst = false, -- PUBLIC (Code Bot v215)" in guide,
      "SupplyDropConfig.GuideHide is enabled and public")
check("function cfg.BigSignLiveFor(userId: any): boolean" in MC and "RetentionConfig) :: any).Live(b, userId)" in MC,
      "board client gate is BigSignLiveFor")
check("function SupplyDropConfig.GuideHideLiveFor(userId: any): boolean" in SDC and "RetentionConfig) :: any).Live(SupplyDropConfig.GuideHide, userId)" in SDC,
      "guide client/server gate is GuideHideLiveFor")

# ---- both client paths and the server setting path ----
check("BigSignLiveFor(lp.UserId)" in read(CL + "Modules/StandSignBig.luau"),
      "non-owner board path consults BigSignLiveFor")
check('GuideHideLiveFor(game:GetService("Players").LocalPlayer.UserId)' in FC and "GH.Attr" in FC,
      "non-owner HIDE LINE path consults GuideHideLiveFor and the saved attribute")
check("GuideHideLiveFor(player.UserId)" in SET and 'RequestAirdropGuideSetting' in SET,
      "non-owner Settings toggle is present and uses the public gate")
check('RemoteGate).Check(player, "RequestAirdropGuideSetting", off)' in AGS
      and 'RateLimitService.Allow(player, "airdrop_guide_setting"' in AGS
      and "GuideHideLiveFor(player.UserId)" in AGS,
      "server validates and accepts AirdropGuideOff through the public gate")
check("IsPlaytestOwner" not in AGS,
      "server AirdropGuideOff path has no separate owner-only ignore")
check('profile.Settings[G.SettingKey] = if off then true else nil' in AGS,
      "server still writes only the existing AirdropGuideOff setting")

# ---- real RetentionConfig semantics: a non-owner gets both public blocks ----
if os.path.isfile(LUAU):
    src = RET.replace("--!strict", "").rsplit("return RetentionConfig", 1)[0]
    sim = r'''local RunService = { IsStudio = function() return false end }
local AdminConfig = { IsPlaytestOwner = function(u) return u == 470626172 end }
game = { GetService = function(_, n) return RunService end }
local function require(_) return AdminConfig end
''' + src + r'''
local owner, other = 470626172, 1
local big = { Enabled = true, OwnerFirst = false }
local guide = { Enabled = true, OwnerFirst = false }
assert(RetentionConfig.Live(big, other) == true, "non-owner BigSign gate")
assert(RetentionConfig.Live(guide, other) == true, "non-owner GuideHide gate")
print("PUBLIC_NON_OWNER_BIG true")
print("PUBLIC_NON_OWNER_GUIDE true")
'''
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(sim)
        path = f.name
    try:
        r = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=60)
        out = (r.stdout or "") + (r.stderr or "")
    finally:
        os.unlink(path)
    check(r.returncode == 0 and "PUBLIC_NON_OWNER_BIG true" in out and "PUBLIC_NON_OWNER_GUIDE true" in out,
          "Luau: a non-owner is live for both public gates" + ("" if r.returncode == 0 else " :: " + out[-300:]))

# ---- no prices, IDs, save keys, or prohibited settings changed ----
prev_mc = old(C + "MonetizationConfig.luau")
if prev_mc is not None:
    check(re.findall(r"\bRobuxPrice = \d+", prev_mc) == re.findall(r"\bRobuxPrice = \d+", MC),
          "every RobuxPrice is unchanged from " + PREV)
    check(re.findall(r"\bId = \d+", prev_mc) == re.findall(r"\bId = \d+", MC),
          "every product/pass Id is unchanged from " + PREV)
check(old(S + "Modules/ProfileSchema.luau") == read(S + "Modules/ProfileSchema.luau"),
      "ProfileSchema and existing save keys are unchanged")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "PreferMesh OFF")
check('"StreamingEnabled": true' not in read("default.project.json"), "StreamingEnabled OFF")
diff = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
check("WE_Building" not in (diff.stdout or ""), "no WE_Building* files changed")
