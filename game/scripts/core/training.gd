class_name Training
extends RefCounted
## 훈련 & 성장 (web/src/core/training.ts 이식)
## 매주 월요일 손패 5장 중 1장으로 팀 연습. 카드 숫자(1~5)가 클수록 효과가 크다.

const CARD_INFO := {
	"batting": {"name": "타격 연습", "desc": "컨택·파워·선구안", "fatigue": 7, "batter": {"contact": 0.45, "power": 0.4, "eye": 0.2}, "pitcher": {"contact": 0.1}},
	"pitching": {"name": "투구 연습", "desc": "구속·제구·변화구 (야수는 어깨)", "fatigue": 7, "batter": {"arm": 0.35}, "pitcher": {"velo": 0.3, "control": 0.4, "breaking": 0.3}},
	"defense": {"name": "수비 연습", "desc": "수비·어깨", "fatigue": 7, "batter": {"fielding": 0.55, "arm": 0.3}, "pitcher": {"control": 0.15, "fielding": 0.2}},
	"running": {"name": "주루 연습", "desc": "주력", "fatigue": 8, "batter": {"speed": 0.7}, "pitcher": {"stamina": 0.3}},
	"stamina": {"name": "체력 훈련", "desc": "스태미나·파워·주력", "fatigue": 11, "batter": {"power": 0.25, "speed": 0.2}, "pitcher": {"stamina": 0.6, "velo": 0.1}},
	"rest": {"name": "휴식", "desc": "피로 회복, 컨디션 상승", "fatigue": -35, "batter": {}, "pitcher": {}},
	"practiceGame": {"name": "연습 경기", "desc": "모든 능력 소폭 + 특수능력 각성", "fatigue": 9, "batter": {"contact": 0.2, "power": 0.15, "eye": 0.15, "fielding": 0.15, "speed": 0.1}, "pitcher": {"control": 0.2, "velo": 0.1, "breaking": 0.15, "stamina": 0.15}},
	"meeting": {"name": "작전 미팅", "desc": "선구안·제구 + 특수능력 습득", "fatigue": 2, "batter": {"eye": 0.35}, "pitcher": {"control": 0.3}},
	"scout": {"name": "스카우트 활동", "desc": "스카우트 행동력 +2", "fatigue": 3, "batter": {"contact": 0.1}, "pitcher": {"control": 0.1}},
	"special": {"name": "특별 훈련", "desc": "개인 연습 효과 2배, 부상 위험", "fatigue": 20, "batter": {}, "pitcher": {}},
}
## 카드에 표시할 짧은 설명
const CARD_SHORT := {"batting": "컨택\n파워", "pitching": "구속\n제구", "defense": "수비\n어깨", "running": "주력", "stamina": "체력", "rest": "피로\n회복", "practiceGame": "전체\n각성", "meeting": "선구\n제구", "scout": "행동력\n+2", "special": "개인\n×2"}
const DRAW_KINDS := ["batting", "pitching", "defense", "running", "stamina", "rest", "practiceGame", "meeting", "scout", "special"]
const DRAW_WEIGHTS := [16, 16, 14, 10, 10, 10, 8, 6, 6, 4]
const FOCUS_KO := {"auto": "자동", "contact": "컨택", "power": "파워", "eye": "선구안", "speed": "주력", "defense": "수비", "velo": "구속", "control": "제구", "breaking": "변화구", "stamina": "스태미나"}
const BATTER_FOCUS := ["auto", "contact", "power", "eye", "speed", "defense"]
const PITCHER_FOCUS := ["auto", "velo", "control", "breaking", "stamina"]


static func draw_card(rng: Rng, id: String) -> Dictionary:
	return {"id": id, "kind": rng.weighted(DRAW_KINDS, DRAW_WEIGHTS), "value": rng.weighted([1, 2, 3, 4, 5], [20, 30, 28, 15, 7])}


static func focus_stats(p: Dictionary) -> Dictionary:
	var f: String = p["focus"]
	if f == "auto":
		f = auto_focus(p)
	if f == "defense":
		return {"fielding": 0.6, "arm": 0.4}
	return {f: 1.0}


static func auto_focus(p: Dictionary) -> String:
	var opts := [["velo", "velo"], ["control", "control"], ["breaking", "breaking"], ["stamina", "stamina"]] if p["pos"] == "P" \
		else [["contact", "contact"], ["power", "power"], ["speed", "speed"], ["defense", "fielding"], ["eye", "eye"]]
	var best: String = opts[0][0]
	var bv := -INF
	for o in opts:
		var k: String = o[1]
		var cur := PlayerUtil.stat_value(p["r"], k)
		var cap: float = PlayerUtil.velo_score(p["cap"]["velo"]) if k == "velo" else p["cap"][k]
		var v := (cap - cur) - cur * 0.3
		if v > bv:
			bv = v
			best = o[0]
	return best


static func growth_mult(p: Dictionary, k: String, pros: Array) -> float:
	var m: float = (0.6 + p["talent"] * 0.18) * 0.9
	match p["personality"]:
		"노력파": m *= 1.15
		"천재": m *= 1.08
		"소심": m *= 0.95
	if p["fatigue"] > 70:
		m *= 0.7
	m *= 1.0 + p["cond"] * 0.05
	if p.get("idolId") != null:
		for pro in pros:
			if pro["id"] == p["idolId"]:
				if k in GameData.styles()[pro["style"]]["stats"]:
					m *= 1.4 if p["idolBond"] >= 50 else 1.25
				break
	return m


## 경험치 적용. 오른 수치 반환
static func apply_exp(p: Dictionary, k: String, pts: float, mult: float, rng: Rng) -> int:
	if pts <= 0:
		return 0
	var exp: Dictionary = p["exp"]
	exp[k] = exp.get(k, 0.0) + pts * mult
	var r: Dictionary = p["r"]
	var cap: Dictionary = p["cap"]
	var gained := 0
	for guard in 20:
		var e: float = exp[k]
		if k == "breaking":
			var br: Array = r["pitches"].filter(func(x): return x["type"] != "FB")
			var min_lv := 0
			if not br.is_empty():
				min_lv = 99
				for x in br:
					min_lv = mini(min_lv, int(x["lv"]))
			var cost := 10.0 + min_lv * 3
			if e < cost or PlayerUtil.breaking_score(r["pitches"]) >= cap["breaking"]:
				break
			exp[k] = e - cost
			if (br.size() < 2 or (br.size() < 4 and rng.chance(0.15))) and p["pos"] == "P":
				var pool := ["SL", "CB", "CH", "FK", "SI", "CT"].filter(func(t): return r["pitches"].all(func(x): return x["type"] != t))
				if not pool.is_empty():
					r["pitches"].append({"type": rng.pick(pool), "lv": 1})
			elif not br.is_empty():
				var target = null
				for x in br:
					if x["lv"] < 7 and (target == null or x["lv"] < target["lv"]):
						target = x
				if target != null:
					target["lv"] += 1
			gained += 1
			continue
		if k == "velo":
			if r["velo"] >= cap["velo"]:
				break
			var vcost := 4.0 + pow((r["velo"] - 110.0) / maxf(1.0, cap["velo"] - 110.0), 2) * 6.0
			if e < vcost:
				break
			exp[k] = e - vcost
			r["velo"] += 1
			gained += 1
			continue
		var cur: float = r[k]
		if cur >= cap[k]:
			break
		var c := 2.2 + pow(cur / maxf(1.0, cap[k]), 2) * 4.0
		if e < c:
			break
		exp[k] = e - c
		r[k] = cur + 1
		gained += 1
	if exp[k] > 40:
		exp[k] = 40.0
	return gained


## 한 주 훈련 적용. report: {gains, injuries, awakenings} (없으면 null)
static func train_player(p: Dictionary, card: Dictionary, pros: Array, rng: Rng, report = null, cpu := false, fac = null) -> void:
	var info: Dictionary = CARD_INFO[card["kind"]]
	var is_p: bool = p["pos"] == "P"
	var dist: Dictionary = info["pitcher"] if is_p else info["batter"]
	var gains := {}
	if p["injury"] > 0:
		p["fatigue"] = clampf(p["fatigue"] - 15, 0, 100)
		return
	for k in dist:
		var g := apply_exp(p, k, card["value"] * dist[k] * 1.1, growth_mult(p, k, pros) * Shop.growth(fac, k), rng)
		if g:
			gains[k] = gains.get(k, 0) + g
	var focus_mul := 1.0
	if card["kind"] == "special":
		focus_mul = 2.2 + card["value"] * 0.25
	elif card["kind"] == "rest":
		focus_mul = 0.2
	var fs := focus_stats(p)
	for k in fs:
		var g2 := apply_exp(p, k, 1.3 * fs[k] * focus_mul, growth_mult(p, k, pros) * Shop.growth(fac, k), rng)
		if g2:
			gains[k] = gains.get(k, 0) + g2
	var fat_mul: float = 1.0 if card["kind"] == "rest" else 0.6 + card["value"] * 0.12
	p["fatigue"] = clampf(p["fatigue"] + info["fatigue"] * fat_mul, 0, 100)
	if card["kind"] == "rest" and rng.chance(0.5 + card["value"] * 0.08):
		p["cond"] = clampi(p["cond"] + 1, -2, 2)
	var risk: float = (maxf(0.0, p["fatigue"] - 60) * 0.004 + (0.01 if card["kind"] == "special" else 0.0)) * (1.0 - 0.2 * Shop.level_of(fac, "ground"))
	if not cpu and rng.chance(risk):
		p["injury"] = rng.irange(5, 25)
		if report != null:
			report["injuries"].append(p["id"])
	var awaken_p := 0.0
	if card["kind"] == "practiceGame":
		awaken_p = 0.02 + card["value"] * 0.004
	elif card["kind"] == "meeting":
		awaken_p = 0.03 + card["value"] * 0.006
	if card["kind"] == "meeting":
		awaken_p *= 1.0 + 0.25 * Shop.level_of(fac, "analysis")
	if awaken_p > 0 and rng.chance(awaken_p * (0.6 + p["talent"] * 0.15)):
		var pool := GameData.abilities().filter(func(a): return a["good"] and a["forPitcher"] == is_p and not a["id"] in p["abilities"])
		if not pool.is_empty():
			var a: Dictionary = rng.pick(pool)
			p["abilities"].append(a["id"])
			if report != null:
				report["awakenings"].append({"playerId": p["id"], "ability": a["id"]})
	if report != null and not gains.is_empty():
		report["gains"][p["id"]] = gains


static func weekly_condition(p: Dictionary, rng: Rng) -> void:
	var vol := 0.45 if p["personality"] == "열혈" else (0.2 if p["personality"] == "냉정" else 0.32)
	if rng.chance(vol):
		p["cond"] = clampi(p["cond"] + (1 if rng.chance(0.5) else -1), -2, 2)
	elif p["cond"] != 0 and rng.chance(0.3):
		p["cond"] += -1 if p["cond"] > 0 else 1
