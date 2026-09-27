class_name Facilities
extends RefCounted
## 학교 시설과 예산 (web/src/core/facilities.ts 이식, 원본 데이터 data/facilities.json, 금액 단위 만원)


static func data() -> Dictionary:
	return GameData.load_json("facilities")


static func defs() -> Array:
	return data()["facilities"]


static func level(state: Dictionary, key: String) -> int:
	var f = state.get("facilities")
	if f == null:
		return 0
	return int(f.get(key, 0))


static func level_of(fac, key: String) -> int:
	if fac == null:
		return 0
	return int(fac.get(key, 0))


## 주간 훈련 성장 배율
static func growth(fac, k: String) -> float:
	if fac == null:
		return 1.0
	var m := 1.0
	for f in defs():
		if k in f["stats"]:
			m += f["growth"] * level_of(fac, f["key"])
	return m


static func upgrade_cost(state: Dictionary, key: String) -> int:
	for f in defs():
		if f["key"] == key:
			var lv := level(state, key)
			return -1 if lv >= f["costs"].size() else int(f["costs"][lv])
	return -1


static func upgrade(state: Dictionary, key: String) -> bool:
	var cost := upgrade_cost(state, key)
	if cost < 0 or int(state.get("budget", 0)) < cost:
		return false
	state["budget"] = int(state.get("budget", 0)) - cost
	if state.get("facilities") == null:
		state["facilities"] = {}
	state["facilities"][key] = level(state, key) + 1
	for f in defs():
		if f["key"] == key:
			state["news"].append({"date": state["date"], "kind": "good", "text": "%s Lv%d 완공! (-%d만원)" % [f["name"], state["facilities"][key], cost]})
	return true


static func monthly_income(state: Dictionary) -> void:
	var d := data()
	var amt := roundi(d["monthlyBase"] + state["reputation"] * d["monthlyPerReputation"])
	state["budget"] = int(state.get("budget", 0)) + amt
	state["news"].append({"date": state["date"], "kind": "info", "text": "후원회 지원금 +%d만원 (예산 %d만원)" % [amt, state["budget"]]})


static func add_prize(state: Dictionary, result: String, label: String) -> void:
	var amt := int(data()["prizes"].get(result, 0))
	if amt <= 0:
		return
	state["budget"] = int(state.get("budget", 0)) + amt
	state["news"].append({"date": state["date"], "kind": "good", "text": "%s %s 격려금 +%d만원" % [label, result, amt]})
