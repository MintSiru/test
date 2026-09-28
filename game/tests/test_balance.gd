extends SceneTree
## godot --headless -s tests/test_balance.gd


## team_seed 를 주면 팀은 그 시드로 따로 만든다 (두 조건을 같은 팀들로 비교할 때)
func run_many(n: int, qa: float, qb: float, seed_val: int, quiet := false, team_seed := -1) -> Dictionary:
	var rng := Rng.new(seed_val)
	var trng := rng if team_seed < 0 else Rng.new(team_seed)
	var bat := PlayerUtil.empty_bat()
	var runs := 0
	var wins_a := 0
	var called := 0
	var errors := 0
	var pitches := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var a := TestUtil.make_team(trng, "A%d" % i, qa)
		var b := TestUtil.make_team(trng, "B%d" % i, qb)
		var m := MatchEngine.new(SideBuilder.build(a["team"], a["players"], "2026-05-01"), SideBuilder.build(b["team"], b["players"], "2026-05-01"), rng)
		m.quiet = quiet
		MatchAI.play_out(m)
		pitches += m.pitch_no
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
		"called": called / float(n), "winA": wins_a / float(n), "msPerGame": ms / float(n), "pitches": pitches / float(n),
	}


## A 팀 선수(타자 또는 투수) 전원에게 능력을 준 경기 N번. 타자 능력은 A 타격, 투수 능력은 B 타격을 본다
func run_ability(ability: String, for_pitchers: bool, n := 200, seed_val := 11) -> Dictionary:
	var rng := Rng.new(seed_val)
	var trng := Rng.new(seed_val + 500) # 모든 능력 비교에 같은 팀들을 쓴다
	var bat := PlayerUtil.empty_bat()
	for i in n:
		var a := TestUtil.make_team(trng, "A%d" % i, 55)
		var b := TestUtil.make_team(trng, "B%d" % i, 55)
		for p in a["players"]:
			p["abilities"] = [ability] if ability != "" and (p["pos"] == "P") == for_pitchers else []
		for p in b["players"]:
			p["abilities"] = []
		var m := MatchEngine.new(SideBuilder.build(a["team"], a["players"], "2026-05-01"), SideBuilder.build(b["team"], b["players"], "2026-05-01"), rng)
		MatchAI.play_out(m)
		var side := m.side_of("B%d" % i) if for_pitchers else m.side_of("A%d" % i)
		for e in side.box.values():
			PlayerUtil.add_line(bat, e["bat"])
	return {"avg": float(bat["h"]) / bat["ab"], "hr": float(bat["hr"]) / bat["pa"], "k": float(bat["so"]) / bat["pa"], "bb": float(bat["bb"]) / bat["pa"]}


func ability_checks() -> Array:
	var base := run_ability("", false)
	var base_p := run_ability("", true)
	var power := run_ability("powerG", false)
	var hit := run_ability("hitG", false)
	var eye_x := run_ability("eyeX", false)
	var k_g := run_ability("kG", true)
	var heavy := run_ability("heavyG", true)
	print("abil base ", base, " powerG ", power, " hitG ", hit, " eyeX ", eye_x)
	print("abil baseP ", base_p, " kG ", k_g, " heavyG ", heavy)
	# 데이터 규칙
	var p := {"pos": "SS", "sub": [], "abilities": ["chanceX"]}
	var removed := Abilities.learn(p, "chance")
	var rules_ok: bool = removed == ["chanceX"] and p["abilities"] == ["chance"] and Abilities.cannot_learn(p, "chanceX") != ""
	Abilities.learn(p, "chanceG")
	rules_ok = rules_ok and p["abilities"] == ["chanceG"] and Abilities.cannot_learn(p, "chance") == "상위 능력을 가지고 있음" and Abilities.cannot_learn(p, "pinch") == "투수 전용"
	return [
		[Abilities.all().size() >= 80, "abilities >= 80"],
		[rules_ok, "ability group rules"],
		[power["hr"] > base["hr"] * 1.3, "powerG hr"],
		[hit["avg"] > base["avg"] + 0.005, "hitG avg"],
		[eye_x["bb"] < base["bb"], "eyeX bb"],
		[k_g["k"] > base_p["k"] + 0.01, "kG k"],
		[heavy["avg"] < base_p["avg"], "heavyG avg"],
	]


## 관전 경기(실황 있음)에서 특수능력 발동 문구가 경기당 몇 번 나오는지
func ability_notes_per_game(n := 80) -> float:
	var trng := Rng.new(5)
	var rng := Rng.new(6)
	var total := 0
	for i in n:
		var a := TestUtil.make_team(trng, "A%d" % i, 55)
		var b := TestUtil.make_team(trng, "B%d" % i, 55)
		var m := MatchEngine.new(SideBuilder.build(a["team"], a["players"], "2026-05-01"), SideBuilder.build(b["team"], b["players"], "2026-05-01"), rng)
		while not m.over:
			if not MatchAI.pitching_change(m, m.def()):
				MatchAI.mound_visit(m, m.def())
			if m.step(MatchAI.orders(m)).get("abilityNote", "") != "":
				total += 1
	return total / float(n)


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
	checks.append_array(ability_checks())
	# CPU끼리 경기 빠른 경로(quiet)는 일반 경로와 같은 분포여야 한다
	var normal := run_many(400, 55, 55, 5, false, 99)
	var fast := run_many(400, 55, 55, 5, true, 99)
	print("normal ", normal)
	print("fast   ", fast)
	checks.append([absf(normal["runsPerTeamGame"] - fast["runsPerTeamGame"]) < 0.4, "fast runs"])
	checks.append([absf(normal["avg"] - fast["avg"]) < 0.012, "fast avg"])
	checks.append([absf(normal["k"] - fast["k"]) < 0.015, "fast k"])
	checks.append([absf(normal["bb"] - fast["bb"]) < 0.012, "fast bb"])
	checks.append([absf(normal["hr"] - fast["hr"]) < 0.06, "fast hr"])
	checks.append([absf(normal["pitches"] - fast["pitches"]) < 8, "fast pitches"])
	var notes := ability_notes_per_game()
	print("특수능력 발동 문구: 경기당 %.1f회" % notes)
	checks.append([notes >= 2.0 and notes <= 6.0, "ability notes 2~6/game"])
	for c in checks:
		if not c[0]:
			print("FAIL: ", c[1])
			fails += 1
	print("BALANCE ", "OK" if fails == 0 else "FAILED")
	quit(1 if fails else 0)
