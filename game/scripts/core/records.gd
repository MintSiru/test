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
		Manager.add_exp(state, int(Manager.data()["exp"]["title"]) * mine.size())
		Achievements.event(state, "title")
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


## 선수 성장 기록: 시즌 시작마다 우리 선수의 종합 능력치를 p.ovrHist = [[연도, 종합], ...] 에 (같은 해는 한 번)
static func snapshot_growth(state: Dictionary) -> void:
	var y := int(state["year"])
	for p in WorldGen.team_players(state, state["userTeamId"]):
		var h: Array = p.get("ovrHist", [])
		if h.is_empty() or int(h[h.size() - 1][0]) != y:
			h.append([y, PlayerUtil.overall(p)])
		p["ovrHist"] = h


## 올해 시작 때 대비 성장 (기록 없으면 0)
static func growth_this_year(state: Dictionary, p: Dictionary) -> int:
	var h: Array = p.get("ovrHist", [])
	for e in h:
		if int(e[0]) == int(state["year"]):
			return PlayerUtil.overall(p) - int(e[1])
	return 0


## 연말 결산 (은퇴식 직전, 3학년 기록이 남아 있을 때): 대회 성적·목표·성장 TOP3·팀 MVP·명장면
static func season_review(state: Dictionary) -> void:
	var y := int(state["year"])
	var lines := []
	var rec: Dictionary = WorldGen.user_team(state)["seasonRecord"]
	lines.append("공식전 %d승 %d패 %d무 · 명성 %d · 감독 Lv%d" % [rec["w"], rec["l"], rec["d"], state["reputation"], Manager.info(state)["level"]])
	for c in state["competitions"]:
		if int(c.get("year", y)) == y and c.get("userResult") != null:
			lines.append("· %s: %s" % [Cal.comp_def(c["key"])["short"], c["userResult"]])
	var gs = state.get("goals")
	if gs != null:
		var done: int = gs["list"].filter(func(g): return g["done"]).size()
		lines.append("후원회 목표 %d/%d 달성" % [done, gs["list"].size()])
	var roster := WorldGen.team_players(state, state["userTeamId"])
	var grow := roster.duplicate()
	grow.sort_custom(func(a, b): return growth_this_year(state, a) > growth_this_year(state, b))
	var gl := []
	for p in grow.slice(0, 3):
		if growth_this_year(state, p) > 0:
			gl.append("%s +%d" % [PlayerUtil.full_name(p), growth_this_year(state, p)])
	if not gl.is_empty():
		lines.append("")
		lines.append("가장 많이 성장: " + ", ".join(gl))
	# 팀 MVP: 타자는 (안타 + 홈런×2 + 타점 + 도루×0.5), 투수는 (아웃 ÷ 3 + 승×3 + 탈삼진×0.3 − 자책×1)
	var bat_mvp = null
	var bat_v := -1.0
	var pit_mvp = null
	var pit_v := -1.0
	for p in roster:
		var b: Dictionary = p["season"]["bat"]
		var bv := float(b["h"]) + float(b["hr"]) * 2.0 + float(b["rbi"]) + float(b["sb"]) * 0.5
		if bv > bat_v:
			bat_v = bv
			bat_mvp = p
		var pt: Dictionary = p["season"]["pit"]
		var pv := float(pt["outs"]) / 3.0 + float(pt["w"]) * 3.0 + float(pt["so"]) * 0.3 - float(pt["er"])
		if int(pt["outs"]) > 0 and pv > pit_v:
			pit_v = pv
			pit_mvp = p
	if bat_mvp != null and bat_v > 0:
		var bb: Dictionary = bat_mvp["season"]["bat"]
		lines.append("타선 MVP: %s (타율 %s %d홈런 %d타점)" % [PlayerUtil.full_name(bat_mvp), PlayerUtil.avg_str(bb), bb["hr"], bb["rbi"]])
	if pit_mvp != null:
		var pp: Dictionary = pit_mvp["season"]["pit"]
		lines.append("마운드 MVP: %s (%d승 %d패 평균자책점 %s)" % [PlayerUtil.full_name(pit_mvp), pp["w"], pp["l"], PlayerUtil.era_str(pp)])
	var hl: Array = state.get("highlights", []).filter(func(h): return str(h["date"]).begins_with(str(y)))
	var tro: Array = state.get("trophies", []).filter(func(t): return int(t["year"]) == y)
	lines.append("")
	lines.append("명장면 %d개 · 업적 %d개 · 우승 %d회" % [hl.size(), Achievements.count(state), tro.size()])
	state["reviews"] = state.get("reviews", {})
	state["reviews"][str(y)] = lines
	state["popups"].append({"kind": "good", "title": "%d년 시즌 결산" % y, "body": "\n".join(lines)})


## 전국대회 우승 기록 + 우승 연출 팝업 (main.gd show_trophy)
static func add_trophy(state: Dictionary, def: Dictionary, opp_name: String, us: int, them: int, date: String) -> void:
	if state.get("trophies") == null:
		state["trophies"] = []
	var fin_score := "%d:%d" % [us, them]
	state["trophies"].append({"year": state["year"], "comp": def["short"], "name": def["name"], "opp": opp_name, "score": fin_score, "date": date})
	state["popups"].append({"kind": "trophy", "title": "%s 우승!" % def["short"], "sub": "결승 vs %s %s" % [opp_name, fin_score],
		"body": "%s, %s 우승!!\n전국에 이름을 떨쳤다. (명성 +%d)" % [WorldGen.user_team(state)["name"], def["name"], def["repWin"]]})


## 명장면 앨범: 우리 경기의 명장면을 state.highlights 에 (최근 60개)
const HIGHLIGHT_MAX := 60
const HIGHLIGHT_KO := {"walkoff": "끝내기", "hr": "홈런", "clutch": "승부처", "escape": "위기 탈출"}


static func add_highlights(state: Dictionary, comp: Dictionary, f: Dictionary, m: MatchEngine) -> void:
	if m.highlights.is_empty():
		return
	if state.get("highlights") == null:
		state["highlights"] = []
	var u: String = state["userTeamId"]
	var opp: String = state["teams"][f["away"] if f["home"] == u else f["home"]]["name"]
	var label: String = Cal.comp_def(comp["key"])["short"] if comp["kind"] != "friendly" else "연습 경기"
	for h in m.highlights:
		var rec := {"date": f["date"], "comp": label, "opp": opp, "inning": "%d회%s" % [h["inning"], "초" if h["top"] else "말"],
			"kind": h["kind"], "text": h["text"], "won": m.winner == u}
		if h.has("b"):
			rec["b"] = h["b"]
		state["highlights"].append(rec)
	var hl: Array = state["highlights"]
	if hl.size() > HIGHLIGHT_MAX:
		state["highlights"] = hl.slice(hl.size() - HIGHLIGHT_MAX)


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
