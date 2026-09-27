extends SceneTree
## godot --headless -s tests/test_balance.gd


func run_many(n: int, qa: float, qb: float, seed_val: int) -> Dictionary:
	var rng := Rng.new(seed_val)
	var bat := PlayerUtil.empty_bat()
	var runs := 0
	var wins_a := 0
	var called := 0
	var errors := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var a := TestUtil.make_team(rng, "A%d" % i, qa)
		var b := TestUtil.make_team(rng, "B%d" % i, qb)
		var m := MatchEngine.new(SideBuilder.build(a["team"], a["players"], "2026-05-01"), SideBuilder.build(b["team"], b["players"], "2026-05-01"), rng)
		MatchAI.play_out(m)
		runs += m.home.score + m.away.score
		errors += m.home.errors + m.away.errors
		if m.called:
			called += 1
		if m.winner == "A%d" % i:
			wins_a += 1
		for s in [m.home, m.away]:
			for e in s.box.values():
				PlayerUtil.add_line(bat, e["bat"])
	var ms := Time.get_ticks_msec() - t0
	return {
		"runsPerTeamGame": runs / float(n) / 2.0, "avg": float(bat["h"]) / bat["ab"], "hr": bat["hr"] / float(n) / 2.0,
		"k": float(bat["so"]) / bat["pa"], "bb": float(bat["bb"]) / bat["pa"], "err": errors / float(n) / 2.0,
		"called": called / float(n), "winA": wins_a / float(n), "msPerGame": ms / float(n),
	}


func _init() -> void:
	var fails := 0
	var even := run_many(150, 55, 55, 1)
	print("even ", even)
	var checks := [
		[even["runsPerTeamGame"] > 3.0 and even["runsPerTeamGame"] < 7.5, "runs"],
		[even["avg"] > 0.24 and even["avg"] < 0.33, "avg"],
		[even["hr"] < 0.8, "hr"],
		[even["k"] > 0.11 and even["k"] < 0.26, "k"],
		[even["bb"] > 0.06 and even["bb"] < 0.15, "bb"],
	]
	var strong := run_many(100, 80, 35, 7)
	print("strong ", strong)
	checks.append([strong["winA"] > 0.7, "strong wins"])
	for c in checks:
		if not c[0]:
			print("FAIL: ", c[1])
			fails += 1
	print("BALANCE ", "OK" if fails == 0 else "FAILED")
	quit(1 if fails else 0)
