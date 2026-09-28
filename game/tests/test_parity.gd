extends SceneTree
## 웹 ↔ Godot 동등성: tests/parity.json(웹 tests/parity.test.ts 가 만든 기준값)과 같은 값을 내는지
## godot --headless --path game -s tests/test_parity.gd

const STATS := ["contact", "power", "eye", "speed", "arm", "fielding", "velo", "control", "stamina", "breaking"]


func _r4(v: float) -> float:
	return roundf(v * 10000.0) / 10000.0


func _init() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity.json"))
	var players: Array = []
	for p in golden["players"]:
		players.append(p)
	var pros: Array = golden["pros"]
	var exp: Dictionary = golden["expected"]
	var act := {}
	act["overall"] = players.map(func(p): return PlayerUtil.overall(p))
	act["batterOverallAsSS"] = players.map(func(p): return PlayerUtil.batter_overall(p["r"], "SS"))
	act["pitcherOverall"] = players.map(func(p): return PlayerUtil.pitcher_overall(p["r"]))
	act["sim"] = players.map(func(p):
		var s := SimPlayer.from_player(p, "2026-05-01")
		return [s.con, s.pow, s.eye, s.spd, s.arm, s.fld, s.velo, s.ctl, s.sta, s.stuff].map(func(v): return _r4(v)))
	act["growth"] = players.map(func(p): return STATS.map(func(k): return _r4(Training.growth_mult(p, k, pros))))
	var letters := []
	for i in 15:
		letters.append(PlayerUtil.letter(i * 7))
	act["letter"] = letters
	var velo := []
	for i in 9:
		velo.append(_r4(PlayerUtil.velo_score(120 + i * 5)))
	act["veloScore"] = velo
	var mp := []
	for fr in [false, true]:
		for wd in [[true, false], [false, true], [false, false]]:
			for runs in [0, 3, 11]:
				mp.append(Shop.match_points(fr, wd[0], wd[1], runs, runs > 10))
	act["matchPoints"] = mp
	act["placing"] = Shop.data()["earn"]["placing"].keys().map(func(k): return Shop.placing_points(k))
	var fg := []
	for lv in 4:
		var fac := {}
		for f in Shop.facilities():
			fac[f["key"]] = lv
		fg.append(STATS.map(func(k): return _r4(Shop.growth(fac, k))))
	act["facilityGrowth"] = fg
	var cd := []
	for y in [2026, 2027, 2028, 2029]:
		for c in Cal.comp_defs():
			var d := Cal.comp_dates(c["key"], y)
			cd.append("%s:%s~%s" % [c["key"], d["start"], d["end"]])
	act["compDates"] = cd
	var sp := []
	for d in ["2026-06-01", "2026-12-01", "2026-04-01"]:
		var sale := Shop.sale_of(d)
		var row := []
		for it in Shop.items():
			var sl := {"key": it["key"]}
			if float(sale.get("discount", 0.0)) > 0.0:
				sl["price"] = int(round(float(it["price"]) * (1.0 - float(sale["discount"])) / 5.0)) * 5
			row.append(Shop.slot_price(sl))
		sp.append(row)
	act["salePrices"] = sp
	var fails := []
	for k in exp:
		if not act.has(k):
			fails.append("%s: Godot 쪽 계산 없음" % k)
		elif not _same(act[k], exp[k]):
			fails.append("%s 불일치\n  웹    %s\n  Godot %s" % [k, JSON.stringify(exp[k]), JSON.stringify(act[k])])
	print("동등성 항목 %d개 비교" % exp.size())
	for f in fails:
		print("FAIL: ", f)
	print("PARITY OK" if fails.is_empty() else "PARITY FAIL")
	quit(0 if fails.is_empty() else 1)


func _same(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.0015
	return str(a) == str(b)
