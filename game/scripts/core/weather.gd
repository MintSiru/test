class_name Weather
extends RefCounted
## 날씨 (web/src/core/weather.ts 이식). 날짜+시드 해시로 결정 → 웹과 같은 결과.
## 비가 오면 그날 경기는 다음 날로 연기 (같은 경기는 최대 2번, 그 뒤엔 강행)

const RAIN := {1: 0.05, 2: 0.05, 3: 0.08, 4: 0.1, 5: 0.1, 6: 0.2, 7: 0.28, 8: 0.18, 9: 0.1, 10: 0.07, 11: 0.07, 12: 0.05}


## FNV-1a 32bit (web 의 hashStr 과 동일)
static func hash_str(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h


static func on(seed_val: int, date: String) -> String:
	var h := hash_str("%d:%s" % [seed_val, date]) / 4294967296.0
	var rain: float = RAIN.get(Cal.month_of(date), 0.08)
	if h < rain:
		return "비"
	if h < rain + 0.07:
		return "가랑비"
	if h < rain + 0.3:
		return "흐림"
	return "맑음"


## 우천 연기. 연기한 경기가 있으면 true
static func postpone_rain(state: Dictionary, today: Array) -> bool:
	if today.is_empty() or on(int(state["seed"]), state["date"]) != "비":
		return false
	var moved := 0
	var user_moved := false
	var u: String = state["userTeamId"]
	for x in today:
		var f: Dictionary = x["f"]
		if int(f.get("postponed", 0)) >= 2:
			continue
		f["postponed"] = int(f.get("postponed", 0)) + 1
		f["date"] = Cal.add_days(f["date"], 1)
		moved += 1
		if f["home"] == u or f["away"] == u:
			user_moved = true
	if moved > 0:
		state["news"].append({"date": state["date"], "kind": "bad" if user_moved else "info",
			"text": "비로 오늘 경기 %d개가 내일로 연기됐다.%s" % [moved, " 우리 경기도 순연! 투수진이 하루 더 쉴 수 있다." if user_moved else ""]})
	return moved > 0
