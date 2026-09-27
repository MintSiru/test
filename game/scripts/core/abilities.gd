class_name Abilities
extends RefCounted
## 특수능력 규칙 (web/src/core/abilities.ts 이식, 원본 데이터 data/abilities.json)
##  - tier: gold(금특·상위 능력) / good(긍정·파랑) / bad(부정·빨강)
##  - for: bat(타자) / pit(투수) / all(공통)
##  - 같은 group 안에서는 하나만 가진다 (good 을 얻으면 bad 가 사라지고, gold 는 good 을 대체)
##  - fx: 경기 효과 (when 조건 + 수치). 구현은 sim/match_engine.gd
##  - season: 훈련 성장(growth)·부상(injury)·피로 회복(recover)·컨디션 기복(mood)

## 조건 없이 항상 적용되는 수비·주루 효과
const FLAT_KEYS := ["fld", "arm", "err", "lead", "block", "steal", "run"]
const PIT_KEYS := {"velo": true, "ctl": true, "stuff": true, "ppFB": true, "ppBR": true, "whiff": true, "wild": true, "sta": true,
	"gbRate": true, "hrAllow": true, "hold": true, "zone": true, "mistake": true}
const RANK := {"bad": 0, "good": 1, "gold": 2}
## 발동 조건 → 정수 코드 (경기 엔진이 문자열 비교 없이 판정하도록)
const COND := {"always": 0, "risp": 1, "lateClose": 2, "late": 3, "early": 4, "twoStrikes": 5, "firstPitch": 6, "runnersOn": 7,
	"basesLoaded": 8, "leadoff": 9, "twoOuts": 10, "vsL": 11, "ahead": 12, "behindLate": 13}

static var _by_id := {}
static var _fx_cache := {}


static func all() -> Array:
	return GameData.abilities()


static func info(id: String) -> Dictionary:
	if _by_id.is_empty():
		for a in all():
			_by_id[a["id"]] = a
	return _by_id.get(id, {})


static func name_of(id: String) -> String:
	return info(id).get("name", id)


static func tier(id: String) -> String:
	return info(id).get("tier", "good")


static func is_bad(id: String) -> bool:
	return tier(id) == "bad"


static func conditions() -> Dictionary:
	return GameData.load_json("abilities")["conditions"]


## 이 선수(타자/투수, 포지션)가 가질 수 있는 능력인가
static func fits(a: Dictionary, p: Dictionary) -> bool:
	if a["for"] != "all" and (a["for"] == "pit") != (p["pos"] == "P"):
		return false
	if a.has("pos"):
		if p["pos"] in a["pos"]:
			return true
		for s in p["sub"]:
			if s in a["pos"]:
				return true
		return false
	return true


## 새로 익힐 수 없으면 이유, 익힐 수 있으면 ""
static func cannot_learn(p: Dictionary, id: String) -> String:
	var a := info(id)
	if a.is_empty():
		return "알 수 없는 능력"
	if a["for"] != "all" and (a["for"] == "pit") != (p["pos"] == "P"):
		return "투수 전용" if a["for"] == "pit" else "타자 전용"
	if id in p["abilities"]:
		return "이미 가지고 있음"
	for x in p["abilities"]:
		var o := info(x)
		if not o.is_empty() and o["group"] == a["group"] and RANK[o["tier"]] >= RANK[a["tier"]]:
			return "상위 능력을 가지고 있음" if o["tier"] == "gold" else "이미 가지고 있음"
	return ""


## 능력 습득: 같은 그룹의 다른 능력(부정 능력 포함)은 사라진다. 사라진 능력 id 목록
static func learn(p: Dictionary, id: String) -> Array:
	var a := info(id)
	if a.is_empty() or id in p["abilities"]:
		return []
	var removed := []
	var keep := []
	for x in p["abilities"]:
		if info(x).get("group", "") == a["group"]:
			removed.append(x)
		else:
			keep.append(x)
	keep.append(id)
	p["abilities"] = keep
	return removed


## 상위(금특) 능력. 없으면 ""
static func gold_of(id: String) -> String:
	return info(id).get("upgrade", "")


## 금특으로 진화할 수 있는 금특 id 목록
static func gold_targets(p: Dictionary) -> Array:
	var out := []
	for x in p["abilities"]:
		var g := gold_of(x)
		if g != "" and cannot_learn(p, g) == "":
			out.append(g)
	return out


## 시즌 효과 합계 (growth, injury, recover, mood)
static func season_fx(p: Dictionary, key: String) -> float:
	if p["abilities"].is_empty():
		return 0.0
	var v := 0.0
	for id in p["abilities"]:
		var s = info(id).get("season")
		if s != null:
			v += float(s.get(key, 0.0))
	return v


## 정렬: 금특 → 긍정 → 부정
static func sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b): return RANK[tier(a)] > RANK[tier(b)])
	return out


## 경기용으로 정리한 효과. 같은 조합은 캐시
##  {bat: {상시 합계}, bat_cond: [[조건 코드, {효과}]], pit: {상시 합계}, pit_cond: [...], flat: {fld, arm, ...}}
##  반환된 Dictionary 는 공유되므로 고치지 말 것
static func compile(ids: Array) -> Dictionary:
	var key := ",".join(ids)
	if _fx_cache.has(key):
		return _fx_cache[key]
	var flat := {}
	for k in FLAT_KEYS:
		flat[k] = 0.0
	var out := {"bat": {}, "bat_cond": [], "pit": {}, "pit_cond": [], "flat": flat}
	for id in ids:
		for fx in info(id).get("fx", []):
			var bat := {}
			var pit := {}
			for k in fx:
				if k == "when":
					continue
				var v: float = fx[k]
				if k in FLAT_KEYS:
					flat[k] += v
				elif PIT_KEYS.has(k):
					pit[k] = v
				else:
					bat[k] = v
			var c: String = fx.get("when", "always")
			for pair in [["bat", bat], ["pit", pit]]:
				var m: Dictionary = pair[1]
				if m.is_empty():
					continue
				if c == "always":
					var st: Dictionary = out[pair[0]]
					for k in m:
						st[k] = st.get(k, 0.0) + m[k]
				else:
					out[pair[0] + "_cond"].append([int(COND.get(c, -1)), m])
	_fx_cache[key] = out
	return out
