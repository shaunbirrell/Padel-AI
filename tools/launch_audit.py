#!/usr/bin/env python3
"""claude-bud JOB 12 (2026-09-29): static end-to-end audit of every game pass and dev product.

For each MonetizationConfig.GamePasses / DevProducts entry it reports:
  Id       non-zero (wired on the Creator Hub)
  Prompt   where a player can buy it (Shop row, Garage ROBUX row, Rebirth panel, pads / offers)
  Grant    what the purchase does on the server (cash / gold / entitlement / saved counter / pass perk reader)
  Keeps    why a rejoin keeps it (pass: UserOwnsGamePassAsync on join; product: saved in the profile before the ack)
and checks the shared receipt rules once (idempotent PurchaseId, save before PurchaseGranted, in-flight lock).
Usage: python tools/launch_audit.py [--markdown]. Exit 1 when a live item has no prompt or no grant.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MC = (ROOT / "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau").read_text(encoding="utf-8")
MS = (ROOT / "src/ServerScriptService/Server/Services/MonetizationService.luau").read_text(encoding="utf-8")
SERVER = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "src/ServerScriptService").rglob("*.luau"))
VC = (ROOT / "src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau").read_text(encoding="utf-8")


def section(name):
    """key -> entry body, walking the section line by line (one-line and multi-line entries)."""
    TAB, NL = chr(9), chr(10)
    i = MC.index(TAB + name + " = {")
    j = MC.index(NL + TAB + "},", i)
    lines = MC[i:j].split(NL)[1:]
    out, cur, buf = {}, None, []
    for ln in lines:
        m = re.match(r"^\t\t(\w+) = \{(.*)$", ln)
        if cur is None and m:
            rest = m.group(2)
            if rest.rstrip().endswith("},") or rest.rstrip().endswith("}"):
                out[m.group(1)] = rest
            else:
                cur, buf = m.group(1), [rest]
        elif cur is not None:
            if re.match(r"^\t\t\}", ln):
                out[cur] = NL.join(buf)
                cur, buf = None, []
            else:
                buf.append(ln)
    return out



def num(body, key):
    m = re.search(r"\b" + key + r" = (\d+)", body)
    return int(m.group(1)) if m else 0


RECEIPT = {
    "idempotent (saved PurchaseId)": "if hasProcessed(profile, receiptId) then" in MS,
    "one run per PurchaseId (in-flight lock)": "if receiptsInFlight[receiptId] then" in MS,
    "saved before PurchaseGranted": "if not DataService.SaveProfile(player, false) then" in MS,
    "unknown product never acked": "findDevProduct(receiptInfo.ProductId)" in MS,
    "pass purchase re-checked with UserOwnsGamePassAsync": "UserOwnsGamePassAsync" in MS,
}


def audit():
    rows = []
    passes, products = section("GamePasses"), section("DevProducts")
    counters = re.findall(r"\n\t\t(Grant\w+) = \{\n\t\t\tField", MC)
    for kind, table in (("Game pass", passes), ("Dev product", products)):
        for key, body in table.items():
            pid = num(body, "Id")
            hide = "HideFromShop = true" in body
            prompt = []
            if not hide:
                prompt.append("Shop")
            if "VehicleIds = {" in body or key == "ExtraGarageSlot":
                prompt.append("Shop ROBUX row" + (" + Garage" if "VehicleIds" in body else ""))
            if 'SoldFrom = "RebirthPanel"' in body:
                prompt.append("Rebirth panel")
            if 'SoldFrom = "Missions"' in body:
                prompt.append("Missions panel")  # Code Bot v180: the paid mission reroll
            if re.search(r'Key = "' + key + '"', MC):
                prompt.append("ATM pad / offer")
            grant = []
            if num(body, "Cash") > 0:
                grant.append("cash")
            if num(body, "Gold") > 0:
                grant.append("gold")
            if "GrantEntitlement" in body:
                grant.append("entitlement")
            if "GrantsBattlePassPremium" in body:
                grant.append("battle pass premium")
            if "GrantsMissionReroll = true" in body:
                grant.append("mission reroll token")  # Code Bot v180: profile.MissionRerollTokens + 1 per receipt
            for c in counters:
                if re.search(r"\b" + c + r" = \d+", body):
                    grant.append("saved counter " + c)
            if kind == "Game pass":
                if "WalkSpeedMult" in body or "CashMult" in body or "CashBonusMult" in body or "XPMult" in body:
                    grant.append("multiplier")
                if "VehicleIds" in body and re.search(r'PassKey = passKey|"' + key + '"', VC):
                    grant.append("premium vehicle + weapons")
                if re.search(r'"' + key + r'"', SERVER):
                    grant.append("server perk")
            keeps = "UserOwnsGamePassAsync on every join" if kind == "Game pass" else ("profile (saved before the ack)" if grant else "-")
            if hide and not prompt:
                prompt.append("hidden (not sold)")
            # a live item a player can buy must grant something; a hidden, unprompted one is simply not for sale
            sold = any(x != "hidden (not sold)" for x in prompt)
            ok = pid == 0 or not sold or bool(grant)
            rows.append((key, kind, pid, ", ".join(prompt) or "-", ", ".join(dict.fromkeys(grant)) or "-", keeps, ok))
    return rows


if __name__ == "__main__":
    rows = audit()
    md = "--markdown" in sys.argv
    if md:
        print("| Key | Type | Id | Prompt | Grant | Rejoin keeps it | OK |")
        print("|---|---|---|---|---|---|---|")
    for r in rows:
        if md:
            print("| %s | %s | %s | %s | %s | %s | %s |" % (r[0], r[1], r[2] or "0 (not created)", r[3], r[4], r[5], "yes" if r[6] else "NO"))
        else:
            print(r)
    for k, v in RECEIPT.items():
        print(("- receipt: %s: %s" % (k, "yes" if v else "NO")) if md else ("receipt", k, v))
    sys.exit(0 if all(r[6] for r in rows) and all(RECEIPT.values()) else 1)
