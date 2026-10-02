"""Code Bot Roblox v209 (2026-10-02): Starter5 public one-time offer at 120 s.
The 5 R$ prices/Ids are unchanged; this guard also proves public non-owner shop ordering.
"""
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V209_PREV", "29467a2")
C = ROOT / "src/ReplicatedStorage/Shared/Configs"
S = ROOT / "src/ServerScriptService/Server"


def read(p):
    return (ROOT / p).read_text(encoding="utf-8").replace("\r\n", "\n")


def old(p):
    r = subprocess.run(["git", "show", PREV + ":" + p], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.replace("\r\n", "\n") if r.returncode == 0 else ""


def check(ok, msg):
    print(("PASS " if ok else "FAIL ") + "CODEBOT v209: " + msg)
    if not ok:
        raise SystemExit(1)

for rel in (
    "Services/BaseService.luau",
    "Services/DataService.luau",
    "EarlyRemotes.server.luau",
):
    check('SetAttribute("WE_Build", 218)' in read(S / rel), "WE_Build=218 " + rel)
check("WE_Build=218" in read(S / "Services/DataService.luau"), "DataService loaded log says WE_Build=218")

mc = read(C / "MonetizationConfig.luau")
check("OwnerFirst = false" in mc[mc.index(").Starter5 = {") : mc.index(").Starter5 = {") + 700], "Starter5 remains public")
check(re.search(r"Starter5\s*=.*?OfferAfterPlaySeconds\s*=\s*120", mc, re.S) is not None,
      "Starter5 OfferAfterPlaySeconds is 120 s")
check(len(re.findall(r"OfferAfterPlaySeconds\s*=\s*120", mc)) == 1, "only Starter5 was changed to 120 s")

# No price or product identity changes relative to the v208 source tip.
prev_mc = old("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
for key in ("StarterRecruit5", "Boost2x10m"):
    a = re.search(r"\b" + key + r"\s*=\s*\{[^\n]*", mc)
    b = re.search(r"\b" + key + r"\s*=\s*\{[^\n]*", prev_mc)
    check(a and b and re.findall(r"\b(?:Id|RobuxPrice)\s*=\s*\d+", a.group()) == re.findall(r"\b(?:Id|RobuxPrice)\s*=\s*\d+", b.group()),
          key + " Id and RobuxPrice unchanged")

for rel in ("Services/BaseService.luau", "Services/DataService.luau", "EarlyRemotes.server.luau"):
    before = old("src/ServerScriptService/Server/" + rel)
    after = read(S / rel)
    check(not any("WE_Building" in x for x in __import__("difflib").ndiff(before.splitlines(), after.splitlines()) if x.startswith(("+ ", "- "))),
          "no WE_Building* change in " + rel)

# Reuse the real Luau service/controller simulations, including uid 9 (non-owner).
def run(script):
    r = subprocess.run(["python3", str(ROOT / script)], cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True, timeout=120)
    print((r.stdout + r.stderr).strip())
    return r.returncode == 0

check(run("tools/sim/run_starter5_test.py"), "run_starter5_test: 0 failed")
check(run("tools/sim/run_shop_render_test.py"), "run_shop_render_test: non-owner uid 9 0 failed")

check('"StreamingEnabled": true' not in read("default.project.json"), "StreamingEnabled stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C / "StructureVisualConfig.luau"), "PreferMesh stays OFF")
check(not any("WE_Building" in x for x in subprocess.run(["git", "diff", "--", "src"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines() if x.startswith(("+", "-"))), "no WE_Building* source diff")
print("CODEBOT v209: 0 failed")
