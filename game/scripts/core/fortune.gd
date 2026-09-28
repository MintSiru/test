class_name Fortune
extends RefCounted
## CPU 학교 흥망 (Godot 전용). 매 시즌 시작(3월)에:
##  - 신흥 강호: 전통이 낮은 학교 1~2곳에 신임 감독·후원사 → 전통 크게 상승, 시설 +1
##  - 명문 몰락: 전통 상위 15개 학교 중 한 곳(해마다 60%)이 감독 교체·주축 이탈 → 전통 하락, 시설 -1
##  - 시설 투자: 지난 시즌 성적 상위 학교는 절반 확률로 시설 +1
## 전통(prestige)은 신입생 품질을, 시설(facLevel 0~2)은 CPU 주간 훈련 성장을 올린다.

const MAX_FAC := 2
const RISE_STORIES := ["신임 감독 부임 후 전력이 급상승했다", "지역 기업의 후원으로 새 실내 연습장을 지었다", "중학 유망주들이 대거 입학했다", "프로 출신 코치진을 영입했다"]
const FALL_STORIES := ["감독 교체로 팀이 흔들리고 있다", "주축 선수들의 전학·부상이 겹쳤다", "야구부 예산이 크게 줄었다"]


## CPU 팀의 시설 (Shop.growth 에 넘기는 형식, 모든 시설이 같은 단계)
static var _fac_cache := {}


static func cpu_fac(t: Dictionary):
	var lv := int(t.get("facLevel", 0))
	if lv <= 0:
		return null
	if not _fac_cache.has(lv):
		var d := {}
		for f in Shop.facilities():
			d[f["key"]] = lv
		_fac_cache[lv] = d
	return _fac_cache[lv]


## 새 시즌 시작 (지난 시즌 성적이 지워지기 전에 부른다)
static func season_start(state: Dictionary, rng: Rng) -> void:
	var cpu: Array = state["teams"].values().filter(func(t): return not t["isUser"])
	if cpu.is_empty():
		return
	# 시설 투자: 지난 시즌 성적(시즌 포인트) 상위 15%
	var by_pts: Array = cpu.duplicate()
	by_pts.sort_custom(func(a, b): return int(a["seasonPoints"]) > int(b["seasonPoints"]))
	for t in by_pts.slice(0, maxi(1, by_pts.size() * 15 / 100)):
		if rng.chance(0.5) and int(t.get("facLevel", 0)) < MAX_FAC:
			t["facLevel"] = int(t.get("facLevel", 0)) + 1
	# 신흥 강호
	var low: Array = cpu.filter(func(t): return int(t["prestige"]) < 45)
	for i in (2 if rng.chance(0.5) else 1):
		if low.is_empty():
			break
		var t: Dictionary = rng.pick(low)
		low.erase(t)
		var up := rng.irange(15, 22)
		t["prestige"] = clampi(int(t["prestige"]) + up, 10, 95)
		t["facLevel"] = mini(MAX_FAC, int(t.get("facLevel", 0)) + 1)
		_story(state, t, rng.pick(RISE_STORIES), "신흥 강호", "good")
	# 명문 몰락: 전통 상위 15개 학교 중 한 곳
	if rng.chance(0.6):
		var high: Array = cpu.duplicate()
		high.sort_custom(func(a, b): return int(a["prestige"]) > int(b["prestige"]))
		high = high.slice(0, 15)
		if not high.is_empty():
			var t: Dictionary = rng.pick(high)
			t["prestige"] = clampi(int(t["prestige"]) - rng.irange(12, 18), 10, 95)
			t["facLevel"] = maxi(0, int(t.get("facLevel", 0)) - 1)
			_story(state, t, rng.pick(FALL_STORIES), "명문의 위기", "bad")


static func _story(state: Dictionary, t: Dictionary, text: String, tag: String, kind: String) -> void:
	t["story"] = {"year": state["year"], "tag": tag, "text": text}
	var same_group: bool = t["leagueGroup"] == state["teams"][state["userTeamId"]]["leagueGroup"]
	state["news"].append({"date": state["date"], "kind": kind if same_group else "info",
		"text": "[고교야구] %s(%s) — %s%s" % [t["name"], t["province"], text, " (같은 권역!)" if same_group else ""]})
