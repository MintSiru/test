class_name Manager
extends RefCounted
## 감독 성장 (Godot 전용, data/manager.json)
##  경기·대회 성적·드래프트로 경험치 → 레벨이 오르면 특기 하나 선택 (선택 팝업, 기본값을 먼저 적용해 두고 바꾸면 교체)
##  특기: 훈련 전문가(훈련 효과) · 분위기 메이커 · 스카우트 인맥 · 살림꾼(포인트) · 작전가(작전 성공 확률)


static func data() -> Dictionary:
	return GameData.load_json("manager")


static func info(state: Dictionary) -> Dictionary:
	if state.get("manager") == null:
		state["manager"] = {"exp": 0, "level": 1, "perks": {}}
	return state["manager"]


static func perk(state: Dictionary, key: String) -> int:
	var m = state.get("manager")
	return 0 if m == null else int(m["perks"].get(key, 0))


## 특기 효과 합계 (value × 겹친 수)
static func bonus(state: Dictionary, key: String) -> float:
	var n := perk(state, key)
	if n == 0:
		return 0.0
	for p in data()["perks"]:
		if p["key"] == key:
			return float(p["value"]) * n
	return 0.0


static func perk_def(key: String) -> Dictionary:
	for p in data()["perks"]:
		if p["key"] == key:
			return p
	return {}


## 다음 레벨까지 필요한 경험치 (최고 레벨이면 -1)
static func next_exp(state: Dictionary) -> int:
	var lv: Array = data()["levels"]
	var level := int(info(state)["level"])
	return -1 if level >= lv.size() else int(lv[level])


static func add_exp(state: Dictionary, n: int) -> void:
	if n <= 0:
		return
	var m := info(state)
	m["exp"] = int(m["exp"]) + n
	while next_exp(state) >= 0 and int(m["exp"]) >= next_exp(state):
		m["level"] = int(m["level"]) + 1
		_level_up(state)


static func exp_for_match(state: Dictionary, won: bool, drew: bool, official: bool) -> void:
	if not official:
		return
	var e: Dictionary = data()["exp"]
	add_exp(state, int(e["win"] if won else (e["draw"] if drew else e["loss"])))


static func _available(state: Dictionary) -> Array:
	return data()["perks"].filter(func(p): return perk(state, p["key"]) < int(p["max"]))


static func _level_up(state: Dictionary) -> void:
	var m := info(state)
	var opts := []
	var lines := []
	var avail := _available(state)
	if avail.is_empty():
		state["news"].append({"date": state["date"], "kind": "good", "text": "감독 레벨 %d! (특기를 모두 익혔다)" % m["level"]})
		return
	# 기본값을 먼저 적용해 두고, 고르면 바꾼다
	var def_key: String = data()["default"]
	if perk(state, def_key) >= int(perk_def(def_key)["max"]):
		def_key = avail[0]["key"]
	m["perks"][def_key] = perk(state, def_key) + 1
	if m.get("defaults") == null:
		m["defaults"] = {}
	var lv := str(m["level"])
	m["defaults"][lv] = def_key
	for p in avail:
		opts.append([lv + ":" + p["key"], "%s (%d/%d)" % [p["name"], perk(state, p["key"]) - (1 if p["key"] == def_key else 0), p["max"]]])
		lines.append("· %s — %s" % [p["name"], p["desc"]])
	state["news"].append({"date": state["date"], "kind": "good", "text": "감독 레벨 %d 달성!" % m["level"]})
	state["popups"].append({"kind": "choice", "choice": "managerPerk", "title": "감독 레벨 %d!" % m["level"], "options": opts,
		"body": "경험이 쌓여 감독으로서 한 단계 성장했다. 익힐 특기를 하나 고르자.\n\n%s" % "\n".join(lines)})


## 선택 key = "레벨:특기". 그 레벨에서 미리 적용한 기본 특기를 고른 특기로 바꾼다
static func choose_perk(state: Dictionary, choice_key: String) -> String:
	var m := info(state)
	var parts := choice_key.split(":")
	if parts.size() != 2:
		return ""
	var key: String = parts[1]
	var d := perk_def(key)
	if d.is_empty():
		return ""
	var defaults: Dictionary = m.get("defaults", {})
	var last: String = defaults.get(parts[0], "")
	defaults.erase(parts[0])
	if last != "" and last != key and perk(state, key) < int(d["max"]):
		m["perks"][last] = perk(state, last) - 1
		if int(m["perks"][last]) <= 0:
			m["perks"].erase(last)
		m["perks"][key] = perk(state, key) + 1
	return "특기 「%s」 (%d/%d)\n%s" % [d["name"], perk(state, key), d["max"], d["desc"]]


static func summary(state: Dictionary) -> String:
	var m := info(state)
	var parts := []
	for p in data()["perks"]:
		var n := perk(state, p["key"])
		if n > 0:
			parts.append("%s %d" % [p["name"], n])
	var nx := next_exp(state)
	return "감독 Lv%d (경험 %d%s)%s" % [m["level"], m["exp"], ("/%d" % nx) if nx >= 0 else "", ("\n특기: " + ", ".join(parts)) if not parts.is_empty() else ""]
