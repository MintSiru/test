extends SceneTree
## 작전 성공 가능성 안내(tactic_odds)가 실제 판정과 맞는지: 같은 상황을 1000번 되풀이해 성공률을 잰다.
## godot --headless -s tests/test_tactics.gd

var fails := 0


func setup(m: MatchEngine, runners: Array) -> void:
	m.over = false
	m.top = true
	m.inning = 3
	m.outs = 0
	m.balls = 0
	m.strikes = 0
	m._outs_before = 0
	# 되풀이하는 동안 투수가 지치지 않게 투구수를 되돌린다
	m.def().pitch_count[m.def().pitcher_id] = 0
	var o := m.off()
	o.batter_idx = 4
	m.bases = [null, null, null]
	for i in 3:
		if runners[i]:
			# 주자는 타순의 다른 선수
			m.bases[i] = {"id": o.order[(5 + i) % 9], "resp": m.def().pitcher_id, "earned": true}


func measure(m: MatchEngine, key: String, runners: Array, n := 1000) -> Array:
	var ok := 0
	var tried := 0
	var guard := 0
	while tried < n and guard < n * 20:
		guard += 1
		setup(m, runners)
		var ev := m.step({"off": key})
		match key:
			"steal":
				if ev.get("steal") != null:
					tried += 1
					ok += 1 if ev["steal"]["success"] else 0
			"bunt", "safetyBunt":
				# 앞으로 간 번트 전부 (실패해서 뜬 번트도 포함)
				var bt = ev.get("batted")
				if ev["call"] == "inplay" and bt != null:
					tried += 1
					var good: bool = bt["result"] == ("SAC" if key == "bunt" else "1B")
					ok += 1 if good else 0
			"squeeze":
				if ev["call"] in ["inplay", "buntMiss"]:
					tried += 1
					var bt2 = ev.get("batted")
					ok += 1 if bt2 != null and bt2["result"] == "SAC" else 0
			"hitRun":
				if ev["call"] in ["foul", "inplay", "swinging"]:
					tried += 1
					ok += 0 if ev["call"] == "swinging" else 1
	return [float(ok) / maxi(1, tried), tried]


func check(m: MatchEngine, key: String, runners: Array, label: String) -> void:
	setup(m, runners)
	var odds := m.tactic_odds()
	var shown: float = odds.get(key, -1.0)
	var r := measure(m, key, runners)
	var real: float = r[0]
	var ok := absf(shown - real) < 0.07
	print("%s %-10s 안내 %.2f(%s) 실제 %.2f(%s) n=%d %s" % ["  ok " if ok else "  FAIL", key, shown, MatchEngine.odds_grade(key, shown), real, MatchEngine.odds_grade(key, real), r[1], label])
	if not ok:
		fails += 1


func _init() -> void:
	var trng := Rng.new(3)
	for q in [[70, 40], [40, 70], [55, 55]]:
		var a := TestUtil.make_team(trng, "A", q[0])
		var b := TestUtil.make_team(trng, "B", q[1])
		var m := MatchEngine.new(SideBuilder.build(b["team"], b["players"], "2026-05-01"), SideBuilder.build(a["team"], a["players"], "2026-05-01"), Rng.new(7))
		m.quiet = true
		var lbl := "(공격 %d vs 수비 %d)" % q
		check(m, "steal", [true, false, false], lbl)
		check(m, "steal", [false, true, false], lbl + " 3루 도루")
		check(m, "bunt", [true, false, false], lbl)
		check(m, "safetyBunt", [false, false, false], lbl)
		check(m, "squeeze", [false, false, true], lbl)
		check(m, "hitRun", [true, false, false], lbl)
	print("TACTICS ", "OK" if fails == 0 else "FAILED")
	quit(1 if fails else 0)
