extends BaseScreen
## 경기 전: 선발 투수 선택, 상대 전력 확인

var starter_id := ""
var fixture: Dictionary
var comp: Dictionary
var plist: VBoxContainer


func setup(_p := {}) -> void:
	add_top_bar("경기 준비")
	var s := st()
	var found := Season.find_fixture(s, s.get("pendingFixture", ""))
	if found.is_empty():
		Game.goto("hub")
		return
	fixture = found["f"]
	comp = found["comp"]
	var u: String = s["userTeamId"]
	var opp: Dictionary = s["teams"][fixture["away"] if fixture["home"] == u else fixture["home"]]
	var ours := WorldGen.team_players(s, u)
	var rec = Lineup.pick_starter(ours, fixture["date"], Game.user_team().get("rotation", []) if Game.user_team().get("rotation") != null else [])
	starter_id = rec["id"] if rec != null else ""

	var head := UI.panel(UI.PANEL, UI.ACCENT, 4)
	UI.place(head, 4, 22, 632, 34)
	add_child(head)
	var hv := UI.vbox(0)
	head.add_child(hv)
	hv.add_child(UI.title_label("%s  —  %s" % [Season.fixture_label(comp, fixture), Cal.pretty(fixture["date"])]))
	hv.add_child(UI.label("%s (%s) vs %s (%s)   ·   %s" % [s["teams"][fixture["away"]]["name"], "원정", s["teams"][fixture["home"]]["name"], "홈",
		"연습 경기: 공식 기록에 남지 않음" if comp["kind"] == "friendly" else ("리그전: 9회 무승부 가능 (12회까지)" if comp["kind"] == "league" else "토너먼트: 10회부터 승부치기 · 콜드게임(5회 10점/7회 7점)")], UI.DIM, true))

	var lp := UI.panel()
	UI.place(lp, 4, 60, 380, 270)
	add_child(lp)
	var lv := UI.vbox(2)
	lp.add_child(lv)
	lv.add_child(UI.label("선발 투수 선택", UI.ACCENT, true))
	lv.add_child(UI.wrap_label("투구수 휴식 규정: 31~45구 1일, 46~60구 2일, 61~75구 3일, 76구 이상 4일 · 1경기 최대 105구", 368, UI.DIM, true))
	plist = UI.vbox(1)
	lv.add_child(UI.scroll(plist, Vector2(368, 196)))
	_fill_pitchers()

	var rp := UI.panel()
	UI.place(rp, 388, 60, 248, 270)
	add_child(rp)
	var rv := UI.vbox(2)
	# 전력 분석·라이벌 정보가 많아지면 넘치지 않게 스크롤
	rp.add_child(UI.scroll(rv))
	rv.add_child(UI.title_label("상대 전력: " + opp["name"]))
	var theirs := WorldGen.team_players(s, opp["id"])
	var r := opp["seasonRecord"] as Dictionary
	rv.add_child(UI.label("%s · 전통 %d · 시즌 %d승 %d패" % [opp["province"], opp["prestige"], r["w"], r["l"]], UI.TEXT, true))
	# CPU 학교 흥망 소식 (최근 2년)
	var story = opp.get("story")
	if story != null and int(st()["year"]) - int(story["year"]) <= 1:
		rv.add_child(UI.wrap_label("[%s] %s" % [story["tag"], story["text"]], 236, UI.GOOD if story["tag"] == "신흥 강호" else UI.BAD, true))
	if int(opp.get("facLevel", 0)) > 0:
		rv.add_child(UI.label("시설 Lv%d (훈련 효과 +%d%%)" % [int(opp["facLevel"]), int(opp["facLevel"]) * 20], UI.DIM, true))
	var hh := Rival.h2h_of(s, opp["id"])
	var tst := Rival.team_stats(s, opp["id"])
	rv.add_child(UI.label("상대 전적 %d승 %d패 %d무" % [hh["w"], hh["l"], hh["d"]], UI.TEXT, true))
	rv.add_child(UI.label("팀 타율 %s · 홈런 %d · 도루 %d · ERA %.2f" % [("%.3f" % tst["avg"]).trim_prefix("0"), tst["hr"], tst["sb"], tst["era"]], UI.TEXT, true))
	if Rival.is_rival_game(s, fixture):
		rv.add_child(UI.label("★ 라이벌전! 선수들의 투지가 불탄다 (컨디션 +1)", UI.BAD, true))
		var ace := Stories.rival_ace(s)
		if not ace.is_empty():
			rv.add_child(UI.label("경계 대상: 에이스 %s (%d학년 %s, 종합 %d)" % [PlayerUtil.full_name(ace), PlayerUtil.grade(ace, s["year"]), PlayerUtil.POS_KO[ace["pos"]], PlayerUtil.overall(ace)], UI.BAD, true))
			var ar := Stories.ace_record_text(s, ace)
			if ar != "":
				rv.add_child(UI.wrap_label("  " + ar, 236, UI.DIM, true))
	var ts = Lineup.pick_starter(theirs, fixture["date"], [])
	if ts != null:
		rv.add_child(UI.label("예상 선발: %s %dkm 제구 %s" % [PlayerUtil.full_name(ts), ts["r"]["velo"], PlayerUtil.letter(ts["r"]["control"])], UI.TEXT, true))
	var an := Shop.level(s, "analysis")
	if an >= 1:
		var staff := theirs.filter(func(p): return p["pos"] == "P")
		staff.sort_custom(func(a, b): return Lineup.starter_score(a) > Lineup.starter_score(b))
		var names := []
		for p in staff.slice(0, 4):
			names.append("%s %dkm%s" % [p["given"], p["r"]["velo"], "" if Lineup.can_pitch_on(p, fixture["date"]) else "(휴식)"])
		rv.add_child(UI.wrap_label("[분석실] 투수진: " + ", ".join(names), 236, UI.DIM, true))
	if an < 1:
		rv.add_child(UI.wrap_label("(전력 분석실을 지으면 더 자세히 볼 수 있다)", 236, UI.DIM, true))
	rv.add_child(UI.label("주요 타자", UI.ACCENT, true))
	var hitters := theirs.filter(func(p): return p["pos"] != "P")
	hitters.sort_custom(func(a, b): return PlayerUtil.bat_value(a["r"]) > PlayerUtil.bat_value(b["r"]))
	for p in hitters.slice(0, 5):
		var pr: Dictionary = p["r"]
		var idol := Idol.idol_of(s, p)
		rv.add_child(UI.label("%s %s 컨%s 파%s 주%s%s" % [PlayerUtil.POS_SHORT[p["pos"]], PlayerUtil.full_name(p), PlayerUtil.letter(pr["contact"]), PlayerUtil.letter(pr["power"]), PlayerUtil.letter(pr["speed"]),
			(" ♥" + idol["given"]) if not idol.is_empty() else ""], UI.TEXT, true))
		if an >= 2 and not p["abilities"].is_empty():
			var fl := UI.ability_flow(p["abilities"], 230)
			rv.add_child(fl)

	var row := UI.hbox(8)
	UI.place(row, 4, 334, 632, 20)
	add_child(row)
	row.add_child(UI.button("◀ 돌아가기", func(): Game.goto("hub")))
	row.add_child(UI.button("오더 편집", func(): Game.goto("lineup")))
	row.add_child(UI.expand(UI.spacer()))
	row.add_child(UI.button("위임 (결과만)", _delegate))
	row.add_child(UI.button("▶ 경기 시작", _start, 110))
	Help.once("firstMatch")


func _fill_pitchers() -> void:
	UI.clear(plist)
	var s := st()
	var ps := WorldGen.team_players(s, s["userTeamId"]).filter(func(p): return p["pos"] == "P")
	ps.sort_custom(func(a, b): return Lineup.starter_score(a) > Lineup.starter_score(b))
	for p in ps:
		var ok := Lineup.can_pitch_on(p, fixture["date"])
		var r: Dictionary = p["r"]
		var txt := "%s %d학년 %dkm 제%s 스%s 변%s 피로%d" % [PlayerUtil.full_name(p), PlayerUtil.grade(p, s["year"]), r["velo"], PlayerUtil.letter(r["control"]),
			PlayerUtil.letter(r["stamina"]), PlayerUtil.letter(PlayerUtil.breaking_score(r["pitches"])), roundi(p["fatigue"])]
		if not ok:
			txt += "  (등판 불가: %s)" % ("부상" if p["injury"] > 0 else "휴식 규정")
		var id: String = p["id"]
		var b := UI.button(("▶ " if id == starter_id else "   ") + txt, func():
			starter_id = id
			_fill_pitchers(), 360, true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not ok
		if id == starter_id:
			b.add_theme_stylebox_override("normal", UI.sb(UI.ACCENT.darkened(0.5), UI.ACCENT))
		plist.add_child(b)


func _start() -> void:
	var s := st()
	var seed_val := randi() % 2000000000
	var m := Season.create_match(s, fixture, Rng.new(seed_val), {"starterId": starter_id})
	# 경기 도중 저장: 시드와 입력 기록으로 같은 상황을 다시 만든다
	m.save_info = {"fixtureId": fixture["id"], "seed": seed_val, "starterId": starter_id}
	m.journal_on = true
	Game.current_match = m
	Game.save_game()
	Game.goto("match")


func _delegate() -> void:
	var m := Season.auto_play_user_match(st())
	Game.save_game()
	if m == null:
		Game.goto("hub")
		return
	Game.main.show_match_result(m, func(): Game.goto("hub"))
