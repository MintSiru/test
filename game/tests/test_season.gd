extends SceneTree
## 한 시즌(1년) 자동 진행 테스트: godot --headless -s tests/test_season.gd


func _init() -> void:
	var fails := []
	var dates := Cal.comp_dates("hwanggeum", 2026)
	if dates["start"] != "2026-05-02" or dates["end"] != "2026-05-16":
		fails.append("황금사자기 일정 불일치 %s" % dates)
	var t0 := Time.get_ticks_msec()
	var state := Season.start_new_game({"schoolName": "한빛고", "managerName": "테스트", "groupId": "seoulA", "seed": 42})
	if state["teams"].size() != 103:
		fails.append("팀 수 %d" % state["teams"].size())
	var popups := []
	var user_games := 0
	var guard := 0
	while state["date"] < "2027-03-03" and guard < 20000:
		guard += 1
		var r := Season.advance(state)
		if r == "training":
			Season.use_card(state, state["hand"][0]["id"])
		elif r == "match":
			Season.auto_play_user_match(state)
			user_games += 1
		elif r == "popup":
			for p in state["popups"]:
				popups.append(p["title"])
			state["popups"].clear()
	var ms := Time.get_ticks_msec() - t0
	print("1년 진행 ms: ", ms, " 우리 경기: ", user_games)
	print("팝업: ", popups)
	print("기록: ", state["history"])
	if state["year"] != 2027:
		fails.append("연도 %d" % state["year"])
	if not "KBO 신인 드래프트" in popups:
		fails.append("드래프트 없음")
	if user_games < 12:
		fails.append("경기 수 부족 %d" % user_games)
	var roster := WorldGen.team_players(state, "user")
	if roster.size() < 12:
		fails.append("로스터 부족 %d" % roster.size())
	# 세이브/로드 왕복
	var json := JSON.stringify(state)
	var back = JSON.parse_string(json)
	if typeof(back) != TYPE_DICTIONARY or back["teams"].size() != 103:
		fails.append("세이브 왕복 실패")
	print("세이브 크기 KB: ", json.length() / 1024)
	for f in fails:
		print("FAIL: ", f)
	print("SEASON ", "OK" if fails.is_empty() else "FAILED")
	quit(1 if not fails.is_empty() else 0)
