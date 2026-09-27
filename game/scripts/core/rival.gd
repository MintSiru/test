class_name Rival
extends RefCounted
## 라이벌 학교 · 상대 전적 (web/src/core/rival.ts 이식)
##  - 시작 시 같은 권역에서 전통이 가장 강한 학교가 라이벌
##  - 한 시즌에 2번 이상 진 학교가 있으면 다음 시즌 새 라이벌
##  - 라이벌전: 우리 선수 컨디션 한 단계 상승(투지), 이기면 명성 +2


static func init_rival(state: Dictionary) -> void:
	var u: Dictionary = state["teams"][state["userTeamId"]]
	var best = null
	for t in state["teams"].values():
		if t["leagueGroup"] == u["leagueGroup"] and t["id"] != u["id"]:
			if best == null or t["prestige"] > best["prestige"]:
				best = t
	state["rivalId"] = best["id"] if best != null else null
	state["h2h"] = {}
	state["rivalLoss"] = {}


static func is_rival_game(state: Dictionary, f: Dictionary) -> bool:
	var r = state.get("rivalId")
	if r == null:
		return false
	var u: String = state["userTeamId"]
	return (f["home"] == u and f["away"] == r) or (f["away"] == u and f["home"] == r)


static func record(state: Dictionary, opp_id: String, winner) -> void:
	if state.get("h2h") == null:
		state["h2h"] = {}
	if state.get("rivalLoss") == null:
		state["rivalLoss"] = {}
	var h2h: Dictionary = state["h2h"]
	if not h2h.has(opp_id):
		h2h[opp_id] = {"w": 0, "l": 0, "d": 0}
	var rec: Dictionary = h2h[opp_id]
	if winner == null:
		rec["d"] += 1
	elif winner == state["userTeamId"]:
		rec["w"] += 1
	else:
		rec["l"] += 1
		state["rivalLoss"][opp_id] = int(state["rivalLoss"].get(opp_id, 0)) + 1
	if opp_id == state.get("rivalId"):
		var nm: String = state["teams"][opp_id]["name"]
		if winner == state["userTeamId"]:
			state["reputation"] = clampi(state["reputation"] + 2, 0, 100)
			state["news"].append({"date": state["date"], "kind": "good", "text": "라이벌 %s 격파! 교내가 들썩인다. (명성 +2)" % nm})
		elif winner != null:
			state["news"].append({"date": state["date"], "kind": "bad", "text": "라이벌 %s에게 졌다... 다음엔 반드시!" % nm})


static func season_update(state: Dictionary) -> void:
	var loss: Dictionary = state.get("rivalLoss", {}) if state.get("rivalLoss") != null else {}
	var best = null
	var bl := 1
	for id in loss:
		if int(loss[id]) > bl and state["teams"].has(id):
			bl = int(loss[id])
			best = id
	if best != null and best != state.get("rivalId"):
		state["rivalId"] = best
		state["popups"].append({"kind": "bad", "title": "새로운 라이벌", "body": "지난 시즌 %s에게 %d번이나 졌다.\n올해는 저 학교를 넘어서야 한다!" % [state["teams"][best]["name"], bl]})
	state["rivalLoss"] = {}


static func h2h_of(state: Dictionary, opp_id: String) -> Dictionary:
	var h = state.get("h2h")
	if h == null or not h.has(opp_id):
		return {"w": 0, "l": 0, "d": 0}
	return h[opp_id]


## 팀 시즌 기록 요약 (상대 분석용)
static func team_stats(state: Dictionary, team_id: String) -> Dictionary:
	var ab := 0
	var h := 0
	var hr := 0
	var sb := 0
	var outs := 0
	var er := 0
	for id in state["teams"][team_id]["playerIds"]:
		var p = state["players"].get(id)
		if p == null:
			continue
		var b: Dictionary = p["season"]["bat"]
		var pt: Dictionary = p["season"]["pit"]
		ab += int(b["ab"])
		h += int(b["h"])
		hr += int(b["hr"])
		sb += int(b["sb"])
		outs += int(pt["outs"])
		er += int(pt["er"])
	return {"avg": float(h) / ab if ab > 0 else 0.0, "hr": hr, "sb": sb, "era": er * 27.0 / outs if outs > 0 else 0.0}
