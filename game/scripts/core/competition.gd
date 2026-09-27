class_name Competition
extends RefCounted
## 대회 생성·대진·순위 (web/src/core/competition.ts 이식)


## 권역별 풀리그. 경기는 토·일
static func create_league(state: Dictionary, key: String, groups: Array) -> Dictionary:
	var def := Cal.comp_def(key)
	var dates := Cal.comp_dates(key, state["year"])
	var id := "%s-%d" % [key, state["year"]]
	var weekend := Cal.date_range(dates["start"], dates["end"]).filter(func(d): return Cal.weekday(d) in [0, 6])
	var fixtures := []
	for g in groups:
		var teams: Array = g["teamIds"].duplicate()
		if teams.size() % 2 == 1:
			teams.append(null)
		var n := teams.size()
		var rounds := n - 1
		var step := maxi(1, weekend.size() / rounds)
		for r in rounds:
			var date: String = weekend[mini(weekend.size() - 1, r * step)]
			for i in n / 2:
				var a = teams[i]
				var b = teams[n - 1 - i]
				if a != null and b != null:
					fixtures.append({"id": "%s-%s-%d-%d" % [id, g["id"], r, i], "compId": id, "date": date,
						"home": b if r % 2 == 0 else a, "away": a if r % 2 == 0 else b, "group": g["id"], "round": r})
			teams.insert(1, teams.pop_back())
	return {"id": id, "key": key, "name": def["name"], "kind": "league", "year": state["year"], "start": dates["start"], "end": dates["end"],
		"status": "upcoming", "fixtures": fixtures, "groups": groups}


static func standings(comp: Dictionary, group_id: String) -> Array:
	var g: Dictionary = {}
	for x in comp["groups"]:
		if x["id"] == group_id:
			g = x
	var table := {}
	for t in g.get("teamIds", []):
		table[t] = {"teamId": t, "w": 0, "l": 0, "d": 0, "rs": 0, "ra": 0}
	for f in comp["fixtures"]:
		if f.get("group") != group_id or f.get("result") == null:
			continue
		var res: Dictionary = f["result"]
		var h: Dictionary = table[f["home"]]
		var a: Dictionary = table[f["away"]]
		h["rs"] += res["homeScore"]
		h["ra"] += res["awayScore"]
		a["rs"] += res["awayScore"]
		a["ra"] += res["homeScore"]
		if res["winner"] == null:
			h["d"] += 1
			a["d"] += 1
		elif res["winner"] == f["home"]:
			h["w"] += 1
			a["l"] += 1
		else:
			a["w"] += 1
			h["l"] += 1
	var rows := table.values()
	rows.sort_custom(func(x, y):
		var px: float = x["w"] + x["d"] * 0.5
		var py: float = y["w"] + y["d"] * 0.5
		if px != py:
			return px > py
		return (x["rs"] - x["ra"]) > (y["rs"] - y["ra"]))
	return rows


static func create_tournament(state: Dictionary, key: String, entrants: Array, rng: Rng, blocked := {}) -> Dictionary:
	var def := Cal.comp_def(key)
	var dates := Cal.comp_dates(key, state["year"])
	var id := "%s-%d" % [key, state["year"]]
	var n := entrants.size()
	var size := 2
	while size < n:
		size *= 2
	var shuffled := rng.shuffle(entrants.duplicate())
	var pairs := []
	var full := n - size / 2
	var k := 0
	for i in size / 2:
		if i < full:
			pairs.append([shuffled[k], shuffled[k + 1]])
			k += 2
		else:
			pairs.append([shuffled[k] if k < n else null, null])
			k += 1
	rng.shuffle(pairs)
	var first := []
	for pr in pairs:
		first.append_array(pr)
	var rounds := roundi(log(size) / log(2))
	var bracket := [first]
	for r in range(1, rounds + 1):
		var arr := []
		arr.resize(size / int(pow(2, r)))
		arr.fill(null)
		bracket.append(arr)

	var days := Cal.date_range(dates["start"], dates["end"])
	var usable := days.filter(func(d): return not blocked.has(d))
	var pool := usable if usable.size() >= rounds else days
	var round_dates := []
	for r in rounds:
		round_dates.append([])
	var cursor := pool.size() - 1
	var late := mini(3, rounds)
	for i in late:
		round_dates[rounds - 1 - i] = [pool[maxi(0, cursor)]]
		cursor -= 2
	var early := rounds - late
	if early > 0:
		var avail := pool.slice(0, maxi(early, cursor + 1))
		var games := []
		var total := 0
		for r in early:
			var gcount := size / int(pow(2, r + 1))
			games.append(gcount)
			total += gcount
		var idx := 0
		for r in early:
			var remain := early - r - 1
			var share := maxi(1, roundi(float(games[r]) / total * avail.size()))
			var take := maxi(1, mini(share, avail.size() - idx - remain))
			round_dates[r] = avail.slice(idx, idx + take)
			idx += take
			if round_dates[r].is_empty():
				round_dates[r] = [avail[avail.size() - 1]]
	var comp := {"id": id, "key": key, "name": def["name"], "kind": "tournament", "year": state["year"], "start": dates["start"], "end": dates["end"],
		"status": "upcoming", "fixtures": [], "bracket": bracket, "roundDates": round_dates, "entrants": entrants.duplicate()}
	schedule_round(comp, 0)
	return comp


static func schedule_round(comp: Dictionary, r: int, min_date := "") -> void:
	var br: Array = comp["bracket"]
	var slots: Array = br[r]
	var dates: Array = comp["roundDates"][r]
	var gi := 0
	for i in slots.size() / 2:
		var a = slots[2 * i]
		var b = slots[2 * i + 1]
		if a != null and b != null:
			var date: String = dates[gi % dates.size()]
			# 우천 연기 등으로 앞 라운드가 늦게 끝났으면 다음 날 이후로
			if min_date != "" and date <= min_date:
				date = Cal.add_days(min_date, 1)
			comp["fixtures"].append({"id": "%s-r%d-%d" % [comp["id"], r, i], "compId": comp["id"], "date": date,
				"home": a, "away": b, "round": r, "slot": i})
			gi += 1
		else:
			br[r + 1][i] = a if a != null else b
	if gi == 0 and r + 1 < br.size() - 1:
		schedule_round(comp, r + 1, min_date)


static func round_name(comp: Dictionary, r: int) -> String:
	var size: int = comp["bracket"][r].size()
	match size:
		2: return "결승"
		4: return "준결승"
		8: return "8강"
		16: return "16강"
		32: return "32강"
	return "%d회전" % (r + 1)


static func advance_tournament(comp: Dictionary, f: Dictionary) -> void:
	if f.get("round") == null or f.get("result") == null or f["result"]["winner"] == null:
		return
	var br: Array = comp["bracket"]
	var r := int(f["round"])
	br[r + 1][int(f["slot"])] = f["result"]["winner"]
	for x in comp["fixtures"]:
		if int(x.get("round", -1)) == r and x.get("result") == null:
			return
	if r + 1 == br.size() - 1:
		comp["champion"] = f["result"]["winner"]
		comp["runnerUp"] = f["away"] if f["result"]["winner"] == f["home"] else f["home"]
		comp["status"] = "done"
	else:
		schedule_round(comp, r + 1, f["date"])


static func tournament_result_for(comp: Dictionary, team_id: String) -> String:
	if not team_id in comp.get("entrants", []):
		return ""
	if comp.get("champion") == team_id:
		return "우승"
	if comp.get("runnerUp") == team_id:
		return "준우승"
	for f in comp["fixtures"]:
		if f.get("result") != null and f["result"]["winner"] != team_id and (f["home"] == team_id or f["away"] == team_id):
			var rn := round_name(comp, int(f["round"]))
			if rn == "준결승":
				return "4강"
			return rn if rn.ends_with("강") else rn + " 탈락"
	return ""
