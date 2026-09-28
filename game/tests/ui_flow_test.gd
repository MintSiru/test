extends Node
## 렌더링 환경(xvfb)에서 실제 화면을 조작하는 통합 테스트.
## 실행: godot --path . -- --uitest   (main.gd 가 이 노드를 붙인다)

var fails := []


func _ready() -> void:
	_run()


func _wait(frames := 10) -> void:
	for i in frames:
		await get_tree().process_frame


func _cur() -> Control:
	return Game.main.current


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails.append(msg)


func _close_modals() -> void:
	for i in 20:
		var layer: Control = Game.main.modal_layer
		if layer.get_child_count() == 0:
			return
		# 모달의 첫 버튼(확인)을 누른다
		var btn := _find_button(layer.get_child(layer.get_child_count() - 1))
		if btn:
			btn.pressed.emit()
		await _wait(3)


func _find_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button:
			return c
		var b := _find_button(c)
		if b:
			return b
	return null


## 맨 위 모달의 글자 모두
func _modal_text() -> String:
	var layer: Control = Game.main.modal_layer
	if layer.get_child_count() == 0:
		return ""
	return _texts(layer.get_child(layer.get_child_count() - 1))


func _texts(n: Node) -> String:
	var t := ""
	for c in n.get_children():
		if c is Label:
			t += c.text + "\n"
		t += _texts(c)
	return t


func _match_snap(m: MatchEngine) -> String:
	return str([m.inning, m.top, m.outs, m.balls, m.strikes, m.home.score, m.away.score, m.pitch_no, m.bases.map(func(b): return null if b == null else b["id"]), m.home.pitcher_id, m.away.pitcher_id])


func _run() -> void:
	await _wait(5)
	# 테스트는 빈 슬롯에서 시작한다 (주의: 이 컴퓨터의 게임 저장 슬롯을 지운다)
	for n in range(1, Game.SLOT_COUNT + 1):
		Game.delete_slot(n)
	Game.goto("new_game")
	await _wait(5)
	_cur()._start()
	await _wait(5)
	_check(Game.main.current_name == "hub", "새 게임 → 홈 화면")
	_check(Game.slot == 1 and Game.slot_used(1), "빈 슬롯 1에 저장")
	_check(_modal_text().contains(Help.topic("welcome")["title"]), "첫 안내 팝업 (환영)")
	await _close_modals()
	Game.goto("roster")
	await _wait(5)
	_check(_modal_text().contains(Help.topic("abilities")["title"]), "선수단 첫 방문 안내 (특수능력 색)")
	await _close_modals()
	Game.goto("hub")
	await _wait(5)
	_check(_modal_text().contains(Help.topic("goals")["title"]), "후원회 목표 첫 안내")
	await _close_modals()
	Game.goto("roster")
	await _wait(5)
	Game.goto("hub")
	await _wait(5)
	# v0.7: 새 게임부터 주장이 있으므로 다음 방문에 주장·분위기 안내 (홈 방문마다 하나씩)
	_check(_modal_text().contains(Help.topic("firstMood")["title"]), "주장·팀 분위기 첫 안내")
	await _close_modals()
	Game.goto("roster")
	await _wait(5)
	Game.goto("hub")
	await _wait(5)
	_check(Game.main.modal_layer.get_child_count() == 0, "안내 팝업은 한 번만")
	_check(Game.state.get("goals") != null and Game.state["goals"]["list"].size() == 3, "후원회 목표 3개")
	_check(not Game.state["weekTrained"], "첫 주 훈련 대기")
	var hub := _cur()
	hub._use_card(Game.state["hand"][0]["id"])
	# 경기일까지 진행
	for i in 600:
		await _wait(1)
		await _close_modals()
		if Game.state.get("pendingFixture") != null and not _cur().advancing:
			break
		if not Game.state["weekTrained"] and not _cur().advancing:
			_cur()._use_card(Game.state["hand"][0]["id"])
		elif not _cur().advancing and Game.state.get("pendingFixture") == null:
			_cur()._start_advance()
	_check(Game.state.get("pendingFixture") != null, "경기일 도달 (%s)" % Game.state["date"])
	Game.goto("prematch")
	await _wait(5)
	_check(Game.main.current_name == "prematch", "경기 준비 화면")
	_cur()._start()
	await _wait(5)
	_check(Game.main.current_name == "match" and Game.current_match != null, "경기 화면 진입")
	# 몇 타석은 직접 지휘 (번트/도루 등 작전 지시 포함)
	var ms := _cur()
	ms.speed_idx = 2
	ms.off_order = "bunt"
	ms.pitch_order = "zone"
	ms._toggle_play()
	for i in 400:
		await _wait(1)
		if ms.waiting and not ms.busy:
			break
	_check(ms.waiting, "타석 종료 후 일시정지 (지시 대기)")
	ms._change_pitcher()
	await _wait(3)
	_check(ms.overlay != null, "투수 교체 선택창")
	ms.overlay.queue_free()
	ms.overlay = null
	var us: MatchEngine.TeamSide = Game.current_match.user_side()
	var v0 := us.visits
	ms._mound_visit()
	_check(us.visits == v0 + 1 and us.visit_pa == 2, "마운드 방문")
	var out_id := ""
	for id in us.order:
		if us.pos_of.get(id, "DH") != "DH":
			out_id = id
			break
	var bench := us.players.filter(func(p): return not p.id in us.used and p.pos != "P")
	if not bench.is_empty():
		Game.current_match.def_sub(us, out_id, bench[0].id)
		_check(bench[0].id in us.order and not out_id in us.order, "수비 교체")
	# 경기 도중 저장 후 나가기 → 불러오기 → 같은 상황
	var snap := _match_snap(Game.current_match)
	ms._save_quit()
	await _wait(5)
	_check(Game.main.current_name == "title", "저장 후 나가기 → 타이틀")
	_check(Game.slot_info(Game.slot).get("inMatch", false), "슬롯 요약에 [경기 중] 표시")
	_check(Game.load_game(Game.slot) and Game.current_match != null, "경기 중 세이브 불러오기")
	_check(Game.current_match != null and _match_snap(Game.current_match) == snap, "같은 이닝·점수·주자에서 재개 " + snap)
	Game.goto("match")
	await _wait(5)
	ms = _cur()
	_check(Game.main.current_name == "match", "경기 화면으로 복귀")
	ms._delegate_all()
	for i in 600:
		await _wait(1)
		if Game.current_match == null:
			break
	_check(Game.current_match == null, "위임으로 경기 종료")
	await _close_modals()
	await _wait(5)
	_check(Game.main.current_name == "hub", "경기 후 홈 복귀")
	var played := Season.user_fixtures(Game.state).filter(func(x): return x["f"].get("result") != null)
	_check(played.size() >= 1, "경기 결과 저장 (%d경기)" % played.size())
	# 다음 경기일까지 다시 진행 (주말 CPU 경기가 여러 프레임에 나눠 처리되는지)
	var before: String = Game.state["date"]
	for i in 900:
		await _wait(1)
		await _close_modals()
		var hub2 := _cur()
		if Game.main.current_name != "hub":
			break
		if Game.state.get("pendingFixture") != null and not hub2.advancing:
			break
		if not Game.state["weekTrained"] and not hub2.advancing:
			hub2._use_card(Game.state["hand"][0]["id"])
		elif not hub2.advancing and Game.state.get("pendingFixture") == null:
			hub2._start_advance()
	_check(Game.state["date"] > before and Game.state.get("pendingFixture") != null, "다음 경기일까지 진행 (%s → %s)" % [before, Game.state["date"]])
	for scr in ["roster", "lineup", "schedule", "scout", "shop", "bag", "records"]:
		Game.goto(scr)
		await _wait(5)
		_check(Game.main.current_name == scr, "화면 열기: " + scr)
	print("UITEST ", "OK" if fails.is_empty() else "FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)
