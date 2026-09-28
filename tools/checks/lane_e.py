# Lane E: UI, HUD, Client shell: BuyPathStatic pins (see LANES.md section 5).
# Runs inside tools/BuyPathStatic.py (its globals): use must_contain(rel, needle, label), must_not_contain(...),
# must_absent(...), read(rel), ok(label), bad(label) and ROOT exactly as in that file. Append only; prefix every label
# with the lane and topic, e.g. "LANE-E guards-fight-back: ...". Never edit another lane's file.
# Helper names you define here must start with _e_ (all check files share one namespace).
