# tools/checks: per-lane BuyPathStatic pins

`python3 tools/BuyPathStatic.py` runs the frozen legacy pins, then every `tools/checks/*.py` in name order (same
globals), then the parse gate. A lane adds pins only to its own `lane_<x>.py`. See LANES.md section 5.
