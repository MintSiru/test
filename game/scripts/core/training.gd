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
	var m := growth_base(p)
	if p.get("idolId") != null and k in _idol_stats(pros, p["idolId"]):
		m *= 1.4 if p["idolBond"] >= 50 else 1.25
	return m


## 능력치와 상관없는 성장 배율 (재능·성격·피로·컨디션·특수능력). 한 선수의 여러 능력치에 같이 쓴다
static func growth_base(p: Dictionary) -> float:
	var m: float = (0.6 + p["talent"] * 0.18) * 0.9
	match p["personality"]:
		"노력파": m *= 1.15
		"천재": m *= 1.08
		"소심": m *= 0.95
	if p["fatigue"] > 70:
		m *= 0.7
	m *= 1.0 + p["cond"] * 0.05
	m *= 1.0 + Abilities.season_fx(p, "growth")
	return m


## 프로 선수 id → 동경 보너스 능력치 목록 (주간 훈련 때 전국 선수마다 명단을 훑지 않도록 색인)
static var _pro_src: Array = []
static var _pro_n := -1
static var _pro_idx := {}


static func _idol_stats(pros: Array, idol_id) -> Array:
	if not is_same(_pro_src, pros) or _pro_n != pros.size():
		_pro_src = pros
		_pro_n = pros.size()
		_pro_idx = {}
		var styles := GameData.styles()
		for pro in pros:
			_pro_idx[pro["id"]] = styles[pro["style"]]["stats"]
	return _pro_idx.get(idol_id, [])


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
const PIT_STATS := ["velo", "control", "breaking", "stamina"]


static func train_player(p: Dictionary, card: Dictionary, pros: Array, rng: Rng, report = null, cpu := false, fac = null) -> void:
	var info: Dictionary = CARD_INFO[card["kind"]]
	var is_p: bool = p["pos"] == "P"
	var dist: Dictionary = info["pitcher"] if is_p else info["batter"]
	var gains := {}
	if p["injury"] > 0:
		p["fatigue"] = clampf(p["fatigue"] - 15, 0, 100)
		return
	var base := growth_base(p)
	# 감독 특기 「투수 코치」: 투수 능력치 성장 배율 (card.pitMult, 우리 팀만)
	var pit_mult: float = float(card.get("pitMult", 1.0)) if is_p else 1.0
	var idol_stats: Array = _idol_stats(pros, p["idolId"]) if p.get("idolId") != null else []
	var idol_mul: float = 1.4 if p["idolBond"] >= 50 else 1.25
	for k in dist:
		var g := apply_exp(p, k, card["value"] * dist[k] * 1.1, base * (idol_mul if k in idol_stats else 1.0) * Shop.growth(fac, k) * (pit_mult if k in PIT_STATS else 1.0), rng)
		if g:
			gains[k] = gains.get(k, 0) + g
	var focus_mul := 1.0
	if card["kind"] == "special":
		focus_mul = 2.2 + card["value"] * 0.25
	elif card["kind"] == "rest":
		focus_mul = 0.2
	var fs := focus_stats(p)
	for k in fs:
		var g2 := apply_exp(p, k, 1.3 * fs[k] * focus_mul, base * (idol_mul if k in idol_stats else 1.0) * Shop.growth(fac, k) * (pit_mult if k in PIT_STATS else 1.0), rng)
		if g2:
			gains[k] = gains.get(k, 0) + g2
	var fat_mul: float = 1.0 + Abilities.season_fx(p, "recover") if card["kind"] == "rest" else 0.6 + card["value"] * 0.12
	p["fatigue"] = clampf(p["fatigue"] + info["fatigue"] * fat_mul, 0, 100)
	if card["kind"] == "rest" and rng.chance(0.5 + card["value"] * 0.08):
		p["cond"] = clampi(p["cond"] + 1, -2, 2)
	var risk: float = (maxf(0.0, p["fatigue"] - 60) * 0.004 + (0.01 if card["kind"] == "special" else 0.0)) * (1.0 - 0.2 * Shop.level_of(fac, "ground")) * maxf(0.0, 1.0 + Abilities.season_fx(p, "injury"))
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
	awaken_p *= float(card.get("awaken", 1.0)) # 해외 전지훈련 등
	if awaken_p > 0 and rng.chance(awaken_p * (0.6 + p["talent"] * 0.15)):
		var aw := awaken(p, rng)
		if not aw.is_empty() and report != null:
			aw["playerId"] = p["id"]
			report["awakenings"].append(aw)
	if report != null and not gains.is_empty():
		report["gains"][p["id"]] = gains


## 특수능력 각성 {ability, removed}. 부정 능력이 있으면 절반 확률로 먼저 극복하고(같은 그룹 긍정 능력으로 바뀌거나 사라짐),
## 가진 긍정 능력은 가끔 금특으로 진화한다. 없으면 새 긍정 능력. 아무 일도 없으면 빈 Dictionary
static func awaken(p: Dictionary, rng: Rng) -> Dictionary:
	var bad: Array = p["abilities"].filter(func(x): return Abilities.is_bad(x))
	if not bad.is_empty() and rng.chance(0.5):
		var b: String = rng.pick(bad)
		var grp: String = Abilities.info(b)["group"]
		for a in Abilities.all():
			if a["group"] == grp and a["tier"] == "good" and Abilities.fits(a, p):
				return {"ability": a["id"], "removed": Abilities.learn(p, a["id"])}
		p["abilities"] = p["abilities"].filter(func(x): return x != b)
		return {"ability": "", "removed": [b]}
	var up := []
	for x in p["abilities"]:
		if Abilities.gold_of(x) != "":
			up.append(Abilities.gold_of(x))
	if not up.is_empty() and rng.chance(0.15 + p["talent"] * 0.03):
		var g: String = rng.pick(up)
		return {"ability": g, "removed": Abilities.learn(p, g)}
	var pool := Abilities.all().filter(func(a): return a["tier"] == "good" and Abilities.fits(a, p) and Abilities.cannot_learn(p, a["id"]) == "")
	if pool.is_empty():
		return {}
	var a: Dictionary = rng.pick(pool)
	return {"ability": a["id"], "removed": Abilities.learn(p, a["id"])}


## 각성 알림 {title, body}
static func awakening_text(n: String, aw: Dictionary) -> Dictionary:
	var bad := ""
	for x in aw["removed"]:
		if Abilities.is_bad(x):
			bad = x
	var ab: String = aw["ability"]
	var q := func(id: String) -> String: return "「%s」" % Abilities.name_of(id)
	if ab == "":
		return {"title": "나쁜 버릇 극복", "body": "%s 꾸준한 노력 끝에 나쁜 버릇 %s을(를) 고쳤다!" % [Text.josa(n, "은/는"), q.call(bad)]}
	if Abilities.tier(ab) == "gold":
		var old: String = aw["removed"][0] if not aw["removed"].is_empty() else ""
		return {"title": "금특 진화!", "body": "%s의 %s이(가) 한 단계 진화했다!\n금특 %s 획득!" % [n, q.call(old), q.call(ab)]}
	if bad != "":
		return {"title": "나쁜 버릇 극복", "body": "%s %s을(를) 극복하고\n%s에 눈을 떴다!" % [Text.josa(n, "은/는"), q.call(bad), q.call(ab)]}
	return {"title": "특수능력 습득", "body": "%s 새로운 능력에 눈을 떴다!\n%s" % [Text.josa(n, "이/가"), q.call(ab)]}


## 주간 컨디션 변동 (평정심: 떨어질 때 절반은 버팀 / 기분파: 기복 큼)
static func weekly_condition(p: Dictionary, rng: Rng) -> void:
	var mood := Abilities.season_fx(p, "mood")
	var vol: float = (0.45 if p["personality"] == "열혈" else (0.2 if p["personality"] == "냉정" else 0.32)) + mood * 0.15
	if rng.chance(vol):
		var up := rng.chance(0.5)
		if not up and mood < 0 and rng.chance(0.5):
			return
		p["cond"] = clampi(p["cond"] + (1 if up else -1), -2, 2)
	elif p["cond"] != 0 and rng.chance(0.3):
		p["cond"] += -1 if p["cond"] > 0 else 1
