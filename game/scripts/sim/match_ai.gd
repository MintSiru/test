class_name MatchAI
extends RefCounted
## CPU 감독 AI (web/src/sim/ai.ts 이식). 사용자 팀 '위임' 시에도 사용.

## 같은 타석 동안 작전을 유지하기 위한 키 (정수)
static func _pa_key(m: MatchEngine) -> int:
	var bs := (1 if m.bases[0] != null else 0) | (2 if m.bases[1] != null else 0) | (4 if m.bases[2] != null else 0)
	return ((((m.inning * 2 + (1 if m.top else 0)) * 10 + m.off().batter_idx) * 4 + m.outs) * 8 + bs)


static func _hitter(p: SimPlayer) -> float:
	return p.con + p.pow


static func _decide_pa(m: MatchEngine) -> Dictionary:
	var key: int = _pa_key(m)
	var cached := m.ai_cache
	if not cached.is_empty() and cached["key"] == key:
		return cached
	return _decide_new(m, key)


static func _decide_new(m: MatchEngine, key: int) -> Dictionary:
	var rng := m.rng
	var b := m.batter()
	var o := m.off()
	var diff := m.score_diff_for(o)
	var late := m.inning >= 7
	var close := diff >= -2 and diff <= 1
	var r1 = m.bases[0]
	var r2 = m.bases[1]
	var r3 = m.bases[2]
	var off_order := "normal"
	var weak := _hitter(b) < 105 and not o.batter_idx in [2, 3, 4]
	if r3 == null and (r1 != null or r2 != null) and m.outs == 0 and (weak or (late and close)) and rng.chance(0.35):
		off_order = "bunt"
	elif r3 != null and m.outs < 2 and late and close and weak and rng.chance(0.2):
		off_order = "squeeze"
	elif r1 != null and r2 == null and m.outs < 2 and rng.chance(maxf(0.0, (o.by_id[r1["id"]].spd - 52) * 0.02)):
		off_order = "steal"
	elif r1 != null and r2 == null and m.outs < 2 and _hitter(b) > 100 and rng.chance(0.04):
		off_order = "hitRun"

	var pitch := "normal"
	var shift := "normal"
	var def_diff := -diff
	if r1 == null and (r2 != null or r3 != null) and late and def_diff >= 0 and def_diff <= 1 and _hitter(b) >= 145:
		var nxt: SimPlayer = o.by_id[o.order[(o.batter_idx + 1) % 9]]
		if _hitter(nxt) < _hitter(b) - 25 and rng.chance(0.5):
			pitch = "ibb"
	if r3 != null and m.outs < 2 and late and def_diff >= -1 and def_diff <= 2:
		shift = "infieldIn"
	elif r1 != null and r3 == null and m.outs == 0 and weak and rng.chance(0.5):
		shift = "buntShift"
	elif _hitter(b) > 150 and rng.chance(0.3):
		shift = "deep"
	var res := {"key": key, "off": off_order, "pitch": pitch, "shift": shift}
	m.ai_cache = res
	return res


static func offense(m: MatchEngine) -> String:
	var d := _decide_pa(m)
	if m.balls == 3 and m.strikes == 0 and d["off"] == "normal":
		return "wait"
	if d["off"] in ["bunt", "squeeze"] and m.strikes == 2:
		return "normal"
	return d["off"]


static func defense(m: MatchEngine) -> Dictionary:
	var d := _decide_pa(m)
	var pitch: String = d["pitch"]
	if pitch == "ibb" and not (m.balls == 0 and m.strikes == 0):
		pitch = "normal"
	return {"pitch": pitch, "shift": d["shift"]}


static func orders(m: MatchEngine) -> Dictionary:
	var d := _decide_pa(m)
	var off: String = d["off"]
	if m.balls == 3 and m.strikes == 0 and off == "normal":
		off = "wait"
	elif (off == "bunt" or off == "squeeze") and m.strikes == 2:
		off = "normal"
	var pitch: String = d["pitch"]
	if pitch == "ibb" and not (m.balls == 0 and m.strikes == 0):
		pitch = "normal"
	return {"off": off, "pitch": pitch, "shift": d["shift"]}


static func reliever_score(p: SimPlayer) -> float:
	return (100.0 if p.pos == "P" else 0.0) + (p.velo - 110) * 1.5 + p.ctl + p.stuff * 0.6


## 구원 후보 (미사용·등판 가능, 능력순)
static func relievers(side: MatchEngine.TeamSide) -> Array:
	var list := side.players.filter(func(p): return not p.id in side.used and p.can_pitch)
	list.sort_custom(func(a, b): return reliever_score(a) > reliever_score(b))
	return list


## 타석 시작 시 투수 교체 판단
static func pitching_change(m: MatchEngine, side: MatchEngine.TeamSide) -> bool:
	if m.balls != 0 or m.strikes != 0:
		return false
	var p: SimPlayer = side.by_id[side.pitcher_id]
	var np: int = side.pitch_count.get(p.id, 0)
	# 피로 = 투구수 - 스태미나 한도 (pitcher_eff 와 같은 계산, 스태미나 능력은 조건 없는 효과)
	var over_ := maxf(0.0, np - (40.0 + p.sta * 0.85 * (1.0 + p.fx_pit.get("sta", 0.0))))
	var runs: int = side.box[p.id]["pit"]["r"]
	var must: bool = np >= m.rules["pitchLimit"]
	var tired: bool = over_ > 10 and over_ > 10 + m.rng.next() * 10
	var shelled := runs >= 6 and m.inning <= 7
	if not must and not tired and not shelled:
		return false
	var pen := relievers(side)
	var cand = null
	for x in pen:
		if x.pos == "P":
			cand = x
			break
	if cand == null and must and not pen.is_empty():
		cand = pen[0]
	if cand == null:
		return false
	m.change_pitcher(side, cand.id)
	return true


## 위기 때 마운드 방문 (타석 시작 시)
static func mound_visit(m: MatchEngine, side: MatchEngine.TeamSide) -> bool:
	if m.balls != 0 or m.strikes != 0 or side.visit_pa > 0:
		return false
	if (m.bases[1] == null and m.bases[2] == null) or m.outs >= 2 or m.inning < 5:
		return false
	if absi(m.home.score - m.away.score) > 3 or not m.rng.chance(0.35):
		return false
	return m.mound_visit(side)


static func play_out(m: MatchEngine) -> void:
	var guard := 0
	while not m.over and guard < 5000:
		guard += 1
		if not pitching_change(m, m.def()):
			mound_visit(m, m.def())
		m.step(orders(m))


static func forget(m: MatchEngine) -> void:
	m.ai_cache = {}
