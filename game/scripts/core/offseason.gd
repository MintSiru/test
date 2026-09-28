class_name Offseason
extends RefCounted
## 비시즌 콘텐츠 (Godot 전용, 데이터 data/offseason.json)
##  - 1월 동계 합숙 장소 선택 (비용·효과가 다른 세 곳)
##  - 9월 3학년 진로 상담: 예상 지명 결과를 보고 한 명에게 감독 추천서 (드래프트 점수 +)
##  - 합숙 주 훈련 때 합숙 에피소드 하나 + 「합숙 마지막 밤」 선택
##  - 10~2월 학교 행사 (주간 이벤트)
##  - 지명받지 못한 3학년의 진로(대학·실업), 대학 소식, 4년 뒤 대졸 드래프트
## 선택은 팝업 {kind: "choice", choice, options: [[key, 버튼 글자]]} 으로 묻고 choose() 로 반영한다.
## 고르지 않고 넘기면 기본값(무료 합숙, 추천서 없음)이 적용된다.


static func data() -> Dictionary:
	return GameData.load_json("offseason")


# ───────────── 동계 합숙 ─────────────

static func camp_event(state: Dictionary) -> void:
	var cfg: Dictionary = data()["camp"]
	var opts := []
	var lines := []
	for o in cfg["options"]:
		if o["key"] == cfg["default"]:
			state["trainingBonus"] = float(o["bonus"])
			state["campKey"] = o["key"]
		opts.append([o["key"], "%s%s" % [o["name"], (" (%dP)" % o["cost"]) if int(o["cost"]) > 0 else ""]])
		lines.append("· %s — %s" % [o["name"], o["desc"]])
	state["popups"].append({"kind": "choice", "choice": "camp", "title": "동계 합숙 장소", "options": opts,
		"body": "겨울 합숙을 어디서 할까? (보유 %dP)\n\n%s" % [Shop.points(state), "\n".join(lines)]})


static func _camp_option(key: String) -> Dictionary:
	for o in data()["camp"]["options"]:
		if o["key"] == key:
			return o
	return {}


# ───────────── 3학년 진로 상담 ─────────────

## 드래프트 예상 점수 (run_draft 의 점수에서 운 요소를 평균값으로)
static func expected_draft_score(p: Dictionary) -> float:
	return PlayerUtil.overall(p) + p["talent"] * 4 + 4.0 + (3.0 if p["pos"] == "P" else 0.0) + (float(data()["counsel"]["recommendBonus"]) if p.get("recommended", false) else 0.0)


## 우리 학교 3학년의 예상 순위와 등급 [{p, rank, grade}]
static func senior_outlook(state: Dictionary) -> Array:
	var seniors := []
	for p in state["players"].values():
		if p["teamId"] != "" and PlayerUtil.grade(p, state["year"]) == 3:
			seniors.append(p)
	seniors.sort_custom(func(a, b): return expected_draft_score(a) > expected_draft_score(b))
	var out := []
	for i in seniors.size():
		var p: Dictionary = seniors[i]
		if p["teamId"] != state["userTeamId"]:
			continue
		var grade := ""
		for g in data()["counsel"]["grades"]:
			if i + 1 <= int(g[0]):
				grade = g[1]
				break
		out.append({"p": p, "rank": i + 1, "grade": grade})
	return out


static func counsel_event(state: Dictionary) -> void:
	var ol := senior_outlook(state)
	if ol.is_empty():
		return
	var lines := []
	var opts := []
	for x in ol:
		var p: Dictionary = x["p"]
		lines.append("· %s (%s) — %s (전국 3학년 중 약 %d위, 지명 70명)" % [PlayerUtil.full_name(p), PlayerUtil.POS_KO[p["pos"]], x["grade"], x["rank"]])
		# 1라운드 유력 선수는 추천서가 필요 없다. 그 밖의 상위 3명에게 선택지
		if x["rank"] > 10 and opts.size() < 3:
			opts.append([p["id"], "%s 추천서 (약 %d위)" % [PlayerUtil.full_name(p), x["rank"]]])
	opts.append(["none", "추천서 없이"])
	state["popups"].append({"kind": "choice", "choice": "counsel", "title": "3학년 진로 상담", "options": opts,
		"body": "드래프트(9월 하순)를 앞두고 3학년과 진로 상담을 했다.\n\n%s\n\n한 명에게 감독 추천서를 써 주면 지명 가능성이 오른다." % "\n".join(lines)})


# ───────────── 합숙 에피소드 ─────────────

## 합숙 주 훈련(use_card) 직후. 에피소드 하나를 소식·팝업으로, 마지막 밤 선택 팝업
static func camp_episode(state: Dictionary, rng: Rng) -> void:
	var place: String = state.get("campKey", "")
	state.erase("campKey")
	var roster := WorldGen.team_players(state, state["userTeamId"])
	if place == "" or roster.is_empty():
		return
	var ob := _pro_alumni_name(state)
	var pool := []
	var w := []
	for e in data()["campEpisodes"]:
		if place in e["places"] and (e["key"] != "obVisit" or ob != ""):
			pool.append(e)
			w.append(float(e["weight"]))
	var e: Dictionary = rng.weighted(pool, w)
	var healthy: Array = roster.filter(func(x): return int(x["injury"]) <= 0)
	var who: Dictionary = rng.pick(healthy if not healthy.is_empty() else roster)
	var extra := ""
	match e["key"]:
		"nightPractice":
			var fs := Training.focus_stats(who)
			for k in fs:
				Training.apply_exp(who, k, 12.0 * fs[k], Training.growth_mult(who, k, state["pros"]), rng)
		"snowRun", "beachRun":
			for p in roster:
				Training.apply_exp(p, "stamina", 4.0, Training.growth_mult(p, "stamina", state["pros"]), rng)
				if e["key"] == "beachRun":
					Training.apply_exp(p, "speed", 4.0, Training.growth_mult(p, "speed", state["pros"]), rng)
		"localGame":
			for i in 3:
				var q: Dictionary = rng.pick(roster)
				var fs2 := Training.focus_stats(q)
				for k in fs2:
					Training.apply_exp(q, k, 6.0 * fs2[k], Training.growth_mult(q, k, state["pros"]), rng)
			state["reputation"] = clampi(int(state["reputation"]) + 1, 0, 100)
		"coachLesson":
			var aw := Training.awaken(who, rng)
			if not aw.is_empty() and aw["ability"] != "":
				extra = " 「%s」을(를) 익혔다!" % Abilities.name_of(aw["ability"])
			else:
				var fs3 := Training.focus_stats(who)
				for k in fs3:
					Training.apply_exp(who, k, 12.0 * fs3[k], Training.growth_mult(who, k, state["pros"]), rng)
				extra = " (한층 성장)"
		"obVisit":
			for p in roster:
				p["cond"] = mini(2, int(p["cond"]) + 1)
			TeamMood.change(state, 5)
		"sprain":
			who["injury"] = maxi(int(who["injury"]), 7)
	var text: String = e["text"].replace("{n}", PlayerUtil.full_name(who)).replace("{ob}", ob) + extra
	state["news"].append({"date": state["date"], "kind": "bad" if e["key"] == "sprain" else "good", "text": "[합숙] " + text})
	var cfg: Dictionary = data()["campNight"]
	_camp_night_apply(state, cfg["default"])
	state["popups"].append({"kind": "choice", "choice": "campNight", "title": cfg["title"], "options": cfg["options"],
		"body": "[합숙 에피소드]\n%s\n\n%s" % [text, cfg["body"].replace("{pts}", str(Shop.points(state)))]})


static func _pro_alumni_name(state: Dictionary) -> String:
	for al in state["alumni"]:
		if al.get("draft") != null:
			return al["name"]
	return ""


## 마지막 밤: 기본값(푹 쉰다)을 먼저 적용해 두고, 다른 걸 고르면 되돌린 뒤 적용
static func _camp_night_apply(state: Dictionary, key: String) -> void:
	var undo := {}
	if key == "rest":
		for p in WorldGen.team_players(state, state["userTeamId"]):
			undo[p["id"]] = p["fatigue"]
			p["fatigue"] = maxf(0.0, p["fatigue"] - 20.0)
	state["campNightUndo"] = undo


static func _camp_night(state: Dictionary, key: String) -> String:
	var roster := WorldGen.team_players(state, state["userTeamId"])
	# 기본값(푹 쉰다) 되돌리기
	var undo: Dictionary = state.get("campNightUndo", {})
	state.erase("campNightUndo")
	if key != "rest":
		for p in roster:
			if undo.has(p["id"]):
				p["fatigue"] = float(undo[p["id"]])
	else:
		TeamMood.change(state, 3)
		return "푹 쉬며 합숙을 마무리했다. (피로 -20)"
	match key:
		"special":
			var rng := Season.rng_of(state)
			for p in roster:
				p["fatigue"] = clampf(p["fatigue"] + 15.0, 0, 100)
				var fs := Training.focus_stats(p)
				for k in fs:
					Training.apply_exp(p, k, 3.0 * fs[k], Training.growth_mult(p, k, state["pros"]), rng)
			Season.save_rng(state, rng)
			return "마지막 밤까지 특별 야간 훈련! 녹초가 됐지만 다들 한층 성장했다."
		"party":
			var cost := int(data()["campNight"]["partyCost"])
			if Shop.points(state) < cost:
				for p in roster:
					p["fatigue"] = maxf(0.0, p["fatigue"] - 20.0)
				return "포인트가 모자라 고기 대신 라면 파티... 그래도 푹 쉬었다. (피로 -20)"
			state["points"] = Shop.points(state) - cost
			for p in roster:
				p["cond"] = mini(2, int(p["cond"]) + 1)
			TeamMood.change(state, 8)
			return "고기 파티! 선수들이 감독님을 헹가래쳤다. (전원 컨디션 상승, -%dP)" % cost
	return "푹 쉬며 합숙을 마무리했다. (피로 -20)"


# ───────────── 졸업 후 진로 ─────────────

## 지명받지 못한 3학년의 진로 (은퇴식 때). rank = 전국 3학년 중 예상 순위
static func after_school(state: Dictionary, p: Dictionary, rank: int, rng: Rng) -> Dictionary:
	var cfg: Dictionary = data()["afterSchool"]
	var chance := 0.0
	for c in cfg["collegeChance"]:
		if rank <= int(c[0]):
			chance = float(c[1])
			break
	# 상위권이거나 절반 확률로 대학 진학, 나머지는 실업·독립리그
	if rank <= 300 or rng.chance(0.5):
		return {"kind": "uni", "school": rng.pick(cfg["universities"]), "chance": chance}
	return {"kind": "work", "chance": chance * 0.5}


## 대졸·독립리그 지명 선수의 프로 스타일 (GameData.styles 의 키여야 동경 선수로 쓸 수 있다)
static func late_style(pos: String, rng: Rng) -> String:
	return rng.pick(["제구파", "변화구", "철완"] if pos == "P" else ["교타자", "준족", "명수비", "강견"])


static func path_text(path) -> String:
	if path == null:
		return ""
	match path["kind"]:
		"uni": return "%s 진학" % path["school"]
		"work": return "독립리그 입단"
	return ""


## 새 시즌: 대학에 간 졸업생 소식 (한 해 한 명)
static func alumni_news(state: Dictionary, rng: Rng) -> void:
	var cand := []
	for al in state["alumni"]:
		var path = al.get("path")
		var yrs := int(state["year"]) - int(al["gradYear"])
		if path != null and path["kind"] == "uni" and yrs >= 1 and yrs <= 3 and al.get("draft") == null:
			cand.append(al)
	if cand.is_empty() or not rng.chance(0.7):
		return
	var al: Dictionary = rng.pick(cand)
	var yrs2 := int(state["year"]) - int(al["gradYear"]) + 1
	state["news"].append({"date": state["date"], "kind": "good",
		"text": "[OB 소식] %s(%s %d학년) — %s" % [al["name"], al["path"]["school"], yrs2, rng.pick(data()["afterSchool"]["news"])]})


## 대졸·독립리그 드래프트 (신인 드래프트 날). 졸업 4년째 졸업생에게 기회. 지명 문구 목록
static func college_draft(state: Dictionary, rng: Rng) -> Array:
	var lines := []
	var years := int(data()["afterSchool"]["collegeDraftYears"])
	for al in state["alumni"]:
		var path = al.get("path")
		if path == null or al.get("draft") != null or int(state["year"]) - int(al["gradYear"]) != years or path.get("done", false):
			continue
		path["done"] = true
		if not rng.chance(float(path["chance"])):
			continue
		var team: Dictionary = rng.pick(state["proTeams"])
		var rnd := rng.irange(3, 11)
		al["draft"] = {"teamId": team["id"], "round": rnd, "late": true}
		var sur: String = al.get("sur", al["name"].substr(0, 1))
		state["pros"].append({"id": "pro" + WorldGen.uid(state, "x"), "sur": sur, "given": al.get("given", al["name"].substr(sur.length())), "teamId": team["id"], "pos": al["pos"],
			"style": late_style(al["pos"], rng), "number": rng.irange(1, 99), "birthYear": int(al["gradYear"]) - 18, "line": "신인", "alumniOf": state["userTeamId"]})
		lines.append("%s (%s) — %s %d라운드 지명!" % [al["name"], path_text(path), team["name"], rnd])
		state["reputation"] = clampi(int(state["reputation"]) + 2, 0, 100)
	if not lines.is_empty():
		Achievements.event(state, "lateDraft")
		state["popups"].append({"kind": "good", "title": "졸업생 프로 지명!",
			"body": "고교 졸업 뒤 %d년, 포기하지 않은 졸업생이 프로에 지명됐다!\n\n%s\n\n(명성 +%d)" % [years, "\n".join(lines), 2 * lines.size()]})
	return lines


# ───────────── 선택 반영 ─────────────

## 선택 결과 문구. 실패(포인트 부족 등)면 기본값을 적용하고 이유를 돌려준다
static func choose(state: Dictionary, choice: String, key: String) -> String:
	match choice:
		"camp":
			var o := _camp_option(key)
			if o.is_empty():
				return ""
			if Shop.points(state) < int(o["cost"]):
				var d := _camp_option(data()["camp"]["default"])
				state["trainingBonus"] = float(d["bonus"])
				state["campKey"] = d["key"]
				return "포인트가 부족해 %s(으)로 대신했다." % d["name"]
			state["points"] = Shop.points(state) - int(o["cost"])
			state["trainingBonus"] = float(o["bonus"])
			state["campKey"] = o["key"]
			var roster := WorldGen.team_players(state, state["userTeamId"])
			if o.has("fatigue"):
				for p in roster:
					p["fatigue"] = clampf(p["fatigue"] + float(o["fatigue"]), 0, 100)
			if o.get("cond", false):
				for p in roster:
					p["cond"] = 2
			if o.has("awaken"):
				state["awakenBonus"] = float(o["awaken"])
			state["news"].append({"date": state["date"], "kind": "good", "text": "%s을(를) 떠났다! (훈련 효과 ×%s%s)" % [o["name"], o["bonus"], (", -%dP" % o["cost"]) if int(o["cost"]) > 0 else ""]})
			return "%s을(를) 떠났다!\n%s" % [o["name"], o["desc"]]
		"counsel":
			var p = state["players"].get(key)
			if p == null:
				return "올해는 추천서를 쓰지 않았다."
			p["recommended"] = true
			var n := PlayerUtil.full_name(p)
			state["news"].append({"date": state["date"], "kind": "good", "text": "%s에게 감독 추천서를 써 주었다." % n})
			return "%s에게 감독 추천서를 써 주었다.\n\"감독님, 꼭 프로에서 보여 드릴게요!\"\n(드래프트 평가 +%d)" % [n, int(data()["counsel"]["recommendBonus"])]
		"campNight":
			return _camp_night(state, key)
		"captain":
			return TeamMood.set_captain(state, key)
		"managerPerk":
			return Manager.choose_perk(state, key)
	return ""


# ───────────── 학교 행사 ─────────────

## 이번 달에 열릴 수 있는 학교 행사 하나 (없으면 빈 Dictionary). 뉴스 {date, kind, text}
static func school_event(state: Dictionary, roster: Array, rng: Rng) -> Dictionary:
	var m := Cal.month_of(state["date"])
	var pool := []
	var w := []
	for e in data()["schoolEvents"]:
		for x in e["months"]:
			if int(x) == m:
				pool.append(e)
				w.append(float(e["weight"]))
				break
	if pool.is_empty() or roster.is_empty():
		return {}
	var e: Dictionary = rng.weighted(pool, w)
	match e["key"]:
		"sportsDay":
			for p in roster:
				if rng.chance(0.6):
					p["cond"] = clampi(int(p["cond"]) + 1, -2, 2)
				p["fatigue"] = clampf(p["fatigue"] + 5, 0, 100)
		"festival":
			state["reputation"] = clampi(int(state["reputation"]) + 1, 0, 100)
		"exam":
			for p in roster:
				p["fatigue"] = clampf(p["fatigue"] - 15, 0, 100)
		"volunteer":
			state["reputation"] = clampi(int(state["reputation"]) + 2, 0, 100)
		"snow":
			for p in roster:
				if rng.chance(0.5):
					p["cond"] = clampi(int(p["cond"]) + 1, -2, 2)
		"obGame":
			for i in 3:
				var p: Dictionary = rng.pick(roster)
				var fs := Training.focus_stats(p)
				for k in fs:
					Training.apply_exp(p, k, 5.0 * fs[k], Training.growth_mult(p, k, state["pros"]), rng)
	# 학교 행사는 팀 분위기도 조금 올린다 (기말고사 제외)
	if e["key"] != "exam":
		TeamMood.change(state, 2)
	return {"date": state["date"], "kind": "good", "text": e["text"]}
