class_name TestUtil
extends RefCounted

const ROSTER_POS := ["P", "P", "P", "P", "P", "P", "C", "C", "1B", "2B", "3B", "SS", "SS", "LF", "CF", "RF", "CF", "2B"]


static func make_team(rng: Rng, id: String, quality: float, year := 2026) -> Dictionary:
	var players := []
	for i in ROSTER_POS.size():
		players.append(PlayerUtil.gen_player(rng, {"id": "%s-%d" % [id, i], "teamId": id, "enrollYear": year - (i % 3), "year": year, "quality": quality, "pos": ROSTER_POS[i], "province": "서울"}))
	var team := {"id": id, "name": id, "colors": ["#000000", "#ffffff"], "isUser": false, "playerIds": players.map(func(p): return p["id"])}
	return {"team": team, "players": players}
