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


func _run() -> void:
	await _wait(5)
	Game.goto("new_game")
	await _wait(5)
	_cur()._start()
	await _wait(5)
	_check(Game.main.current_name == "hub", "새 게임 → 홈 화면")
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
	for scr in ["roster", "lineup", "schedule", "scout", "records"]:
		Game.goto(scr)
		await _wait(5)
		_check(Game.main.current_name == scr, "화면 열기: " + scr)
	print("UITEST ", "OK" if fails.is_empty() else "FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)
