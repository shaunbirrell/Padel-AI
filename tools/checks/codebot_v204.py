# Code Bot Roblox v204 (2026-10-02, Shaun approved): the two 5 R$ starter products (claude-bud JOB 66) get their
# Creator Hub Ids (regional / managed pricing OFF, 5 R$ each): StarterRecruit5 'Recruit Starter Pack' 3715888533 and
# Boost2x10m '2x Income 10 min' 3715888566. Starter5 stays OwnerFirst. The Starter5 pop-up delay is ONE value,
# MonetizationConfig.Starter5.OfferAfterPlaySeconds: 60 s for Shaun's phone test (LIVE VALUE 300; a one-line change).
# No other price / money change. PreferMesh OFF; StreamingEnabled OFF; no WE_Building* diffs.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V204_PREV", "0814f1a")  # v203 code tip (place 201)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
SR5_ID, B10_ID, DELAY = 3715888533, 3715888566, 60


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


BUD = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip
OWN = 'SetAttribute("WE_Build", 205)' in read(S + "Services/DataService.luau")  # this build's own scope

for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 205)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 205)'),
    (S + "Services/DataService.luau", "WE_Build=205"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 205)'),
):
    check(BUD or needle in read(rel), "CODEBOT v204: WE_Build=205 " + rel.rsplit("/", 1)[-1] + (" [bud: skipped]" if BUD else ""))

MON = read(C + "MonetizationConfig.luau")
check(('StarterRecruit5 = { Id = %d, DisplayName = "Recruit Starter Pack", RobuxPrice = 5,' % SR5_ID) in MON,
      "CODEBOT v204: StarterRecruit5 Id 3715888533, 5 R$")
check(('Boost2x10m = { Id = %d, DisplayName = "2x Income 10 min", RobuxPrice = 5,' % B10_ID) in MON,
      "CODEBOT v204: Boost2x10m Id 3715888566, 5 R$")
s5 = MON.split("(MonetizationConfig :: any).Starter5 = {")[1].split("\n}\n")[0] if "(MonetizationConfig :: any).Starter5 = {" in MON else ""
check("Enabled = true," in s5 and "OwnerFirst = true, -- NEW-OWNER-FIRST" in s5, "CODEBOT v204: Starter5 Enabled + OwnerFirst = true kept")
m = re.findall(r"\n\tOfferAfterPlaySeconds = (\d+), (--[^\n]*)", "\n" + s5)
check(len(m) == 1 and int(m[0][0]) == DELAY and "LIVE VALUE IS 300" in m[0][1],
      "CODEBOT v204: Starter5 pop-up delay is ONE value, 60 s (test; comment says live 300)")
check(MON.count("OfferAfterPlaySeconds = 60,") == 1, "CODEBOT v204: only the Starter5 delay is 60 (RecruitPackOffer keeps its own)")
RP = read(S + "Services/RecruitPackService.luau")
check("AfterSeconds = if s5 then MC.Starter5.OfferAfterPlaySeconds else nil" in RP and "300" not in RP.split("local row5")[1].split("Decide({")[0] if "local row5" in RP else False,
      "CODEBOT v204: the offer reads the one config value (no hard-coded 300)")

if not BUD and OWN:
    prev = shipped(C + "MonetizationConfig.luau", PREV)
    a, b = (prev or "").split("\n"), MON.split("\n")
    diff = [(x, y) for x, y in zip(a, b) if x != y]
    allowed = (
        lambda x, y: x.replace("StarterRecruit5 = { Id = 0,", "StarterRecruit5 = { Id = %d," % SR5_ID) == y,
        lambda x, y: x.replace("Boost2x10m = { Id = 0,", "Boost2x10m = { Id = %d," % B10_ID) == y,
        lambda x, y: x.strip().startswith("OfferAfterPlaySeconds = 300,") and y.strip().startswith("OfferAfterPlaySeconds = 60,"),
    )
    check(prev is not None and len(a) == len(b) and len(diff) == 3 and all(any(f(x, y) for f in allowed) for x, y in diff),
          "CODEBOT v204: MonetizationConfig vs " + PREV + ": only the 2 Ids + the Starter5 delay line changed (no price change)")
    for rel in (C + "EconomyConfig.luau", C + "OfflineConfig.luau", C + "RetentionConfig.luau", S + "Services/MonetizationService.luau",
                S + "Services/RecruitPackService.luau", S + "Modules/ProfileSchema.luau"):
        check(shipped(rel, PREV) == read(rel), "CODEBOT v204: " + rel.rsplit("/", 1)[-1] + " byte-identical to " + PREV)
    _pds = shipped(S + "Services/DataService.luau", PREV) or ""
    check(_pds.replace('WE_Build", 203)', 'WE_Build", 205)').replace("WE_Build=203", "WE_Build=205") == read(S + "Services/DataService.luau"),
          "CODEBOT v204: DataService: only the WE_Build number changed (save keys kept)")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v204: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v204: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v204: StreamingEnabled stays OFF")
r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
check(r.returncode == 0 and not [n for n in (r.stdout or "").splitlines() if "WE_Building" in n], "CODEBOT v204: no WE_Building* diffs vs " + PREV)
