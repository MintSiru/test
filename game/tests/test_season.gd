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
	# 기록: 2026 전국 개인 타이틀 7개, 학교 기록, 졸업생 고교 통산
	var t26 = state.get("titles", {}).get("2026")
	print("2026 타이틀: ", t26.map(func(x): return "%s %s(%s) %s" % [x["title"], x["name"], x["school"], x["value"]]) if t26 != null else null)
	if t26 == null or t26.size() != Records.TITLES.size():
		fails.append("개인 타이틀 결산 실패")
	if state.get("schoolRecords") == null or state["schoolRecords"].is_empty():
		fails.append("학교 기록 없음")
	if state["alumni"].is_empty() or not state["alumni"][0].has("hs"):
		fails.append("졸업생 고교 통산 없음")
	# 비시즌 콘텐츠: 진로 상담·합숙 선택 팝업, 학교 행사 소식
	if not "3학년 진로 상담" in popups or not "동계 합숙 장소" in popups:
		fails.append("비시즌 선택 팝업 없음")
	var school_news := 0
	for n in state["news"]:
		for e in Offseason.data()["schoolEvents"]:
			if n["text"] == e["text"]:
				school_news += 1
	print("학교 행사 소식: ", school_news)
	if school_news == 0:
		fails.append("학교 행사 없음")
	# 합숙 선택: 포인트가 있으면 비용을 내고 효과, 없으면 무료 합숙
	var pts0 := Shop.points(state)
	state["points"] = 400
	Offseason.choose(state, "camp", "south")
	if Shop.points(state) != 250 or absf(float(state["trainingBonus"]) - 1.6) > 0.001:
		fails.append("남해 합숙 반영 실패")
	state["points"] = 100
	Offseason.choose(state, "camp", "abroad")
	if Shop.points(state) != 100 or absf(float(state["trainingBonus"]) - 1.3) > 0.001:
		fails.append("포인트 부족 시 기본 합숙 실패")
	state["points"] = pts0
	state.erase("trainingBonus")
	# 추천서: 드래프트 예상 점수 +
	var anyp: Dictionary = WorldGen.team_players(state, state["userTeamId"])[0]
	var before := Offseason.expected_draft_score(anyp)
	Offseason.choose(state, "counsel", anyp["id"])
	if absf(Offseason.expected_draft_score(anyp) - before - float(Offseason.data()["counsel"]["recommendBonus"])) > 0.001:
		fails.append("추천서 반영 실패")
	anyp.erase("recommended")
	if user_games < 12:
		fails.append("경기 수 부족 %d" % user_games)
	var roster := WorldGen.team_players(state, "user")
	if roster.size() < 12:
		fails.append("로스터 부족 %d" % roster.size())
	# 포인트 · 장터
	if Shop.points(state) <= 100 and state["history"][0]["results"].is_empty():
		fails.append("포인트 획득 없음")
	print("1년 후 포인트: ", Shop.points(state), " 프로 명단 예: ", Idol.pro_name(state["pros"][0]))
	if Idol.pro_name(state["pros"][0]) != "김도영":
		fails.append("실명 프로 명단 아님")
	state["points"] = 5000
	state["shop"] = {"openUntil": state["date"], "stock": [{"key": "protein", "qty": 1}, {"key": "bk_k", "qty": 1}]}
	var bat: Dictionary = {}
	var pit: Dictionary = {}
	for p in WorldGen.team_players(state, "user"):
		if p["pos"] != "P" and bat.is_empty():
			bat = p
		if p["pos"] == "P" and pit.is_empty() and not "strikeout" in p["abilities"]:
			pit = p
	var pw: int = bat["r"]["power"]
	if Shop.buy_item(state, "protein") != "" or Shop.buy_item(state, "bk_k") != "":
		fails.append("구매 실패")
	if Shop.buy_item(state, "protein") != "품절이다.":
		fails.append("품절 처리 실패")
	if not Shop.use_item(state, "protein", bat["id"], Rng.new(1))["ok"] or int(bat["r"]["power"]) != mini(99, pw + 3):
		fails.append("능력치 아이템 실패")
	if Shop.use_item(state, "bk_k", bat["id"], Rng.new(1))["ok"]:
		fails.append("투수 전용 책을 타자가 사용함")
	if not Shop.use_item(state, "bk_k", pit["id"], Rng.new(1))["ok"] or not "strikeout" in pit["abilities"]:
		fails.append("특수능력 책 실패")
	# 3월은 시설 설치 불가, 7월은 가능
	if Shop.buy_facility(state, "weight") == "":
		fails.append("시설 설치 시기 제한 실패")
	var saved_date: String = state["date"]
	state["date"] = "2027-07-02"
	state["shop"]["openUntil"] = "2027-07-07"
	if Shop.buy_facility(state, "weight") != "" or Shop.level(state, "weight") != 1:
		fails.append("7월 시설 설치 실패")
	state["date"] = saved_date
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
