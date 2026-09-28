extends SceneTree
## 여러 해 밸런스 점검: 5년 × 3시드 자동 진행 (선택은 기본값, 장터 구매 없음) → 해마다 우리 팀 상위 12명 평균 종합·전국 순위·명성·포인트·감독 레벨
## godot --headless --path game -s tests/multi_year.gd   (약 3~4분. run_tests.sh 에는 넣지 않음)
## 장터를 쓰는 자동 플레이: ... -s tests/multi_year.gd -- shop  (시설은 싼 것부터, 아이템은 사서 종합이 높은 선수부터 사용)
func _top_ovr(state: Dictionary) -> float:
	var ov: Array = WorldGen.team_players(state, state["userTeamId"]).map(func(p): return PlayerUtil.overall(p))
	ov.sort()
	ov.reverse()
	var s := 0.0
	for x in ov.slice(0, 12):
		s += x
	return s / 12.0
func _nat_rank(state: Dictionary) -> int:
	var arr := []
	for t in state["teams"].values():
		var ov: Array = WorldGen.team_players(state, t["id"]).map(func(p): return PlayerUtil.overall(p))
		ov.sort(); ov.reverse()
		var s := 0.0
		for x in ov.slice(0, 12): s += x
		arr.append([s, t["isUser"]])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	for i in arr.size():
		if arr[i][1]: return i + 1
	return -1
var use_shop := false


## 장터: 시설(싼 것부터) → 아이템(비싼 것부터 살 수 있는 만큼, 바로 사용)
func _shop(state: Dictionary) -> void:
	var facs: Array = Shop.facilities().duplicate()
	facs.sort_custom(func(a, b): return Shop.facility_cost(state, a["key"]) < Shop.facility_cost(state, b["key"]))
	for f in facs:
		var c := Shop.facility_cost(state, f["key"])
		if c > 0 and Shop.points(state) >= c + 100:
			Shop.buy_facility(state, f["key"])
	var stock: Array = state["shop"]["stock"].duplicate()
	stock.sort_custom(func(a, b): return Shop.slot_price(a) > Shop.slot_price(b))
	var roster := WorldGen.team_players(state, state["userTeamId"])
	roster.sort_custom(func(a, b): return PlayerUtil.overall(a) > PlayerUtil.overall(b))
	for sl in stock:
		while int(sl["qty"]) > 0 and Shop.points(state) >= Shop.slot_price(sl) + 50:
			if Shop.buy_item(state, sl["key"]) != "":
				break
			var def := Shop.item_def(sl["key"])
			var target := ""
			if Shop.needs_player(def):
				for p in roster:
					if Shop.cannot_use(def, p) == "":
						target = p["id"]
						break
			elif def["type"] == "prospect" and not state["prospects"].is_empty():
				target = state["prospects"][0]["id"]
			Shop.use_item(state, sl["key"], target, Rng.new(1))


func _init() -> void:
	use_shop = "shop" in OS.get_cmdline_user_args()
	print("모드: ", "장터 사용" if use_shop else "장터 미사용")
	var seeds := [11, 22, 33]
	for seed in seeds:
		var state := Season.start_new_game({"schoolName": "한빛고", "managerName": "t", "groupId": "seoulA", "seed": seed})
		var line := "seed %d: 시작 %.1f(%d위)" % [seed, _top_ovr(state), _nat_rank(state)]
		var year := 2026
		var guard := 0
		var last_shop := ""
		while state["date"] < "2031-03-03" and guard < 200000:
			guard += 1
			var r := Season.advance(state, 1)
			if r == "training":
				Season.use_card(state, state["hand"][0]["id"])
			elif r == "match":
				Season.auto_play_user_match(state)
			state["popups"].clear()
			if use_shop and Shop.market_open(state) and state["date"] != last_shop:
				last_shop = state["date"]
				_shop(state)
			if int(state["year"]) != year:
				year = int(state["year"])
				line += " | %d: %.1f(%d위) 명성%d %dP Lv%d" % [year, _top_ovr(state), _nat_rank(state), state["reputation"], Shop.points(state), Manager.info(state)["level"]]
		print(line)
		var best := []
		for y in state["history"]:
			best.append(str(y["year"]) + ":" + ",".join(y["results"].filter(func(x): return not x["comp"].begins_with("주말")).map(func(x): return x["result"])))
		print("   ", best)
	quit()
