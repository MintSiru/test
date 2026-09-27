class_name PlayerUtil
extends RefCounted
## 선수 데이터(Dictionary) 생성·계산. 구조는 web/src/core/types.ts 의 Player 와 동일하다.

const POS_KO := {"P": "투수", "C": "포수", "1B": "1루수", "2B": "2루수", "3B": "3루수", "SS": "유격수", "LF": "좌익수", "CF": "중견수", "RF": "우익수", "DH": "지명타자"}
const POS_SHORT := {"P": "투", "C": "포", "1B": "1", "2B": "2", "3B": "3", "SS": "유", "LF": "좌", "CF": "중", "RF": "우", "DH": "지"}
const PITCH_KO := {"FB": "직구", "SL": "슬라이더", "CB": "커브", "CH": "체인지업", "FK": "포크", "SI": "투심", "CT": "커터"}
const STAT_KO := {"contact": "컨택", "power": "파워", "eye": "선구안", "speed": "주력", "arm": "어깨", "fielding": "수비", "velo": "구속", "control": "제구", "stamina": "스태미나", "breaking": "변화구"}
const COND_KO := ["절불조", "불조", "보통", "호조", "절호조"]
const PERSONALITIES := ["열혈", "냉정", "노력파", "천재", "낙천", "소심"]
const POS_POOL := ["P", "P", "P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF"]
const DEF_WEIGHT := {"P": 0.1, "C": 0.4, "1B": 0.12, "2B": 0.32, "3B": 0.25, "SS": 0.38, "LF": 0.15, "CF": 0.3, "RF": 0.18}
const FIELD_POSITIONS := ["C", "1B", "2B", "3B", "SS", "LF", "CF", "RF"]


static func empty_bat() -> Dictionary:
	return {"g": 0, "pa": 0, "ab": 0, "h": 0, "d2": 0, "d3": 0, "hr": 0, "rbi": 0, "r": 0, "bb": 0, "so": 0, "sb": 0, "cs": 0, "sh": 0, "sf": 0, "e": 0}


static func empty_pit() -> Dictionary:
	return {"g": 0, "gs": 0, "outs": 0, "h": 0, "r": 0, "er": 0, "bb": 0, "so": 0, "hr": 0, "w": 0, "l": 0, "np": 0}


static func add_line(a: Dictionary, b: Dictionary) -> void:
	for k in a:
		a[k] += b.get(k, 0)


static func full_name(p: Dictionary) -> String:
	return p["sur"] + p["given"]


static func grade(p: Dictionary, year: int) -> int:
	return year - int(p["enrollYear"]) + 1


static func is_pitcher(p: Dictionary) -> bool:
	return p["pos"] == "P"


static func letter(v: float) -> String:
	if v >= 90: return "S"
	if v >= 80: return "A"
	if v >= 70: return "B"
	if v >= 60: return "C"
	if v >= 50: return "D"
	if v >= 40: return "E"
	if v >= 20: return "F"
	return "G"


const LETTER_COLORS := {"S": Color("#ff5ca8"), "A": Color("#ff8f5c"), "B": Color("#f4d35e"), "C": Color("#a6e36b"), "D": Color("#6fd0c9"), "E": Color("#7fa6ff"), "F": Color("#9aa0c0"), "G": Color("#6b7090")}


static func letter_color(v: float) -> Color:
	return LETTER_COLORS[letter(v)]


static func velo_score(kmh: float) -> float:
	return clampf((kmh - 110.0) * 2.0, 1.0, 100.0)


static func breaking_score(pitches: Array) -> float:
	var total := 0.0
	var best := 0.0
	var n := 0
	for p in pitches:
		if p["type"] == "FB":
			continue
		n += 1
		total += p["lv"]
		best = maxf(best, p["lv"])
	if n == 0:
		return 5.0
	return clampf(best * 8.0 + total * 4.0 + 8.0, 1.0, 100.0)


static func stat_value(r: Dictionary, k: String) -> float:
	if k == "velo":
		return velo_score(r["velo"])
	if k == "breaking":
		return breaking_score(r["pitches"])
	return r[k]


static func pitcher_overall(r: Dictionary) -> int:
	return roundi(velo_score(r["velo"]) * 0.3 + r["control"] * 0.3 + r["stamina"] * 0.15 + breaking_score(r["pitches"]) * 0.25)


static func bat_value(r: Dictionary) -> float:
	return r["contact"] * 0.36 + r["power"] * 0.32 + r["eye"] * 0.14 + r["speed"] * 0.18


static func batter_overall(r: Dictionary, pos: String) -> int:
	var d: float = r["fielding"] * 0.6 + r["arm"] * 0.4
	var w: float = DEF_WEIGHT.get(pos, 0.1)
	return roundi(bat_value(r) * (1.0 - w) + d * w)


static func overall(p: Dictionary) -> int:
	return pitcher_overall(p["r"]) if is_pitcher(p) else batter_overall(p["r"], p["pos"])


static func pos_aptitude(p: Dictionary, pos: String) -> float:
	if p["pos"] == pos: return 1.0
	if pos in p["sub"]: return 0.85
	if pos == "P": return 0.3
	if p["pos"] == "P": return 0.55
	var inf := ["1B", "2B", "3B", "SS"]
	var of := ["LF", "CF", "RF"]
	if pos == "1B": return 0.8
	if pos in inf and p["pos"] in inf: return 0.7
	if pos in of and p["pos"] in of: return 0.8
	if pos == "C": return 0.4
	return 0.55


static func pick_surname(rng: Rng, exclude := "") -> String:
	var list: Array = GameData.names()["surnames"]
	var items := []
	var weights := []
	for s in list:
		items.append(s[0])
		weights.append(s[1])
	while true:
		var s: String = rng.weighted(items, weights)
		if s != exclude:
			return s
	return "김"


static func pick_given(rng: Rng) -> String:
	return rng.pick(GameData.names()["given"])


static func middle_school(rng: Rng) -> String:
	return str(rng.pick(GameData.names()["middlePrefix"])) + "중"


static func _gen_pitches(rng: Rng, skill: float) -> Array:
	var list := [{"type": "FB", "lv": 0}]
	var pool := ["SL", "CB", "CH", "FK", "SI", "CT"]
	var weights := [30, 25, 15, 10, 10, 10]
	var n := rng.irange(2, 3) if skill > 60 else (rng.irange(1, 2) if skill > 35 else 1)
	for i in n:
		var t: String = rng.weighted(pool, weights)
		var dup := false
		for x in list:
			if x["type"] == t:
				dup = true
		if dup:
			continue
		list.append({"type": t, "lv": clampi(roundi(1 + skill / 25.0 + rng.gauss() * 0.8), 1, 5)})
	return list


## 선수 생성. o: {id, teamId, enrollYear, year, quality, pos?, province, pros?, idolChance?}
static func gen_player(rng: Rng, o: Dictionary) -> Dictionary:
	var grade_now: int = int(o["year"]) - int(o["enrollYear"]) + 1
	var pos: String = o.get("pos", "") if o.get("pos", "") != "" else rng.pick(POS_POOL)
	var quality: float = o["quality"]
	var talent := clampi(roundi(1 + (quality / 100.0) * 2.2 + rng.gauss() * 0.9 + (1.5 if rng.chance(0.04) else 0.0)), 1, 5)
	var base := 22.0 + quality * 0.22 + maxi(0, grade_now - 1) * 7.0 + (talent - 3) * 3.0
	var gv := func(spread := 9.0) -> int: return clampi(roundi(base + rng.gauss() * spread), 5, 92)

	var r := {
		"contact": gv.call(), "power": gv.call(11.0), "eye": gv.call(), "speed": gv.call(12.0), "arm": gv.call(), "fielding": gv.call(),
		"velo": 0, "control": 0, "stamina": 0, "pitches": [],
	}
	if pos == "P":
		r["velo"] = clampi(roundi(120 + (base - 22) * 0.45 + rng.gauss() * 5), 110, 152)
		r["control"] = gv.call()
		r["stamina"] = gv.call(12.0)
		r["pitches"] = _gen_pitches(rng, gv.call())
		r["contact"] = clampi(r["contact"] - 15, 5, 80)
		r["power"] = clampi(r["power"] - 10, 5, 80)
	else:
		r["velo"] = clampi(roundi(112 + (base - 22) * 0.3 + rng.gauss() * 4), 105, 140)
		r["control"] = clampi(gv.call() - 20, 5, 60)
		r["stamina"] = clampi(gv.call() - 15, 5, 60)
		r["pitches"] = [{"type": "FB", "lv": 0}]
		if pos == "C":
			r["arm"] += 5
			r["fielding"] += 3
		if pos in ["SS", "2B", "CF"]:
			r["fielding"] += 4
			r["speed"] += 4
		if pos in ["1B", "LF"]:
			r["power"] += 5
			r["fielding"] -= 4
		if pos == "RF":
			r["arm"] += 5
		for k in ["arm", "fielding", "speed", "power"]:
			r[k] = clampi(r[k], 5, 95)

	var cap_of := func(cur: int) -> int: return clampi(roundi(cur + 12 + talent * 7 + rng.irange(-4, 10)), cur + 5, 99)
	var cap := {
		"contact": cap_of.call(r["contact"]), "power": cap_of.call(r["power"]), "eye": cap_of.call(r["eye"]),
		"speed": clampi(r["speed"] + rng.irange(3, 12) + talent * 2, r["speed"] + 3, 99),
		"arm": cap_of.call(r["arm"]), "fielding": cap_of.call(r["fielding"]),
		"velo": clampi(r["velo"] + 6 + talent * 3 + rng.irange(-2, 6), r["velo"] + 3, 158) if pos == "P" else clampi(r["velo"] + 8, r["velo"], 142),
		"control": cap_of.call(r["control"]), "stamina": cap_of.call(r["stamina"]),
		"breaking": clampi(roundi(breaking_score(r["pitches"]) + 15 + talent * 6), 20, 99),
	}

	var bats := "S" if rng.chance(0.03) else ("L" if rng.chance(0.22 if pos == "P" else 0.33) else "R")
	var throws := "R"
	if pos == "P":
		throws = "L" if rng.chance(0.28) else "R"
	elif not pos in ["C", "2B", "3B", "SS"]:
		throws = "L" if rng.chance(0.2) else "R"

	var sub := []
	if pos != "P" and rng.chance(0.45):
		var cand := ["2B", "3B", "SS", "1B"] if pos in ["SS", "2B", "3B"] else (["1B", "3B"] if pos == "C" else ["LF", "CF", "RF", "1B"])
		cand.erase(pos)
		sub.append(rng.pick(cand))
	if pos == "P" and rng.chance(0.15):
		sub.append(rng.pick(["1B", "RF", "LF"]))

	var p := {
		"id": o["id"], "sur": pick_surname(rng), "given": pick_given(rng), "teamId": o["teamId"],
		"enrollYear": int(o["enrollYear"]), "pos": pos, "sub": sub, "bats": bats, "throws": throws,
		"r": r, "talent": talent, "cap": cap, "exp": {}, "abilities": [],
		"personality": rng.pick(PERSONALITIES), "hometown": o.get("province", ""), "focus": "auto",
		"idolBond": 0, "cond": 0, "fatigue": 0, "injury": 0,
		"season": {"bat": empty_bat(), "pit": empty_pit()}, "career": {"bat": empty_bat(), "pit": empty_pit()},
		"faceSeed": rng.irange(1, 1 << 30), "middleSchool": middle_school(rng),
	}

	roll_abilities(rng, p)

	var pros: Array = o.get("pros", [])
	if not pros.is_empty() and rng.chance(o.get("idolChance", 0.22)):
		assign_idol(rng, p, pros)
	return p


## 입학 선수 특수능력: 긍정은 재능이 높을수록, 부정은 재능이 낮을수록 많고 금특은 드물다
static func roll_abilities(rng: Rng, p: Dictionary) -> void:
	var goods := []
	var bads := []
	for a in Abilities.all():
		if a["tier"] == "gold" or not Abilities.fits(a, p):
			continue
		(goods if a["tier"] == "good" else bads).append(a)
	var talent: int = p["talent"]
	var n_good := (2 if rng.chance(0.3) else 1) if rng.chance(0.28 + talent * 0.08) else 0
	var n_bad := (2 if rng.chance(0.2) else 1) if rng.chance(0.34 - talent * 0.05) else 0
	for i in n_good:
		var a: Dictionary = rng.pick(goods)
		if Abilities.cannot_learn(p, a["id"]) == "":
			Abilities.learn(p, a["id"])
	for i in n_bad:
		var a: Dictionary = rng.pick(bads)
		if Abilities.cannot_learn(p, a["id"]) == "":
			Abilities.learn(p, a["id"])
	# 재능 4 이상은 드물게 금특을 가지고 들어온다
	if talent >= 4 and rng.chance(0.08 * (talent - 3)):
		var up := []
		for x in p["abilities"]:
			if Abilities.gold_of(x) != "":
				up.append(Abilities.gold_of(x))
		if not up.is_empty():
			Abilities.learn(p, rng.pick(up))


## 동경 선수 지정: 성향(투수/야수)이 맞는 프로 선수를 골라 이름을 같게, 성은 다르게 한다
static func assign_idol(rng: Rng, p: Dictionary, pros: Array) -> void:
	var styles := GameData.styles()
	var active := pros.filter(func(x): return not x.get("retired", false))
	var matching := active.filter(func(x): return styles[x["style"]]["pitcher"] == (p["pos"] == "P"))
	var pool := matching if not matching.is_empty() else active
	if pool.is_empty():
		return
	var idol: Dictionary = rng.pick(pool)
	p["idolId"] = idol["id"]
	p["given"] = idol["given"]
	if p["sur"] == idol["sur"]:
		p["sur"] = pick_surname(rng, idol["sur"])
	p["idolBond"] = rng.irange(20, 45)


# ───────────── 기록 표시 ─────────────

static func avg_str(b: Dictionary) -> String:
	if b["ab"] == 0:
		return "-.---"
	return ("%.3f" % (float(b["h"]) / b["ab"])).trim_prefix("0")


static func era_str(p: Dictionary) -> String:
	if p["outs"] == 0:
		return "-.--" if p["er"] == 0 else "∞"
	return "%.2f" % (p["er"] * 27.0 / p["outs"])


static func ip_str(outs: int) -> String:
	var f := outs % 3
	return ("%d %d/3" % [outs / 3, f]) if f else str(outs / 3)
