class_name Lineup
extends RefCounted
## 자동 편성: 수비 위치 → 지명타자 → 타순. (한국 고교야구는 지명타자 제도 사용)

const FILL_ORDER := ["C", "SS", "CF", "2B", "3B", "RF", "LF", "1B"]


static func slot_value(p: Dictionary, pos: String) -> float:
	var apt := PlayerUtil.pos_aptitude(p, pos)
	var d: float = (p["r"]["fielding"] * 0.6 + p["r"]["arm"] * 0.4) * apt
	var w := 0.45 if pos in ["C", "SS"] else (0.35 if pos in ["2B", "CF"] else 0.2)
	return PlayerUtil.bat_value(p["r"]) * (1.0 - w) + d * w - (30.0 if apt < 0.6 else 0.0)


static func available(p: Dictionary) -> bool:
	return p["injury"] <= 0


static func can_pitch_on(p: Dictionary, date: String) -> bool:
	return p["injury"] <= 0 and (not p.has("restUntil") or p["restUntil"] == null or str(p["restUntil"]) <= date)


## [{playerId, pos}] × 9
static func auto_lineup(players: Array, exclude_ids: Array = []) -> Array:
	var pool := players.filter(func(p): return available(p) and not p["id"] in exclude_ids)
	var fielders := pool.filter(func(p): return p["pos"] != "P")
	var chosen := []
	var used := {}
	for pos in FILL_ORDER:
		var best = null
		var bv := -INF
		for p in fielders:
			if used.has(p["id"]):
				continue
			var v := slot_value(p, pos)
			if v > bv:
				bv = v
				best = p
		if best == null:
			for p in pool:
				if not used.has(p["id"]):
					best = p
					break
		if best != null:
			chosen.append({"p": best, "pos": pos})
			used[best["id"]] = true
	var rest := pool.filter(func(p): return not used.has(p["id"]))
	rest.sort_custom(func(a, b): return PlayerUtil.bat_value(a["r"]) > PlayerUtil.bat_value(b["r"]))
	if not rest.is_empty():
		# 지명타자: 남은 야수 우선 (야수가 없을 때만 투수)
		var dh = rest[0]
		for p in rest:
			if p["pos"] != "P":
				dh = p
				break
		chosen.append({"p": dh, "pos": "DH"})
	var ordered := batting_order(chosen)
	return ordered.map(func(x): return {"playerId": x["p"]["id"], "pos": x["pos"]})


## 1번 출루·주력, 2번 컨택, 3번 최고 타자, 4번 파워, 5번, 나머지 타격순
static func batting_order(nine: Array) -> Array:
	var rest := nine.duplicate()
	var bv := func(x): return PlayerUtil.bat_value(x["p"]["r"])
	var cleanup := nine.duplicate()
	cleanup.sort_custom(func(a, b): return bv.call(a) > bv.call(b))
	cleanup = cleanup.slice(0, 3)
	var no3 = cleanup[0] if cleanup.size() > 0 else null
	var others := cleanup.filter(func(c): return c != no3)
	others.sort_custom(func(a, b): return a["p"]["r"]["power"] > b["p"]["r"]["power"])
	var no4 = others[0] if others.size() > 0 else null
	var no5 = others[1] if others.size() > 1 else null
	for c in [no3, no4, no5]:
		if c != null:
			rest.erase(c)
	var take := func(score: Callable):
		if rest.is_empty():
			return null
		rest.sort_custom(func(a, b): return score.call(a["p"]) > score.call(b["p"]))
		return rest.pop_front()
	var no1 = take.call(func(p): return p["r"]["speed"] * 0.5 + p["r"]["eye"] * 0.3 + p["r"]["contact"] * 0.4)
	var no2 = take.call(func(p): return p["r"]["contact"] * 0.7 + p["r"]["speed"] * 0.2)
	var tail := []
	while true:
		var t = take.call(func(p): return PlayerUtil.bat_value(p["r"]))
		if t == null:
			break
		tail.append(t)
	var out := []
	for x in [no1, no2, no3, no4, no5]:
		if x != null:
			out.append(x)
	out.append_array(tail)
	return out


static func starter_score(p: Dictionary) -> float:
	return PlayerUtil.pitcher_overall(p["r"]) + p["r"]["stamina"] * 0.2 - p["fatigue"] * 0.2


## 선발 투수: 휴식 규정을 지킨 투수 중 최고 (로테이션 우선)
static func pick_starter(players: Array, date: String, rotation: Array = []):
	var ok := players.filter(func(p): return p["pos"] == "P" and can_pitch_on(p, date))
	for id in rotation:
		for p in ok:
			if p["id"] == id:
				return p
	ok.sort_custom(func(a, b): return starter_score(a) > starter_score(b))
	if not ok.is_empty():
		return ok[0]
	var any := players.filter(func(p): return can_pitch_on(p, date))
	any.sort_custom(func(a, b): return a["r"]["arm"] > b["r"]["arm"])
	return any[0] if not any.is_empty() else (players[0] if not players.is_empty() else null)
