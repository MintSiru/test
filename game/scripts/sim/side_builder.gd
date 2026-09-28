class_name SideBuilder
extends RefCounted
## 팀·선수 데이터 → 경기 입력 (web/src/sim/build.ts 이식)


## CPU 팀 자동 오더 캐시: 능력치는 주 1회(월요일 훈련)만 바뀌므로 같은 주(월요일 기준)·같은 출전 가능 선수면 결과가 같다
static var _lineup_cache := {}


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
		if team.get("isUser", false):
			lineup = Lineup.auto_lineup(healthy, [starter["id"]])
		else:
			var ids := PackedStringArray()
			for p in healthy:
				ids.append(p["id"])
			var key := "%s|%s|%s" % [team["id"], Cal.add_days(date, -((Cal.weekday(date) + 6) % 7)), ",".join(ids)]
			lineup = _lineup_cache.get(key)
			# 선발 투수는 타순에서 빠져야 한다 (보통 투수는 타순에 없으므로 대부분 그대로 쓴다)
			if lineup != null:
				for sl in lineup:
					if sl["playerId"] == starter["id"]:
						lineup = null
						break
			if lineup == null:
				if _lineup_cache.size() > 3000:
					_lineup_cache.clear()
				lineup = Lineup.auto_lineup(healthy, [starter["id"]])
				_lineup_cache[key] = lineup
	var bonus: int = opts.get("condBonus", 0)
	var sims := healthy.map(func(p): return SimPlayer.from_player(p, date, bonus))
	return {
		"teamId": team["id"], "name": team["name"], "colors": team["colors"], "players": sims,
		"lineup": lineup, "pitcherId": starter["id"], "isUser": team.get("isUser", false),
	}
