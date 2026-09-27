extends BaseScreen
## 오더 편집: 타순·수비 위치 (지명타자 제도) + 선발 투수 우선순위

const POS_LIST := ["C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH"]

var lineup: Array = []
var rot_order: Array = []
var sel := -1
var left: VBoxContainer
var right: VBoxContainer
var rot_box: VBoxContainer
var msg: Label


func setup(_p := {}) -> void:
	add_top_bar("오더 편집")
	var team := Game.user_team()
	var players := WorldGen.team_players(st(), team["id"])
	if team.get("lineup") != null and team["lineup"].size() == 9:
		lineup = team["lineup"].duplicate(true)
	else:
		lineup = Lineup.auto_lineup(players)
	var pitchers := players.filter(func(p): return p["pos"] == "P")
	pitchers.sort_custom(func(a, b): return Lineup.starter_score(a) > Lineup.starter_score(b))
	rot_order = team.get("rotation", []) if team.get("rotation") != null else []
	rot_order = rot_order.filter(func(id): return st()["players"].has(id))
	for p in pitchers:
		if not p["id"] in rot_order:
			rot_order.append(p["id"])

	var lp := UI.panel()
	UI.place(lp, 4, 22, 300, 290)
	add_child(lp)
	left = UI.vbox(1)
	lp.add_child(left)
	var rp := UI.panel()
	UI.place(rp, 308, 22, 150, 290)
	add_child(rp)
	right = UI.vbox(1)
	rp.add_child(UI.scroll(right))
	var tp := UI.panel()
	UI.place(tp, 462, 22, 174, 290)
	add_child(tp)
	rot_box = UI.vbox(1)
	tp.add_child(rot_box)
	var row := UI.hbox(6)
	UI.place(row, 4, 318, 632, 20)
	add_child(row)
	row.add_child(UI.button("자동 편성", func():
		lineup = Lineup.auto_lineup(WorldGen.team_players(st(), st()["userTeamId"]))
		_refresh()))
	row.add_child(UI.button("항상 자동 (감독 추천)", func():
		Game.user_team().erase("lineup")
		msg.text = "경기마다 자동으로 편성합니다."
		msg.add_theme_color_override("font_color", UI.GOOD)))
	row.add_child(UI.button("이 오더로 확정", _save))
	msg = UI.label("", UI.DIM, true)
	UI.place(msg, 4, 340, 632, 14)
	add_child(msg)
	_refresh()


func _p(id: String) -> Dictionary:
	return st()["players"].get(id, {})


func _refresh() -> void:
	UI.clear(left)
	left.add_child(UI.label("타순 (선택 후 다른 타순/벤치 선수를 누르면 교체)", UI.DIM, true))
	for i in lineup.size():
		var slot: Dictionary = lineup[i]
		var p := _p(slot["playerId"])
		var h := UI.hbox(4)
		var b := UI.button("%d번" % (i + 1), func():
			if sel == -1:
				sel = i
			elif sel == i:
				sel = -1
			else:
				var t = lineup[sel]
				lineup[sel] = lineup[i]
				lineup[i] = t
				sel = -1
			_refresh(), 34, true)
		if sel == i:
			b.add_theme_stylebox_override("normal", UI.sb(UI.ACCENT.darkened(0.4), UI.ACCENT))
		h.add_child(b)
		var idx := POS_LIST.find(slot["pos"])
		h.add_child(UI.option(POS_LIST.map(func(x): return PlayerUtil.POS_SHORT[x] + " " + PlayerUtil.POS_KO[x]), idx, func(k):
			lineup[i]["pos"] = POS_LIST[k]
			_refresh()))
		var name_l := UI.label(PlayerUtil.full_name(p) if not p.is_empty() else "?", UI.TEXT, true)
		name_l.custom_minimum_size.x = 50
		h.add_child(name_l)
		if not p.is_empty():
			var r: Dictionary = p["r"]
			h.add_child(UI.label("컨%s 파%s 주%s" % [PlayerUtil.letter(r["contact"]), PlayerUtil.letter(r["power"]), PlayerUtil.letter(r["speed"])], UI.DIM, true))
			if slot["pos"] != "DH":
				var apt := PlayerUtil.pos_aptitude(p, slot["pos"])
				if apt < 0.85:
					h.add_child(UI.label("적성↓", UI.BAD, true))
		left.add_child(h)
	var dup := {}
	for s in lineup:
		dup[s["pos"]] = dup.get(s["pos"], 0) + 1
	var bad := dup.keys().filter(func(k): return dup[k] > 1)
	if not bad.is_empty():
		left.add_child(UI.label("⚠ 수비 위치 중복: " + ", ".join(bad.map(func(k): return PlayerUtil.POS_KO[k])), UI.BAD, true))

	UI.clear(right)
	right.add_child(UI.label("벤치", UI.DIM, true))
	var in_lineup := lineup.map(func(s): return s["playerId"])
	for p in WorldGen.team_players(st(), st()["userTeamId"]):
		if p["id"] in in_lineup:
			continue
		var pid: String = p["id"]
		var txt := "%s %s %d" % [PlayerUtil.POS_SHORT[p["pos"]], PlayerUtil.full_name(p), PlayerUtil.overall(p)]
		var b := UI.button(txt, func():
			if sel >= 0:
				lineup[sel]["playerId"] = pid
				sel = -1
				_refresh(), 130, true)
		if p["injury"] > 0:
			b.disabled = true
			b.text += " 부상"
		right.add_child(b)

	UI.clear(rot_box)
	rot_box.add_child(UI.label("선발 투수 우선순위", UI.DIM, true))
	rot_box.add_child(UI.wrap_label("휴식 규정(투구수)을 지킨 투수 중 위에서부터 선발 등판", 164, UI.DIM, true))
	for i in rot_order.size():
		var p := _p(rot_order[i])
		if p.is_empty():
			continue
		var h := UI.hbox(2)
		h.add_child(UI.button("▲", func():
			if i > 0:
				var t = rot_order[i - 1]
				rot_order[i - 1] = rot_order[i]
				rot_order[i] = t
				_refresh(), 0, true))
		var l := UI.label("%d. %s %dkm 제%s" % [i + 1, PlayerUtil.full_name(p), p["r"]["velo"], PlayerUtil.letter(p["r"]["control"])], UI.TEXT, true)
		h.add_child(l)
		rot_box.add_child(h)


func _save() -> void:
	var poss := {}
	var ids := {}
	for s in lineup:
		poss[s["pos"]] = true
		ids[s["playerId"]] = true
	if poss.size() != 9 or ids.size() != 9:
		msg.text = "수비 위치(9곳)와 선수(9명)가 겹치지 않게 정해 주세요."
		msg.add_theme_color_override("font_color", UI.BAD)
		return
	var team := Game.user_team()
	team["lineup"] = lineup.duplicate(true)
	team["rotation"] = rot_order.duplicate()
	Game.save_game()
	msg.text = "오더를 확정했습니다. (부상자가 생기면 자동 편성으로 대체)"
	msg.add_theme_color_override("font_color", UI.GOOD)
