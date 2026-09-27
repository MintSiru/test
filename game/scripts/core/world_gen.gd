class_name WorldGen
extends RefCounted
## 새 게임 세계 생성 (web/src/core/world.ts 이식)

const SAVE_VERSION := 1
const INTAKE_POS := [
	["P", "P", "C", "SS", "CF", "2B"],
	["P", "P", "3B", "1B", "LF", "RF"],
	["P", "P", "C", "SS", "CF", "3B"],
	["P", "P", "2B", "RF", "LF", "SS"],
]


static func uid(state: Dictionary, prefix: String) -> String:
	var n: int = state["nextId"]
	state["nextId"] = n + 1
	return prefix + String.num_int64(n, 36)


static func create_pros(rng: Rng, year: int) -> Array:
	var out := []
	var i := 0
	for d in GameData.pros()["players"]:
		out.append({"id": "pro%d" % i, "sur": d["sur"], "given": d["given"], "teamId": d["team"], "pos": d["pos"], "style": d["style"],
			"number": rng.irange(1, 99), "birthYear": year - int(d["age"]), "line": ""})
		i += 1
	return out


static func intake_for(state: Dictionary, rng: Rng, team: Dictionary, enroll_year: int, count: int, quality: float) -> Array:
	var out := []
	var pos_set: Array = INTAKE_POS[rng.irange(0, INTAKE_POS.size() - 1)]
	for i in count:
		out.append(PlayerUtil.gen_player(rng, {"id": uid(state, "p"), "teamId": team["id"], "enrollYear": enroll_year, "year": state["year"],
			"quality": quality + rng.gauss() * 10, "pos": pos_set[i] if i < pos_set.size() else "", "province": team["province"], "pros": state["pros"]}))
	return out


## o: {schoolName, managerName, groupId, seed?, year?}
static func new_game(o: Dictionary) -> Dictionary:
	var seed_val: int = o.get("seed", randi())
	var rng := Rng.new(seed_val)
	var year: int = o.get("year", 2026)
	var state := {
		"version": SAVE_VERSION, "seed": seed_val, "rngState": "", "date": Cal.season_start(year), "year": year,
		"userTeamId": "user", "managerName": o.get("managerName", "감독"), "reputation": 20,
		"teams": {}, "players": {}, "proTeams": GameData.pros()["teams"].duplicate(true), "pros": create_pros(rng, year),
		"competitions": [], "hand": [], "weekTrained": false, "scoutPoints": 0, "prospects": [], "news": [], "popups": [],
		"history": [], "alumni": [], "settings": {"speed": 2, "pauseMode": "pa", "sound": true}, "nextId": 1,
	}
	var colors: Array = GameData.schools()["teamColors"]
	var color_idx := 0
	for g in GameData.schools()["groups"]:
		var schools: Array = g["schools"]
		for i in schools.size():
			var s: Dictionary = schools[i]
			var is_user: bool = g["id"] == o["groupId"] and i == schools.size() - 1
			var id := "user" if is_user else "t%s%d" % [g["id"], i]
			var prestige := 25 if is_user else roundi(minf(92, maxf(15, 45 + rng.gauss() * 15 + (25.0 if rng.chance(0.08) else 0.0))))
			var team := {
				"id": id, "name": o.get("schoolName", "한빛고") if is_user else s["name"], "province": s["province"], "leagueGroup": g["id"],
				"colors": ["#1d4e89", "#f4d35e"] if is_user else colors[color_idx % colors.size()], "prestige": prestige,
				"playerIds": [], "isUser": is_user, "seasonPoints": 0, "seasonRecord": {"w": 0, "l": 0, "d": 0},
			}
			if not is_user:
				color_idx += 1
			state["teams"][id] = team
			var per_grade := 5 if is_user else 6
			for gr in 3:
				for p in intake_for(state, rng, team, year - gr, per_grade, 30.0 if is_user else float(prestige)):
					state["players"][p["id"]] = p
					team["playerIds"].append(p["id"])
	for i in 5:
		state["hand"].append(Training.draw_card(rng, uid(state, "c")))
	state["rngState"] = rng.get_state_str()
	state["news"].append({"date": state["date"], "kind": "info", "text": "%s 야구부 감독으로 부임했다. 목표는 전국 제패!" % state["teams"]["user"]["name"]})
	return state


static func team_players(state: Dictionary, team_id: String) -> Array:
	var out := []
	for id in state["teams"][team_id]["playerIds"]:
		var p = state["players"].get(id)
		if p != null:
			out.append(p)
	return out


static func user_team(state: Dictionary) -> Dictionary:
	return state["teams"][state["userTeamId"]]
