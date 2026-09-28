# Lane A: Vehicles, Air and Naval looks: BuyPathStatic pins (see LANES.md section 5).
# Runs inside tools/BuyPathStatic.py (its globals): use must_contain(rel, needle, label), must_not_contain(...),
# must_absent(...), read(rel), ok(label), bad(label) and ROOT exactly as in that file. Append only; prefix every label
# with the lane and topic, e.g. "LANE-A guards-fight-back: ...". Never edit another lane's file.
# Helper names you define here must start with _a_ (all check files share one namespace).
