extends BaseScreen
## 홈 화면: 주간 훈련 카드 선택 → 날짜 진행 → 경기일/이벤트 처리

const CARD_COLORS := {
	"batting": Color("#d2553c"), "pitching": Color("#3c7fd2"), "defense": Color("#3ca05a"), "running": Color("#d2a03c"),
	"stamina": Color("#8c5ad2"), "rest": Color("#5ab4b4"), "practiceGame": Color("#d23c8c"), "meeting": Color("#7a7a9a"),
	"scout": Color("#b48c5a"), "special": Color("#e8e8e8"),
}

var advancing := false
var action_box: Control
var news_box: VBoxContainer
var left_box: VBoxContainer
var scene: Control
var anim_t := 0.0
var status_label: Label
## 직전 훈련 성과 (진행 중 표시)
var train_lines: Array = []


func setup(_p := {}) -> void:
	_build()
	if not st()["popups"].is_empty():
		Game.main.drain_popups(_refresh)


func _build() -> void:
	UI.clear(self)
	top_root = null
	add_top_bar("", false)
	# 왼쪽: 다음 경기 · 일정
	var lp := UI.panel()
	UI.place(lp, 4, 22, 196, 206)
	add_child(lp)
	left_box = UI.vbox(2)
	lp.add_child(left_box)
	# 가운데: 연습 풍경 + 행동
	scene = Control.new()
	UI.place(scene, 204, 22, 280, 84)
	scene.draw.connect(_draw_scene)
	scene.clip_contents = true
	add_child(scene)
	action_box = Control.new()
	UI.place(action_box, 204, 108, 280, 120)
	add_child(action_box)
	# 오른쪽 메뉴
	var rp := UI.panel()
	UI.place(rp, 488, 22, 148, 206)
	add_child(rp)
	var menu := UI.vbox(3)
	rp.add_child(menu)
	menu.add_child(UI.label("메뉴", UI.DIM, true))
	menu.add_child(UI.button("선수단", func(): Game.goto("roster")))
	menu.add_child(UI.button("오더 편집", func(): Game.goto("lineup")))
	menu.add_child(UI.button("일정 · 대진표", func(): Game.goto("schedule")))
	var sp: int = st()["scoutPoints"]
	menu.add_child(UI.button("스카우트 (행동력 %d)" % sp if not st()["prospects"].is_empty() else "스카우트", func(): Game.goto("scout")))
	menu.add_child(UI.button("기록실", func(): Game.goto("records")))
	menu.add_child(UI.button("시설 · 예산 (%d만원)" % int(st().get("budget", 0)), func(): Game.goto("facilities")))
	var snd: bool = st()["settings"].get("sound", true)
	menu.add_child(UI.button("소리: 켜짐" if snd else "소리: 꺼짐", func():
		st()["settings"]["sound"] = not st()["settings"].get("sound", true)
		Game.bgm("title")
		_build(), 0, true))
	menu.add_child(UI.button("저장", func():
		Game.save_game()
		Game.main.show_modal("저장", "저장했습니다.")))
	menu.add_child(UI.button("타이틀로", func():
		Game.save_game()
		Game.goto("title")))
	# 아래: 소식
	var np := UI.panel()
	UI.place(np, 4, 232, 632, 124)
	add_child(np)
	news_box = UI.vbox(1)
	var sc := UI.scroll(news_box)
	np.add_child(sc)
	_refresh()


func _refresh() -> void:
	var s := st()
	refresh_top_bar()
	_fill_left()
	_fill_action()
	UI.clear(news_box)
	var news: Array = s["news"]
	for i in range(news.size() - 1, maxi(-1, news.size() - 40), -1):
		var n: Dictionary = news[i]
		var row := UI.hbox(4)
		row.add_child(UI.label(Cal.short(n["date"]), UI.DIM, true))
		var l := UI.wrap_label(n["text"], 580, UI.KIND_COLORS.get(n["kind"], UI.TEXT), true)
		row.add_child(l)
		news_box.add_child(row)


func _fill_left() -> void:
	UI.clear(left_box)
	var s := st()
	left_box.add_child(UI.label("다음 경기", UI.ACCENT, true))
	var nx := Season.next_user_fixture(s)
	if nx.is_empty():
		left_box.add_child(UI.label("예정된 경기 없음", UI.DIM, true))
	else:
		var f: Dictionary = nx["f"]
		var u: String = s["userTeamId"]
		var opp: Dictionary = s["teams"][f["away"] if f["home"] == u else f["home"]]
		left_box.add_child(UI.label(Cal.pretty(f["date"]), UI.TEXT, true))
		left_box.add_child(UI.label(Season.fixture_label(nx["comp"], f), UI.TEXT, true))
		left_box.add_child(UI.label("vs %s (%s)" % [opp["name"], opp["province"]], UI.GOOD, true))
	var rid = s.get("rivalId")
	if rid != null:
		var hh := Rival.h2h_of(s, rid)
		left_box.add_child(UI.label("라이벌: %s (%d승 %d패)" % [s["teams"][rid]["name"], hh["w"], hh["l"]], UI.BAD, true))
	left_box.add_child(UI.spacer(0, 2))
	left_box.add_child(UI.label("연간 일정", UI.ACCENT, true))
	var shown := 0
	for e in Season.year_schedule(s):
		if e["end"] < s["date"]:
			continue
		var active: bool = e["date"] <= s["date"] and e["end"] >= s["date"]
		var txt := "%s %s" % [Cal.short(e["date"]), e["label"]]
		left_box.add_child(UI.label(txt, UI.GOOD if active else UI.TEXT, true))
		shown += 1
		if shown >= 8:
			break


func _fill_action() -> void:
	UI.clear(action_box)
	var s := st()
	status_label = null
	if advancing:
		var l := UI.label("진행 중... %s" % Cal.pretty(s["date"]), UI.ACCENT)
		UI.place(l, 4, 0, 270, 14)
		action_box.add_child(l)
		status_label = l
		return
	if not s["weekTrained"]:
		action_box.add_child(UI.place(UI.label("이번 주 훈련 카드를 고르세요", UI.ACCENT, true), 0, 0, 280, 12))
		var hand: Array = s["hand"]
		for i in hand.size():
			var c: Dictionary = hand[i]
			action_box.add_child(_card_widget(c, Vector2(i * 56, 16)))
		if s.get("trainingBonus") != null:
			action_box.add_child(UI.place(UI.label("★ 전지훈련: 이번 주 효과 ×%.1f" % s["trainingBonus"], UI.GOOD, true), 0, 106, 280, 12))
		return
	if s.get("pendingFixture") != null:
		var found := Season.find_fixture(s, s["pendingFixture"])
		var f: Dictionary = found["f"]
		var u: String = s["userTeamId"]
		var opp: Dictionary = s["teams"][f["away"] if f["home"] == u else f["home"]]
		var p := UI.panel(UI.PANEL, UI.ACCENT, 6)
		UI.place(p, 10, 6, 260, 106)
		action_box.add_child(p)
		var v := UI.vbox(4)
		p.add_child(v)
		v.add_child(UI.title_label("오늘은 경기일!"))
		v.add_child(UI.label(Season.fixture_label(found["comp"], f), UI.TEXT, true))
		v.add_child(UI.label("상대: %s (%s · 전통 %d)" % [opp["name"], opp["province"], opp["prestige"]], UI.TEXT, true))
		var row := UI.hbox(6)
		v.add_child(row)
		row.add_child(UI.button("경기 준비 (직접 지휘)", func(): Game.goto("prematch")))
		row.add_child(UI.button("위임", _delegate))
		return
	if not train_lines.is_empty():
		var v := UI.vbox(0)
		UI.place(v, 4, 0, 272, 92)
		action_box.add_child(v)
		for i in train_lines.size():
			v.add_child(UI.label(train_lines[i], UI.GOOD if i == 0 else (UI.BAD if train_lines[i].begins_with("부상") else UI.TEXT), true))
	var b := UI.button("▶ 다음으로 진행", _start_advance, 200)
	UI.place(b, 40, 96 if not train_lines.is_empty() else 40, 200, 20)
	action_box.add_child(b)


func _card_widget(c: Dictionary, pos: Vector2) -> Control:
	var info: Dictionary = Training.CARD_INFO[c["kind"]]
	var col: Color = CARD_COLORS[c["kind"]]
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", UI.sb(col.darkened(0.55), col, 1))
	btn.add_theme_stylebox_override("hover", UI.sb(col.darkened(0.35), UI.ACCENT, 2))
	btn.add_theme_stylebox_override("pressed", UI.sb(col, UI.ACCENT, 2))
	UI.place(btn, pos.x, pos.y, 52, 88)
	btn.tooltip_text = "%s Lv%d\n%s" % [info["name"], c["value"], info["desc"]]
	btn.pressed.connect(func(): _use_card(c["id"]))
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(v, 3, 3, 46, 82)
	btn.add_child(v)
	var name_l := UI.wrap_label(info["name"], 46, UI.TEXT, true)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var num := UI.label(str(c["value"]), col.lightened(0.3), false, true)
	num.add_theme_font_size_override("font_size", 24)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(num)
	var d := UI.wrap_label(Training.CARD_SHORT[c["kind"]], 46, UI.DIM, true)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	return btn


func _use_card(id: String) -> void:
	var card_kind := ""
	for c in st()["hand"]:
		if c["id"] == id:
			card_kind = Training.CARD_INFO[c["kind"]]["name"]
	var report := Season.use_card(st(), id)
	var rows := []
	var ups := 0
	for pid in report["gains"]:
		var p = st()["players"].get(pid)
		if p == null:
			continue
		var parts := []
		var total := 0
		for k in report["gains"][pid]:
			var g := int(report["gains"][pid][k])
			total += g
			parts.append("%s+%d" % [PlayerUtil.STAT_KO[k], g] if k != "velo" else "구속+%dkm" % g)
		ups += total
		rows.append({"t": total, "s": "%s %s" % [PlayerUtil.full_name(p), " ".join(parts)]})
	rows.sort_custom(func(a, b): return a["t"] > b["t"])
	train_lines = ["%s 성과: 능력치 총 +%d" % [card_kind, ups]]
	for r in rows.slice(0, 6):
		train_lines.append(r["s"])
	for pid in report["injuries"]:
		train_lines.append("부상: %s" % PlayerUtil.full_name(st()["players"][pid]))
	st()["news"].append({"date": st()["date"], "kind": "good", "text": train_lines[0]})
	_refresh()


func _delegate() -> void:
	var m := Season.auto_play_user_match(st())
	Game.save_game()
	if m != null:
		Game.main.show_match_result(m, _after_popups)


func _start_advance() -> void:
	train_lines = []
	advancing = true
	_fill_action()


func _process(delta: float) -> void:
	anim_t += delta
	scene.queue_redraw()
	if not advancing:
		return
	var s := st()
	# 한 프레임에 경기 몇 개 또는 조용한 날 며칠까지만 처리 (웹 빌드에서도 끊기지 않게)
	var start_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 30:
		var r := Season.step_day(s, 3)
		if r != "":
			advancing = false
			Game.save_game()
			_refresh()
			if r == "popup":
				Game.main.drain_popups(_after_popups)
			return
	if status_label:
		status_label.text = "진행 중... %s" % Cal.pretty(s["date"])


func _after_popups() -> void:
	var s := st()
	_refresh()
	if s["weekTrained"] and s.get("pendingFixture") == null:
		_start_advance()


# ───────────── 연습 풍경 (도트) ─────────────

func _draw_scene() -> void:
	var w := 280.0
	var h := 84.0
	scene.draw_rect(Rect2(0, 0, w, h), Color("#2f7a3f"))
	for y in range(0, int(h), 8):
		scene.draw_rect(Rect2(0, y, w, 4), Color("#2a6e39"))
	scene.draw_rect(Rect2(0, 0, w, 14), Color("#5a4a3a"))
	scene.draw_rect(Rect2(0, 12, w, 2), Color("#3a2f25"))
	# 교사 건물
	scene.draw_rect(Rect2(10, 0, 90, 12), Color("#c8c0b0"))
	for i in 8:
		scene.draw_rect(Rect2(14 + i * 11, 3, 6, 5), Color("#6a8ab0"))
	scene.draw_rect(Rect2(200, 2, 60, 10), Color("#9a8a70"))
	# 내야 흙
	scene.draw_colored_polygon(PackedVector2Array([Vector2(140, 34), Vector2(190, 58), Vector2(140, 82), Vector2(90, 58)]), Color("#b07a4a"))
	for b in [Vector2(140, 34), Vector2(190, 58), Vector2(140, 82), Vector2(90, 58)]:
		scene.draw_rect(Rect2(b.x - 1, b.y - 1, 3, 3), Color.WHITE)
	var t: Dictionary = st()["teams"][st()["userTeamId"]]
	var cap := Color(t["colors"][0])
	var acc := Color(t["colors"][1])
	# 달리는 선수들
	for i in 5:
		var phase := anim_t * 0.25 + i * 0.2
		var x := fmod(phase * 280.0, 320.0) - 20
		var y := 20.0 + i * 12
		var frame := 1 + int(anim_t * 8 + i) % 2
		scene.draw_texture(PixelArt.sprite(Color("#f4f4f4"), cap, acc, frame), Vector2(roundi(x), roundi(y)))
	# 투수 연습
	var sw := int(anim_t * 2) % 2
	scene.draw_texture(PixelArt.sprite(Color("#f4f4f4"), cap, acc, 0), Vector2(136, 52))
	var bx := 140.0 + (fmod(anim_t, 0.5) / 0.5) * 0.0
	var by := 58.0 + fmod(anim_t * 60.0, 24.0)
	if sw == 0:
		scene.draw_rect(Rect2(bx, by, 2, 2), Color.WHITE)
	var label := "이번 주: 훈련 카드 선택 대기" if not st()["weekTrained"] else ("경기일" if st().get("pendingFixture") != null else "연습 중")
	scene.draw_string(UI.font_small, Vector2(4, 80), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffffffcc"))
