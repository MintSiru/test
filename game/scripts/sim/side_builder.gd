class_name SideBuilder
extends RefCounted
## 팀·선수 데이터 → 경기 입력 (web/src/sim/build.ts 이식)


static func build(team: Dictionary, roster: Array, date: String, opts: Dictionary = {}) -> Dictionary:
	var healthy := roster.filter(func(p): return p["injury"] <= 0)
	var starter = null
	if opts.get("starterId", "") != "":
		for p in healthy:
			if p["id"] == opts["starterId"]:
				starter = p
	if starter == null:
		starter = Lineup.pick_starter(healthy, date, team.get("rotation", []) if team.get("rotation") != null else [])
	if starter == null:
		starter = healthy[0]
	var lineup = opts.get("lineup", team.get("lineup"))
	var valid: bool = lineup != null and lineup.size() == 9
	if valid:
		var ids := {}
		var poss := {}
		for s in lineup:
			var ok := false
			for p in healthy:
				if p["id"] == s["playerId"]:
					ok = true
			if not ok or s["playerId"] == starter["id"]:
				valid = false
			ids[s["playerId"]] = true
			poss[s["pos"]] = true
		if ids.size() != 9 or poss.size() != 9:
			valid = false
	if not valid:
		lineup = Lineup.auto_lineup(healthy, [starter["id"]])
	var sims := healthy.map(func(p): return SimPlayer.from_player(p, date))
	return {
		"teamId": team["id"], "name": team["name"], "colors": team["colors"], "players": sims,
		"lineup": lineup, "pitcherId": starter["id"], "isUser": team.get("isUser", false),
	}
