extends SceneTree
## 성능 측정: godot --headless -s tests/bench.gd


func _init() -> void:
	var state := Season.start_new_game({"schoolName": "한빛고", "managerName": "t", "groupId": "seoulA", "seed": 9})
	var rng := Rng.new(1)
	var fx: Array = []
	for c in state["competitions"]:
		if c["key"] == "league1":
			fx = c["fixtures"].slice(0, 60)
	var t_build := 0
	var t_play := 0
	var t_apply := 0
	var pitches := 0
	for f in fx:
		var t0 := Time.get_ticks_usec()
		var m := Season.create_match(state, f, rng)
		var t1 := Time.get_ticks_usec()
		m.quiet = true
		MatchAI.play_out(m)
		var t2 := Time.get_ticks_usec()
		pitches += m.home.pitch_count.values().reduce(func(a, b): return a + b, 0) + m.away.pitch_count.values().reduce(func(a, b): return a + b, 0)
		var comp = Season.comp_by_id(state, f["compId"])
		Season.apply_result(state, comp, f, m, rng)
		var t3 := Time.get_ticks_usec()
		t_build += t1 - t0
		t_play += t2 - t1
		t_apply += t3 - t2
	var n := float(fx.size())
	print("games %d  build %.2fms  play %.2fms  apply %.2fms  pitches/game %.0f  us/pitch %.1f" % [fx.size(), t_build / n / 1000.0, t_play / n / 1000.0, t_apply / n / 1000.0, pitches / n, t_play / float(pitches)])
	var t4 := Time.get_ticks_usec()
	var d: String = state["date"]
	for i in 7:
		Season._end_of_day(state, rng)
	print("end_of_day x7: %.1fms" % ((Time.get_ticks_usec() - t4) / 1000.0))
	var t5 := Time.get_ticks_usec()
	Season._week_start(state, rng)
	print("week_start: %.1fms" % ((Time.get_ticks_usec() - t5) / 1000.0))
	var t6 := Time.get_ticks_usec()
	for i in 20:
		Season.fixtures_on(state, d)
	print("fixtures_on x20: %.1fms" % ((Time.get_ticks_usec() - t6) / 1000.0))
	var t7 := Time.get_ticks_usec()
	var js := JSON.stringify(state)
	print("save stringify: %.1fms (%d KB)" % [(Time.get_ticks_usec() - t7) / 1000.0, js.length() / 1024])
	quit()
