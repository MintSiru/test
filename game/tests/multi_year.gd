extends SceneTree
## 여러 해 밸런스 점검: 5년 × 3시드 자동 진행 (선택은 기본값, 장터 구매 없음) → 해마다 우리 팀 상위 12명 평균 종합·전국 순위·명성·포인트·감독 레벨
## godot --headless --path game -s tests/multi_year.gd   (약 3~4분. run_tests.sh 에는 넣지 않음)
func _top_ovr(state: Dictionary) -> float:
	var ov: Array = WorldGen.team_players(state, state["userTeamId"]).map(func(p): return PlayerUtil.overall(p))
	ov.sort()
	ov.reverse()
	var s := 0.0
	for x in ov.slice(0, 12):
		s += x
	return s / 12.0
func _nat_rank(state: Dictionary) -> int:
	var arr := []
	for t in state["teams"].values():
		var ov: Array = WorldGen.team_players(state, t["id"]).map(func(p): return PlayerUtil.overall(p))
		ov.sort(); ov.reverse()
		var s := 0.0
		for x in ov.slice(0, 12): s += x
		arr.append([s, t["isUser"]])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	for i in arr.size():
		if arr[i][1]: return i + 1
	return -1
func _init() -> void:
	var seeds := [11, 22, 33]
	for seed in seeds:
		var state := Season.start_new_game({"schoolName": "한빛고", "managerName": "t", "groupId": "seoulA", "seed": seed})
		var line := "seed %d: 시작 %.1f(%d위)" % [seed, _top_ovr(state), _nat_rank(state)]
		var year := 2026
		var guard := 0
		while state["date"] < "2031-03-03" and guard < 200000:
			guard += 1
			var r := Season.advance(state, 1)
			if r == "training":
				Season.use_card(state, state["hand"][0]["id"])
			elif r == "match":
				Season.auto_play_user_match(state)
			state["popups"].clear()
			if int(state["year"]) != year:
				year = int(state["year"])
				line += " | %d: %.1f(%d위) 명성%d %dP Lv%d" % [year, _top_ovr(state), _nat_rank(state), state["reputation"], Shop.points(state), Manager.info(state)["level"]]
		print(line)
		var best := []
		for y in state["history"]:
			best.append(str(y["year"]) + ":" + ",".join(y["results"].filter(func(x): return not x["comp"].begins_with("주말")).map(func(x): return x["result"])))
		print("   ", best)
	quit()
