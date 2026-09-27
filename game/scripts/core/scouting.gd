class_name Scouting
extends RefCounted
## 스카우트 (web/src/core/scouting.ts 이식)
## 드래프트 후 중학 유망주 명단 공개 → 주 1회 행동력으로 방문 → 3월 입학식 때 의향 비례 확률로 입학


static func generate_prospects(state: Dictionary, rng: Rng) -> void:
	var team: Dictionary = state["teams"][state["userTeamId"]]
	var rivals := []
	for g in GameData.schools()["groups"]:
		for s in g["schools"]:
			if s["name"] != team["name"]:
				rivals.append(s["name"])
	var out := []
	for i in 12:
		var quality := clampf(35 + state["reputation"] * 0.35 + rng.gauss() * 18 + (15.0 if i < 2 else 0.0), 10, 100)
		var player := PlayerUtil.gen_player(rng, {"id": WorldGen.uid(state, "p"), "teamId": "", "enrollYear": int(state["year"]) + 1, "year": int(state["year"]) + 1,
			"quality": quality, "province": team["province"], "pros": state["pros"], "idolChance": 0.3})
		var idol := Idol.idol_of(state, player)
		var alumni_bonus := 25 if not idol.is_empty() and idol.get("alumniOf") == team["id"] else 0
		out.append({"id": player["id"], "player": player,
			"interest": clampi(roundi(5 + state["reputation"] * 0.3 + rng.irange(0, 20) - (quality - 50) * 0.3 + alumni_bonus), 0, 90),
			"visits": 0, "revealed": 0, "rival": rng.pick(rivals)})
	out.sort_custom(func(a, b): return a["player"]["talent"] > b["player"]["talent"])
	state["prospects"] = out


static func visit(state: Dictionary, id: String, rng: Rng) -> String:
	var pr = null
	for x in state["prospects"]:
		if x["id"] == id:
			pr = x
	if pr == null:
		return ""
	if state["scoutPoints"] <= 0:
		return "스카우트 행동력이 부족하다."
	state["scoutPoints"] -= 1
	pr["visits"] += 1
	pr["revealed"] = mini(3, int(pr["revealed"]) + 1)
	var gain := roundi(10 + state["reputation"] * 0.15 + rng.irange(0, 8) - pr["visits"] * 1.5)
	pr["interest"] = clampi(pr["interest"] + maxi(3, gain), 0, 100)
	return "%s 만나고 왔다. 입학 의향 %d%%" % [Text.josa(PlayerUtil.full_name(pr["player"]), "을/를"), pr["interest"]]


static func enroll(state: Dictionary, rng: Rng) -> Array:
	var team: Dictionary = state["teams"][state["userTeamId"]]
	var joined := []
	# 선수단은 최대 40명 정도로 유지한다 (의향 높은 유망주부터)
	var room := maxi(0, 40 - team["playerIds"].size())
	var sorted: Array = state["prospects"].duplicate()
	sorted.sort_custom(func(a, b): return a["interest"] > b["interest"])
	for pr in sorted:
		if joined.size() >= room:
			break
		if rng.chance(pr["interest"] / 100.0) or pr["interest"] >= 90:
			var p: Dictionary = pr["player"]
			p["teamId"] = team["id"]
			p["enrollYear"] = state["year"]
			joined.append(p)
	state["prospects"] = []
	var walk_ons := mini(rng.irange(3, 5), maxi(0, 36 - team["playerIds"].size() - joined.size()))
	joined.append_array(WorldGen.intake_for(state, rng, team, state["year"], walk_ons, 18 + state["reputation"] * 0.35))
	for p in joined:
		state["players"][p["id"]] = p
		team["playerIds"].append(p["id"])
	return joined
