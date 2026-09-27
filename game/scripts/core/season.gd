class_name Season
extends RefCounted
## 시즌 진행 (web/src/core/season.ts 이식)
## advance() 는 사용자가 할 일이 생길 때까지 하루씩 진행한다.
##  "training" 월요일 훈련 카드 선택 / "match" 오늘 우리 팀 경기 / "popup" 이벤트 팝업

const LEAGUE_RULES := {"innings": 9, "mercy": [[5, 10], [7, 7]], "tiebreakFrom": 10, "pitchLimit": 105, "allowDraw": true, "maxInnings": 12}


static func rng_of(state: Dictionary) -> Rng:
	return Rng.new(int(state["seed"]), str(state.get("rngState", "")))


static func save_rng(state: Dictionary, rng: Rng) -> void:
	state["rngState"] = rng.get_state_str()


static func start_new_game(o: Dictionary) -> Dictionary:
	var state := WorldGen.new_game(o)
	var rng := rng_of(state)
	create_season_competitions(state, rng)
	save_rng(state, rng)
	return state


static func _blocked_by_leagues(state: Dictionary) -> Dictionary:
	var s := {}
	for c in state["competitions"]:
		if c["kind"] == "league" and c["year"] == state["year"]:
			for f in c["fixtures"]:
				s[f["date"]] = true
	return s


static func _groups_now(state: Dictionary) -> Array:
	var out := []
	for g in GameData.schools()["groups"]:
		var ids := []
		for t in state["teams"].values():
			if t["leagueGroup"] == g["id"]:
				ids.append(t["id"])
		out.append({"id": g["id"], "name": g["name"], "teamIds": ids})
	return out


static func create_season_competitions(state: Dictionary, rng: Rng) -> void:
	var groups := _groups_now(state)
	state["competitions"] = [Competition.create_league(state, "league1", groups), Competition.create_league(state, "league2", groups)]
	var all: Array = state["teams"].keys()
	state["competitions"].append(Competition.create_tournament(state, "emart", all, rng, _blocked_by_leagues(state)))
	state["competitions"].append(Competition.create_tournament(state, "bonghwang", all, rng))


static func comp_by_id(state: Dictionary, id: String):
	for c in state["competitions"]:
		if c["id"] == id:
			return c
	return null


static func find_fixture(state: Dictionary, id: String) -> Dictionary:
	for c in state["competitions"]:
		for f in c["fixtures"]:
			if f["id"] == id:
				return {"comp": c, "f": f}
	return {}


static func fixtures_on(state: Dictionary, date: String) -> Array:
	var out := []
	for c in state["competitions"]:
		for f in c["fixtures"]:
			if f["date"] == date:
				out.append({"comp": c, "f": f})
	return out


static func user_fixtures(state: Dictionary) -> Array:
	var out := []
	var u: String = state["userTeamId"]
	for c in state["competitions"]:
		for f in c["fixtures"]:
			if f["home"] == u or f["away"] == u:
				out.append({"comp": c, "f": f})
	out.sort_custom(func(a, b): return a["f"]["date"] < b["f"]["date"])
	return out


static func next_user_fixture(state: Dictionary) -> Dictionary:
	for x in user_fixtures(state):
		if x["f"].get("result") == null:
			return x
	return {}


static func fixture_label(comp: Dictionary, f: Dictionary) -> String:
	var short: String = Cal.comp_def(comp["key"])["short"]
	if comp["kind"] == "tournament":
		return "%s %s" % [short, Competition.round_name(comp, int(f["round"]))]
	return short


# ───────────── 메인 루프 ─────────────

static func advance(state: Dictionary, max_days := 800) -> String:
	var rng := rng_of(state)
	var result := ""
	for i in max_days:
		if not state["popups"].is_empty():
			result = "popup"
			break
		if not state["weekTrained"]:
			result = "training"
			break
		if state.get("pendingFixture") != null:
			result = "match"
			break
		if _process_day(state, rng) == "match":
			result = "match"
			break
	save_rng(state, rng)
	return result


## 조금씩 진행 (UI 용). 한 번에 CPU 경기를 최대 budget 개까지만 처리해 화면이 멈추지 않게 한다.
## 멈춰야 하면 이유("training"/"match"/"popup")를, 계속 진행하면 "" 반환
static func step_day(state: Dictionary, budget := 8) -> String:
	if not state["popups"].is_empty():
		return "popup"
	if not state["weekTrained"]:
		return "training"
	if state.get("pendingFixture") != null:
		return "match"
	var rng := rng_of(state)
	var r := _process_day(state, rng, budget)
	save_rng(state, rng)
	if r == "match":
		return "match"
	if not state["popups"].is_empty():
		return "popup"
	if not state["weekTrained"]:
		return "training"
	return ""


## budget > 0 이면 CPU 경기를 그 수만큼만 처리하고 "partial" 을 돌려준다 (날짜는 그대로)
static func _process_day(state: Dictionary, rng: Rng, budget := -1) -> String:
	var d: String = state["date"]
	if state.get("dayEventsDone") != d:
		state["dayEventsDone"] = d
		_day_start_events(state, rng)
		if not state["popups"].is_empty():
			return "next"
	for c in state["competitions"]:
		if c["status"] == "upcoming" and c["start"] <= d:
			c["status"] = "active"
	var today := fixtures_on(state, d).filter(func(x): return x["f"].get("result") == null)
	var u: String = state["userTeamId"]
	for x in today:
		if x["f"]["home"] == u or x["f"]["away"] == u:
			state["pendingFixture"] = x["f"]["id"]
			return "match"
	var todo := today.filter(func(x): return x["f"].get("result") == null)
	var partial := budget > 0 and todo.size() > budget
	if partial:
		todo = todo.slice(0, budget)
	_sim_cpu_games(state, todo, rng)
	if partial:
		return "partial"
	_end_of_day(state, rng)
	state["date"] = Cal.add_days(d, 1)
	if Cal.season_year_of(state["date"]) > state["year"]:
		_new_season(state, rng)
	if Cal.weekday(state["date"]) == 1:
		_week_start(state, rng)
	return "next"


## CPU끼리 경기를 시뮬레이션 (실황 문구 생략 모드).
## 참고: GDScript 스레드 병렬화(WorkerThreadPool)는 측정 결과 빨라지지 않아 쓰지 않는다.
static func _sim_cpu_games(state: Dictionary, todo: Array, rng: Rng) -> void:
	for x in todo:
		var m := create_match(state, x["f"], rng)
		m.quiet = true
		MatchAI.play_out(m)
		apply_result(state, x["comp"], x["f"], m, rng)


static func _day_start_events(state: Dictionary, rng: Rng) -> void:
	var d: String = state["date"]
	if d.ends_with("-01"):
		Facilities.monthly_income(state)
	for ev in Cal.year_events(state["year"]):
		if ev["date"] != d:
			continue
		match ev["key"]:
			"allstar":
				_news(state, "info", "고교-대학 올스타전이 열렸다. 전국의 스타 선수들이 한자리에!")
			"sportsSelect":
				_create_sports_festival(state, rng)
			"draft":
				run_draft(state, rng)
				Scouting.generate_prospects(state, rng)
				_news(state, "info", "중학 유망주 명단이 공개됐다. 스카우트 활동을 시작하자.")
			"retire":
				_retire_seniors(state)
			"proSeason":
				Idol.pro_season_end(state, rng)
				_news(state, "idol", "프로야구 시즌이 막을 내렸다.")
			"camp":
				state["trainingBonus"] = 1.6
				state["popups"].append({"kind": "good", "title": "동계 전지훈련", "body": "따뜻한 남쪽으로 전지훈련을 떠났다!\n이번 주 훈련 효과가 크게 오른다."})
			"graduate":
				_news(state, "info", "졸업식. 한 시즌이 끝났다.")


static func _news(state: Dictionary, kind: String, text: String) -> void:
	state["news"].append({"date": state["date"], "kind": kind, "text": text})


static func _end_of_day(state: Dictionary, rng: Rng) -> void:
	for p in state["players"].values():
		if p["injury"] > 0:
			p["injury"] -= 1
		if p["fatigue"] > 0:
			p["fatigue"] = maxf(0.0, p["fatigue"] - 2)
	for c in state["competitions"].duplicate():
		if c["kind"] != "league" or c["status"] == "done":
			continue
		if state["date"] >= c["end"] and c["fixtures"].all(func(f): return f.get("result") != null):
			_finish_league(state, c, rng)


static func _week_start(state: Dictionary, rng: Rng) -> void:
	state["weekTrained"] = false
	var m := Cal.month_of(state["date"])
	if (m >= 9 or m <= 2) and not state["prospects"].is_empty():
		state["scoutPoints"] = mini(6, int(state["scoutPoints"]) + 1)
	Idol.weekly_pro_news(state, rng)
	var roster := WorldGen.team_players(state, state["userTeamId"])
	for p in state["players"].values():
		Training.weekly_condition(p, rng)
	var dorm := Facilities.level(state, "dorm")
	if dorm > 0:
		for p in roster:
			p["fatigue"] = maxf(0.0, p["fatigue"] - 5 * dorm)
	var ev := WeeklyEvents.roll(state, roster, rng)
	if ev.has("news"):
		state["news"].append(ev["news"])
	if ev.has("popup"):
		state["popups"].append(ev["popup"])
	for p in roster:
		var pop = Idol.check_milestones(state, p)
		if pop != null:
			state["popups"].append(pop)
	for t in state["teams"].values():
		if t["isUser"]:
			continue
		var card := Training.draw_card(rng, "cpu")
		for p in WorldGen.team_players(state, t["id"]):
			Training.train_player(p, card, state["pros"], rng, null, true)
	if state["news"].size() > 300:
		state["news"] = state["news"].slice(state["news"].size() - 300)


# ───────────── 훈련 ─────────────

static func use_card(state: Dictionary, card_id: String) -> Dictionary:
	var rng := rng_of(state)
	var hand: Array = state["hand"]
	var card: Dictionary = hand[0]
	for c in hand:
		if c["id"] == card_id:
			card = c
	var report := {"gains": {}, "injuries": [], "awakenings": []}
	var bonus: float = state.get("trainingBonus", 1.0) if state.get("trainingBonus") != null else 1.0
	var eff := card.duplicate()
	eff["value"] = card["value"] * bonus
	for p in WorldGen.team_players(state, state["userTeamId"]):
		Training.train_player(p, eff, state["pros"], rng, report, false, state.get("facilities"))
	state.erase("trainingBonus")
	if card["kind"] == "scout":
		state["scoutPoints"] = mini(8, int(state["scoutPoints"]) + 2)
	hand.erase(card)
	hand.append(Training.draw_card(rng, WorldGen.uid(state, "c")))
	state["weekTrained"] = true
	_news(state, "info", "이번 주 훈련: %s Lv%d" % [Training.CARD_INFO[card["kind"]]["name"], card["value"]])
	for id in report["injuries"]:
		_news(state, "bad", "%s, 훈련 중 부상! (%d일)" % [PlayerUtil.full_name(state["players"][id]), state["players"][id]["injury"]])
	for a in report["awakenings"]:
		state["popups"].append({"kind": "good", "playerId": a["playerId"], "title": "특수능력 습득",
			"body": "%s 새로운 능력에 눈을 떴다!\n「%s」" % [Text.josa(PlayerUtil.full_name(state["players"][a["playerId"]]), "이/가"), GameData.ability_name(a["ability"])]})
	save_rng(state, rng)
	return report


# ───────────── 경기 ─────────────

static func rules_for(comp: Dictionary) -> Dictionary:
	return LEAGUE_RULES if comp["kind"] == "league" else MatchEngine.DEFAULT_RULES


## user_opts: {starterId?, lineup?}
static func create_match(state: Dictionary, f: Dictionary, rng: Rng, user_opts := {}) -> MatchEngine:
	var home: Dictionary = state["teams"][f["home"]]
	var away: Dictionary = state["teams"][f["away"]]
	var comp = comp_by_id(state, f["compId"])
	var hs := SideBuilder.build(home, WorldGen.team_players(state, home["id"]), f["date"], user_opts if home["isUser"] else {})
	var as_ := SideBuilder.build(away, WorldGen.team_players(state, away["id"]), f["date"], user_opts if away["isUser"] else {})
	return MatchEngine.new(hs, as_, rng, rules_for(comp))


## 투구수에 따른 의무 휴식일 (대한야구소프트볼협회 투구수 제한 규정)
static func rest_days(np: int) -> int:
	if np <= 30: return 0
	if np <= 45: return 1
	if np <= 60: return 2
	if np <= 75: return 3
	return 4


static func apply_result(state: Dictionary, comp: Dictionary, f: Dictionary, m: MatchEngine, rng: Rng) -> void:
	var res := {
		"homeScore": m.home.score, "awayScore": m.away.score, "innings": m.inning, "winner": m.winner,
		"lineScore": {"home": m.home.line.duplicate(), "away": m.away.line.duplicate()},
		"hits": {"home": m.home.hits, "away": m.away.hits}, "errors": {"home": m.home.errors, "away": m.away.errors}, "called": m.called,
	}
	f["result"] = res
	var u: String = state["userTeamId"]
	var is_user_game: bool = f["home"] == u or f["away"] == u
	for side in [m.home, m.away]:
		var team: Dictionary = state["teams"][side.team_id]
		var won: bool = m.winner == team["id"]
		var rec: Dictionary = team["seasonRecord"]
		if won:
			rec["w"] += 1
			team["seasonPoints"] += 1 if comp["kind"] == "league" else 3
		elif m.winner == null:
			rec["d"] += 1
		else:
			rec["l"] += 1
		for id in side.box:
			var p = state["players"].get(id)
			if p == null:
				continue
			var box: Dictionary = side.box[id]
			PlayerUtil.add_line(p["season"]["bat"], box["bat"])
			PlayerUtil.add_line(p["career"]["bat"], box["bat"])
			PlayerUtil.add_line(p["season"]["pit"], box["pit"])
			PlayerUtil.add_line(p["career"]["pit"], box["pit"])
			p["fatigue"] = clampf(p["fatigue"] + 4 + box["pit"]["np"] / 4.0, 0, 100)
			if box["pit"]["np"] > 0:
				p["restUntil"] = Cal.add_days(f["date"], rest_days(box["pit"]["np"]) + 1)
			if team["isUser"]:
				if box["bat"]["pa"] > 0:
					_gain(state, p, "contact", 0.6, rng)
					_gain(state, p, "eye", 0.4, rng)
					if box["bat"]["h"] > 0:
						_gain(state, p, "power", 0.4, rng)
				if box["pit"]["outs"] > 0:
					_gain(state, p, "control", box["pit"]["outs"] / 12.0, rng)
					_gain(state, p, "stamina", box["pit"]["outs"] / 15.0, rng)
				var good: bool = box["bat"]["h"] >= 2 or box["bat"]["hr"] > 0 or (box["pit"]["outs"] >= 15 and box["pit"]["er"] <= 2)
				if good and p.get("idolId") != null:
					p["idolBond"] = clampi(p["idolBond"] + 2, 0, 100)
					var pop = Idol.check_milestones(state, p)
					if pop != null:
						state["popups"].append(pop)

	if comp["kind"] == "tournament":
		Competition.advance_tournament(comp, f)
		if comp["status"] == "done" and comp.get("champion") != null:
			var ch: Dictionary = state["teams"][comp["champion"]]
			ch["seasonPoints"] += 5
			ch["prestige"] = clampi(ch["prestige"] + 3, 0, 95)

	if is_user_game:
		state.erase("pendingFixture")
		var opp: Dictionary = state["teams"][f["away"] if f["home"] == u else f["home"]]
		var us: int = res["homeScore"] if f["home"] == u else res["awayScore"]
		var them: int = res["awayScore"] if f["home"] == u else res["homeScore"]
		var outcome := "승리" if res["winner"] == u else ("패배" if res["winner"] != null else "무승부")
		state["news"].append({"date": f["date"], "kind": "good" if res["winner"] == u else ("bad" if res["winner"] != null else "info"),
			"text": "[%s] vs %s %d:%d %s%s" % [fixture_label(comp, f), opp["name"], us, them, outcome, " (콜드)" if res["called"] else ""]})
		if comp["kind"] == "tournament":
			if res["winner"] == u:
				state["reputation"] = clampi(state["reputation"] + 1, 0, 100)
			var r := Competition.tournament_result_for(comp, u)
			if r != "" and (comp.get("champion") != null or res["winner"] != u):
				comp["userResult"] = r
				var def := Cal.comp_def(comp["key"])
				Facilities.add_prize(state, r, def["short"])
				if r == "우승":
					state["reputation"] = clampi(state["reputation"] + int(def["repWin"]), 0, 100)
					state["popups"].append({"kind": "good", "title": "%s 우승!" % def["short"], "body": "%s, %s 우승!!\n전국에 이름을 떨쳤다. (명성 +%d)" % [WorldGen.user_team(state)["name"], def["name"], def["repWin"]]})
				else:
					var bonus := roundi(def["repWin"] / 2.0) if r == "준우승" else (4 if r == "4강" else (2 if r == "8강" else 0))
					state["reputation"] = clampi(state["reputation"] + bonus, 0, 100)
					state["popups"].append({"kind": "good" if r in ["준우승", "4강"] else "info", "title": "%s %s" % [def["short"], r],
						"body": "%s에서 %s%s%s" % [def["name"], r, "했다." if r.ends_with("탈락") else "의 성적을 거뒀다.", (" (명성 +%d)" % bonus) if bonus else ""]})


static func _gain(state: Dictionary, p: Dictionary, k: String, pts: float, rng: Rng) -> void:
	Training.apply_exp(p, k, pts, Training.growth_mult(p, k, state["pros"]), rng)


static func auto_play_user_match(state: Dictionary) -> MatchEngine:
	if state.get("pendingFixture") == null:
		return null
	var found := find_fixture(state, state["pendingFixture"])
	if found.is_empty():
		return null
	var rng := rng_of(state)
	var m := create_match(state, found["f"], rng)
	MatchAI.play_out(m)
	apply_result(state, found["comp"], found["f"], m, rng)
	save_rng(state, rng)
	return m


static func finish_user_match(state: Dictionary, m: MatchEngine) -> void:
	if state.get("pendingFixture") == null:
		return
	var found := find_fixture(state, state["pendingFixture"])
	if found.is_empty():
		return
	var rng := rng_of(state)
	apply_result(state, found["comp"], found["f"], m, rng)
	save_rng(state, rng)


# ───────────── 대회 전환 ─────────────

static func _finish_league(state: Dictionary, c: Dictionary, rng: Rng) -> void:
	c["status"] = "done"
	var u: String = state["userTeamId"]
	var hw := []
	var cr := []
	var pres := []
	for g in c["groups"]:
		var table := Competition.standings(c, g["id"])
		for i in table.size():
			var row: Dictionary = table[i]
			var rank := i + 1
			if rank == 1:
				hw.append(row["teamId"])
				cr.append(row["teamId"])
				state["teams"][row["teamId"]]["seasonPoints"] += 3
			elif rank % 2 == 0:
				hw.append(row["teamId"])
			else:
				cr.append(row["teamId"])
			if rank <= 4:
				pres.append(row["teamId"])
			if row["teamId"] == u:
				c["userResult"] = "%s %d위 (%d승 %d패%s)" % [g["name"], rank, row["w"], row["l"], (" %d무" % row["d"]) if row["d"] else ""]
				if rank == 1:
					state["reputation"] = clampi(state["reputation"] + 3, 0, 100)
	if c["key"] == "league1":
		state["competitions"].append(Competition.create_tournament(state, "hwanggeum", hw, rng))
		state["competitions"].append(Competition.create_tournament(state, "cheongryong", cr, rng))
		var in_hw := u in hw
		var in_cr := u in cr
		state["popups"].append({"kind": "good", "title": "주말리그 전반기 종료",
			"body": "최종 성적: %s\n%s" % [c.get("userResult", ""), "황금사자기와 청룡기 동시 출전권 획득!" if in_hw and in_cr else ("황금사자기 출전권 획득!" if in_hw else "청룡기 출전권 획득!")]})
	else:
		state["competitions"].append(Competition.create_tournament(state, "president", pres, rng))
		var in_p := u in pres
		state["popups"].append({"kind": "good" if in_p else "info", "title": "주말리그 후반기 종료",
			"body": "최종 성적: %s\n%s" % [c.get("userResult", ""), "대통령배 출전권 획득!" if in_p else "아쉽게도 대통령배 출전권을 놓쳤다..."]})


static func _create_sports_festival(state: Dictionary, rng: Rng) -> void:
	var by_prov := {}
	var score := func(id: String) -> float: return state["teams"][id]["seasonPoints"] * 10.0 + state["teams"][id]["prestige"] * 0.1
	for t in state["teams"].values():
		var cur = by_prov.get(t["province"])
		if cur == null or score.call(t["id"]) > score.call(cur):
			by_prov[t["province"]] = t["id"]
	state["competitions"].append(Competition.create_tournament(state, "sports", by_prov.values(), rng))
	var ut := WorldGen.user_team(state)
	var rep: String = by_prov[ut["province"]]
	if rep == ut["id"]:
		state["popups"].append({"kind": "good", "title": "전국체전 대표 선발", "body": "%s 대표로 전국체육대회에 출전하게 됐다!" % ut["province"]})
	else:
		_news(state, "info", "전국체전 %s 대표로 %s 선발됐다." % [ut["province"], Text.josa(state["teams"][rep]["name"], "이/가")])


# ───────────── 드래프트 / 은퇴 / 새 시즌 ─────────────

static func _style_from_player(p: Dictionary) -> String:
	var opts := [["파이어볼러", "velo"], ["제구파", "control"], ["변화구", "breaking"], ["철완", "stamina"]] if p["pos"] == "P" \
		else [["파워히터", "power"], ["교타자", "contact"], ["준족", "speed"], ["강견", "arm"], ["명수비", "fielding"]]
	opts.sort_custom(func(a, b): return PlayerUtil.stat_value(p["r"], a[1]) > PlayerUtil.stat_value(p["r"], b[1]))
	return opts[0][0]


static func pro_team_name(state: Dictionary, id: String) -> String:
	for t in state["proTeams"]:
		if t["id"] == id:
			return t["name"]
	return ""


static func run_draft(state: Dictionary, rng: Rng) -> void:
	var scored := []
	for p in state["players"].values():
		if p["teamId"] != "" and PlayerUtil.grade(p, state["year"]) == 3:
			scored.append({"p": p, "s": PlayerUtil.overall(p) + p["talent"] * 4 + rng.next() * 8 + (3.0 if p["pos"] == "P" else 0.0)})
	scored.sort_custom(func(a, b): return a["s"] > b["s"])
	var picks := scored.slice(0, 70)
	var lines := []
	for i in picks.size():
		var p: Dictionary = picks[i]["p"]
		var rnd := (i * 11) / picks.size() + 1
		var team: Dictionary = rng.pick(state["proTeams"])
		p["draft"] = {"year": state["year"], "teamId": team["id"], "round": rnd}
		if p["teamId"] == state["userTeamId"]:
			var line := "%s — %s %d라운드 지명!" % [PlayerUtil.full_name(p), team["name"], rnd]
			var idol := Idol.idol_of(state, p)
			if not idol.is_empty() and idol["teamId"] == team["id"] and not idol.get("retired", false):
				line += "\n   ★ 동경하던 %s 같은 유니폼을 입게 됐다! \"%s 선배, 이제 동료예요!\"" % [Text.josa(Idol.pro_name(idol), "과/와"), idol["given"]]
			lines.append(line)
			state["reputation"] = clampi(state["reputation"] + (6 if rnd == 1 else (4 if rnd <= 3 else 2)), 0, 100)
			state["budget"] = int(state.get("budget", 0)) + int(Facilities.data()["draftDonation"])
			state["pros"].append({"id": "pro" + WorldGen.uid(state, "x"), "sur": p["sur"], "given": p["given"], "teamId": team["id"], "pos": p["pos"],
				"style": _style_from_player(p), "number": rng.irange(1, 99), "birthYear": int(state["year"]) - 18, "line": "신인", "alumniOf": state["userTeamId"]})
	if not picks.is_empty():
		var top: Dictionary = picks[0]["p"]
		_news(state, "info", "KBO 신인 드래프트 개최. 전체 1순위: %s %s" % [state["teams"][top["teamId"]]["name"], PlayerUtil.full_name(top)])
	state["popups"].append({"kind": "good" if not lines.is_empty() else "info", "title": "KBO 신인 드래프트",
		"body": ("우리 학교에서 프로 선수가 탄생했다!\n\n" + "\n".join(lines)) if not lines.is_empty() else "올해는 우리 학교에서 지명된 선수가 없었다...\n3학년들은 대학 진학을 준비한다."})


static func _retire_seniors(state: Dictionary) -> void:
	var names := []
	for t in state["teams"].values():
		var keep := []
		for id in t["playerIds"]:
			var p = state["players"].get(id)
			if p == null:
				continue
			if PlayerUtil.grade(p, state["year"]) >= 3:
				if t["isUser"]:
					var dr = p.get("draft")
					names.append("%s (%s)" % [PlayerUtil.full_name(p), (pro_team_name(state, dr["teamId"]) + " 입단") if dr != null else "대학 진학"])
					state["alumni"].append({"playerId": p["id"], "name": PlayerUtil.full_name(p), "gradYear": state["year"], "pos": p["pos"],
						"draft": {"teamId": dr["teamId"], "round": dr["round"]} if dr != null else null})
				state["players"].erase(id)
			else:
				keep.append(id)
		t["playerIds"] = keep
	if not names.is_empty():
		state["popups"].append({"kind": "info", "title": "3학년 은퇴식", "body": "3년간 함께한 3학년들이 야구부를 떠난다. 고마웠다!\n\n" + "\n".join(names)})


static func _new_season(state: Dictionary, rng: Rng) -> void:
	var prev: int = state["year"]
	var results := []
	for c in state["competitions"]:
		if c.get("userResult") != null:
			results.append({"comp": Cal.comp_def(c["key"])["short"], "result": c["userResult"]})
	var drafted := []
	for a in state["alumni"]:
		if a["gradYear"] == prev and a.get("draft") != null:
			drafted.append(a["name"])
	state["history"].append({"year": prev, "results": results, "drafted": drafted})
	state["year"] = Cal.season_year_of(state["date"])
	for p in state["players"].values():
		p["season"] = {"bat": PlayerUtil.empty_bat(), "pit": PlayerUtil.empty_pit()}
		p["fatigue"] = 0
		p.erase("restUntil")
	for t in state["teams"].values():
		t["seasonPoints"] = 0
		t["seasonRecord"] = {"w": 0, "l": 0, "d": 0}
		if t["isUser"]:
			continue
		for p in WorldGen.intake_for(state, rng, t, state["year"], 6, t["prestige"]):
			state["players"][p["id"]] = p
			t["playerIds"].append(p["id"])
		t["prestige"] = clampi(roundi(t["prestige"] * 0.9 + 4.5), 10, 95)
	var joined := Scouting.enroll(state, rng)
	WorldGen.user_team(state).erase("lineup")
	state["reputation"] = clampi(roundi(state["reputation"] * 0.92 + 1.6), 0, 100)
	create_season_competitions(state, rng)
	_news(state, "info", "%d 시즌 개막! 신입생 %d명이 입부했다." % [state["year"], joined.size()])
	var lines := []
	for p in joined:
		var idol := Idol.idol_of(state, p)
		lines.append("%s (%s, 재능 %s)%s" % [PlayerUtil.full_name(p), PlayerUtil.POS_KO[p["pos"]], Text.stars(p["talent"]), (" — 동경: " + Idol.pro_name(idol)) if not idol.is_empty() else ""])
	state["popups"].append({"kind": "good", "title": "%d 시즌 개막" % state["year"], "body": "신입생이 입부했다!\n\n" + "\n".join(lines)})


# ───────────── UI 헬퍼 ─────────────

static func year_schedule(state: Dictionary) -> Array:
	var items := []
	for k in ["league1", "emart", "hwanggeum", "league2", "cheongryong", "president", "bonghwang", "sports"]:
		var d := Cal.comp_dates(k, state["year"])
		items.append({"date": d["start"], "end": d["end"], "label": Cal.comp_def(k)["short"], "comp": k})
	for e in Cal.year_events(state["year"]):
		items.append({"date": e["date"], "end": e["date"], "label": e["label"], "comp": ""})
	items.sort_custom(func(a, b): return a["date"] < b["date"])
	return items
