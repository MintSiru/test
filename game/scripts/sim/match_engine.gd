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
	var visits := 0 # 마운드 방문 횟수
	var visit_pa := 0 # 방문 효과가 남은 타자 수
	var lead_any := false # 포수 리드 능력을 가진 선수가 있는가 (없으면 계산 생략)
	var pos_cache := {} # 수비 위치 → 선수 (교체 때 비운다)
	var tac := 0.0 # 감독 특기 「작전가」: 도루·번트·스퀴즈·히트앤런 성공 확률 보정
	var err_mul := 1.0 # 감독 특기 「수비 코치」: 이 팀이 수비할 때 실책 확률 배율

	func _init(input: Dictionary) -> void:
		team_id = input["teamId"]
		name = input["name"]
		colors = input["colors"]
		is_user = input.get("isUser", false)
		players = input["players"]
		for p in players:
			by_id[p.id] = p
			if p.f_lead > 0:
				lead_any = true
		for s in input["lineup"]:
			order.append(s["playerId"])
			pos_of[s["playerId"]] = s["pos"]
		pitcher_id = input["pitcherId"]
		# 투타 겸업: 선발 투수가 지명타자로 타순에 있으면 타순의 위치(DH)를 그대로 둔다
		if not pitcher_id in order:
			pos_of[pitcher_id] = "P"
		used = order.duplicate()
		if not pitcher_id in used:
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
## 경기 도중 저장용 입력 기록: [종류, 인자..., 호출 직전 난수 상태]. journal_on 일 때만 쌓는다
var journal: Array = []
var journal_on := false
## 다시 만들 때 필요한 정보 {fixtureId, seed, starterId}
var save_info := {}
## 특수능력 발동 문구 횟수 (선수+능력 → 횟수)
var _note_count := {}
## 우리 팀 명장면 [{inning, top, kind, text}] (quiet 가 아닐 때만)
var highlights: Array = []


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
	var c = side.pos_cache.get(pos)
	if c != null:
		return c
	var f: SimPlayer = side.by_id[side.pitcher_id]
	for id in side.order:
		if side.pos_of.get(id, "") == pos:
			f = side.by_id[id]
			break
	side.pos_cache[pos] = f
	return f


func def_value(pos: String) -> float:
	var f := fielder(pos)
	var apt := 1.0 if f.pos == pos else (0.88 if pos in f.sub else (0.82 if pos == "1B" else 0.7))
	var v := f.fld * apt
	if pos in ["LF", "CF", "RF"]:
		v = v * 0.7 + f.spd * 0.3 * apt
	return v + f.f_fld


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


# ───────────── 경기 도중 저장 (입력 기록 재생) ─────────────

func _side_key(side: TeamSide) -> String:
	return "home" if side == home else "away"


func _rec(entry: Array) -> void:
	if journal_on:
		entry.append(rng.get_state_str())
		journal.append(entry)


func save_data() -> Dictionary:
	var d := save_info.duplicate()
	d["journal"] = journal
	# 마지막 기록 이후의 난수 상태와 CPU 작전 캐시까지 저장 → 이어서 진행해도 저장하지 않았을 때와 똑같이 흘러간다
	d["rngNow"] = rng.get_state_str()
	d["ai"] = ai_cache.duplicate()
	return d


## 기록을 처음부터 다시 적용한다 (각 호출 직전 난수 상태도 되돌려 CPU 판단까지 똑같이 재현)
func replay(entries: Array) -> void:
	var was := journal_on
	journal_on = false
	for e in entries:
		rng.g.state = str(e[e.size() - 1]).to_int()
		var side: TeamSide = home if str(e[1]) == "home" else away
		match str(e[0]):
			"step":
				if not over:
					step(e[1] if typeof(e[1]) == TYPE_DICTIONARY else {})
			"pitcher": change_pitcher(side, str(e[2]))
			"visit": mound_visit(side)
			"ph": pinch_hit(side, str(e[2]))
			"pr": pinch_run(side, int(e[2]), str(e[3]))
			"def": def_sub(side, str(e[2]), str(e[3]))
	journal = entries.duplicate()
	journal_on = was


## 저장된 경기(state.matchSave)를 다시 만든다. 경기일이 지났거나 기록이 맞지 않으면 null
static func resume(state: Dictionary, ms: Dictionary) -> MatchEngine:
	var found := Season.find_fixture(state, str(ms.get("fixtureId", "")))
	if found.is_empty() or found["f"].get("result") != null or state.get("pendingFixture") != ms.get("fixtureId"):
		return null
	var opts := {}
	if ms.get("starterId") != null:
		opts["starterId"] = str(ms["starterId"])
	var m := Season.create_match(state, found["f"], Rng.new(int(ms["seed"])), opts)
	m.save_info = {"fixtureId": ms["fixtureId"], "seed": int(ms["seed"]), "starterId": ms.get("starterId")}
	m.journal_on = true
	m.replay(ms.get("journal", []))
	if ms.get("rngNow") != null:
		m.rng.g.state = str(ms["rngNow"]).to_int()
	if typeof(ms.get("ai")) == TYPE_DICTIONARY:
		m.ai_cache = ms["ai"]
	return m


# ───────────── 작전 판정 공식 (경기 판정과 화면 안내가 함께 쓴다) ─────────────

## 도루할 주자의 베이스 (0 = 1루 주자, 1 = 2루 주자). 도루할 수 없으면 -1 (step() 의 도루·히트앤런 규칙과 같다)
func steal_base() -> int:
	if bases[1] != null and bases[2] == null:
		return 1
	if bases[0] != null and bases[1] == null:
		return 0
	return -1


## 도루 성공 확률
func steal_prob(base: int) -> float:
	var runner: SimPlayer = off().by_id[bases[base]["id"]]
	var catcher := fielder("C")
	var arm := catcher.arm + catcher.f_arm * 0.8
	var pit := pitcher()
	var hold: float = pit_mods(pit, def()).get("hold", 0.0)
	var p := 0.62 + (runner.spd - 50) * 0.009 - (arm - 50) * 0.005 + runner.f_steal + hold + off().tac
	if base == 1:
		p -= 0.08
	if pit.throws == "L" and base == 0:
		p -= 0.05
	return clampf(p, 0.1, 0.96)


## 번트가 제대로 굴러갈 확률 (타구가 앞으로 갔을 때 성공)
func bunt_good(b: SimPlayer, bm: Dictionary, pp: float, in_zone: bool, shift: String) -> float:
	var good: float = 0.6 + (b.con - 50) * 0.004 - (pp - 28) * 0.004 + bm.get("bunt", 0.0) - (0.0 if in_zone else 0.15) + off().tac
	if shift == "buntShift":
		good -= 0.12
	return good


## 기습번트가 성공했을 때 내야안타가 될 확률
func safety_hit_prob(b: SimPlayer, bm: Dictionary, shift: String) -> float:
	return 0.2 + (b.spd - 50) * 0.009 + bm.get("buntHit", 0.0) - (0.1 if shift == "buntShift" else 0.0) + off().tac


## 지금 투수의 구종별 [비율, 구위] (step() 의 구종 선택·구위 계산과 같다)
func pp_mix() -> Array:
	var p := pitcher()
	var pm := pit_mods(p, def())
	var eff := pitcher_eff(p, def(), pm)
	var velo: float = eff["velo"]
	var base: float = (eff["stuff"] - 40) * 0.08
	var fb: float = (velo - 115) * 1.2 + pm.get("ppFB", 0.0) + base
	if p.breaking.is_empty():
		return [[1.0, fb]]
	var fb_rate := clampf(0.64 - p.breaking.size() * 0.06 + (0.15 if balls >= 3 else 0.0), 0.35, 0.95)
	var out := [[fb_rate, fb]]
	var wsum := 0.0
	for w in p.breaking_w:
		wsum += w
	for i in p.breaking.size():
		var w: float = p.breaking_w[i]
		out.append([(1.0 - fb_rate) * w / wsum, int(p.breaking[i]["lv"]) * 5.5 + (velo - 115) * 0.55 + 5 + pm.get("ppBR", 0.0) + base])
	return out


## 지금 투수의 평균 구위
func avg_pp() -> float:
	var t := 0.0
	for x in pp_mix():
		t += x[0] * x[1]
	return t


## 작전 성공 가능성 (화면 안내용). 쓸 수 없는 작전은 빠진다
##  steal: 도루 성공 / bunt: 번트가 앞으로 갔을 때 희생번트 성공 / safetyBunt: 앞으로 갔을 때 내야안타
##  squeeze: 공 하나에 스퀴즈 성공 (헛스윙이면 3루 주자 아웃) / hitRun: 휘둘렀을 때 공을 맞힐 확률
func tactic_odds() -> Dictionary:
	var out := {}
	var b := batter()
	var bm := bat_mods(b)
	var pm := pit_mods(pitcher(), def())
	var mix := pp_mix()
	var pp := avg_pp()
	var sb := steal_base()
	if sb >= 0:
		out["steal"] = steal_prob(sb)
	# 번트: 구종마다 성공률이 다르고, 대기 쉬운 공일수록 앞으로 굴러가기도 쉽다 → 앞으로 간 번트 기준으로 가중
	var hit := clampf(safety_hit_prob(b, bm, "normal"), 0.0, 1.0)
	var num := 0.0
	var den := 0.0
	var sq := 0.0
	for x in mix:
		var g := clampf(bunt_good(b, bm, x[1], true, "normal"), 0.0, 1.0)
		var ip := maxf(0.0, 1.0 - (0.1 + (1.0 - g) * 0.55))
		num += x[0] * ip * g
		den += x[0] * ip
		# 스퀴즈는 볼에도 번트를 댄다 (공이 존 밖일 확률 약 40%), 헛스윙이면 실패
		var g2 := clampf(g - 0.15 * 0.4, 0.0, 1.0)
		sq += x[0] * (1.0 - (0.1 + (1.0 - g2) * 0.1)) * g2
	var bunt := num / maxf(den, 0.001)
	out["bunt"] = bunt
	out["safetyBunt"] = bunt * hit
	if bases[2] != null:
		out["squeeze"] = sq
	if bases[0] != null and bases[1] == null:
		var platoon := 0.01 if b.bats == "S" else (-0.015 if b.bats == pitcher().throws else 0.015)
		var c: float = 0.87 + (b.con + bm.get("con", 0.0) - 50) * 0.0045 - (pp - 28) * 0.0062 + platoon + bm.get("contact", 0.0) - pm.get("whiff", 0.0) + 0.05 + off().tac
		# 히트앤런은 존 안 95%, 존 밖 70% 를 휘두른다 (존 안 약 55%)
		var w_in := 0.55 * 0.95 / (0.55 * 0.95 + 0.45 * 0.7)
		out["hitRun"] = clampf(c, 0.3, 0.97) * w_in + clampf(c - 0.22, 0.3, 0.97) * (1.0 - w_in)
	return out


## 성공 가능성 → 상·중·하 (기습번트는 원래 낮아서 기준이 다르다)
static func odds_grade(key: String, p: float) -> String:
	var hi := 0.35 if key == "safetyBunt" else 0.7
	var mid := 0.2 if key == "safetyBunt" else 0.45
	return "상" if p >= hi else ("중" if p >= mid else "하")


# ───────────── 특수능력 ─────────────



## 발동 조건 (코드는 Abilities.COND). batting: 타자 쪽 효과인가, side: 능력을 가진 선수의 팀
func _cond(c: int, batting: bool, side: TeamSide) -> bool:
	match c:
		0: return true
		1: return bases[1] != null or bases[2] != null
		2: return late_close()
		3: return inning >= 7
		4: return inning <= 2
		5: return strikes == 2
		6: return balls == 0 and strikes == 0
		7: return _any_runner()
		8: return bases[0] != null and bases[1] != null and bases[2] != null
		9: return outs == 0 and not _any_runner()
		10: return outs == 2
		11: return (pitcher().throws if batting else batter().bats) == "L"
		12: return score_diff_for(side) > 0
		13: return inning >= 7 and score_diff_for(side) < 0
	return false


## 상시 효과(공유 Dictionary)에 지금 조건이 맞는 효과를 더한다. 더할 게 없으면 복사하지 않는다
func _sum_fx(static_fx: Dictionary, list: Array, batting: bool, side: TeamSide) -> Dictionary:
	var out := static_fx
	var copied := false
	for e in list:
		if not _cond(e[0], batting, side):
			continue
		if not copied:
			out = static_fx.duplicate()
			copied = true
		var m: Dictionary = e[1]
		for k in m:
			out[k] = out.get(k, 0.0) + m[k]
	return out


## 현재 타자의 특수능력 효과
func bat_mods(b: SimPlayer) -> Dictionary:
	if b.fx_bat_cond.is_empty():
		return b.fx_bat
	return _sum_fx(b.fx_bat, b.fx_bat_cond, true, off())


## 투수의 특수능력 효과 (현재 타자 상대)
func pit_mods(p: SimPlayer, side: TeamSide) -> Dictionary:
	if p.fx_pit_cond.is_empty():
		return p.fx_pit
	return _sum_fx(p.fx_pit, p.fx_pit_cond, false, side)


## 지금 상황에서 조건이 맞아 발동 중인 특수능력 (조건 없는 상시 능력은 제외, 화면 표시용)
func active_abilities(sp: SimPlayer, batting: bool) -> Array:
	var out := []
	var side := off() if batting else def()
	for id in sp.abil:
		for fx in Abilities.info(id).get("fx", []):
			if fx.has("when") and _cond(Abilities.COND.get(fx["when"], -1), batting, side):
				out.append(id)
				break
	return out


## 투수 현재 능력 (피로·특수능력 반영). pm 을 생략하면 계산한다
func pitcher_eff(p: SimPlayer, side: TeamSide, pm = null) -> Dictionary:
	var m: Dictionary = pit_mods(p, side) if pm == null else pm
	var m_on := not m.is_empty()
	var np: int = side.pitch_count.get(p.id, 0)
	var pool: float = 40.0 + p.sta * 0.85 * (1.0 + (m.get("sta", 0.0) if m_on else 0.0))
	var over_ := maxf(0.0, np - pool)
	var velo: float = p.velo - over_ * 0.12 + (m.get("velo", 0.0) if m_on else 0.0)
	var ctl: float = p.ctl - over_ * 0.45 + (m.get("ctl", 0.0) if m_on else 0.0)
	var stuff: float = p.stuff - over_ * 0.3 + (m.get("stuff", 0.0) if m_on else 0.0)
	if side.lead_any:
		var lead := fielder("C", side).f_lead
		ctl += lead
		stuff += lead
	if side.visit_pa > 0:
		ctl += 8
	return {"velo": velo, "ctl": ctl, "stuff": stuff, "tired": over_}


# ───────────── 교체 ─────────────

func change_pitcher(side: TeamSide, id: String) -> void:
	_rec(["pitcher", _side_key(side), id])
	if side.pitcher_id == id or not side.by_id.has(id) or id in side.used:
		return
	side.pitcher_id = id
	side.used.append(id)
	side.pitchers.append(id)
	side.pitch_count[id] = 0
	side.pos_of[id] = "P"
	side.pos_cache.clear()
	side.ensure_box(id)["pit"]["g"] = 1
	game_log.append("[투수 교체] %s: %s" % [side.name, side.by_id[id].name])


const MAX_VISITS := 3


## 마운드 방문: 한 경기 3번까지, 다음 두 타자 동안 제구 +8
func mound_visit(side: TeamSide) -> bool:
	_rec(["visit", _side_key(side)])
	if side.visits >= MAX_VISITS:
		return false
	side.visits += 1
	side.visit_pa = 2
	game_log.append("[마운드 방문] %s (%d/%d)" % [side.name, side.visits, MAX_VISITS])
	return true


func pinch_hit(side: TeamSide, id: String) -> void:
	_rec(["ph", _side_key(side), id])
	if side != off() or not side.by_id.has(id) or id in side.used:
		return
	var old: String = side.order[side.batter_idx]
	side.order[side.batter_idx] = id
	side.pos_of[id] = side.pos_of[old]
	side.pos_of.erase(old)
	side.pos_cache.clear()
	side.used.append(id)
	side.ensure_box(id)["bat"]["g"] = 1
	game_log.append("[대타] %s → %s" % [side.by_id[old].name, side.by_id[id].name])


func pinch_run(side: TeamSide, base: int, id: String) -> void:
	_rec(["pr", _side_key(side), base, id])
	var r = bases[base]
	if r == null or side != off() or not side.by_id.has(id) or id in side.used:
		return
	var idx := side.order.find(r["id"])
	if idx < 0:
		return
	side.order[idx] = id
	side.pos_of[id] = side.pos_of[r["id"]]
	side.pos_of.erase(r["id"])
	side.pos_cache.clear()
	side.used.append(id)
	side.ensure_box(id)["bat"]["g"] = 1
	game_log.append("[대주자] %s → %s" % [side.by_id[r["id"]].name, side.by_id[id].name])
	bases[base] = {"id": id, "resp": r["resp"], "earned": r["earned"]}


func def_sub(side: TeamSide, out_id: String, in_id: String) -> void:
	_rec(["def", _side_key(side), out_id, in_id])
	var idx := side.order.find(out_id)
	if idx < 0 or not side.by_id.has(in_id) or in_id in side.used:
		return
	side.order[idx] = in_id
	side.pos_of[in_id] = side.pos_of[out_id]
	side.pos_of.erase(out_id)
	side.pos_cache.clear()
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
	if journal_on:
		_rec(["step", orders.duplicate()])
	if quiet:
		return _step(orders)
	# 실황용: 이 공을 던지기 전에 조건이 맞아 켜져 있던 특수능력 → 타석 결과에 영향을 줬으면 「발동」 문구
	var b := batter()
	var p := pitcher()
	var act_b := active_abilities(b, true)
	var act_p := active_abilities(p, false)
	var risp_before := risp()
	var o := off()
	var d := def()
	var lead_before := o.score - d.score
	var inn := inning
	var tp := top
	var ev := _step(orders)
	ev["rispBefore"] = risp_before
	if ev["paResult"] != "" or ev.get("steal") != null:
		ev["abilityNote"] = _ability_note(ev, b, p, act_b, act_p)
	if ev["paResult"] != "" and (o.is_user or d.is_user):
		_highlight(ev, o, d, lead_before, risp_before, b, p, inn, tp)
	return ev


## 우리 팀 명장면: 홈런, 7회 이후 역전·결승타, 끝내기, 6회 이후 득점권 위기를 끝낸 삼진
func _highlight(ev: Dictionary, o: TeamSide, d: TeamSide, lead_before: int, risp_before: bool, b: SimPlayer, p: SimPlayer, inn: int, tp: bool) -> void:
	var res: String = ev["batted"]["result"] if ev.get("batted") != null else ""
	var lead_after := o.score - d.score
	var txt := ""
	var kind := ""
	if o.is_user:
		if ev["gameOver"] and not tp and winner == o.team_id and lead_before <= 0:
			kind = "walkoff"
			txt = "%s 끝내기 %s!" % [b.name, "홈런" if res == "HR" else ("안타" if res in ["1B", "2B", "3B"] else ev["paResult"])]
		elif res == "HR":
			kind = "hr"
			txt = "%s %s!" % [b.name, "만루 홈런" if int(ev["runs"]) >= 4 else ("%d점 홈런" % int(ev["runs"]) if int(ev["runs"]) > 1 else "솔로 홈런")]
			if inn >= 7 and lead_before <= 0 and lead_after > 0:
				txt += " (%s)" % ("역전" if lead_before < 0 else "균형을 깨는 한 방")
		elif inn >= 7 and lead_before <= 0 and lead_after > 0:
			kind = "clutch"
			txt = "%s %s %s" % [b.name, "역전" if lead_before < 0 else "균형을 깨는", "적시타" if res in ["1B", "2B", "3B"] else ev["paResult"]]
	elif d.is_user and inn >= 6 and risp_before and str(ev["paResult"]).ends_with("삼진") and ev["endHalf"] and absf(lead_before) <= 3:
		kind = "escape"
		txt = "%s 위기에서 %s 삼진으로 이닝 종료" % [p.name, b.name]
	if kind != "":
		var h := {"inning": inn, "top": tp, "kind": kind, "text": txt}
		# 다시 보기용 타구 (방향·거리·종류·결과)
		if ev.get("batted") != null:
			var bt: Dictionary = ev["batted"]
			h["b"] = {"type": bt["type"], "angle": bt["angle"], "dist": bt["dist"], "result": bt["result"]}
		highlights.append(h)


## 타석 결과에 영향을 준 특수능력 한 줄 (없으면 "")
##  조건부 능력: 켜진 상태에서 그 능력 주인에게 유리한(긍정)·불리한(부정) 결과가 나왔을 때
##  상시 능력: 홈런(비거리), 도루 성공, 희생번트 성공처럼 효과가 분명히 드러난 결과일 때
func _ability_note(ev: Dictionary, b: SimPlayer, p: SimPlayer, act_b: Array, act_p: Array) -> String:
	var res: String = ev["batted"]["result"] if ev.get("batted") != null else ""
	var pa: String = ev["paResult"]
	var bat_good: bool = res in ["1B", "2B", "3B", "HR"] or pa in ["볼넷", "몸에 맞는 공"] or res == "SF"
	# 아웃은 삼진이거나 득점권 위기였을 때만 (평범한 아웃마다 나오면 지루하다)
	var bat_bad: bool = pa.ends_with("삼진") or (res in ["OUT", "DP"] and ev.get("rispBefore", false))
	var pick := func(ids: Array, want_tier_good: bool) -> String:
		for id in Abilities.sorted(ids):
			if (Abilities.tier(id) != "bad") == want_tier_good:
				return id
		return ""
	var id := ""
	var who := ""
	if bat_good:
		id = pick.call(act_b, true)
		who = b.name
		if id == "":
			id = pick.call(act_p, false)
			who = p.name
	elif bat_bad:
		id = pick.call(act_p, true)
		who = p.name
		if id == "":
			id = pick.call(act_b, false)
			who = b.name
	if id == "":
		# 상시 능력이 결과에 분명히 드러난 경우
		var st = ev.get("steal")
		if st != null and st["success"]:
			var runner: SimPlayer = (away if ev["top"] else home).by_id.get(st["runnerId"])
			if runner != null:
				for x in runner.abil:
					if Abilities.info(x).get("group", "") == "steal" and not Abilities.is_bad(x):
						return "%s의 「%s」! 발로 만든 도루" % [runner.name, Abilities.name_of(x)]
		for x in b.abil:
			var grp: String = Abilities.info(x).get("group", "")
			if (res == "HR" and grp == "power") or (pa == "희생번트 성공" and grp == "bunt") or (res == "1B" and pa == "내야 안타" and grp == "infield"):
				if not Abilities.is_bad(x):
					return "%s의 「%s」!" % [b.name, Abilities.name_of(x)]
		return ""
	# 같은 선수의 같은 능력은 한 경기에 두 번까지
	var key := who + id
	var cnt: int = _note_count.get(key, 0)
	if cnt >= 2:
		return ""
	_note_count[key] = cnt + 1
	return ("%s의 「%s」 발동!" if Abilities.tier(id) != "bad" else "%s, 「%s」… 흔들렸다") % [who, Abilities.name_of(id)]


func _step(orders: Dictionary) -> Dictionary:
	var b := batter()
	var p := pitcher()
	var off_order: String = orders.get("off", "normal")
	var shift: String = orders.get("shift", "normal")
	var pitch_order: String = orders.get("pitch", "normal")

	# CPU끼리 경기의 작전 없는 타석은 빠른 경로로 (확률은 같고 연출용 계산만 생략)
	if quiet and off_order == "normal" and pitch_order == "normal":
		return _fast_pa(b, p, shift)

	var o := off()
	var d := def()
	var ev := _new_event(b, p)
	if pitch_order == "ibb":
		ev["call"] = "ibb"
		ev["loc"] = Vector2(2.2, 0)
		_walk(ev, "고의사구")
		ev["text"] = "%s, 고의사구로 출루" % b.name
		return _finish(ev)

	pitch_no += 1
	d.pitch_count[p.id] = d.pitch_count.get(p.id, 0) + 1
	d.box[p.id]["pit"]["np"] += 1

	var pm := pit_mods(p, d)
	var bm := bat_mods(b)
	var pm_on := not pm.is_empty()
	var bm_on := not bm.is_empty()
	var eff := pitcher_eff(p, d, pm)
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
	pp += (pm.get("ppBR", 0.0) if pm_on else 0.0) if is_breaking else (pm.get("ppFB", 0.0) if pm_on else 0.0)
	pp += (eff["stuff"] - 40) * 0.08

	var want_zone := 0.56
	if balls == 3:
		want_zone += 0.25
	elif balls == 2:
		want_zone += 0.08
	if strikes == 2 and balls < 2:
		want_zone -= 0.2
	if pitch_order == "zone":
		want_zone += 0.22
	if pitch_order == "edge":
		want_zone -= 0.22
	var bunting := off_order in ["bunt", "squeeze", "safetyBunt"]
	if bunting:
		want_zone -= 0.06
	want_zone += (pm.get("zone", 0.0) if pm_on else 0.0)
	var ctl: float = eff["ctl"]
	var wild: float = (pm.get("wild", 0.0) if pm_on else 0.0)
	if wild > 0 and rng.chance(wild):
		ctl -= 30
	var intend_zone := rng.chance(clampf(want_zone, 0.1, 0.95))
	var in_zone: bool
	var mistake := false
	if intend_zone:
		in_zone = rng.chance(clampf(0.7 + ctl * 0.0026 - (0.05 if is_breaking else 0.0), 0.55, 0.97))
		if in_zone:
			mistake = rng.chance(clampf(0.13 - ctl * 0.0011 + (pm.get("mistake", 0.0) if pm_on else 0.0), 0.01, 0.2))
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
		return _resolve_bunt(ev, b, bm, pp, in_zone, off_order, shift, squeeze_runner)

	var swing_p: float
	if in_zone:
		swing_p = 0.63 + (-0.08 if strikes == 0 else 0.0) + (0.22 if strikes == 2 else 0.0)
		if balls == 3 and strikes == 0:
			swing_p = 0.15
	else:
		swing_p = 0.34 - (b.eye + (bm.get("eye", 0.0) if bm_on else 0.0)) * 0.0028 + (0.12 if strikes == 2 else 0.0) + (0.06 if is_breaking else 0.0)
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
	swing_p += (bm.get("swing", 0.0) if bm_on else 0.0)
	var swing := rng.chance(clampf(swing_p, 0.01, 0.98))

	if not swing:
		if in_zone:
			strikes += 1
			ev["call"] = "called"
		else:
			balls += 1
			ev["call"] = "ball"
	else:
		var con: float = b.con + (bm.get("con", 0.0) if bm_on else 0.0)
		var pw: float = b.pow + (bm.get("pow", 0.0) if bm_on else 0.0)
		var platoon := 0.01 if b.bats == "S" else (-0.015 if b.bats == p.throws else 0.015)
		var contact_p := 0.87 + (con - 50) * 0.0045 - (pp - 28) * 0.0062 + platoon - (0.0 if in_zone else 0.22) + (0.08 if mistake else 0.0)
		contact_p += (bm.get("contact", 0.0) if bm_on else 0.0) - (pm.get("whiff", 0.0) if pm_on else 0.0)
		if off_order == "hitRun":
			contact_p += 0.05 + off().tac
		if not rng.chance(clampf(contact_p, 0.3, 0.97)):
			strikes += 1
			ev["call"] = "swinging"
		else:
			var foul_p: float = (0.4 if in_zone else 0.55) + (bm.get("foul", 0.0) if bm_on else 0.0)
			if rng.chance(foul_p):
				ev["call"] = "foul"
				if strikes < 2:
					strikes += 1
			else:
				ev["call"] = "inplay"
				_resolve_in_play(ev, b, pw, pp, in_zone, mistake, shift, stealer, bm, pm)
				return _finish(ev)

	# 폭투/포일
	if _any_runner() and ev["call"] != "foul":
		var catcher := fielder("C")
		var wp_p := (0.007 + maxf(0.0, 55 - ctl) * 0.00025 + maxf(0.0, 50 - catcher.fld) * 0.0002 + (0.004 if is_breaking else 0.0)) * (1.0 - catcher.f_block)
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


## 빠른 경로: step() 과 같은 확률로 공을 계속 던지다가 타석이 끝나거나 폭투가 나면 이벤트를 만들어 돌려준다.
## 화면 연출용 값(구속 표시·공 위치)은 계산하지 않는다. quiet(실황 없음) + 작전 없음일 때만 쓴다.
func _fast_pa(b: SimPlayer, p: SimPlayer, shift: String) -> Dictionary:
	var o := off()
	var d := def()
	var g := rng.g
	var pit_box: Dictionary = d.box[p.id]["pit"]
	var lead: float = fielder("C", d).f_lead if d.lead_any else 0.0
	var visit_ctl := 8.0 if d.visit_pa > 0 else 0.0
	var breaking := p.breaking
	var nb := breaking.size()
	var platoon := 0.01 if b.bats == "S" else (-0.015 if b.bats == p.throws else 0.015)
	var runners := _any_runner()
	while true:
		pitch_no += 1
		var np: int = d.pitch_count.get(p.id, 0) + 1
		d.pitch_count[p.id] = np
		pit_box["np"] += 1
		var pm := pit_mods(p, d)
		var bm := bat_mods(b)
		var pm_on := not pm.is_empty()
		var bm_on := not bm.is_empty()
		# pitcher_eff 와 같은 계산
		var pool: float = 40.0 + p.sta * 0.85 * (1.0 + (pm.get("sta", 0.0) if pm_on else 0.0))
		var over_ := maxf(0.0, np - pool)
		var velo: float = p.velo - over_ * 0.12 + (pm.get("velo", 0.0) if pm_on else 0.0)
		var ctl: float = p.ctl - over_ * 0.45 + (pm.get("ctl", 0.0) if pm_on else 0.0) + lead + visit_ctl
		var stuff: float = p.stuff - over_ * 0.3 + (pm.get("stuff", 0.0) if pm_on else 0.0) + lead
		# 구종
		var pt := "FB"
		var lv := 0
		if nb > 0 and not g.randf() < clampf(0.64 - nb * 0.06 + (0.15 if balls >= 3 else 0.0), 0.35, 0.95):
			var c: Dictionary = rng.weighted(breaking, p.breaking_w)
			pt = c["type"]
			lv = int(c["lv"])
		var is_breaking := pt != "FB"
		var pp: float = (lv * 5.5 + (velo - 115) * 0.55 + 5) if is_breaking else (velo - 115) * 1.2
		if pm_on:
			pp += pm.get("ppBR", 0.0) if is_breaking else pm.get("ppFB", 0.0)
		pp += (stuff - 40) * 0.08
		# 제구
		var want_zone := 0.56
		if balls == 3:
			want_zone += 0.25
		elif balls == 2:
			want_zone += 0.08
		if strikes == 2 and balls < 2:
			want_zone -= 0.2
		if pm_on:
			want_zone += pm.get("zone", 0.0)
			var wild: float = pm.get("wild", 0.0)
			if wild > 0 and g.randf() < wild:
				ctl -= 30
		var in_zone: bool
		var mistake := false
		if g.randf() < clampf(want_zone, 0.1, 0.95):
			in_zone = g.randf() < clampf(0.7 + ctl * 0.0026 - (0.05 if is_breaking else 0.0), 0.55, 0.97)
			if in_zone:
				mistake = g.randf() < clampf(0.13 - ctl * 0.0011 + (pm.get("mistake", 0.0) if pm_on else 0.0), 0.01, 0.2)
		else:
			in_zone = not g.randf() < clampf(0.8 + ctl * 0.0015, 0.75, 0.97)
			if in_zone:
				mistake = g.randf() < 0.4
		# 사구
		if not in_zone and g.randf() < 0.012 + (0.008 if ctl < 40 else 0.0):
			var evh := _new_event(b, p)
			evh["pitchType"] = pt
			evh["call"] = "hbp"
			_walk(evh, "몸에 맞는 공", true)
			return _finish(evh)
		# 스윙
		var swing_p: float
		if in_zone:
			swing_p = 0.63 + (-0.08 if strikes == 0 else 0.0) + (0.22 if strikes == 2 else 0.0)
			if balls == 3 and strikes == 0:
				swing_p = 0.15
		else:
			swing_p = 0.34 - (b.eye + (bm.get("eye", 0.0) if bm_on else 0.0)) * 0.0028 + (0.12 if strikes == 2 else 0.0) + (0.06 if is_breaking else 0.0)
			if balls == 3 and strikes < 2:
				swing_p *= 0.4
		# CPU 감독은 3볼 0스트라이크에서 「기다려」 (MatchAI.orders 와 같게)
		if balls == 3 and strikes == 0:
			swing_p = 0.03
		if mistake:
			swing_p += 0.12
		if bm_on:
			swing_p += bm.get("swing", 0.0)
		var call := ""
		if not g.randf() < clampf(swing_p, 0.01, 0.98):
			if in_zone:
				strikes += 1
				call = "called"
			else:
				balls += 1
				call = "ball"
		else:
			var con: float = b.con + (bm.get("con", 0.0) if bm_on else 0.0)
			var pw: float = b.pow + (bm.get("pow", 0.0) if bm_on else 0.0)
			var contact_p := 0.87 + (con - 50) * 0.0045 - (pp - 28) * 0.0062 + platoon - (0.0 if in_zone else 0.22) + (0.08 if mistake else 0.0)
			if bm_on:
				contact_p += bm.get("contact", 0.0)
			if pm_on:
				contact_p -= pm.get("whiff", 0.0)
			if not g.randf() < clampf(contact_p, 0.3, 0.97):
				strikes += 1
				call = "swinging"
			elif g.randf() < (0.4 if in_zone else 0.55) + (bm.get("foul", 0.0) if bm_on else 0.0):
				if strikes < 2:
					strikes += 1
				continue
			else:
				var evp := _new_event(b, p)
				evp["pitchType"] = pt
				evp["call"] = "inplay"
				_resolve_in_play(evp, b, pw, pp, in_zone, mistake, shift, null, bm, pm)
				return _finish(evp)
		# 폭투/포일 (볼·스트라이크일 때)
		var wp := false
		if runners:
			var catcher := fielder("C")
			var wp_p := (0.007 + maxf(0.0, 55 - ctl) * 0.00025 + maxf(0.0, 50 - catcher.fld) * 0.0002 + (0.004 if is_breaking else 0.0)) * (1.0 - catcher.f_block)
			wp = g.randf() < wp_p
		if not wp and strikes < 3 and balls < 4:
			continue
		var ev := _new_event(b, p)
		ev["pitchType"] = pt
		ev["call"] = call
		if wp:
			ev["wildPitch"] = true
			_advance_all(ev, 1, false)
		if strikes >= 3:
			var bl: Dictionary = o.box[b.id]["bat"]
			bl["pa"] += 1
			bl["ab"] += 1
			bl["so"] += 1
			pit_box["so"] += 1
			_add_out(ev, b.id, 0)
			ev["paResult"] = "루킹 삼진" if call == "called" else "헛스윙 삼진"
			return _finish(ev, true)
		if balls >= 4:
			_walk(ev, "볼넷")
			return _finish(ev)
		return _finish(ev, false)
	return {}


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


func _resolve_bunt(ev: Dictionary, b: SimPlayer, bm: Dictionary, pp: float, in_zone: bool, order: String, shift: String, squeeze_runner) -> Dictionary:
	if not in_zone and order != "squeeze" and rng.chance(0.75):
		balls += 1
		ev["call"] = "ball"
		if balls >= 4:
			_walk(ev, "볼넷")
			ev["text"] = _pitch_text(ev) + " — 볼넷"
			return _finish(ev)
		ev["text"] = _pitch_text(ev) + " (번트 자세에서 배트를 거둠)"
		return _finish(ev, false)
	var good := bunt_good(b, bm, pp, in_zone, shift)
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
	var success: bool = rng.next() < good
	if order == "safetyBunt" and success:
		var hit_p := safety_hit_prob(b, bm, shift)
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


func _resolve_in_play(ev: Dictionary, b: SimPlayer, pw: float, pp: float, in_zone: bool, mistake: bool, shift: String, stealer, bm: Dictionary, pm: Dictionary) -> void:
	var bm_on := not bm.is_empty()
	var pm_on := not pm.is_empty()
	var o := off()
	var d := def()
	var p := pitcher()
	var bl: Dictionary = o.box[b.id]["bat"]
	var pl: Dictionary = d.box[p.id]["pit"]

	var evel := 113 + pw * 0.42 + rng.gauss() * 13 - (pp - 28) * 0.35 + (10.0 if mistake else 0.0) - (0.0 if in_zone else 10.0)
	evel += (bm.get("evel", 0.0) if bm_on else 0.0)
	var gb_rate: float = (pm.get("gbRate", 0.0) if pm_on else 0.0)
	var gb_w := 0.44 - (pw - 50) * 0.002 + gb_rate
	var fb_w := 0.27 + (pw - 50) * 0.002 - gb_rate * 0.6
	if ev["pitchType"] in ["SI", "FK"]:
		gb_w += 0.08
		fb_w -= 0.05
	var type: String = rng.weighted(["GB", "LD", "FB", "PU"], [gb_w, 0.21 + (bm.get("ld", 0.0) if bm_on else 0.0), fb_w, maxf(0.01, 0.08 + (bm.get("pu", 0.0) if bm_on else 0.0))])
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
		var hit_p: float = 0.25 + (evel - 130) * 0.0045 + (b.spd - 50) * 0.0025 - (dv - 50) * 0.0025 + (bm.get("gbHit", 0.0) if bm_on else 0.0)
		if absf(angle) < 7:
			hit_p += 0.06
		if shift == "infieldIn":
			hit_p += 0.08
		dist = rng.frange(28, 40)
		if rng.chance(clampf(hit_p, 0.05, 0.6)):
			result = "2B" if absf(angle) > 36 and evel > 140 and rng.chance(0.4) else "1B"
			dist = 80.0 if result == "2B" else 55.0
		elif rng.chance(clampf(0.05 + (55 - dv) * 0.001 + fielder(fpos).f_err, 0.01, 0.14) * def().err_mul):
			result = "E"
		elif bases[0] != null and outs < 2 and not runner_on_first_stealing and rng.chance(clampf(0.42 - (b.spd - 50) * 0.004 + (dv - 50) * 0.003 + (bm.get("dp", 0.0) if bm_on else 0.0), 0.05, 0.75)):
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
		if rng.chance((0.02 + fielder(fpos).f_err * 0.5) * def().err_mul):
			result = "E"
			caught = false
	else:
		fpos = "LF" if angle < -15 else ("RF" if angle > 15 else "CF")
		dist = (evel - 55) * 0.95 + rng.gauss() * 6 + (-12.0 if type == "LD" else 0.0) + (bm.get("dist", 0.0) if bm_on else 0.0) + (pm.get("hrAllow", 0.0) if pm_on else 0.0)
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
				if rng.chance(clampf(0.02 + (50 - dv) * 0.0006 + fielder(fpos).f_err, 0.003, 0.08) * def().err_mul):
					result = "E"
					caught = false
			elif dist > 88:
				result = "3B" if b.spd > 60 and rng.chance(0.25) else "2B"
			else:
				result = "2B" if dist > 72 and rng.chance(0.35) else "1B"
		if caught and result == "OUT" and outs < 2 and r3 != null and type == "FB":
			var of := fielder(fpos)
			var of_arm := of.arm + of.f_arm
			var sf_p: float = 0.5 + (dist - 60) * 0.018 + (o.by_id[r3["id"]].spd - 50) * 0.006 - (of_arm - 50) * 0.005
			if dist > 55 and rng.chance(clampf(sf_p, 0.05, 0.97)):
				result = "SF"

	ev["batted"] = {"type": type, "angle": angle, "dist": dist, "result": result, "fielder": fpos, "caught": caught}
	var pos_name: String = "" if quiet else PlayerUtil.POS_KO[fpos] # 실황 문구용 (quiet 에서는 만들지 않음)
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
			ev["paResult"] = result if quiet else "%s %s" % [_dir_hr(angle), "만루 홈런" if ev["runs"] >= 4 else "홈런"]
			ev["text"] = "" if quiet else "%s!! %s의 한 방!" % [ev["paResult"], b.name]
		"3B":
			bl["ab"] += 1
			bl["h"] += 1
			bl["d3"] += 1
			o.hits += 1
			pl["h"] += 1
			_advance_all(ev, 3, false, b.id)
			_move_batter(ev, b.id, 3, true)
			ev["paResult"] = result if quiet else "%s 3루타" % _dir_xbh(angle)
			ev["text"] = "" if quiet else ev["paResult"] + "!"
		"2B":
			bl["ab"] += 1
			bl["h"] += 1
			bl["d2"] += 1
			o.hits += 1
			pl["h"] += 1
			_advance_hit(ev, 2, b.id, fpos, stealer != null)
			_move_batter(ev, b.id, 2, true)
			ev["paResult"] = result if quiet else "%s 2루타" % _dir_xbh(angle)
			ev["text"] = "" if quiet else ev["paResult"] + "!"
		"1B":
			bl["ab"] += 1
			bl["h"] += 1
			o.hits += 1
			pl["h"] += 1
			var infield := type == "GB" and dist < 45
			_advance_hit(ev, 0 if infield else 1, b.id, fpos, stealer != null)
			_move_batter(ev, b.id, 1, true)
			ev["paResult"] = result if quiet else "내야 안타" if infield else ("%s 땅볼 안타" % _dir_single(angle) if type == "GB" else "%s 안타" % _dir_single(angle))
			ev["text"] = "" if quiet else ev["paResult"] + "!"
		"E":
			bl["ab"] += 1
			d.errors += 1
			var f := fielder(fpos)
			if d.box.has(f.id):
				d.box[f.id]["bat"]["e"] += 1
			_advance_forced(ev, b.id, false, false)
			ev["paResult"] = result if quiet else "%s 실책" % pos_name
			ev["text"] = "" if quiet else "%s 실책! 타자 출루" % pos_name
		"DP":
			bl["ab"] += 1
			var r1: Dictionary = bases[0]
			bases[0] = null
			ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": -1})
			outs += 1
			_add_out(ev, b.id, 0)
			if not _half_over():
				_advance_others_on_ground(ev, shift)
			ev["paResult"] = result if quiet else "%s 앞 병살타" % pos_name
			ev["text"] = "" if quiet else ev["paResult"]
		"FC":
			bl["ab"] += 1
			var r1f: Dictionary = bases[0]
			bases[0] = null
			ev["moves"].append({"runnerId": r1f["id"], "from": 1, "to": -1})
			outs += 1
			if not _half_over():
				_advance_others_on_ground(ev, shift)
				_move_batter(ev, b.id, 1, false)
			ev["paResult"] = result if quiet else "%s 땅볼 (선행주자 아웃)" % pos_name
			ev["text"] = "" if quiet else ev["paResult"]
		"SF":
			bl["sf"] += 1
			_add_out(ev, b.id, 0)
			var rr: Dictionary = bases[2]
			bases[2] = null
			ev["moves"].append({"runnerId": rr["id"], "from": 3, "to": 4})
			_score_runner(ev, rr, b.id, true)
			ev["paResult"] = result if quiet else "%s 희생플라이" % pos_name
			ev["text"] = "" if quiet else ev["paResult"] + "! 3루 주자 홈인"
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
			ev["paResult"] = result if quiet else "%s %s" % [pos_name, kind]
			ev["text"] = "" if quiet else ev["paResult"]


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


## 주력 + 주루 능력 (확률 가산을 주력 환산: 0.009 당 1)
func _run_spd(o: TeamSide, r: Dictionary) -> float:
	var sp: SimPlayer = o.by_id[r["id"]]
	return sp.spd + sp.f_run / 0.009


func _advance_hit(ev: Dictionary, kind: int, batter_id: String, fpos: String, running: bool) -> void:
	var o := off()
	var f := fielder(fpos)
	var arm := f.arm + f.f_arm
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
			var pr: float = 0.4 + (_run_spd(o, r1) - 50) * 0.009 - (arm - 50) * 0.004 + (0.35 if running else 0.0) + (0.15 if outs == 2 else 0.0)
			if rng.chance(clampf(pr, 0.05, 0.97)):
				ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 4})
				_score_runner(ev, r1, batter_id, true)
			else:
				ev["moves"].append({"runnerId": r1["id"], "from": 1, "to": 3})
				bases[2] = r1
		return
	if r2 != null:
		var pr2: float = 0.55 + (_run_spd(o, r2) - 50) * 0.009 - (arm - 50) * 0.005 + (0.2 if outs == 2 else 0.0) + (0.2 if running else 0.0)
		if rng.chance(clampf(pr2, 0.1, 0.97)):
			ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 4})
			_score_runner(ev, r2, batter_id, true)
		else:
			ev["moves"].append({"runnerId": r2["id"], "from": 2, "to": 3})
			bases[2] = r2
	if r1 != null:
		var pr1: float = 0.22 + (_run_spd(o, r1) - 50) * 0.007 - (arm - 50) * 0.003 + (0.1 if fpos == "RF" else 0.0) + (0.4 if running else 0.0)
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
	var success := rng.chance(steal_prob(base))
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
		if d.visit_pa > 0:
			d.visit_pa -= 1
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
