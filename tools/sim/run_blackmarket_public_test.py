"""Code Bot Roblox v157: the weekly Black Market live for EVERY player while every other Endgame part stays owner-first
(EndgameConfig.PublicParts). Real EndgameConfig / EndgameService / EndgameController / BaseTierBuilder on the
run_endgame_test stand-ins (no Studio):
1. GATING: a non-owner (uid 9) has BlackMarket live and no other part; the owner has every part; Live.Enabled = false or
   Parts.BlackMarket = false = off for everyone; CamoLiveFor = Mastery or BlackMarket.
2. SERVICE: the non-owner buys at the Black Market (Cash slot = SpendCash "endgame_market", Gold slot = SpendGold only,
   never Robux), is refused away from the stall and when hurt, and every other endgame purchase says Not open yet.
   State carries Market and no other panel; the station list is the Black Market only; WE_EndgameLive is set, the
   Empire level is not.
3. APPLY: a Black Market camo goes on the gun in his hand and shows (CamoFor) without the Armory; an Armory-only camo
   never shows and cannot be put on; the Armory camo purchase stays refused. Berets / paint / banners follow his
   equipped item; banners show on his gate posts below Tier 4 (4 parts).
4. CLIENT: the Black Market list shows his camo PUT ON row for the gun in his hand.
Run: LUAU=path/to/luau python tools/sim/run_blackmarket_public_test.py   (exit 1 on any failure)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402
from run_endgame_test import MODS, EXTRA  # noqa: E402

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local EG = require(node("Configs/EndgameConfig"))
local OWNER, OTHER = 470626172, 9

-- ── 1. gating ──
-- codebot_v166: Live.OwnerFirst=false (every part for everyone); this test still proves the v157 public-part rule
-- with OwnerFirst = true, then checks the launch at the end
local EG_LAUNCHED = EG.Live.OwnerFirst
check(EG.Live.Enabled == true and EG_LAUNCHED == false, "codebot_v166: Endgame Enabled + OwnerFirst=false (everyone)")
EG.Live.OwnerFirst = true
check(EG.PublicParts.BlackMarket == true, "PublicParts.BlackMarket = true")
local pubCount = 0
for k, v in pairs(EG.PublicParts) do if v == true then pubCount += 1 end end
check(pubCount == 1, "the Black Market is the ONLY public part (" .. pubCount .. ")")
check(EG.LiveFor(OTHER, "BlackMarket") and EG.AnyLiveFor(OTHER), "non-owner: Black Market live")
local leak = {}
for part, on in pairs(EG.Parts) do
  if part ~= "BlackMarket" and EG.LiveFor(OTHER, part) then table.insert(leak, part) end
  if on and not EG.LiveFor(OWNER, part) then table.insert(leak, "owner-missing:" .. part) end
end
check(#leak == 0, "non-owner sees no other part; the owner keeps every part (" .. table.concat(leak, ",") .. ")")
check(EG.CamoLiveFor(OTHER) and not EG.LiveFor(OTHER, "Mastery") and EG.CamoLiveFor(OWNER), "camo wear path: live via the Black Market, the Armory stays owner-only")
EG.Live.Enabled = false
check(not EG.LiveFor(OTHER, "BlackMarket") and not EG.LiveFor(OWNER, "BlackMarket") and not EG.AnyLiveFor(OTHER), "Live.Enabled = false: off for everyone")
EG.Live.Enabled = true
EG.Parts.BlackMarket = false
check(not EG.LiveFor(OTHER, "BlackMarket") and not EG.AnyLiveFor(OTHER) and not EG.CamoLiveFor(OTHER), "Parts.BlackMarket = false: off for everyone")
EG.Parts.BlackMarket = true
local mc = EG.MarketCamos()
check(mc.Urban == "CamoUrban" and mc.Tiger == "CamoTiger" and mc.Gold == "CamoGold" and mc.Olive == nil, "Black Market camos: Urban, Tiger, Gold (Olive is Armory-only)")
local golds = {}
for w = 0, 2 do local s = EG.BlackMarketStock(w); golds[s.Gold] = s.GoldPrice end
check(golds.CamoGold == 100 and golds.BeretGold == 150 and golds.BannerGold == 250, "the Gold slot rotates CamoGold 100 / BeretGold 150 / BannerGold 250")

-- ── 2. service ──
local ES = require(node("Services/EndgameService"))
local spentLog, goldLog = {}, {}
local profiles = {}
local deps = {
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() end, OnProfileLoaded = function() end },
  EconomyService = {
    SpendCash = function(p, n, why) local pr = profiles[p.UserId]; if pr.Cash < n then return false, "Short" end; pr.Cash -= n; table.insert(spentLog, { n = n, why = why }); return true end,
    SpendGold = function(p, n, why) local pr = profiles[p.UserId]; if pr.Gold < n then return false, "Short" end; pr.Gold -= n; table.insert(goldLog, { n = n, why = why }); return true end,
  },
  NotificationService = { Notify = function() end },
}
ES.Init(deps)
local t = 1000
ES._SetClock(function() return t end)
for kind, cf in pairs({ BlackMarket = CFrame.new(0, 5, 300), Command = CFrame.new(100, 5, 200), Armory = CFrame.new(0, 5, 300), Intel = CFrame.new(-300, 5, 300), Recruits = CFrame.new(50, 5, 50), Heist = CFrame.new(229.6, 1.6, -218.5) }) do
  ES._SetStation(kind, cf)
end
local other = mkPlayer(OTHER, ES.StationPoint("BlackMarket"))
BY_UID[OTHER] = other
profiles[OTHER] = { Cash = 5e9, Gold = 1000, Prestige = 3, Endgame = {}, BasePlotId = 4 }
local gun = nil
for id in pairs(require(node("Configs/WeaponConfig")).Weapons) do gun = gun or id end
other:SetAttribute("WE_Weapons", gun)
other:SetAttribute("WE_EquippedWeapon", gun)

ES.SyncAttributes(other)
check(other.attrs.WE_EndgameLive == true and other.attrs.WE_EmpireLevel == nil and other.attrs.WE_BaseTier == nil and other.attrs.WE_MedKits == nil,
  "attributes: WE_EndgameLive (stations / EMPIRE button), no Empire level / tier / med kits")
local st = ES.State(other)
local panels = {}
for _, k in ipairs({ "Empire", "Rebirth", "Tier", "Defence", "Warheads", "Heist", "Intel", "Armory", "Workshop", "Hospital", "Elite" }) do
  if st[k] ~= nil then table.insert(panels, k) end
end
local stations = {}
for k in pairs(st.Stations or {}) do table.insert(stations, k) end
check(st.Live == true and typeof(st.Market) == "table" and #st.Market.Rows == 4 and #panels == 0, "State: the Market panel (3 Cash + 1 Gold rows) and no other panel (" .. table.concat(panels, ",") .. ")")
check(#stations == 1 and stations[1] == "BlackMarket", "State: the only station point is the Black Market (" .. table.concat(stations, ",") .. ")")

-- every other purchase stays owner-only
local refusals = {
  { "Empire", "Next" }, { "Tier", "Next" }, { "Defence", "Plating" }, { "Rebuild", "Now" }, { "Elite", "Infantry" }, { "Retrain", "Now" },
  { "Mastery", gun }, { "Attach", gun .. ":Grip" }, { "Camo", gun .. ":Tiger" }, { "Workshop", "Ground" }, { "Warhead", "Tactical" },
  { "Heist", "Next" }, { "Claim", "D1" }, { "Scout", "4" }, { "Heal", "Now" }, { "MedKit", "One" }, { "Medicine", "Next" }, { "UseMedKit", "One" },
}
local bad = {}
for _, r in ipairs(refusals) do
  local ok, msg = ES.Purchase(other, r[1], r[2])
  if ok or msg ~= EG.Text.NotLive then table.insert(bad, r[1] .. "=" .. tostring(msg)) end
end
check(#bad == 0 and #spentLog == 0 and #goldLog == 0, "every other endgame purchase: Not open yet, nothing spent (" .. table.concat(bad, "; ") .. ")")

-- buy at the Black Market (weeks pinned through os.time)
local realOs = os
local fakeNow = 0
os = setmetatable({ time = function() return fakeNow end }, { __index = realOs })
local function weekWith(pred)
  for w = 2900, 2960 do
    local s = EG.BlackMarketStock(w)
    local id = pred(s)
    if id then fakeNow = EG.BlackMarket.EpochMondayUnix + w * 604800 + 3600; return id, s end
  end
  return nil
end
local cashCamo = weekWith(function(s) for i, id in ipairs(s.Cash) do if EG.BlackMarket.Items[id].Kind == "Camo" then return id end end return nil end)
check(cashCamo ~= nil and ES.MarketStock().Cash[1] ~= nil, "found a week with a Cash camo (" .. tostring(cashCamo) .. ")")
local camoId = EG.BlackMarket.Items[cashCamo].Camo
other.Root.Position = ES.StationPoint("BlackMarket") + Vector3.new(40, 0, 0)
local ok, msg = ES.Purchase(other, "Market", cashCamo)
check(not ok and #spentLog == 0, "away from the stall: refused (" .. tostring(msg) .. ")")
other.Root.Position = ES.StationPoint("BlackMarket")
ES._Hurt(OTHER, t - 2)
ok, msg = ES.Purchase(other, "Market", cashCamo)
check(not ok and msg == EG.Text.Hurt, "hurt 2 s ago: refused")
ES._Hurt(OTHER, nil)
ok, msg = ES.Purchase(other, "Market", cashCamo)
check(ok and #spentLog == 1 and spentLog[1].why == "endgame_market" and spentLog[1].n >= 1e6 and #goldLog == 0, "non-owner buys a Cash slot: SpendCash endgame_market (" .. tostring(msg) .. ")")
local pe = profiles[OTHER].Endgame
check(pe.Camos[camoId] == true and pe.Camos.Equip[gun] == camoId, "the camo is owned and put on the gun in his hand")
check(ES.CamoFor(other, gun) == camoId, "CamoFor shows his Black Market camo without the Armory")
check(ES.Purchase(other, "Market", cashCamo) == false, "one of each")
ok, msg = ES.Purchase(other, "EquipCamo", gun .. ":None")
check(ok and ES.CamoFor(other, gun) == nil, "TAKE OFF works without the Armory")
ok, msg = ES.Purchase(other, "EquipCamo", gun .. ":" .. camoId)
check(ok and ES.CamoFor(other, gun) == camoId, "PUT ON works without the Armory")
pe.Camos.Olive = true
ok, msg = ES.Purchase(other, "EquipCamo", gun .. ":Olive")
check(not ok and msg == EG.Text.NotLive and ES.CamoFor(other, gun) == camoId, "an Armory-only camo cannot be put on without the Armory")
pe.Camos.Equip[gun] = "Olive"
check(ES.CamoFor(other, gun) == nil, "an Armory-only camo never shows without the Armory")
pe.Camos.Equip[gun] = camoId
pe.Camos.Olive = nil
ok, msg = ES.Purchase(other, "EquipCamo", "NotAGun:" .. camoId)
check(not ok, "a gun he does not own is refused")

-- the Gold slot: Gold only
local goldItem = weekWith(function(s) return if s.Gold == "BeretGold" then s.Gold else nil end)
local g0, c0 = profiles[OTHER].Gold, profiles[OTHER].Cash
ok, msg = ES.Purchase(other, "Market", goldItem)
check(ok and profiles[OTHER].Gold == g0 - 150 and profiles[OTHER].Cash == c0 and goldLog[#goldLog].why == "endgame_market", "Gold slot BeretGold: 150 Gold via SpendGold, no Cash (" .. tostring(msg) .. ")")
check(ES.BeretColor(OTHER) == EG.BlackMarket.Items.BeretGold.Color, "his soldiers wear the Gold beret")
profiles[OTHER].Gold = 10
local bannerGold = weekWith(function(s) return if s.Gold == "BannerGold" then s.Gold else nil end)
ok, msg = ES.Purchase(other, "Market", bannerGold)
check(not ok and string.find(msg, "Gold") ~= nil and profiles[OTHER].Gold == 10, "short of Gold: refused (" .. tostring(msg) .. ")")
profiles[OTHER].Gold = 1000
ok, msg = ES.Purchase(other, "Market", bannerGold)
check(ok and profiles[OTHER].Gold == 750 and ES.BannerColor(OTHER) == EG.BlackMarket.Items.BannerGold.Color, "BannerGold 250 Gold: his banner colour is set")
ok, msg = ES.Purchase(other, "MarketEquip", "None:Beret")
check(ok and ES.BeretColor(OTHER) == nil, "MarketEquip takes the beret off")
ok, msg = ES.Purchase(other, "MarketEquip", "BeretGold")
check(ok and ES.BeretColor(OTHER) ~= nil, "MarketEquip puts it back on")
check(ES.Purchase(other, "MarketEquip", "PaintSand") == false, "an item he does not own cannot be equipped")
os = realOs

-- banners on his gate posts below Tier 4
local BTB = require(node("Modules/BaseTierBuilder"))
local post = { CFrame = CFrame.new(0, 5, 0), Size = Vector3.new(2, 10, 2) }
local ctx = { Ground = CFrame.new(0, 0, 0), PadCentre = Vector3.new(0, 0, 0), HalfX = 40, HalfZ = 40, WallTop = 12, GroundY = 0, Posts = { post, post }, Nests = {}, BannerColor = EG.BlackMarket.Items.BannerGold.Color }
local m0 = BTB.Build(ctx, 0)
local ban, total = 0, 0
for _, d in ipairs(m0:GetDescendants()) do
  if d.ClassName == "Part" then total += 1; if d.Name == "GateBanner" and d.Color == ctx.BannerColor then ban += 1 end end
end
check(ban == 2 and total == 4, string.format("tier 0 + a Black Market banner: 2 gate banners in his colour (%d parts)", total))
local ctxN = table.clone(ctx); ctxN.BannerColor = nil
local mN = BTB.Build(ctxN, 0)
local nN = 0
for _, d in ipairs(mN:GetDescendants()) do if d.ClassName == "Part" then nN += 1 end end
check(nN == 0, "no banner bought: nothing extra")

-- ── 4. client list ──
local CT = require(node("Controllers/EndgameController"))
local st2 = ES.State(other)
local rows = CT.ListRows("BlackMarket", st2)
local put = nil
for _, r in ipairs(rows) do if r.Kind == "EquipCamo" then put = r end end
check(st2.Market.Held == gun and #st2.Market.Camos == 1 and put ~= nil and put.Id == gun .. ":None" and put.Label == "TAKE OFF", "Black Market list: his camo row on the gun in his hand (" .. tostring(put and put.Id) .. ")")

EG.Live.OwnerFirst = EG_LAUNCHED
local bmOff = {}
for part, on in pairs(EG.Parts) do if on == true and not EG.LiveFor(OTHER, part) then table.insert(bmOff, part) end end
check(#bmOff == 0 and EG.LiveFor(OTHER, "Mastery") and EG.CamoLiveFor(OTHER), "codebot_v166: launched: a non-owner gets every part, the Armory included (" .. table.concat(bmOff, ",") .. ")")
print(string.format("BLACK MARKET PUBLIC TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip()
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("BLACK MARKET")) or out))
    if r.returncode != 0:
        print(r.stderr.strip()[-2000:])
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
