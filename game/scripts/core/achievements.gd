class_name Achievements
extends RefCounted
## 업적·특수능력 수집 (Godot 전용, data/achievements.json)
##  - state.achievements = {key: 달성 날짜}. 달성하면 포인트 보상 + 소식 + 팝업
##  - state.seenAbilities = {id: true}: 우리 팀 선수에게 나타난 적 있는 특수능력 (수집률)


static func data() -> Dictionary:
	return GameData.load_json("achievements")


static func done(state: Dictionary, key: String) -> bool:
	var a = state.get("achievements")
	return a != null and a.has(key)


static func def_of(key: String) -> Dictionary:
	for a in data()["list"]:
		if a["key"] == key:
			return a
	return {}


## 사건형 업적 달성
static func event(state: Dictionary, key: String) -> void:
	if done(state, key):
		return
	var d := def_of(key)
	if d.is_empty():
		return
	if state.get("achievements") == null:
		state["achievements"] = {}
	state["achievements"][key] = state["date"]
	var pts := int(d["points"])
	state["points"] = Shop.points(state) + pts
	state["news"].append({"date": state["date"], "kind": "good", "text": "업적 달성: 「%s」 +%dP" % [d["name"], pts]})
	state["popups"].append({"kind": "good", "title": "업적 달성!", "body": "「%s」\n%s\n\n(+%dP)" % [d["name"], d["desc"], pts]})


## 상태형 업적 판정 + 특수능력 수집 (우리 경기 뒤·매주)
static func check(state: Dictionary) -> void:
	if state.get("seenAbilities") == null:
		state["seenAbilities"] = {}
	var seen: Dictionary = state["seenAbilities"]
	var has_gold := false
	for p in WorldGen.team_players(state, state["userTeamId"]):
		for a in p["abilities"]:
			seen[a] = true
			if Abilities.tier(a) == "gold":
				has_gold = true
	if int(state.get("streak", 0)) >= 5:
		event(state, "streak5")
	var rid = state.get("rivalId")
	if rid != null and int(Rival.h2h_of(state, rid)["w"]) >= 5:
		event(state, "rival5")
	if has_gold:
		event(state, "gold")
	if seen.size() >= 30:
		event(state, "catalog30")
	if seen.size() >= 60:
		event(state, "catalog60")
	var lv := int(Manager.info(state)["level"])
	if lv >= 5:
		event(state, "manager5")
	if lv >= 10:
		event(state, "manager10")
	if TeamMood.mood(state) >= 90:
		event(state, "mood90")
	for f in Shop.facilities():
		if Shop.level(state, f["key"]) >= f["costs"].size():
			event(state, "facilityMax")
	if Shop.points(state) >= 1000:
		event(state, "points1000")
	if int(state["reputation"]) >= 80:
		event(state, "rep80")


static func count(state: Dictionary) -> int:
	var a = state.get("achievements")
	return 0 if a == null else a.size()


static func seen_count(state: Dictionary) -> int:
	var s = state.get("seenAbilities")
	return 0 if s == null else s.size()
