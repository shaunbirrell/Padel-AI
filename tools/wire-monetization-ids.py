#!/usr/bin/env python3
"""Wire product IDs into MonetizationConfig.luau from a JSON map.
Usage: python3 tools/wire-monetization-ids.py /tmp/we-product-ids.json
JSON shape: {"GamePasses":{"VIP":123},"DevProducts":{"CashSmall":456,"CashMega":789}}
"""
import json, re, sys
from pathlib import Path
cfg = Path("/workspace/war-empire/src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
data = json.loads(Path(sys.argv[1]).read_text())
text = cfg.read_text()
# Ensure CashMega exists if provided
if "CashMega" in data.get("DevProducts", {}) and "CashMega" not in text:
    text = text.replace(
        'CashLarge = { Id = 0, DisplayName = "Cash Pack L", RobuxPrice = 399, Cash = 200000, Gold = 0 },',
        'CashLarge = { Id = 0, DisplayName = "Cash Pack L", RobuxPrice = 399, Cash = 200000, Gold = 0 },\n\t\tCashMega = { Id = 0, DisplayName = "Cash Pack Mega", RobuxPrice = 799, Cash = 2000000, Gold = 0 },',
    )
for section, mapping in (("GamePasses", data.get("GamePasses", {})), ("DevProducts", data.get("DevProducts", {}))):
    for key, pid in mapping.items():
        # replace Id = 0 inside the named block
        pat = rf'({key}\s*=\s*\{{[^}}]*?Id\s*=\s*)0(\b)'
        text2, n = re.subn(pat, rf'\\g<1>{int(pid)}\\2', text, count=1, flags=re.S)
        if n:
            text = text2
            print(f"set {section}.{key} = {pid}")
        else:
            print(f"WARN no match for {key}")
cfg.write_text(text)
print("done")
