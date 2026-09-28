class_name Records
extends RefCounted
## 기록·명예의 전당 (Godot 전용)
##  - 시즌 개인 타이틀: 3학년 은퇴식(10월 말) 직전에 전국 선수 중 1위 (타격왕·홈런왕·타점왕·도루왕·다승왕·평균자책점왕·탈삼진왕)
##  - 학교 기록: 우리 학교 선수의 한 시즌 최고 기록 (갱신하면 소식)
##  - 명예의 전당: 졸업생의 고교 통산 성적·지명·프로 성적 (alumni 에 저장)

## better: high(클수록 좋음)/low, min: 규정 (타석 또는 아웃카운트)
const TITLES := [
	{"key": "avg", "name": "타격왕", "kind": "bat", "better": "high", "min": 40},
	{"key": "hr", "name": "홈런왕", "kind": "bat", "better": "high", "min": 1},
	{"key": "rbi", "name": "타점왕", "kind": "bat", "better": "high", "min": 1},
	{"key": "sb", "name": "도루왕", "kind": "bat", "better": "high", "min": 1},
	{"key": "w", "name": "다승왕", "kind": "pit", "better": "high", "min": 1},
	{"key": "era", "name": "평균자책점왕", "kind": "pit", "better": "low", "min": 60},
	{"key": "so", "name": "탈삼진왕", "kind": "pit", "better": "high", "min": 1},
]
const TITLE_POINTS := 30


## 규정을 채웠으면 값, 못 채웠으면 null
static func stat_value(line: Dictionary, t: Dictionary):
	match t["key"]:
		"avg":
			return float(line["h"]) / line["ab"] if int(line["pa"]) >= int(t["min"]) and int(line["ab"]) > 0 else null
		"era":
			return line["er"] * 27.0 / line["outs"] if int(line["outs"]) >= int(t["min"]) else null
	var v := float(line.get(t["key"], 0))
	return v if v >= float(t["min"]) else null


static func fmt(t: Dictionary, v: float) -> String:
	match t["key"]:
		"avg": return ("%.3f" % v).trim_prefix("0")
		"era": return "%.2f" % v
	return str(int(v))


static func _better(t: Dictionary, a: float, b: float) -> bool:
	return a > b if t["better"] == "high" else a < b


## 올해 전국 개인 타이틀 [{key, title, playerId, name, teamId, school, value}]
static func season_titles(state: Dictionary) -> Array:
	var out := []
	for t in TITLES:
		var best = null
		var best_v := 0.0
		for p in state["players"].values():
			if p["teamId"] == "":
				continue
			var v = stat_value(p["season"][t["kind"]], t)
			if v == null:
				continue
			if best == null or _better(t, v, best_v):
				best = p
				best_v = v
		if best != null:
			out.append({"key": t["key"], "title": t["name"], "playerId": best["id"], "name": PlayerUtil.full_name(best),
				"teamId": best["teamId"], "school": state["teams"][best["teamId"]]["name"], "value": fmt(t, best_v)})
	return out


## 시즌 결산 (은퇴식 직전): 타이틀 기록·보상, 학교 기록 갱신
static func season_end(state: Dictionary) -> void:
	var year := str(state["year"])
	var titles := season_titles(state)
	if state.get("titles") == null:
		state["titles"] = {}
	state["titles"][year] = titles
	var mine := titles.filter(func(x): return x["teamId"] == state["userTeamId"])
	if not mine.is_empty():
		var lines := []
		for x in mine:
			lines.append("%s — %s (%s)" % [x["title"], x["name"], x["value"]])
			var p = state["players"].get(x["playerId"])
			if p != null:
				if p.get("titles") == null:
					p["titles"] = []
				p["titles"].append("%s %s" % [year, x["title"]])
		state["points"] = Shop.points(state) + TITLE_POINTS * mine.size()
		state["reputation"] = clampi(int(state["reputation"]) + mine.size(), 0, 100)
		state["popups"].append({"kind": "good", "title": "개인 타이틀 수상!",
			"body": "올 시즌 전국 개인 타이틀을 우리 선수가 차지했다!\n\n%s\n\n(+%dP, 명성 +%d)" % ["\n".join(lines), TITLE_POINTS * mine.size(), mine.size()]})
	_update_school_records(state)


## 학교 기록: 우리 선수의 한 시즌 최고 기록 {key: {value, name, year}}
static func _update_school_records(state: Dictionary) -> void:
	if state.get("schoolRecords") == null:
		state["schoolRecords"] = {}
	var recs: Dictionary = state["schoolRecords"]
	var news := []
	for t in TITLES:
		for p in WorldGen.team_players(state, state["userTeamId"]):
			var v = stat_value(p["season"][t["kind"]], t)
			if v == null:
				continue
			var cur = recs.get(t["key"])
			if cur == null or _better(t, v, float(cur["raw"])):
				var first: bool = cur == null
				recs[t["key"]] = {"raw": v, "value": fmt(t, v), "name": PlayerUtil.full_name(p), "year": state["year"]}
				if not first:
					news.append("%s %s" % [t["name"].replace("왕", ""), fmt(t, v)])
	for n in news:
		state["news"].append({"date": state["date"], "kind": "good", "text": "학교 신기록! 한 시즌 %s" % n})


## 졸업생 고교 통산 요약 (명예의 전당)
static func career_summary(p: Dictionary) -> Dictionary:
	var b: Dictionary = p["career"]["bat"]
	var pt: Dictionary = p["career"]["pit"]
	var out := {"bat": "타율 %s %d홈런 %d타점 %d도루" % [PlayerUtil.avg_str(b), b["hr"], b["rbi"], b["sb"]]}
	if int(pt["outs"]) > 0:
		out["pit"] = "%d승 %d패 ERA %s %d탈삼진 (%s이닝)" % [pt["w"], pt["l"], PlayerUtil.era_str(pt), pt["so"], PlayerUtil.ip_str(pt["outs"])]
	out["talent"] = int(p["talent"])
	out["gold"] = p["abilities"].filter(func(a): return Abilities.tier(a) == "gold")
	out["titles"] = p.get("titles", [])
	return out


## 졸업생의 프로 선수 기록 (드래프트 때 만든 프로 명단 항목). 없으면 빈 Dictionary
static func pro_of(state: Dictionary, al: Dictionary) -> Dictionary:
	if al.get("draft") == null:
		return {}
	for pro in state["pros"]:
		if pro.get("alumniOf") == state["userTeamId"] and pro["sur"] + pro["given"] == al["name"] and int(pro["birthYear"]) == int(al["gradYear"]) - 18:
			return pro
	return {}
