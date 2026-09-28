extends BaseScreen
## 선수단: 목록 + 선수 상세 (얼굴, 능력치, 특수능력, 동경 선수, 개인 연습 방침)

var list_box: VBoxContainer
var detail: Control
var filter := "all"
var selected_id := ""


func setup(p := {}) -> void:
	add_top_bar("선수단")
	selected_id = p.get("id", "")
	var tabs := UI.hbox(3)
	UI.place(tabs, 4, 22, 250, 16)
	add_child(tabs)
	for f in [["all", "전체"], ["P", "투수"], ["F", "야수"]]:
		var key: String = f[0]
		tabs.add_child(UI.button(f[1], func():
			filter = key
			_fill_list(), 0, true))
	var lp := UI.panel()
	UI.place(lp, 4, 40, 250, 316)
	add_child(lp)
	list_box = UI.vbox(1)
	lp.add_child(UI.scroll(list_box))
	detail = Control.new()
	UI.place(detail, 258, 22, 378, 334)
	add_child(detail)
	_fill_list()
	Help.once("abilities")


func _players() -> Array:
	var ps := WorldGen.team_players(st(), st()["userTeamId"])
	var year: int = st()["year"]
	ps = ps.filter(func(p): return filter == "all" or (filter == "P" and p["pos"] == "P") or (filter == "F" and p["pos"] != "P"))
	ps.sort_custom(func(a, b):
		var pa := 0 if a["pos"] == "P" else 1
		var pb := 0 if b["pos"] == "P" else 1
		if pa != pb:
			return pa < pb
		var ga := PlayerUtil.grade(a, year)
		var gb := PlayerUtil.grade(b, year)
		if ga != gb:
			return ga > gb
		return PlayerUtil.overall(a) > PlayerUtil.overall(b))
	return ps


func _fill_list() -> void:
	UI.clear(list_box)
	var year: int = st()["year"]
	var header := UI.hbox(4)
	for h in [["학년", 22], ["위치", 26], ["이름", 56], ["종합", 26], ["상태", 40], ["", 60]]:
		var l := UI.label(h[0], UI.DIM, true)
		l.custom_minimum_size.x = h[1]
		header.add_child(l)
	list_box.add_child(header)
	var ps := _players()
	if selected_id == "" and not ps.is_empty():
		selected_id = ps[0]["id"]
	for p in ps:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(236, 15)
		var sel: bool = p["id"] == selected_id
		b.add_theme_stylebox_override("normal", UI.sb(UI.PANEL2 if sel else UI.PANEL, UI.ACCENT if sel else UI.PANEL, 1, 1))
		b.add_theme_stylebox_override("hover", UI.sb(UI.PANEL2, UI.LINE, 1, 1))
		b.add_theme_stylebox_override("pressed", UI.sb(UI.PANEL2, UI.ACCENT, 1, 1))
		var id: String = p["id"]
		b.pressed.connect(func():
			selected_id = id
			_fill_list())
		var row := UI.hbox(4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UI.place(row, 2, 1, 234, 13)
		b.add_child(row)
		var cells := [
			[str(PlayerUtil.grade(p, year)), 22, UI.TEXT],
			[PlayerUtil.POS_SHORT[p["pos"]], 26, UI.TEXT],
			[PlayerUtil.full_name(p), 56, UI.IDOL if p.get("idolId") != null else UI.TEXT],
			[str(PlayerUtil.overall(p)), 26, PlayerUtil.letter_color(PlayerUtil.overall(p))],
			["부상" if p["injury"] > 0 else PlayerUtil.COND_KO[int(p["cond"]) + 2], 40, UI.BAD if p["injury"] > 0 else _cond_color(p["cond"])],
			[Text.stars(p["talent"]), 60, UI.ACCENT],
		]
		for c in cells:
			var l := UI.label(c[0], c[2], true)
			l.custom_minimum_size.x = c[1]
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(l)
		list_box.add_child(b)
	_fill_detail()


static func _cond_color(c: int) -> Color:
	return [UI.BAD, Color("#e0a060"), UI.TEXT, Color("#a6e36b"), UI.GOOD][c + 2]


func _fill_detail() -> void:
	UI.clear(detail)
	var p = st()["players"].get(selected_id)
	if p == null:
		return
	var s := st()
	var team: Dictionary = s["teams"][s["userTeamId"]]
	var pn := UI.panel()
	UI.place(pn, 0, 0, 378, 334)
	detail.add_child(pn)
	var root := Control.new()
	pn.add_child(root)
	# 얼굴 + 기본 정보
	var face := TextureRect.new()
	face.texture = PixelArt.portrait(int(p["faceSeed"]), Color(team["colors"][0]), Color(team["colors"][1]))
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	UI.place(face, 0, 0, 48, 48)
	root.add_child(face)
	var info := UI.vbox(1)
	UI.place(info, 54, 0, 310, 48)
	root.add_child(info)
	var nm := UI.label("%s  %d학년 %s" % [PlayerUtil.full_name(p), PlayerUtil.grade(p, s["year"]), PlayerUtil.POS_KO[p["pos"]]], UI.ACCENT, false, true)
	info.add_child(nm)
	var hand := "%s투%s타" % ["좌" if p["throws"] == "L" else "우", {"L": "좌", "R": "우", "S": "양"}[p["bats"]]]
	info.add_child(UI.label("%s · 재능 %s · 성격 %s · %s 출신" % [hand, Text.stars(p["talent"]), p["personality"], p["middleSchool"]], UI.TEXT, true))
	var subs := ", ".join(p["sub"].map(func(x): return PlayerUtil.POS_KO[x]))
	info.add_child(UI.label("종합 %d  %s" % [PlayerUtil.overall(p), ("서브: " + subs) if subs != "" else ""], PlayerUtil.letter_color(PlayerUtil.overall(p)), true))
	var cond_row := UI.hbox(6)
	cond_row.add_child(UI.label("컨디션 %s" % PlayerUtil.COND_KO[int(p["cond"]) + 2], _cond_color(int(p["cond"])), true))
	cond_row.add_child(UI.label("피로", UI.DIM, true))
	cond_row.add_child(UI.bar(p["fatigue"], 100, 50, UI.BAD if p["fatigue"] > 60 else UI.ACCENT))
	if p["injury"] > 0:
		cond_row.add_child(UI.label("부상 %d일" % p["injury"], UI.BAD, true))
	if p["pos"] == "P" and p.get("restUntil") != null and str(p["restUntil"]) > s["date"]:
		cond_row.add_child(UI.label("등판 가능 %s" % Cal.short(p["restUntil"]), UI.BAD, true))
	info.add_child(cond_row)

	# 능력치
	var g := UI.grid(4, 6, 2)
	UI.place(g, 0, 54, 250, 110)
	root.add_child(g)
	var keys := ["velo", "control", "stamina", "breaking", "contact", "power"] if p["pos"] == "P" else ["contact", "power", "eye", "speed", "arm", "fielding"]
	for k in keys:
		var v := PlayerUtil.stat_value(p["r"], k)
		g.add_child(UI.label(PlayerUtil.STAT_KO[k], UI.DIM, true))
		var txt := "%s %s" % [PlayerUtil.letter(v), ("%dkm" % p["r"]["velo"]) if k == "velo" else str(roundi(v))]
		g.add_child(UI.label(txt, PlayerUtil.letter_color(v), true))
		g.add_child(UI.bar(v, 100, 50, PlayerUtil.letter_color(v)))
		var capv: float = PlayerUtil.velo_score(p["cap"]["velo"]) if k == "velo" else float(p["cap"][k])
		g.add_child(UI.label("한계 %s" % PlayerUtil.letter(capv), UI.DIM, true))
	if p["pos"] == "P":
		var pitches := []
		for x in p["r"]["pitches"]:
			if x["type"] != "FB":
				pitches.append("%s %d" % [PlayerUtil.PITCH_KO[x["type"]], x["lv"]])
		var pl := UI.label("구종: " + (" · ".join(pitches) if not pitches.is_empty() else "직구만"), UI.TEXT, true)
		UI.place(pl, 0, 146, 370, 12)
		root.add_child(pl)

	# 개인 연습 방침
	var fr := UI.hbox(4)
	UI.place(fr, 256, 54, 114, 30)
	root.add_child(fr)
	var fv := UI.vbox(1)
	fr.add_child(fv)
	fv.add_child(UI.label("개인 연습", UI.DIM, true))
	var opts: Array = Training.PITCHER_FOCUS if p["pos"] == "P" else Training.BATTER_FOCUS
	var cur := opts.find(p["focus"])
	fv.add_child(UI.option(opts.map(func(x): return Training.FOCUS_KO[x]), maxi(0, cur), func(i):
		p["focus"] = opts[i]))

	# 포지션 연습 (야수) · 투타 겸업 (투수)
	var pv := UI.vbox(1)
	UI.place(pv, 256, 86, 118, 30)
	root.add_child(pv)
	if p["pos"] == "P":
		var ok := Lineup.can_two_way(p)
		var on: bool = p.get("twoWay", false)
		var tb := UI.button("투타 겸업: %s" % ("켬" if on else "끔"), func():
			p["twoWay"] = not on
			_fill_detail(), 118, true)
		tb.disabled = not ok and not on
		tb.tooltip_text = "선발로 나오는 날에도 지명타자로 타석에 선다. 강판 뒤에도 지명타자로 남는다." if ok else "타격이 야수 평균 이상인 투수만 (타격 %d / 필요 %d)" % [roundi(PlayerUtil.bat_value(p["r"])), roundi(Lineup.TWO_WAY_BAT)]
		if on:
			tb.add_theme_color_override("font_color", UI.ACCENT)
		pv.add_child(UI.label("투타 겸업" + ("" if ok else " (타격 부족)"), UI.DIM, true))
		pv.add_child(tb)
	else:
		var prac = p.get("practicePos")
		pv.add_child(UI.label("포지션 연습" + ((" %d%%" % roundi(float(p.get("practiceProg", 0.0)))) if prac != null else ""), UI.DIM, true))
		var popts: Array = Lineup.practice_options(p)
		var labels := ["안 함"] + popts.map(func(x): return PlayerUtil.POS_KO[x])
		var idx := 0 if prac == null else popts.find(prac) + 1
		var prow := UI.hbox(2)
		pv.add_child(prow)
		prow.add_child(UI.option(labels, maxi(0, idx), func(i):
			if i == 0:
				p.erase("practicePos")
			elif p.get("practicePos") != popts[i - 1]:
				p["practicePos"] = popts[i - 1]
				p["practiceProg"] = 0.0
			_fill_detail()))
		# 서브 포지션을 주 포지션으로
		if not p["sub"].is_empty():
			var sub_list: Array = p["sub"].duplicate()
			prow.add_child(UI.option(["주 포지션"] + sub_list.map(func(x): return PlayerUtil.POS_KO[x] + "로"), 0, func(i):
				if i > 0:
					Lineup.set_main_pos(p, sub_list[i - 1])
					Game.main.show_modal("포지션 변경", "%s의 주 포지션을 %s(으)로 바꿨다." % [PlayerUtil.full_name(p), PlayerUtil.POS_KO[p["pos"]]])
					_fill_list()))

	# 특수능력 (색: 금특 노랑 · 긍정 파랑 · 부정 빨강, 눌러서 설명 보기)
	var ab := UI.vbox(2)
	var abs_ := UI.scroll(ab)
	UI.place(abs_, 256, 118, 118, 44)
	root.add_child(abs_)
	var ah := UI.hbox(4)
	ah.add_child(UI.label("특수능력", UI.DIM, true))
	ah.add_child(UI.expand(UI.spacer()))
	ah.add_child(UI.button("목록", func(): Game.main.show_panel("특수능력 목록 (%d종)" % Abilities.all().size(), UI.ability_catalog()), 0, true))
	ab.add_child(ah)
	if p["abilities"].is_empty():
		ab.add_child(UI.label("없음", UI.DIM, true))
	else:
		ab.add_child(UI.ability_flow(p["abilities"], 108))

	# 동경 선수
	var idol := Idol.idol_of(s, p)
	var ip := UI.panel(Color("#2a2140"), UI.IDOL, 4)
	UI.place(ip, 0, 164, 370, 66)
	root.add_child(ip)
	var iv := UI.vbox(2)
	ip.add_child(iv)
	if idol.is_empty():
		iv.add_child(UI.label("동경하는 프로 선수: 없음", UI.DIM, true))
		iv.add_child(UI.wrap_label("동경하는 선수가 있으면 그 선수의 장기를 닮아 가며 더 빨리 성장합니다.", 356, UI.DIM, true))
	else:
		var sty: Dictionary = GameData.styles()[idol["style"]]
		iv.add_child(UI.label("동경: %s %s (%s) %s" % [Idol.pro_team_name(s, idol), Idol.pro_name(idol), PlayerUtil.POS_KO[idol["pos"]], "· 은퇴" if idol.get("retired", false) else ""], UI.IDOL, true))
		iv.add_child(UI.label("\"같은 이름 '%s'의 %s — %s\"" % [idol["given"], sty["desc"], idol.get("line", "")], UI.TEXT, true))
		var br := UI.hbox(6)
		br.add_child(UI.label("동경도 %d" % p["idolBond"], UI.IDOL, true))
		br.add_child(UI.bar(p["idolBond"], 100, 120, UI.IDOL))
		var nxt := "70: 비결 전수" if p["idolBond"] < 70 else ("100: 꿈의 만남" if p["idolBond"] < 100 else "달성!")
		br.add_child(UI.label("다음 " + nxt, UI.DIM, true))
		iv.add_child(br)
		var bonus := ", ".join(sty["stats"].map(func(k): return PlayerUtil.STAT_KO[k]))
		iv.add_child(UI.label("성장 보너스: %s ×%s" % [bonus, "1.4" if p["idolBond"] >= 50 else "1.25"], UI.DIM, true))

	# 기록
	var rec := UI.vbox(1)
	UI.place(rec, 0, 234, 370, 90)
	root.add_child(rec)
	rec.add_child(UI.label("시즌 기록", UI.DIM, true))
	var b: Dictionary = p["season"]["bat"]
	var pt: Dictionary = p["season"]["pit"]
	if p["pos"] == "P" or pt["outs"] > 0:
		rec.add_child(UI.label("투구 %d경기 %s이닝 %d승 %d패 ERA %s 탈삼진 %d 볼넷 %d" % [pt["g"], PlayerUtil.ip_str(pt["outs"]), pt["w"], pt["l"], PlayerUtil.era_str(pt), pt["so"], pt["bb"]], UI.TEXT, true))
	rec.add_child(UI.label("타격 %d경기 타율 %s %d안타 %d홈런 %d타점 %d도루" % [b["g"], PlayerUtil.avg_str(b), b["h"], b["hr"], b["rbi"], b["sb"]], UI.TEXT, true))
	var c: Dictionary = p["career"]["bat"]
	var cp: Dictionary = p["career"]["pit"]
	rec.add_child(UI.label("통산", UI.DIM, true))
	if p["pos"] == "P" or cp["outs"] > 0:
		rec.add_child(UI.label("투구 %s이닝 %d승 %d패 ERA %s" % [PlayerUtil.ip_str(cp["outs"]), cp["w"], cp["l"], PlayerUtil.era_str(cp)], UI.TEXT, true))
	rec.add_child(UI.label("타격 타율 %s %d홈런 %d타점" % [PlayerUtil.avg_str(c), c["hr"], c["rbi"]], UI.TEXT, true))
