extends BaseScreen
## 장터: 경기로 얻은 포인트로 아이템과 시설 기물을 산다 (매월 1~7일)

var head: Label
var stock_box: VBoxContainer
var fac_box: VBoxContainer


func setup(_p := {}) -> void:
	add_top_bar("장터")
	head = UI.label("", UI.ACCENT)
	UI.place(head, 6, 22, 628, 14)
	add_child(head)
	var sub := UI.label("포인트는 경기 결과로 얻는다: 승리 %d · 무 %d · 패 %d · 득점당 %d · 대회 성적·권역 1위·프로 지명 보너스" % [
		Shop.data()["earn"]["win"], Shop.data()["earn"]["draw"], Shop.data()["earn"]["loss"], Shop.data()["earn"]["perRun"]], UI.DIM, true)
	UI.place(sub, 6, 38, 628, 12)
	add_child(sub)
	var lp := UI.panel()
	UI.place(lp, 4, 54, 380, 280)
	add_child(lp)
	stock_box = UI.vbox(3)
	lp.add_child(UI.scroll(stock_box))
	var rp := UI.panel()
	UI.place(rp, 388, 54, 248, 280)
	add_child(rp)
	fac_box = UI.vbox(3)
	rp.add_child(UI.scroll(fac_box))
	var bag := UI.button("가방 열기", func(): Game.goto("bag"), 120)
	UI.place(bag, 516, 338, 120, 18)
	add_child(bag)
	_fill()


func _fill() -> void:
	var s := st()
	var open := Shop.market_open(s)
	head.text = "보유 %dP   ·   %s" % [Shop.points(s), ("장터 영업 중 (~%s)" % Cal.short(s["shop"]["openUntil"])) if open else ("장터 닫힘 — 다음 장터 %s" % Cal.pretty(Shop.next_market(s)))]
	refresh_top_bar()
	UI.clear(stock_box)
	stock_box.add_child(UI.label("이번 장터 물건", UI.ACCENT, true))
	var stock: Array = s["shop"]["stock"] if s.get("shop") != null else []
	if stock.is_empty():
		stock_box.add_child(UI.label("아직 장터가 열린 적이 없다. (매월 1일 개장)", UI.DIM, true))
	for sl in stock:
		var def := Shop.item_def(sl["key"])
		var row := UI.hbox(4)
		var v := UI.vbox(0)
		v.custom_minimum_size.x = 250
		row.add_child(v)
		var kind_col: Color = UI.TIER_COLORS["good"] if def["type"] == "ability" else (UI.TIER_COLORS["gold"] if def["type"] == "gold" else (UI.GOOD if def["type"] == "stat" else UI.TEXT))
		var nr := UI.hbox(4)
		nr.add_child(UI.label("%s  (남은 %d)" % [def["name"], sl["qty"]], kind_col, true))
		if def["type"] == "ability":
			nr.add_child(UI.ability_chip(def["ability"]))
		v.add_child(nr)
		v.add_child(UI.wrap_label(def["desc"], 250, UI.DIM, true))
		var key: String = sl["key"]
		var b := UI.button("%dP 구매" % def["price"], func(): _buy(key), 90, true)
		b.disabled = not open or int(sl["qty"]) <= 0 or Shop.points(s) < int(def["price"])
		row.add_child(b)
		stock_box.add_child(row)

	UI.clear(fac_box)
	var fm := Shop.facility_month(s)
	fac_box.add_child(UI.label("시설 기물", UI.ACCENT, true))
	fac_box.add_child(UI.wrap_label("1·2·7·8·12월(방학·비시즌) 장터에서만 설치할 수 있다." + (" 지금 설치 가능!" if open and fm else ""), 236, UI.GOOD if open and fm else UI.DIM, true))
	for f in Shop.facilities():
		var key2: String = f["key"]
		var lv := Shop.level(s, key2)
		var cost := Shop.facility_cost(s, key2)
		fac_box.add_child(UI.label("%s  %s" % [f["name"], "■".repeat(lv) + "□".repeat(f["costs"].size() - lv)], UI.ACCENT if lv > 0 else UI.TEXT, true))
		var row2 := UI.hbox(4)
		var dl := UI.wrap_label(f["desc"], 150, UI.DIM, true)
		row2.add_child(dl)
		var b2 := UI.button(("%dP 설치" % cost) if cost >= 0 else "최고", func(): _buy_fac(key2), 80, true)
		b2.disabled = cost < 0 or not open or not fm or Shop.points(s) < cost
		row2.add_child(b2)
		fac_box.add_child(row2)


func _buy(key: String) -> void:
	var err := Shop.buy_item(st(), key)
	if err != "":
		Game.main.show_modal("장터", err)
	else:
		Game.sfx("fanfare", -10.0)
		Game.save_game()
	_fill()


func _buy_fac(key: String) -> void:
	var err := Shop.buy_facility(st(), key)
	if err != "":
		Game.main.show_modal("장터", err)
	else:
		Game.sfx("fanfare", -6.0)
		Game.save_game()
	_fill()
