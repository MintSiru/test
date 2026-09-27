class_name MatchEngine
extends RefCounted
## 투구 단위 야구 시뮬레이션 엔진 (web/src/sim/engine.ts 이식).
## step() 한 번 = 공 하나. 결과 Dictionary(이벤트)로 화면 연출을 만든다.
## 확률 상수는 웹 쪽 tests/balance.test.ts 로 튜닝한 값과 같다.

const DEFAULT_RULES := {"innings": 9, "mercy": [[5, 10], [7, 7]], "tiebreakFrom": 10, "pitchLimit": 105, "allowDraw": false, "maxInnings": 15}
const SPEED_MUL := {"FB": 1.0, "SL": 0.9, "CB": 0.82, "CH": 0.86, "FK": 0.88, "SI": 0.97, "CT": 0.95}


class TeamSide:
	var team_id: String
	var name: String
	var colors: Array
	var is_user: bool
	var players: Array = [] # SimPlayer
	var by_id := {}
	var order: Array = [] # 타순 9명 id
	var pos_of := {} # id -> 수비 위치 (P, C, ... DH)
	var batter_idx := 0
	var pitcher_id: String
	var used: Array = []
	var pitchers: Array = []
	var pitch_count := {}
	var score := 0
	var hits := 0
	var errors := 0
	var line: Array = []
	var box := {} # id -> {bat, pit}

	func _init(input: Dictionary) -> void:
		team_id = input["teamId"]
		name = input["name"]
		colors = input["colors"]
		is_user = input.get("isUser", false)
		players = input["players"]
		for p in players:
			by_id[p.id] = p
		for s in input["lineup"]:
			order.append(s["playerId"])
			pos_of[s["playerId"]] = s["pos"]
		pitcher_id = input["pitcherId"]
		pos_of[pitcher_id] = "P"
		used = order.duplicate()
		used.append(pitcher_id)
		for id in used:
			box[id] = {"bat": PlayerUtil.empty_bat(), "pit": PlayerUtil.empty_pit()}
		for id in order:
			box[id]["bat"]["g"] = 1
		box[pitcher_id]["pit"]["g"] = 1
		box[pitcher_id]["pit"]["gs"] = 1
		pitchers = [pitcher_id]
		pitch_count[pitcher_id] = 0

	func ensure_box(id: String) -> Dictionary:
		if not box.has(id):
			box[id] = {"bat": PlayerUtil.empty_bat(), "pit": PlayerUtil.empty_pit()}
		return box[id]


var rng: Rng
var rules: Dictionary
var home: TeamSide
var away: TeamSide
var inning := 1
var top := true
var outs := 0
var balls := 0
var strikes := 0
var bases: Array = [null, null, null] # {id, resp, earned}
var over := false
var winner = null
var called := false
var game_log: Array = []
## true 면 실황 문구·로그를 만들지 않는다 (CPU끼리 경기 고속 처리)
var quiet := false
## CPU 감독 AI 의 타석별 작전 캐시
var ai_cache := {}
var pitch_no := 0
var _pW = null
var _pL = null
var _leader = null
var _outs_before := 0


func _init(home_input: Dictionary, away_input: Dictionary, rng_: Rng, rules_: Dictionary = DEFAULT_RULES) -> void:
	rng = rng_
	rules = rules_
	home = TeamSide.new(home_input)
	away = TeamSide.new(away_input)


func off() -> TeamSide:
	return away if top else home


func def() -> TeamSide:
	return home if top else away


func batter() -> SimPlayer:
	var o := off()
	return o.by_id[o.order[o.batter_idx]]


func pitcher() -> SimPlayer:
	var d := def()
	return d.by_id[d.pitcher_id]


func fielder(pos: String, side: TeamSide = null) -> SimPlayer:
	if side == null:
		side = def()
	if pos == "P":
		return side.by_id[side.pitcher_id]
	for id in side.order:
		if side.pos_of.get(id, "") == pos:
			return side.by_id[id]
	return side.by_id[side.pitcher_id]


func def_value(pos: String) -> float:
	var f := fielder(pos)
	var apt := 1.0 if f.pos == pos else (0.88 if pos in f.sub else (0.82 if pos == "1B" else 0.7))
	var v := f.fld * apt
	if pos in ["LF", "CF", "RF"]:
		v = v * 0.7 + f.spd * 0.3 * apt
	if f.has("glove"):
		v += 8
	return v


func side_of(team_id: String) -> TeamSide:
	return home if home.team_id == team_id else away


func score_diff_for(side: TeamSide) -> int:
	var other := away if side == home else home
	return side.score - other.score


func risp() -> bool:
	return bases[1] != null or bases[2] != null


func late_close() -> bool:
	return inning >= 7 and absi(home.score - away.score) <= 2


func user_side() -> TeamSide:
	return home if home.is_user else away


## 투수 현재 능력 (피로 반영)
func pitcher_eff(p: SimPlayer, side: TeamSide) -> Dictionary:
	var np: int = side.pitch_count.get(p.id, 0)
	var pool := 40.0 + p.sta * 0.85 * (1.2 if p.has("ironArm") else 1.0)
	var over_ := maxf(0.0, np - pool)
	var velo := p.velo - over_ * 0.12
	var ctl := p.ctl - over_ * 0.45
	var stuff := p.stuff - over_ * 0.3
	if risp():
		if p.has("pinch"):
			ctl += 6
			velo += 1.5
			stuff += 4
		if p.has("pinchX"):
			ctl -= 12
	if late_close() and p.has("bigHeart"):
		ctl += 5
		velo += 1.5
	return {"velo": velo, "ctl": ctl, "stuff": stuff, "tired": over_}


# ───────────── 교체 ─────────────

func change_pitcher(side: TeamSide, id: String) -> void:
	if side.pitcher_id == id or not side.by_id.has(id) or id in side.used:
		return
	side.pitcher_id = id
	side.used.append(id)
	side.pitchers.append(id)
	side.pitch_count[id] = 0
	side.pos_of[id] = "P"
	side.ensure_box(id)["pit"]["g"] = 1
	game_log.append("[투수 교체] %s: %s" % [side.name, side.by_id[id].name])


func pinch_hit(side: TeamSide, id: String) -> void:
	if side != off() or not side.by_id.has(id) or id in side.used:
		return
	var old: String = side.order[side.batter_idx]
	side.order[side.batter_idx] = id
	side.pos_of[id] = side.pos_of[old]
	side.pos_of.erase(old)
	side.used.append(id)
	side.ensure_box(id)["bat"]["g"] = 1
	game_log.append("[대타] %s → %s" % [side.by_id[old].name, side.by_id[id].name])


func pinch_run(side: TeamSide, base: int, id: String) -> void:
	var r = bases[base]
	if r == null or side != off() or not side.by_id.has(id) or id in side.used:
		return
	var idx := side.order.find(r["id"])
	if idx < 0:
		return
	side.order[idx] = id
	side.pos_of[id] = side.pos_of[r["id"]]
	side.pos_of.erase(r["id"])
	side.used.append(id)
	side.ensure_box(id)["bat"]["g"] = 1
	game_log.append("[대주자] %s → %s" % [side.by_id[r["id"]].name, side.by_id[id].name])
	bases[base] = {"id": id, "resp": r["resp"], "earned": r["earned"]}


func def_sub(side: TeamSide, out_id: String, in_id: String) -> void:
	var idx := side.order.find(out_id)
	if idx < 0 or not side.by_id.has(in_id) or in_id in side.used:
		return
	side.order[idx] = in_id
	side.pos_of[in_id] = side.pos_of[out_id]
	side.pos_of.erase(out_id)
	side.used.append(in_id)
	side.ensure_box(in_id)["bat"]["g"] = 1
	game_log.append("[수비 교체] %s → %s" % [side.by_id[out_id].name, side.by_id[in_id].name])


# ───────────── 핵심: 공 하나 ─────────────

func _new_event(b: SimPlayer, p: SimPlayer) -> Dictionary:
	return {
		"inning": inning, "top": top, "pitcherId": p.id, "batterId": b.id, "pitchType": "FB", "kmh": 0,
		"loc": Vector2.ZERO, "call": "ball", "batted": null, "steal": null, "wildPitch": false,
		"moves": [], "runs": 0, "paResult": "", "text": "", "endHalf": false, "gameOver": false,
	}


## orders: {off, pitch, shift}
func step(orders: Dictionary = {}) -> Dictionary:
	assert(not over, "game over")
	var o := off()
	var d := def()
	var b := batter()
	var p := pitcher()
	var ev := _new_event(b, p)
	var off_order: String = orders.get("off", "normal")
	var shift: String = orders.get("shift", "normal")

	if orders.get("pitch", "normal") == "ibb":
		ev["call"] = "ibb"
		ev["loc"] = Vector2(2.2, 0)
		_walk(ev, "고의사구")
		ev["text"] = "%s, 고의사구로 출루" % b.name
		return _finish(ev)

	pitch_no += 1
	d.pitch_count[p.id] = d.pitch_count.get(p.id, 0) + 1
	d.box[p.id]["pit"]["np"] += 1

	var eff := pitcher_eff(p, d)
	var breaking := p.breaking
	var pt := "FB"
	var lv := 0
	var fb_rate := clampf(0.64 - breaking.size() * 0.06 + (0.15 if balls >= 3 else 0.0), 0.35, 0.95)
	if not breaking.is_empty() and not rng.chance(fb_rate):
		var c: Dictionary = rng.weighted(breaking, p.breaking_w)
		pt = c["type"]
		lv = int(c["lv"])
	var is_breaking := pt != "FB"
	ev["pitchType"] = pt
	ev["kmh"] = roundi(eff["velo"] * SPEED_MUL[pt] + rng.gauss() * 1.5)

	var pp: float = (lv * 5.5 + (eff["velo"] - 115) * 0.55 + 5) if is_breaking else (eff["velo"] - 115) * 1.2
	if not is_breaking and p.has("heavyBall"):
		pp += 5
	pp += (eff["stuff"] - 40) * 0.08

	var want_zone := 0.56
	if balls == 3:
		want_zone += 0.25
	elif balls == 2:
		want_zone += 0.08
	if strikes == 2 and balls < 2:
		want_zone -= 0.2
	var pitch_order: String = orders.get("pitch", "normal")
	if pitch_order == "zone":
		want_zone += 0.22
	if pitch_order == "edge":
		want_zone -= 0.22
	var bunting := off_order in ["bunt", "squeeze", "safetyBunt"]
	if bunting:
		want_zone -= 0.06
	var ctl: float = eff["ctl"]
	if p.has("wild") and rng.chance(0.06):
		ctl -= 30
	if p.has("pinpoint"):
		ctl += 6
	var intend_zone := rng.chance(clampf(want_zone, 0.1, 0.95))
	var in_zone: bool
	var mistake := false
	if intend_zone:
		in_zone = rng.chance(clampf(0.7 + ctl * 0.0026 - (0.05 if is_breaking else 0.0), 0.55, 0.97))
		if in_zone:
			mistake = rng.chance(clampf(0.13 - ctl * 0.0011, 0.02, 0.15))
	else:
		in_zone = not rng.chance(clampf(0.8 + ctl * 0.0015, 0.75, 0.97))
		if in_zone:
			mistake = rng.chance(0.4)
	if in_zone:
		ev["loc"] = Vector2(rng.frange(-0.9, 0.9), rng.frange(-0.9, 0.9))
	else:
		var sd := rng.irange(0, 3)
		var dd := rng.frange(1.1, 1.8)
		var t := rng.frange(-1.2, 1.2)
		ev["loc"] = [Vector2(dd, t), Vector2(-dd, t), Vector2(t, dd), Vector2(t, -dd)][sd]
	if mistake:
		ev["loc"] = Vector2(rng.frange(-0.4, 0.4), rng.frange(-0.3, 0.3))

	if not in_zone and rng.chance(0.012 + (0.008 if ctl < 40 else 0.0)):
		ev["call"] = "hbp"
		_walk(ev, "몸에 맞는 공", true)
		ev["text"] = "%s, 몸에 맞는 공으로 출루" % b.name
		return _finish(ev)

	var stealer = null
	if off_order in ["steal", "hitRun"]:
		if bases[1] != null and bases[2] == null:
			stealer = {"base": 1, "r": bases[1]}
		elif bases[0] != null and bases[1] == null:
			stealer = {"base": 0, "r": bases[0]}
	var squeeze_runner = bases[2] if off_order == "squeeze" else null

	if bunting:
		return _resolve_bunt(ev, b, pp, in_zone, off_order, shift, squeeze_runner)

	var swing_p: float
	if in_zone:
		swing_p = 0.63 + (-0.08 if strikes == 0 else 0.0) + (0.22 if strikes == 2 else 0.0)
		if balls == 3 and strikes == 0:
			swing_p = 0.15
	else:
		swing_p = 0.34 - b.eye * 0.0028 + (0.12 if strikes == 2 else 0.0) + (0.06 if is_breaking else 0.0)
		if balls == 3 and strikes < 2:
			swing_p *= 0.4
	if off_order == "wait":
		swing_p = 0.03 if strikes == 0 else swing_p
	if off_order == "aggressive":
		swing_p += 0.15
	if off_order == "hitRun":
		swing_p = 0.95 if in_zone else 0.7
	if mistake:
		swing_p += 0.12
	var swing := rng.chance(clampf(swing_p, 0.01, 0.98))

	if not swing:
		if in_zone:
			strikes += 1
			ev["call"] = "called"
		else:
			balls += 1
			ev["call"] = "ball"
	else:
		var con := b.con
		var pw := b.pow
		if risp():
			if b.has("chance"):
				con += 7
				pw += 5
			if b.has("chanceX"):
				con -= 8
				pw -= 5
		if b.has("hitMachine"):
			con += 5
		if p.throws == "L" and b.has("lefty"):
			con += 6
		var platoon := 0.01 if b.bats == "S" else (-0.015 if b.bats == p.throws else 0.015)
		var contact_p := 0.87 + (con - 50) * 0.0045 - (pp - 28) * 0.0062 + platoon - (0.0 if in_zone else 0.22) + (0.08 if mistake else 0.0)
		if strikes == 2 and b.has("tenacious"):
			contact_p += 0.05
		if strikes == 2 and p.has("strikeout"):
			contact_p -= 0.05
		if off_order == "hitRun":
			contact_p += 0.05
		if not rng.chance(clampf(contact_p, 0.3, 0.97)):
			strikes += 1
			ev["call"] = "swinging"
		else:
			var foul_p := (0.4 if in_zone else 0.55) + (0.1 if strikes == 2 and b.has("tenacious") else 0.0)
			if rng.chance(foul_p):
				ev["call"] = "foul"
				if strikes < 2:
					strikes += 1
			else:
				ev["call"] = "inplay"
				_resolve_in_play(ev, b, pw, pp, in_zone, mistake, shift, stealer)
				return _finish(ev)

	# 폭투/포일
	if _any_runner() and ev["call"] != "foul":
		var catcher := fielder("C")
		var wp_p := 0.007 + maxf(0.0, 55 - ctl) * 0.00025 + maxf(0.0, 50 - catcher.fld) * 0.0002 + (0.004 if is_breaking else 0.0)
		if rng.chance(wp_p):
			ev["wildPitch"] = true
			_advance_all(ev, 1, false)
			ev["text"] = "폭투! 주자 진루"
			stealer = null

	if strikes >= 3:
		var bl: Dictionary = o.box[b.id]["bat"]
		bl["pa"] += 1
		bl["ab"] += 1
		bl["so"] += 1
		d.box[p.id]["pit"]["so"] += 1
		_add_out(ev, b.id, 0)
		ev["paResult"] = "루킹 삼진" if ev["call"] == "called" else "헛스윙 삼진"
		if stealer != null and not _half_over():
			_resolve_steal(ev, stealer)
		ev["text"] = _pitch_text(ev) + " — %s!" % ev["paResult"]
		return _finish(ev, true)
	if balls >= 4:
		_walk(ev, "볼넷")
		ev["text"] = _pitch_text(ev) + " — 볼넷"
		return _finish(ev)
	if stealer != null and ev["call"] != "foul":
		_resolve_steal(ev, stealer)
	if ev["text"] == "":
		ev["text"] = _pitch_text(ev)
	return _finish(ev, false)


func _any_runner() -> bool:
	return bases[0] != null or bases[1] != null or bases[2] != null


const CALL_KO := {"ball": "볼", "called": "스트라이크", "swinging": "헛스윙", "foul": "파울", "inplay": "타격", "hbp": "사구", "ibb": "고의사구", "buntFoul": "번트 파울", "buntMiss": "번트 헛스윙"}


func _pitch_text(ev: Dictionary) -> String:
	if quiet:
		return ""
	return "%dkm %s %s" % [ev["kmh"], PlayerUtil.PITCH_KO[ev["pitchType"]], CALL_KO[ev["call"]]]


# ───────────── 번트 ─────────────

func _strikeout_bunt(ev: Dictionary, b: SimPlayer, label: String) -> Dictionary:
	var bl: Dictionary = off().box[b.id]["bat"]
	bl["pa"] += 1
	bl["ab"] += 1
	bl["so"] += 1
	def().box[pitcher().id]["pit"]["so"] += 1
	_add_out(ev, b.id, 0)
	ev["paResult"] = label
	return _finish(ev, true)


func _resolve_bunt(ev: Dictionary, b: SimPlayer, pp: float, in_zone: bool, order: String, shift: String, squeeze_runner) -> Dictionary:
	if not in_zone and order != "squeeze" and rng.chance(0.75):
		balls += 1
		ev["call"] = "ball"
		if balls >= 4:
			_walk(ev, "볼넷")
			ev["text"] = _pitch_text(ev) + " — 볼넷"
			return _finish(ev)
		ev["text"] = _pitch_text(ev) + " (번트 자세에서 배트를 거둠)"
		return _finish(ev, false)
	var good := 0.6 + (b.con - 50) * 0.004 - (pp - 28) * 0.004 + (0.22 if b.has("bunter") else 0.0) - (0.0 if in_zone else 0.15)
	if shift == "buntShift":
		good -= 0.12
	var roll := rng.next()
	if roll < 0.1 + (1 - good) * 0.1:
		ev["call"] = "buntMiss"
		strikes += 1
		if squeeze_runner != null:
			bases[2] = null
			ev["moves"].append({"runnerId": squeeze_runner["id"], "from": 3, "to": -1})
			outs += 1
			ev["text"] = "스퀴즈 실패! 3루 주자 협살"
		if strikes >= 3:
			ev["text"] = (ev["text"] + " / " if ev["text"] != "" else "") + "번트 헛스윙 삼진"
			return _strikeout_bunt(ev, b, "번트 헛스윙 삼진")
		if ev["text"] == "":
			ev["text"] = "번트 헛스윙"
		return _finish(ev, false)
	if roll < 0.1 + (1 - good) * 0.55 and order != "squeeze":
		ev["call"] = "buntFoul"
		if strikes == 2:
			strikes = 3
			ev["text"] = "번트 파울 — 스리번트 실패, 삼진"
			return _strikeout_bunt(ev, b, "스리번트 실패 (삼진)")
		strikes += 1
		ev["text"] = "번트 파울"
		return _finish(ev, false)
	ev["call"] = "inplay"
	var angle := rng.frange(-25, 25)
	var fpos := "3B" if angle < -10 else ("1B" if angle > 10 else ("P" if rng.chance(0.5) else "C"))
	var o := off()
	var bl: Dictionary = o.box[b.id]["bat"]
	var success := rng.next() < good
	if order == "safetyBunt" and success:
		var hit_p := 0.2 + (b.spd - 50) * 0.009 + (0.08 if b.has("bunter") else 0.0) - (0.1 if shift == "buntShift" else 0.0)
		if rng.chance(hit_p):
			ev["batted"] = {"type": "BUNT", "angle": angle, "dist": 12.0, "result": "1B", "fielder": fpos, "caught": false}
			bl["pa"] += 1
			bl["ab"] += 1
			bl["h"] += 1
			o.hits += 1
			def().box[pitcher().id]["pit"]["h"] += 1
			_advance_forced(ev, b.id, false, true)
			ev["paResult"] = "기습번트 안타"
			ev["text"] = "기습번트! 내야 안타"
			return _finish(ev, true)
	if success:
		ev["batted"] = {"type": "BUNT", "angle": angle, "dist": 12.0, "result": "SAC", "fielder": fpos, "caught": false}
		var had_runners := _any_runner()
		bl["pa"] += 1
		if had_runners:
			bl["sh"] += 1
		else:
			bl["ab"] += 1
		_advance_all(ev, 1, true, b.id)
		_add_out(ev, b.id, 0)
		ev["paResult"] = "스퀴즈 성공" if squeeze_runner != null else ("희생번트 성공" if had_runners else "번트 아웃")
		ev["text"] = ev["paResult"] + ("! 3루 주자 홈인" if squeeze_runner != null else "")
		return _finish(ev, true)
	bl["pa"] += 1
	bl["ab"] += 1
	if rng.chance(0.35):
		ev["batted"] = {"type": "PU", "angle": angle, "dist": 15.0, "result": "OUT", "fielder": fpos, "caught": true}
		_add_out(ev, b.id, 0)
		ev["paResult"] = "번트 뜬공"
		ev["text"] = "번트가 떴다 — 뜬공 아웃"
		if squeeze_runner != null and not _half_over():
			bases[2] = null
			ev["moves"].append({"runnerId": squeeze_runner["id"], "from": 3, "to": -1})
			outs += 1
			ev["text"] += ", 3루 주자까지 더블아웃"
		return _finish(ev, true)
	ev["batted"] = {"type": "BUNT", "angle": angle, "dist": 12.0, "result": "FC", "fielder": fpos, "caught": false}
	var lead := -1
	for i in [2, 1, 0]:
		if bases[i] != null and (i == 0 or _forced_at(i)):
			lead = i
			break
	if lead >= 0:
		var r: Dictionary = bases[lead]
		bases[lead] = null
		ev["moves"].append({"runnerId": r["id"], "from": lead + 1, "to": -1})
		outs += 1
		if not _half_over():
			_advance_forced(ev, b.id, false, false)
		ev["paResult"] = "번트 실패 (선행주자 아웃)"
		ev["text"] = "번트 실패! 선행 주자 아웃"
	else:
		_add_out(ev, b.id, 0)
		ev["paResult"] = "번트 아웃"
		ev["text"] = "번트 아웃"
	return _finish(ev, true)


func _forced_at(i: int) -> bool:
	for k in i:
		if bases[k] == null:
			return false
	return true


# ───────────── 인플레이 ─────────────

static func _dir_single(a: float) -> String:
	return "좌전" if a < -14 else ("우전" if a > 14 else "중전")


static func _dir_xbh(a: float) -> String:
	if a < -33: return "좌익선상"
	if a < -10: return "좌중간"
	if a > 33: return "우익선상"
	if a > 10: return "우중간"
	return "중견수 키를 넘기는"


static func _dir_hr(a: float) -> String:
	return "좌월" if a < -14 else ("우월" if a > 14 else "중월")


func _resolve_in_play(ev: Dictionary, b: SimPlayer, pw: float, pp: float, in_zone: bool, mistake: bool, shift: String, stealer) -> void:
	var o := off()
	var d := def()
	var p := pitcher()
	var bl: Dictionary = o.box[b.id]["bat"]
	var pl: Dictionary = d.box[p.id]["pit"]

	var evel := 113 + pw * 0.42 + rng.gauss() * 13 - (pp - 28) * 0.35 + (10.0 if mistake else 0.0) - (0.0 if in_zone else 10.0)
	if b.has("powerHitter"):
		evel += 4
	var gb_w := 0.44 - (pw - 50) * 0.002
	var fb_w := 0.27 + (pw - 50) * 0.002
	if ev["pitchType"] in ["SI", "FK"]:
		gb_w += 0.08
		fb_w -= 0.05
	var type: String = rng.weighted(["GB", "LD", "FB", "PU"], [gb_w, 0.21, fb_w, 0.08])
	var pull := 1.0 if b.bats == "L" else (-1.0 if b.bats == "R" else (1.0 if p.throws == "R" else -1.0))
	var angle := clampf(rng.gauss() * 21 + pull * 7, -44, 44)

	var result := "OUT"
	var fpos := "CF"
	var dist := 0.0
	var caught := false
	var r3 = bases[2]
	var runner_on_first_stealing: bool = stealer != null and stealer["base"] == 0

	if type == "GB":
		if angle < -24: fpos = "3B"
		elif angle < -7: fpos = "SS"
		elif angle < 7: fpos = "P" if rng.chance(0.15) else ("SS" if angle < 0 else "2B")
		elif angle < 24: fpos = "2B"
		else: fpos = "1B"
		var dv := def_value(fpos)
		var hit_p := 0.25 + (evel - 130) * 0.0045 + (b.spd - 50) * 0.0025 - (dv - 50) * 0.0025
		if absf(angle) < 7:
			hit_p += 0.06
		if shift == "infieldIn":
			hit_p += 0.08
		dist = rng.frange(28, 40)
		if rng.chance(clampf(hit_p, 0.05, 0.6)):
			result = "2B" if absf(angle) > 36 and evel > 140 and rng.chance(0.4) else "1B"
			dist = 80.0 if result == "2B" else 55.0
		elif rng.chance(clampf(0.05 + (55 - dv) * 0.001, 0.015, 0.1)):
			result = "E"
		elif bases[0] != null and outs < 2 and not runner_on_first_stealing and rng.chance(clampf(0.42 - (b.spd - 50) * 0.004 + (dv - 50) * 0.003, 0.1, 0.65)):
			result = "DP"
		elif bases[0] != null and outs < 2 and not runner_on_first_stealing and rng.chance(0.3):
			result = "FC"
	elif type == "PU":
		if absf(angle) < 10 and rng.chance(0.3): fpos = "C"
		elif angle < -20: fpos = "3B"
		elif angle < 0: fpos = "SS"
		elif angle < 20: fpos = "2B"
		else: fpos = "1B"
		dist = rng.frange(10, 35)
		caught = true
		if rng.chance(0.02):
			result = "E"
			caught = false
	else:
		fpos = "LF" if angle < -15 else ("RF" if angle > 15 else "CF")
		dist = (evel - 55) * 0.95 + rng.gauss() * 6 + (-12.0 if type == "LD" else 0.0) + (3.0 if b.has("powerHitter") else 0.0)
		var dv := def_value(fpos)
		var fence := 98.0 + (1.0 - absf(angle) / 45.0) * 20.0
		if type == "LD" and dist < 45:
			fpos = "3B" if angle < -24 else ("SS" if angle < 0 else ("2B" if angle < 24 else "1B"))
		if type == "FB" and dist > fence:
			result = "HR"
		elif type == "LD":
			var hit_p := 0.7 + (evel - 130) * 0.004 - (dv - 50) * 0.002
			if shift == "deep":
				hit_p -= 0.04
			if shift == "infieldIn":
				hit_p += 0.05
			if rng.chance(clampf(hit_p, 0.35, 0.85)):
				var gap := absf(angle) > 8 and absf(angle) < 38
				if evel > 142 and (gap or rng.chance(0.2)) and rng.chance(0.4):
					result = "3B" if b.spd > 65 and rng.chance(0.14) else "2B"
					dist = maxf(dist, 85)
				else:
					result = "1B"
			else:
				caught = true
		else:
			var catch_p := 0.83 - maxf(0.0, dist - 80) * 0.014 + (dv - 50) * 0.003
			if dist > 38 and dist < 58:
				catch_p -= 0.28
			if shift == "deep":
				catch_p += 0.06 if dist > 80 else -0.08
			if shift == "infieldIn":
				catch_p -= 0.04
			if rng.chance(clampf(catch_p, 0.2, 0.97)):
				caught = true
				if rng.chance(clampf(0.02 + (50 - dv) * 0.0006, 0.005, 0.05)):
					result = "E"
					caught = false
			elif dist > 88:
				result = "3B" if b.spd > 60 and rng.chance(0.25) else "2B"
			else:
				result = "2B" if dist > 72 and rng.chance(0.35) else "1B"
		if caught and result == "OUT" and outs < 2 and r3 != null and type == "FB":
			var of := fielder(fpos)
			var of_arm := of.arm + (15.0 if of.has("laser") else 0.0)
			var sf_p: float = 0.5 + (dist - 60) * 0.018 + (o.by_id[r3["id"]].spd - 50) * 0.006 - (of_arm - 50) * 0.005
			if dist > 55 and rng.chance(clampf(sf_p, 0.05, 0.97)):
				result = "SF"

	ev["batted"] = {"type": type, "angle": angle, "dist": dist, "result": result, "fielder": fpos, "caught": caught}
	var pos_name: String = PlayerUtil.POS_KO[fpos]
	bl["pa"] += 1
	match result:
		"HR":
			bl["ab"] += 1
			bl["h"] += 1
			bl["hr"] += 1
			o.hits += 1
			pl["h"] += 1
			pl["hr"] += 1
			_advance_all(ev, 4, false, b.id)
			_move_batter(ev, b.id, 4, true)
			ev["paResult"] = "%s %s" % [_dir_hr(angle), "만루 홈런" if ev["runs"] >= 4 else "홈런"]
			ev["text"] = "%s!! %s의 한 방!" % [ev["paResult"], b.name]
		"3B":
			bl["ab"] += 1
			bl["h"] += 1
			bl["d3"] += 1
			o.hits += 1
			pl["h"] += 1
			_advance_all(ev, 3, false, b.id)
			_move_batter(ev, b.id, 3, true)
			ev["paResult"] = "%s 3루타" % _dir_xbh(angle)
			ev["text"] = ev["paResult"] + "!"
		"2B":
			bl["ab"] += 1
			bl["h"] += 1
			bl["d2"] += 1
			o.hits += 1
			pl["h"] += 1
			_advance_hit(ev, 2, b.id, fpos, stealer != null)
			_move_batter(ev, b.id, 2, true)
			ev["paResult"] = "%s 2루타" % _dir_xbh(angle)
			ev["text"] = ev["paResult"] + "!"
		"1B":
			bl["ab"] += 1
			bl["h"] += 1
			o.hits += 1
			pl["h"] += 1
			var infield := type == "GB" and dist < 45
			_advance_hit(ev, 0 if infield else 1, b.id, fpos, stealer != null)
			_move_batter(ev, b.id, 1, true)
			ev["paResult"] = "내야 안타" if infield else ("%s 땅볼 안타" % _dir_single(angle) if type == "GB" else "%s 안타" % _dir_single(angle))
			ev["text"] = ev["paResult"] + "!"
		"E":
			bl["ab"] += 1
			d.errors += 1
			var f := fielder(fpos)
			if d.box.has(f.id):
				d.box[f.id]["bat"]["e"] += 1
			_advance_forced(ev, b.id, false, false)
			ev["paResult"] = "%s 실책" % pos_name
			ev["text"] = "%s 실책! 타자 출루" % pos_name
		"DP":
			bl["ab"] += 1
			var r1: Dictionary = bases[0]
			bases[0] = null
			ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": -1})
			outs += 1
			_add_out(ev, b.id, 0)
			if not _half_over():
				_advance_others_on_ground(ev, shift)
			ev["paResult"] = "%s 앞 병살타" % pos_name
			ev["text"] = ev["paResult"]
		"FC":
			bl["ab"] += 1
			var r1f: Dictionary = bases[0]
			bases[0] = null
			ev["moves"].append({"runnerId": r1f["id"], "from": 1, "to": -1})
			outs += 1
			if not _half_over():
				_advance_others_on_ground(ev, shift)
				_move_batter(ev, b.id, 1, false)
			ev["paResult"] = "%s 땅볼 (선행주자 아웃)" % pos_name
			ev["text"] = ev["paResult"]
		"SF":
			bl["sf"] += 1
			_add_out(ev, b.id, 0)
			var rr: Dictionary = bases[2]
			bases[2] = null
			ev["moves"].append({"runnerId": rr["id"], "from": 3, "to": 4})
			_score_runner(ev, rr, b.id, true)
			ev["paResult"] = "%s 희생플라이" % pos_name
			ev["text"] = ev["paResult"] + "! 3루 주자 홈인"
		_:
			bl["ab"] += 1
			_add_out(ev, b.id, 0)
			if not _half_over():
				if type == "GB":
					_advance_others_on_ground(ev, shift, b.id)
				elif type == "FB" and dist > 85 and bases[1] != null and bases[2] == null and rng.chance(0.5):
					var r2: Dictionary = bases[1]
					bases[1] = null
					bases[2] = r2
					ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 3})
			var kind := "땅볼" if type == "GB" else ("직선타" if type == "LD" else (("파울플라이" if fpos == "C" else "뜬공") if type == "PU" else "플라이"))
			ev["paResult"] = "%s %s" % [pos_name, kind]
			ev["text"] = ev["paResult"]


# ───────────── 주자 처리 ─────────────

func _score_runner(ev: Dictionary, r: Dictionary, batter_id, rbi: bool) -> void:
	var o := off()
	var d := def()
	o.score += 1
	ev["runs"] += 1
	var li := inning - 1
	while o.line.size() <= li:
		o.line.append(0)
	o.line[li] += 1
	if o.box.has(r["id"]):
		o.box[r["id"]]["bat"]["r"] += 1
	if rbi and batter_id != null and o.box.has(batter_id):
		o.box[batter_id]["bat"]["rbi"] += 1
	var resp: String = r["resp"] if d.box.has(r["resp"]) else d.pitcher_id
	d.box[resp]["pit"]["r"] += 1
	if r["earned"]:
		d.box[resp]["pit"]["er"] += 1
	_check_lead()


func _check_lead() -> void:
	var lead = null
	if home.score > away.score:
		lead = "home"
	elif away.score > home.score:
		lead = "away"
	if lead != null and lead != _leader:
		var ls := home if lead == "home" else away
		var os := away if lead == "home" else home
		_pW = ls.pitcher_id
		_pL = os.pitcher_id
	_leader = lead


func _move_batter(ev: Dictionary, id: String, to: int, earned: bool) -> void:
	var r := {"id": id, "resp": def().pitcher_id, "earned": earned}
	ev["moves"].append({"runnerId": id, "from": 0, "to": to})
	if to >= 4:
		_score_runner(ev, r, id, true)
	else:
		bases[to - 1] = r


func _advance_all(ev: Dictionary, n: int, rbi: bool, batter_id = null) -> void:
	for i in [2, 1, 0]:
		var r = bases[i]
		if r == null:
			continue
		var to := mini(4, i + 1 + n)
		bases[i] = null
		ev["moves"].append({"runnerId": r["id"], "from": i + 1, "to": to})
		if to >= 4:
			_score_runner(ev, r, batter_id, rbi or n >= 2)
		else:
			bases[to - 1] = r


func _advance_forced(ev: Dictionary, batter_id: String, rbi: bool, earned: bool) -> void:
	_carry(ev, 0, batter_id, rbi)
	_move_batter(ev, batter_id, 1, earned)


func _carry(ev: Dictionary, i: int, batter_id: String, rbi: bool) -> void:
	if i > 2:
		return
	var r = bases[i]
	if r == null:
		return
	_carry(ev, i + 1, batter_id, rbi)
	bases[i] = null
	ev["moves"].append({"runnerId": r["id"], "from": i + 1, "to": i + 2})
	if i + 2 >= 4:
		_score_runner(ev, r, batter_id, rbi)
	else:
		bases[i + 1] = r


func _advance_hit(ev: Dictionary, kind: int, batter_id: String, fpos: String, running: bool) -> void:
	var o := off()
	var f := fielder(fpos)
	var arm := f.arm + (15.0 if f.has("laser") else 0.0)
	var r3 = bases[2]
	var r2 = bases[1]
	var r1 = bases[0]
	bases = [null, null, null]
	if kind == 0:
		if r3 != null and r2 != null and r1 != null:
			ev["moves"].append({"runnerId": r3["id"], "from": 3, "to": 4})
			_score_runner(ev, r3, batter_id, true)
		elif r3 != null:
			bases[2] = r3
		if r2 != null and r1 != null:
			ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 3})
			bases[2] = r2
		elif r2 != null:
			bases[1] = r2
		if r1 != null:
			ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 2})
			bases[1] = r1
		return
	if r3 != null:
		ev["moves"].append({"runnerId": r3["id"], "from": 3, "to": 4})
		_score_runner(ev, r3, batter_id, true)
	if kind == 2:
		if r2 != null:
			ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 4})
			_score_runner(ev, r2, batter_id, true)
		if r1 != null:
			var pr: float = 0.4 + (o.by_id[r1["id"]].spd - 50) * 0.009 - (arm - 50) * 0.004 + (0.35 if running else 0.0) + (0.15 if outs == 2 else 0.0)
			if rng.chance(clampf(pr, 0.05, 0.97)):
				ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 4})
				_score_runner(ev, r1, batter_id, true)
			else:
				ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 3})
				bases[2] = r1
		return
	if r2 != null:
		var pr2: float = 0.55 + (o.by_id[r2["id"]].spd - 50) * 0.009 - (arm - 50) * 0.005 + (0.2 if outs == 2 else 0.0) + (0.2 if running else 0.0)
		if rng.chance(clampf(pr2, 0.1, 0.97)):
			ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 4})
			_score_runner(ev, r2, batter_id, true)
		else:
			ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 3})
			bases[2] = r2
	if r1 != null:
		var pr1: float = 0.22 + (o.by_id[r1["id"]].spd - 50) * 0.007 - (arm - 50) * 0.003 + (0.1 if fpos == "RF" else 0.0) + (0.4 if running else 0.0)
		if bases[2] == null and rng.chance(clampf(pr1, 0.03, 0.9)):
			ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 3})
			bases[2] = r1
		else:
			ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 2})
			bases[1] = r1


func _advance_others_on_ground(ev: Dictionary, shift: String, batter_id = null) -> void:
	var r3 = bases[2]
	var r2 = bases[1]
	var r1 = bases[0]
	if r3 != null:
		var forced := r2 != null and r1 != null
		var go_p := 1.0 if forced else (0.12 if shift == "infieldIn" else 0.55)
		if rng.chance(go_p):
			bases[2] = null
			ev["moves"].append({"runnerId": r3["id"], "from": 3, "to": 4})
			_score_runner(ev, r3, batter_id, true)
	if r2 != null and bases[2] == null:
		bases[1] = null
		bases[2] = r2
		ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 3})
	if r1 != null and bases[1] == null and bases[0] == r1:
		bases[0] = null
		bases[1] = r1
		ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 2})


func _walk(ev: Dictionary, label: String, hbp := false) -> void:
	var b := batter()
	var bl: Dictionary = off().box[b.id]["bat"]
	bl["pa"] += 1
	bl["bb"] += 1
	if not hbp:
		def().box[def().pitcher_id]["pit"]["bb"] += 1
	_advance_forced(ev, b.id, true, true)
	ev["paResult"] = label


func _resolve_steal(ev: Dictionary, s: Dictionary) -> void:
	var base: int = s["base"]
	if bases[base] != s["r"] or bases[base + 1] != null:
		return
	var o := off()
	var runner: SimPlayer = o.by_id[s["r"]["id"]]
	var catcher := fielder("C")
	var arm := catcher.arm + (12.0 if catcher.has("laser") else 0.0)
	var p := 0.62 + (runner.spd - 50) * 0.009 - (arm - 50) * 0.005 + (0.13 if runner.has("stealer") else 0.0)
	if base == 1:
		p -= 0.08
	if pitcher().throws == "L" and base == 0:
		p -= 0.05
	var success := rng.chance(clampf(p, 0.1, 0.96))
	ev["steal"] = {"runnerId": runner.id, "from": base + 1, "success": success}
	bases[base] = null
	var prefix: String = (ev["text"] + " / ") if ev["text"] != "" else (_pitch_text(ev) + " / ")
	if success:
		bases[base + 1] = s["r"]
		o.box[runner.id]["bat"]["sb"] += 1
		ev["moves"].append({"runnerId": runner.id, "from": base + 1, "to": base + 2})
		ev["text"] = prefix + "%s %d루 도루 성공!" % [runner.name, base + 2]
	else:
		o.box[runner.id]["bat"]["cs"] += 1
		ev["moves"].append({"runnerId": runner.id, "from": base + 1, "to": -1})
		outs += 1
		ev["text"] = prefix + "%s 도루 실패" % runner.name


func _add_out(ev: Dictionary, runner_id: String, from: int) -> void:
	outs += 1
	ev["moves"].append({"runnerId": runner_id, "from": from, "to": -1})


func _half_over() -> bool:
	return outs >= 3


# ───────────── 타석/이닝 마무리 ─────────────

func _finish(ev: Dictionary, pa_ended := true) -> Dictionary:
	var d := def()
	var new_outs := mini(3, outs) - _outs_before
	if new_outs > 0:
		d.box[d.pitcher_id]["pit"]["outs"] += new_outs
	_outs_before = mini(3, outs)

	if ev["paResult"] != "":
		pa_ended = true
	if pa_ended:
		balls = 0
		strikes = 0
		var o := off()
		o.batter_idx = (o.batter_idx + 1) % 9
		if ev["paResult"] != "" and not quiet:
			game_log.append("%d회%s %s: %s%s" % [inning, "초" if top else "말", o.by_id[ev["batterId"]].name, ev["paResult"], (" (+%d점)" % ev["runs"]) if ev["runs"] else ""])

	if not top and inning >= rules["innings"] and home.score > away.score:
		_end_game(ev)
		return ev
	if not top and home.score - away.score >= _mercy_gap(inning):
		called = true
		_end_game(ev)
		return ev
	if outs >= 3:
		ev["endHalf"] = true
		_end_half(ev)
	return ev


func _mercy_gap(inn: int) -> int:
	var gap := 1 << 30
	for m in rules["mercy"]:
		if inn >= m[0]:
			gap = m[1]
	return gap


func _end_half(ev: Dictionary) -> void:
	var o := off()
	while o.line.size() < inning:
		o.line.append(0)
	outs = 0
	_outs_before = 0
	balls = 0
	strikes = 0
	bases = [null, null, null]
	var diff := home.score - away.score
	if top:
		if inning >= rules["innings"] and diff > 0:
			_end_game(ev)
			return
		if diff >= _mercy_gap(inning):
			called = true
			_end_game(ev)
			return
		top = false
	else:
		if inning >= rules["innings"] and diff != 0:
			_end_game(ev)
			return
		if absi(diff) >= _mercy_gap(inning):
			called = true
			_end_game(ev)
			return
		if inning >= rules["maxInnings"]:
			_end_game(ev)
			return
		top = true
		inning += 1
	_setup_tiebreak()


## 승부치기: 무사 1,2루 (직전 두 타순의 타자가 주자)
func _setup_tiebreak() -> void:
	if inning < rules["tiebreakFrom"]:
		return
	var o := off()
	var n := o.order.size()
	var r2: String = o.order[(o.batter_idx - 1 + n) % n]
	var r1: String = o.order[(o.batter_idx - 2 + n) % n]
	bases = [{"id": r1, "resp": def().pitcher_id, "earned": false}, {"id": r2, "resp": def().pitcher_id, "earned": false}, null]


func _end_game(ev: Dictionary) -> void:
	over = true
	ev["gameOver"] = true
	while away.line.size() < inning:
		away.line.append(0)
	var home_n := inning - 1 if top else inning
	while home.line.size() < home_n:
		home.line.append(0)
	var diff := home.score - away.score
	if diff == 0:
		if rules["allowDraw"]:
			winner = null
		else:
			var w := home if home.hits > away.hits else away
			if home.hits == away.hits:
				w = home if rng.chance(0.5) else away
			winner = w.team_id
	else:
		winner = home.team_id if diff > 0 else away.team_id
	if winner != null:
		var ws := side_of(winner)
		var ls := away if ws == home else home
		var wp: String = _pW if _pW != null and ws.box.has(_pW) else ws.pitchers[0]
		var lp: String = _pL if _pL != null and ls.box.has(_pL) else ls.pitchers[0]
		ws.box[wp]["pit"]["w"] = 1
		ls.box[lp]["pit"]["l"] = 1
