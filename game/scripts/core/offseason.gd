class_name Offseason
extends RefCounted
## 비시즌 콘텐츠 (Godot 전용, 데이터 data/offseason.json)
##  - 1월 동계 합숙 장소 선택 (비용·효과가 다른 세 곳)
##  - 9월 3학년 진로 상담: 예상 지명 결과를 보고 한 명에게 감독 추천서 (드래프트 점수 +)
##  - 10~2월 학교 행사 (주간 이벤트)
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
				return "포인트가 부족해 %s(으)로 대신했다." % d["name"]
			state["points"] = Shop.points(state) - int(o["cost"])
			state["trainingBonus"] = float(o["bonus"])
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
	return {"date": state["date"], "kind": "good", "text": e["text"]}
