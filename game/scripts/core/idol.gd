class_name Idol
extends RefCounted
## 동경 시스템 (web/src/core/idol.ts 이식)
##  고교 선수 일부는 '이름이 같고 성이 다른' 프로 선수를 동경한다.
##  - 동경 선수 스타일 능력치 성장 보너스 (×1.25, 동경도 50 이상 ×1.4)
##  - 프로 선수의 활약 소식 → 동경도·컨디션 상승
##  - 동경도 70: 비결 전수 (대표 특수능력) / 100: 꿈의 만남 (능력 대폭 상승)
##  - 드래프트에서 동경 선수의 구단에 지명되면 특별 이벤트

const NEWS := {
	"bat": ["3경기 연속 홈런!", "끝내기 안타로 팀을 구했다!", "4안타 맹타를 휘둘렀다!", "결승 2루타를 터뜨렸다!", "멀티 홈런 경기!", "월간 MVP에 선정됐다!"],
	"run": ["한 경기 도루 3개!", "시즌 30도루 돌파!", "빠른 발로 결승 득점!"],
	"def": ["몸을 날리는 호수비로 실점을 막았다!", "보살 2개로 흐름을 끊었다!", "무실책 행진을 이어가고 있다!"],
	"pit": ["완봉승을 거뒀다!", "12탈삼진 호투!", "시즌 10승 달성!", "157km 강속구로 삼진 퍼레이드!", "7이닝 무실점 역투!", "세이브 행진을 이어가고 있다!"],
}


## 동경하는 프로 선수 (없으면 빈 Dictionary)
static func idol_of(state: Dictionary, p: Dictionary) -> Dictionary:
	var id = p.get("idolId")
	if id == null:
		return {}
	for x in state["pros"]:
		if x["id"] == id:
			return x
	return {}


static func pro_name(pro: Dictionary) -> String:
	return pro["sur"] + pro["given"]


static func pro_team_name(state: Dictionary, pro: Dictionary) -> String:
	for t in state["proTeams"]:
		if t["id"] == pro["teamId"]:
			return t["name"]
	return ""


static func label(state: Dictionary, p: Dictionary) -> String:
	var idol := idol_of(state, p)
	if idol.is_empty():
		return ""
	return "%s %s (%s)%s" % [pro_team_name(state, idol), pro_name(idol), GameData.styles()[idol["style"]]["desc"], " · 은퇴" if idol.get("retired", false) else ""]


static func _news_for(rng: Rng, pro: Dictionary) -> String:
	var style: String = pro["style"]
	var cat := "bat"
	if GameData.styles()[style]["pitcher"]:
		cat = "pit"
	elif style == "준족":
		cat = rng.pick(["run", "bat"])
	elif style in ["명수비", "강견"]:
		cat = rng.pick(["def", "bat"])
	return rng.pick(NEWS[cat])


static func weekly_pro_news(state: Dictionary, rng: Rng) -> void:
	var m := Cal.month_of(state["date"])
	if m < 4 or m > 10:
		return
	var active: Array = state["pros"].filter(func(p): return not p.get("retired", false))
	var users := []
	for id in state["teams"][state["userTeamId"]]["playerIds"]:
		var p = state["players"].get(id)
		if p != null and p.get("idolId") != null:
			users.append(p)
	var idol_ids := {}
	for p in users:
		idol_ids[p["idolId"]] = true
	var pro = null
	if not idol_ids.is_empty() and rng.chance(0.6):
		var pick_id = rng.pick(idol_ids.keys())
		for x in active:
			if x["id"] == pick_id:
				pro = x
	else:
		pro = rng.pick(active)
	if pro == null:
		return
	state["news"].append({"date": state["date"], "kind": "idol", "text": "[프로야구] %s %s, %s" % [pro_team_name(state, pro), pro_name(pro), _news_for(rng, pro)]})
	for p in users:
		if p["idolId"] != pro["id"]:
			continue
		p["idolBond"] = clampi(p["idolBond"] + rng.irange(3, 7), 0, 100)
		if rng.chance(0.5):
			p["cond"] = clampi(p["cond"] + 1, -2, 2)
		state["news"].append({"date": state["date"], "kind": "idol", "text": "%s: \"%s 선배처럼 되고 싶어!\" (동경도 %d)" % [PlayerUtil.full_name(p), pro["given"], p["idolBond"]]})


## 동경도 단계 이벤트 → 팝업 Dictionary 또는 null
static func check_milestones(state: Dictionary, p: Dictionary):
	var idol := idol_of(state, p)
	if idol.is_empty():
		return null
	var info: Dictionary = GameData.styles()[idol["style"]]
	var flags := int(p.get("idolFlags", 0))
	var n := PlayerUtil.full_name(p)
	if p["idolBond"] >= 70 and not (flags & 1):
		p["idolFlags"] = flags | 1
		var had: bool = Abilities.cannot_learn(p, info["ability"]) != ""
		if not had:
			Abilities.learn(p, info["ability"])
		return {"kind": "idol", "playerId": p["id"], "title": "동경의 비결",
			"body": "%s %s의 경기 영상을 수백 번 돌려 보며 그 비결을 깨달았다!\n%s" % [Text.josa(n, "은/는"), pro_name(idol),
				"가지고 있던 특수능력이 더욱 단단해졌다." if had else "특수능력 「%s」 습득!" % GameData.ability_name(info["ability"])]}
	if p["idolBond"] >= 100 and not (flags & 2):
		p["idolFlags"] = int(p.get("idolFlags", 0)) | 2
		var r: Dictionary = p["r"]
		var cap: Dictionary = p["cap"]
		for k in info["stats"]:
			if k == "velo":
				r["velo"] = mini(int(cap["velo"]) + 2, int(r["velo"]) + 3)
				cap["velo"] += 2
			elif k == "breaking":
				for x in r["pitches"]:
					if x["type"] != "FB":
						x["lv"] = mini(7, int(x["lv"]) + 1)
						break
			else:
				r[k] = mini(99, int(r[k]) + 5)
				cap[k] = mini(99, int(cap[k]) + 5)
		p["cond"] = 2
		# 동경 선수의 대표 능력이 금특으로 진화
		var gold := Abilities.gold_of(info["ability"])
		var evolve: bool = gold != "" and info["ability"] in p["abilities"] and Abilities.cannot_learn(p, gold) == ""
		if evolve:
			Abilities.learn(p, gold)
		return {"kind": "idol", "playerId": p["id"], "title": "꿈의 만남",
			"body": "%s의 %s 모교 방문 행사로 근처에 왔다!\n\"%s? 나랑 이름이 같네. 열심히 해!\"\n%s 사인볼을 품에 안고 누구보다 늦게까지 연습했다. (능력 대폭 상승)%s" % [
				pro_team_name(state, idol), Text.josa(pro_name(idol), "이/가"), p["given"], Text.josa(n, "은/는"),
				"\n「%s」이(가) 금특 「%s」(으)로 진화!" % [Abilities.name_of(info["ability"]), Abilities.name_of(gold)] if evolve else ""]}
	return null


static func pro_season_end(state: Dictionary, rng: Rng) -> void:
	for pro in state["pros"]:
		if pro.get("retired", false):
			continue
		var age: int = int(state["year"]) - int(pro["birthYear"])
		if GameData.styles()[pro["style"]]["pitcher"]:
			pro["line"] = "%d승 %d패 ERA %.2f %dK" % [rng.irange(3, 16), rng.irange(3, 12), 2.2 + rng.next() * 3.2, rng.irange(60, 190)]
		else:
			var hr := rng.irange(18, 42) if pro["style"] == "파워히터" else rng.irange(2, 20)
			pro["line"] = "타율 %s %d홈런 %d타점%s" % [("%.3f" % (0.24 + rng.next() * 0.1)).trim_prefix("0"), hr, rng.irange(30, 110), (" %d도루" % rng.irange(20, 50)) if pro["style"] == "준족" else ""]
		if age >= 37 and rng.chance((age - 35) * 0.15):
			pro["retired"] = true
			state["news"].append({"date": state["date"], "kind": "idol", "text": "[프로야구] %s %s 현역 은퇴 발표" % [pro_team_name(state, pro), pro_name(pro)]})
