extends Node
## 한 시즌을 실제 화면으로 끝까지 진행하는 자동 플레이 테스트 (느림, 수동 실행용)
## xvfb-run godot --path . --rendering-driver opengl3 -- --uiseason [--shots=/tmp/dir]

var shots := ""
var shot_dates := {"2026-04-27": "league1", "2026-07-12": "summer", "2026-09-22": "draft", "2026-10-27": "retire", "2027-03-03": "newyear"}
var taken := {}
var stats := {"matches": 0, "screen_matches": 0, "visits": 0, "upgrades": 0, "modals": 0}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run()


func _wait(n := 1) -> void:
	for i in n:
		await get_tree().process_frame


func _cur() -> Control:
	return Game.main.current


func _find_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_find_buttons(c, out)


func _close_modals() -> void:
	var layer: Control = Game.main.modal_layer
	for i in 30:
		if layer.get_child_count() == 0:
			return
		var bs := []
		_find_buttons(layer.get_child(layer.get_child_count() - 1), bs)
		# 마지막 버튼 = 확인
		if bs.is_empty():
			return
		bs.back().pressed.emit()
		stats["modals"] += 1
		await _wait(2)


func _shot(name: String) -> void:
	if shots == "":
		return
	await _wait(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, name])


func _visit_screens() -> void:
	for scr in ["roster", "lineup", "schedule", "scout", "shop", "bag", "records"]:
		Game.goto(scr)
		await _wait(3)
	Game.goto("hub")
	await _wait(3)


func _run() -> void:
	await _wait(5)
	Game.new_game("한빛고", "자동", "seoulA")
	Game.goto("hub")
	await _wait(3)
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while Game.state["date"] < "2027-03-15" and guard < 200000:
		guard += 1
		await _wait(1)
		await _close_modals()
		var s: Dictionary = Game.state
		for d in shot_dates:
			if s["date"] >= d and not taken.has(d):
				taken[d] = true
				await _shot(shot_dates[d])
				await _visit_screens()
				if shot_dates[d] == "draft":
					Game.goto("scout")
					await _shot("scout")
					Game.goto("hub")
					await _wait(2)
		if Game.main.current_name != "hub":
			Game.goto("hub")
			await _wait(2)
			continue
		var hub := _cur()
		if hub.advancing:
			continue
		# 장터: 시설 기물(가능한 달) → 능력치 아이템 → 가방의 아이템 사용
		if Shop.market_open(s):
			if Shop.facility_month(s):
				var best := ""
				var bc := 1 << 30
				for f in Shop.facilities():
					var c := Shop.facility_cost(s, f["key"])
					if c >= 0 and c < bc:
						bc = c
						best = f["key"]
				if best != "" and Shop.buy_facility(s, best) == "":
					stats["upgrades"] += 1
			for sl in s["shop"]["stock"]:
				var d := Shop.item_def(sl["key"])
				if d["type"] == "stat" and int(sl["qty"]) > 0 and Shop.points(s) >= int(d["price"]) + 200:
					if Shop.buy_item(s, sl["key"]) == "":
						stats["bought"] = int(stats.get("bought", 0)) + 1
			var inv: Dictionary = s["inventory"]
			for k in inv.keys():
				var d2 := Shop.item_def(k)
				for p in WorldGen.team_players(s, s["userTeamId"]):
					if Shop.cannot_use(d2, p) == "" and inv.has(k):
						Shop.use_item(s, k, p["id"], Season.rng_of(s))
						stats["used"] = int(stats.get("used", 0)) + 1
						break
		# 스카우트 방문
		while int(s["scoutPoints"]) > 0 and not s["prospects"].is_empty():
			var target = null
			for pr in s["prospects"]:
				if pr["interest"] < 95 and (target == null or pr["player"]["talent"] > target["player"]["talent"]):
					target = pr
			if target == null:
				break
			var rng := Season.rng_of(s)
			Scouting.visit(s, target["id"], rng)
			Season.save_rng(s, rng)
			stats["visits"] += 1
		if not s["weekTrained"]:
			var hand: Array = s["hand"].duplicate()
			hand.sort_custom(func(a, b): return a["value"] > b["value"])
			hub._use_card(hand[0]["id"])
			await _wait(1)
			hub._start_advance()
		elif s.get("pendingFixture") != null:
			stats["matches"] += 1
			if stats["matches"] % 4 == 1:
				# 경기 화면으로 직접 (결과만 속도)
				Game.goto("prematch")
				await _wait(3)
				_cur()._start()
				await _wait(3)
				var ms := _cur()
				ms._delegate_all()
				for i in 3000:
					await _wait(1)
					if Game.current_match == null:
						break
				stats["screen_matches"] += 1
			else:
				hub._delegate()
				await _wait(2)
		else:
			hub._start_advance()
	var played := Season.user_fixtures(Game.state).size()
	print("UISEASON 완료 날짜 %s, 소요 %.0f초, 통계 %s, 기록 %s" % [Game.state["date"], (Time.get_ticks_msec() - t0) / 1000.0, stats, Game.state["history"]])
	print("UISEASON ", "OK" if Game.state["date"] >= "2027-03-15" else "FAILED")
	get_tree().quit()
