extends SceneTree
## 한 시즌(1년) 자동 진행 테스트: godot --headless -s tests/test_season.gd


func _init() -> void:
	var fails := []
	var dates := Cal.comp_dates("hwanggeum", 2026)
	if dates["start"] != "2026-05-02" or dates["end"] != "2026-05-16":
		fails.append("황금사자기 일정 불일치 %s" % dates)
	# 날씨 해시가 웹과 같은지 (web/tests/season.test.ts 와 같은 값)
	if Weather.mix32(Weather.hash_str("42:2026-07-01")) != 3842815896:
		fails.append("날씨 해시 불일치 %d" % Weather.mix32(Weather.hash_str("42:2026-07-01")))
	var t0 := Time.get_ticks_msec()
	var state := Season.start_new_game({"schoolName": "한빛고", "managerName": "테스트", "groupId": "seoulA", "seed": 42})
	if state["teams"].size() != 103:
		fails.append("팀 수 %d" % state["teams"].size())
	var popups := []
	var user_games := 0
	var guard := 0
	var checked := false
	while state["date"] < "2027-03-03" and guard < 20000:
		if not checked and state["date"] >= "2026-11-01":
			checked = true
			for c in state["competitions"]:
				if c["status"] != "done" or (c["kind"] == "tournament" and c.get("champion") == null):
					fails.append("미완료 대회: " + c["name"])
			var rain := 0
			for c in state["competitions"]:
				for f in c["fixtures"]:
					if int(f.get("postponed", 0)) > 0:
						rain += 1
			var total := 0
			var twice := 0
			for c in state["competitions"]:
				total += c["fixtures"].size()
				for f in c["fixtures"]:
					if int(f.get("postponed", 0)) >= 2:
						twice += 1
			print("우천 연기된 경기: %d / %d (두 번 연기 %d)" % [rain, total, twice])
			if rain == 0 or float(rain) / total > 0.25 or float(twice) / total > 0.05:
				fails.append("우천 연기 비율 이상")
			# 연습 경기
			var rec: Dictionary = state["teams"]["user"]["seasonRecord"].duplicate()
			var fd := Season.friendly_date(state)
			if fd == "":
				fails.append("비시즌 연습 경기 불가")
			else:
				var ff := Season.schedule_friendly(state, Season.friendly_opponents(state, Rng.new(1))[0])
				if Season.friendly_date(state) != "":
					fails.append("같은 주 연습 경기 중복 허용")
				while state["date"] <= ff["date"]:
					var rr := Season.advance(state, 1)
					if rr == "training":
						Season.use_card(state, state["hand"][0]["id"])
					elif rr == "match":
						Season.auto_play_user_match(state)
					elif rr == "popup":
						state["popups"].clear()
				if ff.get("result") == null:
					fails.append("연습 경기 미진행")
				if state["teams"]["user"]["seasonRecord"] != rec:
					fails.append("연습 경기가 공식 전적에 반영됨")
				print("연습 경기 결과: ", ff.get("result", {}).get("homeScore", -1), ":", ff.get("result", {}).get("awayScore", -1))
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
