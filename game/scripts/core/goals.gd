class_name Goals
extends RefCounted
## 후원회 연간 목표 (web/src/core/goals.ts 이식, 원본 데이터 data/goals.json)
##  - 매년 시즌 시작에 명성에 맞춰 3개. 달성 즉시 포인트·명성 보상
##  - 진행 상황은 경기 결과·리그 종료·전국대회 성적·드래프트에서 갱신

const RANK_KINDS := ["leagueRank", "nationalBest"]
const PLACING_RANK := {"우승": 1, "준우승": 2, "4강": 4, "8강": 8, "16강": 16}


static func data() -> Dictionary:
	return GameData.load_json("goals")


## 전국대회 성적 → 순위 숫자 (우승 1, 준우승 2, 4강 4, 8강 8, 16강 16, 그 밖 99)
static func placing_rank(r: String) -> int:
	return int(PLACING_RANK.get(r, 99))


static func text(g: Dictionary) -> String:
	var t: String = data()["kinds"][g["kind"]]
	var n: int = g["target"]
	return t.replace("{n}", str(n)).replace("{r}", "우승" if n <= 1 else ("결승" if n == 2 else "%d강" % n))


static func progress_text(g: Dictionary) -> String:
	if g["done"]:
		return "달성"
	var pr: int = g["progress"]
	if g["kind"] in RANK_KINDS:
		if pr == 0:
			return "-"
		if g["kind"] == "leagueRank":
			return "최고 %d위" % pr
		return "초반 탈락" if pr >= 99 else "최고 %d강" % pr
	return "%d/%d" % [pr, g["target"]]


## 올해 목표 정하기
static func set_goals(state: Dictionary) -> void:
	var tier: Dictionary = data()["tiers"][0]
	for t in data()["tiers"]:
		if state["reputation"] >= int(t["minRep"]):
			tier = t
	var list := []
	for g in tier["goals"]:
		list.append({"kind": g["kind"], "target": int(g["target"]), "progress": 0, "done": false})
	state["goals"] = {"year": state["year"], "tier": tier["name"], "points": int(tier["points"]), "rep": int(tier["rep"]), "list": list}
	state["news"].append({"date": state["date"], "kind": "info", "text": "후원회 올해 목표(%s): %s" % [tier["name"], " · ".join(list.map(func(x): return text(x)))]})


## 목표 진행 갱신. 누적형은 value 만큼 더하고, 순위형은 더 좋은(작은) 순위를 기록한다. 달성하면 보상·팝업
static func event(state: Dictionary, kind: String, value: int) -> void:
	var gs = state.get("goals")
	if gs == null:
		return
	for g in gs["list"]:
		if g["kind"] != kind or g["done"]:
			continue
		var rank_kind: bool = kind in RANK_KINDS
		if rank_kind:
			g["progress"] = mini(int(g["progress"]), value) if int(g["progress"]) > 0 else value
		else:
			g["progress"] = int(g["progress"]) + value
		var ok: bool = int(g["progress"]) <= int(g["target"]) if rank_kind else int(g["progress"]) >= int(g["target"])
		if not ok:
			continue
		g["done"] = true
		state["points"] = Shop.points(state) + int(gs["points"])
		state["reputation"] = clampi(int(state["reputation"]) + int(gs["rep"]), 0, 100)
		var all := true
		for x in gs["list"]:
			all = all and x["done"]
		state["news"].append({"date": state["date"], "kind": "good", "text": "후원회 목표 달성: %s +%dP" % [text(g), gs["points"]]})
		state["popups"].append({"kind": "good", "title": "후원회 목표 달성!",
			"body": "「%s」 달성!\n후원회에서 격려금을 보내왔다. (+%dP, 명성 +%d)%s" % [text(g), gs["points"], gs["rep"], "\n\n올해 목표를 모두 이뤘다!" if all else ""]})


## 시즌 끝: 달성 수 반환하고 소식 남기기
static func close_goals(state: Dictionary) -> int:
	var gs = state.get("goals")
	if gs == null:
		return 0
	var n := 0
	for g in gs["list"]:
		if g["done"]:
			n += 1
	state["news"].append({"date": state["date"], "kind": "good" if n > 0 else "info", "text": "%d 후원회 목표 %d/%d 달성" % [gs["year"], n, gs["list"].size()]})
	return n
