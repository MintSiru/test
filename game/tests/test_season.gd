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
	# 포지션 연습: 1루 연습 → 몇 주 뒤 서브 포지션, 주 포지션 바꾸기
	var fielder: Dictionary = WorldGen.team_players(state, state["userTeamId"]).filter(func(x): return x["pos"] != "P" and x["pos"] != "1B" and not "1B" in x["sub"] and x["injury"] <= 0)[0]
	fielder["practicePos"] = "1B"
	var weeks := 0
	while fielder.has("practicePos") and weeks < 20:
		Lineup.weekly_position_practice(state, {"kind": "defense", "value": 3})
		weeks += 1
	print("1루 연습 %d주 → 서브 %s" % [weeks, fielder["sub"]])
	if not "1B" in fielder["sub"] or weeks > 8:
		fails.append("포지션 연습 실패")
	var old_pos: String = fielder["pos"]
	Lineup.set_main_pos(fielder, "1B")
	if fielder["pos"] != "1B" or not old_pos in fielder["sub"]:
		fails.append("주 포지션 변경 실패")
	# 투타 겸업: 선발 투수가 지명타자로 타석에 서고, 강판 뒤에도 타순에 남는다
	var tw_team: Dictionary = state["teams"][state["userTeamId"]]
	var roster2 := WorldGen.team_players(state, tw_team["id"]).filter(func(x): return x["injury"] <= 0)
	var ace: Dictionary = roster2.filter(func(x): return x["pos"] == "P")[0]
	ace["twoWay"] = true
	ace.erase("restUntil")
	var lu := Lineup.auto_lineup(roster2, [ace["id"]])
	for sl in lu:
		if sl["pos"] == "DH":
			sl["playerId"] = ace["id"]
	var side := SideBuilder.build(tw_team, roster2, "2026-12-01", {"lineup": lu, "starterId": ace["id"]})
	var opp_id: String = state["teams"].keys().filter(func(k): return k != tw_team["id"])[0]
	var opp := SideBuilder.build(state["teams"][opp_id], WorldGen.team_players(state, opp_id), "2026-12-01")
	var tm := MatchEngine.new(side, opp, Rng.new(4))
	var us := tm.home
	var tw_ok: bool = side["pitcherId"] == ace["id"] and ace["id"] in us.order and us.pos_of[ace["id"]] == "DH"
	for i in 60:
		if tm.over:
			break
		tm.step(MatchAI.orders(tm))
	var reliever := MatchAI.relievers(us)
	if not reliever.is_empty():
		tm.change_pitcher(us, reliever[0].id)
	tw_ok = tw_ok and ace["id"] in us.order and int(us.box[ace["id"]]["bat"]["pa"]) > 0 and int(us.box[ace["id"]]["pit"]["np"]) > 0
	if not tw_ok:
		fails.append("투타 겸업 실패")
	ace.erase("twoWay")
	# CPU 학교 흥망: 새 시즌에 신흥 강호 1~2곳
	var risen: int = state["teams"].values().filter(func(t): return t.get("story") != null and t["story"]["tag"] == "신흥 강호").size()
	print("신흥 강호: ", risen)
	if risen < 1:
		fails.append("CPU 학교 흥망 없음")
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
	# 합숙 에피소드 · 마지막 밤 선택
	var camp_news: int = state["news"].filter(func(n): return n["text"].begins_with("[합숙]")).size()
	print("합숙 에피소드 소식: ", camp_news)
	if camp_news != 1 or not "합숙 마지막 밤" in popups:
		fails.append("합숙 에피소드 없음 (%d)" % camp_news)
	# 마지막 밤: 기본값(푹 쉰다) → 고기 파티로 바꾸면 피로가 되돌아가고 포인트가 빠진다
	var r0: Dictionary = WorldGen.team_players(state, "user")[0]
	r0["fatigue"] = 50.0
	Offseason._camp_night_apply(state, "rest")
	var pts_n := Shop.points(state)
	state["points"] = maxi(pts_n, 40)
	var pts1 := Shop.points(state)
	if absf(r0["fatigue"] - 30.0) > 0.01:
		fails.append("마지막 밤 기본값 실패")
	Offseason.choose(state, "campNight", "party")
	if absf(r0["fatigue"] - 50.0) > 0.01 or Shop.points(state) != pts1 - 40 or state.has("campNightUndo"):
		fails.append("마지막 밤 선택 반영 실패")
	state["points"] = pts_n
	# 졸업 후 진로: 지명 못 받은 졸업생은 대학·독립리그, 4년 뒤 대졸 드래프트
	var no_draft: Array = state["alumni"].filter(func(a): return a.get("draft") == null)
	var with_path: Array = no_draft.filter(func(a): return a.get("path") != null)
	print("졸업생 %d명 중 미지명 %d명, 진로 %s" % [state["alumni"].size(), no_draft.size(), with_path.map(func(a): return Offseason.path_text(a["path"]))])
	if no_draft.size() != with_path.size() or (not no_draft.is_empty() and not no_draft[0].has("sur")):
		fails.append("졸업생 진로 없음")
	var fake := {"playerId": "zz", "name": "남궁민수", "sur": "남궁", "given": "민수", "gradYear": int(state["year"]) - 4, "pos": "SS", "draft": null,
		"path": {"kind": "uni", "school": "한빛대", "chance": 1.0}, "hs": {}}
	state["alumni"].append(fake)
	var npros: int = state["pros"].size()
	var cl := Offseason.college_draft(state, Rng.new(5))
	var late := Records.pro_of(state, fake)
	if cl.size() < 1 or fake.get("draft") == null or state["pros"].size() != npros + cl.size() or late.is_empty() or late["sur"] != "남궁":
		fails.append("대졸 드래프트 실패 %s" % [cl])
	if not Offseason.college_draft(state, Rng.new(5)).is_empty():
		fails.append("대졸 드래프트 중복")
	state["alumni"].erase(fake)
	state["pros"] = state["pros"].filter(func(x): return x != late)
	state["popups"].clear()
	# 감독 성장: 1년 경험치로 레벨이 오르고, 레벨마다 특기 하나 (기본값 → 선택으로 교체)
	var mg := Manager.info(state)
	var perks_n := 0
	for k in mg["perks"]:
		perks_n += int(mg["perks"][k])
	print("감독: ", Manager.summary(state).replace("\n", " / "))
	if int(mg["level"]) < 2 or perks_n != int(mg["level"]) - 1:
		fails.append("감독 성장 실패 (레벨 %d, 특기 %d)" % [mg["level"], perks_n])
	var tr0 := Manager.perk(state, "trainer")
	var tac0 := Manager.perk(state, "tactician")
	Manager.add_exp(state, Manager.next_exp(state) - int(mg["exp"]))
	var lv_key := str(mg["level"])
	if Manager.perk(state, "trainer") != tr0 + 1 and tr0 < 3:
		fails.append("레벨 업 기본 특기 미적용")
	Manager.choose_perk(state, lv_key + ":tactician")
	if Manager.perk(state, "tactician") != tac0 + 1 or (tr0 < 3 and Manager.perk(state, "trainer") != tr0):
		fails.append("특기 선택 교체 실패 %s" % [mg["perks"]])
	var pts_e := Shop.points(state)
	mg["perks"]["earner"] = 1
	Shop.earn(state, 100, "테스트")
	if Shop.points(state) != pts_e + 110:
		fails.append("살림꾼 특기 실패")
	mg["perks"].erase("earner")
	state["points"] = pts_e
	# 명장면 앨범
	var hl: Array = state.get("highlights", [])
	var kinds := {}
	for h in hl:
		kinds[h["kind"]] = int(kinds.get(h["kind"], 0)) + 1
	print("명장면 %d개 %s 예: %s" % [hl.size(), kinds, hl[0]["text"] if not hl.is_empty() else "-"])
	if hl.size() < 3:
		fails.append("명장면이 너무 적음 %d" % hl.size())
	# 주장 · 팀 분위기
	var cap := TeamMood.captain(state)
	print("팀 분위기 %d, 주장 %s, 연속 %d" % [TeamMood.mood(state), PlayerUtil.full_name(cap) if not cap.is_empty() else "-", int(state.get("streak", 0))])
	if cap.is_empty() or PlayerUtil.grade(cap, state["year"]) != 3 or not "새 주장 선출" in popups:
		fails.append("주장 선출 실패")
	var m0 := TeamMood.mood(state)
	TeamMood.after_match(state, true, false, true)
	if TeamMood.mood(state) <= m0 and m0 < 100:
		fails.append("승리 후 분위기 그대로")
	state["teamMood"] = 90
	var ros := WorldGen.team_players(state, "user")
	for p in ros:
		p["cond"] = 0
	TeamMood.week(state, ros, Rng.new(4))
	var ups := ros.filter(func(p): return int(p["cond"]) > 0).size()
	if ups == 0 or TeamMood.mood(state) >= 90:
		fails.append("분위기 주간 효과 실패 (컨디션 상승 %d, 분위기 %d)" % [ups, TeamMood.mood(state)])
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
	# 시기 한정 상품 · 연말 대바겐 · 복주머니 · 일괄 사용
	state["date"] = "2027-04-01"
	Shop.open_market(state, Rng.new(1))
	for sl in state["shop"]["stock"]:
		if sl["key"] in ["icevest", "samgyetang", "luckybag"]:
			fails.append("한정 상품이 4월에 나옴")
	state["date"] = "2027-06-01"
	Shop.open_market(state, Rng.new(1))
	var keys6: Array = state["shop"]["stock"].map(func(x): return x["key"])
	if not "icevest" in keys6 or state["shop"]["stock"].size() != 9:
		fails.append("여름 특가 진열 실패 %s" % [keys6])
	state["date"] = "2027-12-01"
	Shop.open_market(state, Rng.new(1))
	var bag_slot = null
	for sl in state["shop"]["stock"]:
		if sl["key"] == "luckybag":
			bag_slot = sl
	if bag_slot == null or Shop.slot_price(bag_slot) != 55 or state["shop"]["stock"].size() != 10:
		fails.append("연말 대바겐 실패")
	state["inventory"] = {}
	state["points"] = 55
	if Shop.buy_item(state, "luckybag") != "" or Shop.points(state) != 0:
		fails.append("할인가 구매 실패")
	if not Shop.use_item(state, "luckybag", "", Rng.new(2))["ok"]:
		fails.append("복주머니 사용 실패")
	var n_items := 0
	for k in state["inventory"]:
		n_items += int(state["inventory"][k])
	if n_items != 2 or state["inventory"].has("luckybag"):
		fails.append("복주머니 내용물 %s" % [state["inventory"]])
	state["inventory"] = {"charm": 3}
	for p in WorldGen.team_players(state, "user"):
		p["cond"] = 0
	var nn: int = state["news"].size()
	var bulk := Shop.use_bulk(state, "charm", Rng.new(3))
	var n_cond := 0
	for p in WorldGen.team_players(state, "user"):
		if int(p["cond"]) == 2:
			n_cond += 1
	if not bulk["ok"] or int(bulk["n"]) != 3 or n_cond != 3 or state["inventory"].has("charm") or state["news"].size() != nn + 1:
		fails.append("일괄 사용 실패 %s" % [bulk])
	print("일괄 사용: ", bulk["msg"])
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
