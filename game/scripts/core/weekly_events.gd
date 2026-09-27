class_name WeeklyEvents
extends RefCounted
## 주간 랜덤 이벤트 (web/src/core/events.ts 이식). 중요한 것만 팝업, 나머지는 뉴스.


static func _grow_focus(state: Dictionary, p: Dictionary, pts: float, rng: Rng) -> void:
	var fs := Training.focus_stats(p)
	for k in fs:
		Training.apply_exp(p, k, pts * fs[k], Training.growth_mult(p, k, state["pros"]), rng)


## 반환: {news?, popup?} 또는 {}
static func roll(state: Dictionary, roster: Array, rng: Rng) -> Dictionary:
	if roster.is_empty() or not rng.chance(0.4):
		return {}
	var p: Dictionary = rng.pick(roster)
	var date: String = state["date"]
	var n := PlayerUtil.full_name(p)
	var has_idol := roster.any(func(x): return x.get("idolId") != null)
	var kind: String = rng.weighted(
		["selfTrain", "slump", "hot", "ob", "paper", "talent", "minorInjury", "rival", "lunch", "idolCopy"],
		[20, 10, 12, 6 if not state["alumni"].is_empty() else 0, 6, 2, 6, 10, 8, 12 if has_idol else 0])
	match kind:
		"selfTrain":
			_grow_focus(state, p, 6, rng)
			return {"news": {"date": date, "kind": "good", "text": "%s 밤늦게까지 자율 훈련에 매진했다. (능력 상승)" % Text.josa(n, "이/가")}}
		"slump":
			p["cond"] = clampi(p["cond"] - 2, -2, 2)
			return {"news": {"date": date, "kind": "bad", "text": "%s, 요즘 뭘 해도 잘 안 풀린다... (컨디션 하락)" % n}}
		"hot":
			p["cond"] = 2
			return {"news": {"date": date, "kind": "good", "text": "%s, 공이 수박만 하게 보인다! (절호조)" % n}}
		"ob":
			for x in roster:
				if rng.chance(0.5):
					x["cond"] = clampi(x["cond"] + 1, -2, 2)
			return {"news": {"date": date, "kind": "good", "text": "졸업생 선배들이 간식을 들고 격려 방문했다. 팀 분위기 상승!"}}
		"paper":
			state["reputation"] = clampi(state["reputation"] + 1, 0, 100)
			return {"news": {"date": date, "kind": "info", "text": "지역 신문에 우리 야구부 기사가 실렸다. (명성 +1)"}}
		"talent":
			if p["talent"] >= 5:
				return {}
			p["talent"] += 1
			for k in p["cap"]:
				p["cap"][k] = p["cap"][k] + 3 if k == "velo" else mini(99, int(p["cap"][k]) + 6)
			return {"popup": {"kind": "good", "playerId": p["id"], "title": "재능 개화", "body": "%s 무언가를 깨달은 듯하다!\n재능이 ★%d(으)로 올랐다." % [Text.josa(n, "이/가"), p["talent"]]}}
		"minorInjury":
			if p["injury"] > 0:
				return {}
			p["injury"] = rng.irange(3, 8)
			return {"news": {"date": date, "kind": "bad", "text": "%s, 연습 중 발목을 삐끗했다. (부상 %d일)" % [n, p["injury"]]}}
		"rival":
			var other = null
			for x in roster:
				if x != p and x["pos"] == p["pos"]:
					other = x
					break
			if other == null:
				return {}
			_grow_focus(state, p, 3, rng)
			_grow_focus(state, other, 3, rng)
			return {"news": {"date": date, "kind": "good", "text": "%s %s 주전 자리를 두고 불꽃 튀는 경쟁 중! (둘 다 능력 상승)" % [Text.josa(n, "과/와"), Text.josa(PlayerUtil.full_name(other), "이/가")]}}
		"lunch":
			for x in roster:
				x["fatigue"] = clampf(x["fatigue"] - 10, 0, 100)
			return {"news": {"date": date, "kind": "good", "text": "매니저가 도시락을 싸 왔다. 모두 기운이 난다! (피로 회복)"}}
		"idolCopy":
			var fans := roster.filter(func(x): return x.get("idolId") != null)
			var q: Dictionary = rng.pick(fans)
			var idol := Idol.idol_of(state, q)
			if idol.is_empty():
				return {}
			q["idolBond"] = clampi(q["idolBond"] + 5, 0, 100)
			return {"news": {"date": date, "kind": "idol", "text": "%s %s의 폼을 따라 하고 있다. \"이름도 같으니까 나도 할 수 있어!\" (동경도 %d)" % [Text.josa(PlayerUtil.full_name(q), "이/가"), Idol.pro_name(idol), q["idolBond"]]}}
	return {}
