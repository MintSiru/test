class_name TeamMood
extends RefCounted
## 주장과 팀 분위기 (Godot 전용)
##  - 팀 분위기 0~100 (state.teamMood, 처음 50). 이기면 오르고 지면 내려가며, 연승·연패는 더 크게.
##    매주 「50 + 주장 보너스」 쪽으로 15% 돌아간다.
##  - 분위기 70 이상이면 매주 선수 컨디션이 오를 가능성, 30 이하면 떨어질 가능성.
##  - 주장: 은퇴식 직후 다음 해 3학년(지금 2학년) 중에서, 새 게임은 3학년 중에서 고른다 (선택 팝업, 기본값 1순위).
##    주장 보너스 = 3 + 성격(열혈 4 · 낙천 3 · 노력파 2 · 냉정 1) + 종합 능력치(50 넘는 10마다 1, 최대 4)

const LEAD_BONUS := {"열혈": 4, "낙천": 3, "노력파": 2, "냉정": 1}
const LABELS := [[80, "최고"], [62, "좋음"], [38, "보통"], [20, "나쁨"], [-1, "최악"]]


static func mood(state: Dictionary) -> int:
	return int(state.get("teamMood", 50))


static func change(state: Dictionary, delta: int) -> void:
	state["teamMood"] = clampi(mood(state) + delta, 0, 100)


static func label(m: int) -> String:
	for x in LABELS:
		if m > int(x[0]):
			return x[1]
	return "최악"


static func captain(state: Dictionary) -> Dictionary:
	var id = state.get("captainId")
	if id == null or not state["players"].has(id):
		return {}
	var p: Dictionary = state["players"][id]
	return p if p["teamId"] == state["userTeamId"] else {}


static func captain_bonus(p: Dictionary) -> int:
	if p.is_empty():
		return 0
	return 3 + int(LEAD_BONUS.get(p["personality"], 0)) + clampi((PlayerUtil.overall(p) - 50) / 10, 0, 4)


## 경기 뒤 (우리 경기만). 연습 경기는 절반
static func after_match(state: Dictionary, won: bool, drew: bool, official: bool) -> void:
	var st := int(state.get("streak", 0))
	if drew:
		st = 0
	elif won:
		st = maxi(1, st + 1) if st >= 0 else 1
	else:
		st = mini(-1, st - 1) if st <= 0 else -1
	state["streak"] = st
	var d := 0
	if won:
		d = 4 + (2 if st >= 3 else 0)
	elif not drew:
		d = -4 - (2 if st <= -3 else 0)
	change(state, d if official else d / 2)


## 주간: 기준점으로 돌아가기, 컨디션 영향
static func week(state: Dictionary, roster: Array, rng: Rng) -> void:
	var target := 50 + captain_bonus(captain(state)) + int(Manager.bonus(state, "motivator"))
	var m := mood(state)
	state["teamMood"] = clampi(m + roundi((target - m) * 0.15), 0, 100)
	for p in roster:
		if m >= 70 and rng.chance((m - 65) / 100.0):
			p["cond"] = mini(2, int(p["cond"]) + 1)
		elif m <= 30 and rng.chance((35 - m) / 100.0):
			p["cond"] = maxi(-2, int(p["cond"]) - 1)


## 주장 선출 팝업. grade = 후보 학년 (은퇴식 직후 2, 새 게임 3)
static func captain_event(state: Dictionary, grade: int) -> void:
	var cand: Array = WorldGen.team_players(state, state["userTeamId"]).filter(func(p): return PlayerUtil.grade(p, state["year"]) == grade)
	if cand.is_empty():
		state.erase("captainId")
		return
	cand.sort_custom(func(a, b): return _score(a) > _score(b))
	cand = cand.slice(0, 3)
	state["captainId"] = cand[0]["id"]
	var opts := []
	var lines := []
	for p in cand:
		opts.append([p["id"], "%s (%s · %s)" % [PlayerUtil.full_name(p), PlayerUtil.POS_KO[p["pos"]], p["personality"]]])
		lines.append("· %s — %s, 종합 %d, 분위기 +%d" % [PlayerUtil.full_name(p), p["personality"], PlayerUtil.overall(p), captain_bonus(p)])
	state["popups"].append({"kind": "choice", "choice": "captain", "title": "새 주장 선출", "options": opts,
		"body": "%s 이끌 주장을 뽑자.\n주장은 팀 분위기의 기준을 끌어올린다 (성격이 열혈·낙천이면 더).\n\n%s" % ["다음 시즌 야구부를" if grade == 2 else "야구부를", "\n".join(lines)]})


static func _score(p: Dictionary) -> float:
	return PlayerUtil.overall(p) + int(LEAD_BONUS.get(p["personality"], 0)) * 3.0


static func set_captain(state: Dictionary, id: String) -> String:
	var p = state["players"].get(id)
	if p == null:
		return ""
	state["captainId"] = id
	var n := PlayerUtil.full_name(p)
	state["news"].append({"date": state["date"], "kind": "good", "text": "%s 새 주장이 됐다." % Text.josa(n, "이/가")})
	return "%s 주장 완장을 찼다!\n\"감독님, 저만 믿으세요!\"\n(팀 분위기 기준 +%d)" % [Text.josa(n, "이/가"), captain_bonus(p)]
