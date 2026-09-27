extends BaseScreen
## 가방: 장터에서 산 아이템을 선수에게 사용

var list: VBoxContainer
var overlay: Control


func setup(_p := {}) -> void:
	add_top_bar("가방")
	var p := UI.panel()
	UI.place(p, 4, 22, 632, 312)
	add_child(p)
	list = UI.vbox(3)
	p.add_child(UI.scroll(list))
	var shop := UI.button("장터로", func(): Game.goto("shop"), 100)
	UI.place(shop, 536, 338, 100, 18)
	add_child(shop)
	_fill()


func _fill() -> void:
	UI.clear(list)
	var inv = st().get("inventory")
	if inv == null or inv.is_empty():
		list.add_child(UI.label("가방이 비어 있다. 장터(매월 1~7일)에서 물건을 사 보자.", UI.DIM, true))
		return
	for key in inv:
		var def := Shop.item_def(key)
		if def.is_empty():
			continue
		var row := UI.hbox(6)
		var v := UI.vbox(0)
		v.custom_minimum_size.x = 500
		row.add_child(v)
		v.add_child(UI.label("%s ×%d" % [def["name"], inv[key]], UI.ACCENT, true))
		v.add_child(UI.label(def["desc"], UI.DIM, true))
		var k: String = key
		row.add_child(UI.button("사용", func(): _use(k), 80, true))
		list.add_child(row)


func _use(key: String) -> void:
	var def := Shop.item_def(key)
	var s := st()
	if Shop.needs_player(def):
		var items := []
		var ps := WorldGen.team_players(s, s["userTeamId"])
		ps.sort_custom(func(a, b): return PlayerUtil.overall(a) > PlayerUtil.overall(b))
		for p in ps:
			var why := Shop.cannot_use(def, p)
			var info := "%d학년 %s %s 종합 %d" % [PlayerUtil.grade(p, s["year"]), PlayerUtil.POS_SHORT[p["pos"]], PlayerUtil.full_name(p), PlayerUtil.overall(p)]
			if def["type"] == "stat":
				var sv := PlayerUtil.stat_value(p["r"], def["stat"])
				info += "  %s %s" % [PlayerUtil.STAT_KO[def["stat"]], PlayerUtil.letter(sv)]
			items.append([info + (("  (%s)" % why) if why != "" else ""), p["id"], why == ""])
		_choose("%s — 누구에게 쓸까?" % def["name"], items, func(id): _apply(key, id))
	elif def["type"] == "prospect":
		var items2 := []
		for pr in s["prospects"]:
			items2.append(["%s %s  의향 %d%%" % [PlayerUtil.POS_KO[pr["player"]["pos"]], PlayerUtil.full_name(pr["player"]), pr["interest"]], pr["id"], true])
		if items2.is_empty():
			Game.main.show_modal("가방", "지금은 유망주 명단이 없다. (9월 드래프트 이후 공개)")
			return
		_choose("추천서를 보낼 유망주", items2, func(id): _apply(key, id))
	else:
		_apply(key, "")


func _apply(key: String, target: String) -> void:
	var rng := Season.rng_of(st())
	var r := Shop.use_item(st(), key, target, rng)
	Season.save_rng(st(), rng)
	Game.save_game()
	Game.main.show_modal("아이템 사용" if r["ok"] else "사용할 수 없음", r["msg"], "good" if r["ok"] else "bad", func(): Game.main.drain_popups(_fill))
	_fill()


func _choose(title: String, items: Array, cb: Callable) -> void:
	if overlay:
		overlay.queue_free()
	overlay = UI.panel(UI.PANEL, UI.ACCENT, 6)
	UI.place(overlay, 90, 30, 460, 300)
	add_child(overlay)
	var v := UI.vbox(2)
	overlay.add_child(v)
	v.add_child(UI.title_label(title))
	var l := UI.vbox(1)
	v.add_child(UI.scroll(l, Vector2(446, 236)))
	for it in items:
		var id: String = it[1]
		var b := UI.button(it[0], func():
			overlay.queue_free()
			overlay = null
			cb.call(id), 440, true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not it[2]
		l.add_child(b)
	v.add_child(UI.button("취소", func():
		overlay.queue_free()
		overlay = null, 80, true))
