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
	# 처음 한 번 안내 (새 게임 직후 등)
	if not Help.once("welcome"):
		var g := _guide_key()
		if g != "":
			Help.once(g)


## 진행 중 처음 만나는 상황의 안내 (장터 개장, 스카우트 시작, 후원회 목표)
func _guide_key() -> String:
	var s := st()
	if not Help.enabled():
		return ""
	if Shop.market_open(s) and not Help.seen("firstMarket"):
		return "firstMarket"
	if not s["prospects"].is_empty() and not Help.seen("firstScout"):
		return "firstScout"
	if s.get("goals") != null and not Help.seen("goals"):
		return "goals"
	if not TeamMood.captain(s).is_empty() and not Help.seen("firstMood"):
		return "firstMood"
	if int(Manager.info(s)["level"]) >= 2 and not Help.seen("firstManager"):
		return "firstManager"
	if Achievements.count(s) >= 1 and not Help.seen("firstAchieve"):
		return "firstAchieve"
	if not s.get("highlights", []).is_empty() and not Help.seen("firstHighlight"):
		return "firstHighlight"
	return ""


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
	menu.add_child(UI.title_label("메뉴"))
	menu.add_child(UI.icon_button("선수단", "people", func(): Game.goto("roster")))
	menu.add_child(UI.icon_button("오더 편집", "lineup", func(): Game.goto("lineup")))
	menu.add_child(UI.icon_button("일정 · 대진표", "cal", func(): Game.goto("schedule")))
	var sp: int = st()["scoutPoints"]
	menu.add_child(UI.icon_button("스카우트 (행동력 %d)" % sp if not st()["prospects"].is_empty() else "스카우트", "scout", func(): Game.goto("scout")))
	menu.add_child(UI.icon_button("기록실", "trophy", func(): Game.goto("records")))
	var shop_b := UI.icon_button(("장터 영업 중! (%dP)" if Shop.market_open(st()) else "장터 (%dP)") % Shop.points(st()), "shop", func(): Game.goto("shop"))
	if Shop.market_open(st()):
		shop_b.add_theme_color_override("font_color", UI.GOOD)
	menu.add_child(shop_b)
	var inv = st().get("inventory")
	var cnt := 0
	if inv != null:
		for k in inv:
			cnt += int(inv[k])
	menu.add_child(UI.icon_button("가방 (%d)" % cnt, "bag", func(): Game.goto("bag"), 0, true))
	# 소리 · 저장 · 타이틀 (한 줄에 작게)
	var snd: bool = st()["settings"].get("sound", true)
	var sys_row := UI.hbox(2)
	menu.add_child(sys_row)
	sys_row.add_child(UI.expand(UI.icon_button("소리" if snd else "끔", "sound" if snd else "mute", func():
		st()["settings"]["sound"] = not st()["settings"].get("sound", true)
		Game.bgm(Game.main.bgm_for("hub"))
		_build(), 0, true)))
	sys_row.add_child(UI.expand(UI.icon_button("저장", "save", func():
		Game.save_game()
		Game.main.show_modal("저장", "슬롯 %d에 저장했습니다." % Game.slot), 0, true)))
	sys_row.add_child(UI.expand(UI.icon_button("처음", "home", func():
		Game.save_game()
		Game.goto("title"), 0, true)))
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
	left_box.add_child(UI.title_label("다음 경기"))
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
	# 팀 분위기 · 주장
	var md := TeamMood.mood(s)
	var cap := TeamMood.captain(s)
	var ml := UI.label("분위기 %s (%d)%s" % [TeamMood.label(md), md, ("  주장 " + PlayerUtil.full_name(cap)) if not cap.is_empty() else ""],
		UI.GOOD if md >= 62 else (UI.BAD if md <= 38 else UI.TEXT), true)
	ml.tooltip_text = "팀 분위기: 이기면 오르고 지면 내려갑니다. 65 이상이면 선수 컨디션이 오르기 쉽고, 35 이하면 떨어지기 쉽습니다. 주장이 기준점을 올려 줍니다."
	ml.mouse_filter = Control.MOUSE_FILTER_STOP
	left_box.add_child(ml)
	var mgr := Manager.info(s)
	var mgl := UI.label("감독 Lv%d%s" % [mgr["level"], ("  (다음까지 %d)" % (Manager.next_exp(s) - int(mgr["exp"]))) if Manager.next_exp(s) >= 0 else ""], UI.IDOL, true)
	mgl.tooltip_text = Manager.summary(s) + "\n경기 승리·대회 성적·프로 지명·개인 타이틀로 경험치를 얻습니다."
	mgl.mouse_filter = Control.MOUSE_FILTER_STOP
	left_box.add_child(mgl)
	var rid = s.get("rivalId")
	if rid != null:
		var hh := Rival.h2h_of(s, rid)
		left_box.add_child(UI.label("라이벌: %s (%d승 %d패)" % [s["teams"][rid]["name"], hh["w"], hh["l"]], UI.BAD, true))
	var gs = s.get("goals")
	if gs != null:
		left_box.add_child(UI.spacer(0, 2))
		left_box.add_child(UI.title_label("후원회 목표 (%s)" % gs["tier"]))
		for g in gs["list"]:
			left_box.add_child(UI.label("%s  %s" % [Goals.text(g), Goals.progress_text(g)], UI.GOOD if g["done"] else UI.TEXT, true))
	left_box.add_child(UI.spacer(0, 2))
	left_box.add_child(UI.title_label("연간 일정"))
	var shown := 0
	for e in Season.year_schedule(s):
		if e["end"] < s["date"]:
			continue
		var active: bool = e["date"] <= s["date"] and e["end"] >= s["date"]
		var txt := "%s %s" % [Cal.short(e["date"]), e["label"]]
		left_box.add_child(UI.label(txt, UI.GOOD if active else UI.TEXT, true))
		shown += 1
		if shown >= (4 if gs != null else 8):
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
	if train_lines.is_empty() and Season.friendly_date(s) != "":
		var fb := UI.button("연습 경기 신청 (%s)" % Cal.short(Season.friendly_date(s)), _ask_friendly, 200, true)
		fb.tooltip_text = "공식 기록에 남지 않지만 실전 경험을 쌓는다"
		UI.place(fb, 40, 66, 200, 16)
		action_box.add_child(fb)


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


func _ask_friendly() -> void:
	var s := st()
	var rng := Season.rng_of(s)
	var opps := Season.friendly_opponents(s, rng)
	Season.save_rng(s, rng)
	var buttons := []
	for id in opps:
		var t: Dictionary = s["teams"][id]
		var oid: String = id
		buttons.append(["%s (전통 %d)" % [t["name"], t["prestige"]], func():
			Season.schedule_friendly(s, oid)
			Game.save_game()
			_refresh()])
	buttons.append(["취소", func(): pass])
	Game.main.show_modal("연습 경기 상대", "연습 경기는 공식 기록에 남지 않지만 실전 경험치를 얻고, 투수 휴식 규정은 똑같이 적용됩니다.\n상대를 고르세요.", "info", Callable(), buttons)


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
		if r == "":
			var g := _guide_key()
			if g != "":
				advancing = false
				Game.save_game()
				_refresh()
				Help.once(g, _after_popups)
				return
		if r != "":
			advancing = false
			Game.save_game()
			_refresh()
			if r == "popup":
				Game.main.drain_popups(_after_popups)
			return
	if status_label:
		var pr := Season.day_progress(s)
		status_label.text = "진행 중... %s%s" % [Cal.pretty(s["date"]), ("  (오늘 경기 %d/%d)" % pr) if int(pr[1]) >= 6 else ""]


func _after_popups() -> void:
	var s := st()
	_refresh()
	if s["weekTrained"] and s.get("pendingFixture") == null:
		_start_advance()


# ───────────── 연습 풍경 (도트) ─────────────

func _draw_scene() -> void:
	var w := 280.0
	var h := 84.0
	var m := Cal.month_of(st()["date"])
	var season := "spring" if m in [3, 4, 5] else ("summer" if m in [6, 7, 8] else ("autumn" if m in [9, 10, 11] else "winter"))
	var sky_c: Color = {"spring": Color("#9ec9f0"), "summer": Color("#5fb0ff"), "autumn": Color("#f0b878"), "winter": Color("#b8c4d8")}[season]
	var leaf: Color = {"spring": Color("#f6b6c8"), "summer": Color("#2f8a3a"), "autumn": Color("#e0782f"), "winter": Color("#6a5a4a")}[season]
	var grass_a: Color = {"spring": Color("#3f9048"), "summer": Color("#348a3e"), "autumn": Color("#6a8a3a"), "winter": Color("#5f7a5a")}[season]
	# 하늘
	scene.draw_rect(Rect2(0, 0, w, 16), sky_c)
	scene.draw_rect(Rect2(0, 10, w, 6), sky_c.darkened(0.08))
	# 잔디 (깎은 결)
	scene.draw_rect(Rect2(0, 16, w, h - 16), grass_a)
	for y in range(16, int(h), 8):
		scene.draw_rect(Rect2(0, y, w, 4), grass_a.darkened(0.08))
	# 교사 건물: 지붕 · 창문 · 시계
	scene.draw_rect(Rect2(8, 2, 100, 14), Color("#d8d0c0"))
	scene.draw_rect(Rect2(6, 0, 104, 3), Color("#7a3b30"))
	for i in 8:
		scene.draw_rect(Rect2(12 + i * 12, 6, 7, 5), Color("#6a8ab0"))
		scene.draw_rect(Rect2(12 + i * 12, 6, 7, 1), Color("#9ab8d8"))
	scene.draw_circle(Vector2(58, 3), 3, Color("#f4f4f4"))
	scene.draw_rect(Rect2(58, 1, 1, 2), Color("#303030"))
	# 나무 (계절 색)
	for tx in [122, 150, 250, 268]:
		scene.draw_rect(Rect2(tx, 8, 2, 8), Color("#5a3a22"))
		if season != "winter":
			scene.draw_circle(Vector2(tx + 1, 6), 6, leaf)
			scene.draw_circle(Vector2(tx - 1, 5), 3, leaf.lightened(0.15))
		else:
			scene.draw_line(Vector2(tx + 1, 8), Vector2(tx - 3, 2), leaf, 1.0)
			scene.draw_line(Vector2(tx + 1, 8), Vector2(tx + 5, 3), leaf, 1.0)
			scene.draw_rect(Rect2(tx - 3, 2, 3, 1), Color("#f4f8ff"))
	# 백네트
	scene.draw_rect(Rect2(196, 2, 44, 14), Color(0.2, 0.25, 0.3, 0.35))
	for nx in range(196, 241, 4):
		scene.draw_rect(Rect2(nx, 2, 1, 14), Color("#8a9aa8"))
	scene.draw_rect(Rect2(196, 2, 45, 1), Color("#8a9aa8"))
	scene.draw_rect(Rect2(0, 15, w, 1), Color("#3a2f25"))
	# 내야 흙
	scene.draw_colored_polygon(PackedVector2Array([Vector2(140, 34), Vector2(190, 58), Vector2(140, 82), Vector2(90, 58)]), Color("#b8804c") if season != "winter" else Color("#b89a7c"))
	for b in [Vector2(140, 34), Vector2(190, 58), Vector2(140, 82), Vector2(90, 58)]:
		scene.draw_rect(Rect2(b.x - 1, b.y - 1, 3, 3), Color.WHITE)
	# 겨울: 운동장에 쌓인 눈
	if season == "winter":
		var sr := RandomNumberGenerator.new()
		sr.seed = 3
		for i in 140:
			scene.draw_rect(Rect2(sr.randi_range(0, 279), sr.randi_range(16, 83), sr.randi_range(2, 5), 1), Color("#eef4ff"))
	var t: Dictionary = st()["teams"][st()["userTeamId"]]
	var cap := Color(t["colors"][0])
	var acc := Color(t["colors"][1])
	# 달리는 선수들
	for i in 5:
		var phase := anim_t * 0.25 + i * 0.2
		var x := fmod(phase * 280.0, 320.0) - 20
		var y := 20.0 + i * 12
		var frame := 1 + int(anim_t * 8 + i) % 2
		scene.draw_rect(Rect2(roundi(x) + 1, roundi(y) + 11, 7, 2), Color(0, 0, 0, 0.3))
		scene.draw_texture(PixelArt.sprite(Color("#f4f4f4"), cap, acc, frame), Vector2(roundi(x), roundi(y)))
	# 투수 연습
	var sw := int(anim_t * 2) % 2
	scene.draw_texture(PixelArt.sprite(Color("#f4f4f4"), cap, acc, 0), Vector2(136, 52))
	var bx := 140.0 + (fmod(anim_t, 0.5) / 0.5) * 0.0
	var by := 58.0 + fmod(anim_t * 60.0, 24.0)
	if sw == 0:
		scene.draw_rect(Rect2(bx, by, 2, 2), Color.WHITE)
	# 계절 입자: 벚꽃잎 · 낙엽 · 눈
	var season2 := "spring" if Cal.month_of(st()["date"]) in [3, 4] else ("autumn" if Cal.month_of(st()["date"]) in [10, 11] else ("winter" if Cal.month_of(st()["date"]) in [12, 1, 2] else ""))
	if season2 != "":
		var pc: Color = {"spring": Color("#ffd0dc"), "autumn": Color("#e8903a"), "winter": Color("#ffffff")}[season2]
		for i in 18:
			var px := fmod(i * 37.0 + anim_t * (8.0 + i % 4) + sin(anim_t * 1.3 + i) * 6.0, 290.0) - 5.0
			var py := fmod(i * 13.0 + anim_t * (10.0 + i % 3 * 4.0), 90.0) - 4.0
			scene.draw_rect(Rect2(roundi(px), roundi(py), 2 if season2 != "winter" else 1 + i % 2, 1 + i % 2), pc)
	# 테두리 (안쪽 밝은 선 + 바깥 어두운 선)
	scene.draw_rect(Rect2(0, 0, w, h), Color("#0c0f22"), false)
	scene.draw_rect(Rect2(1, 1, w - 2, 1), Color(1, 1, 1, 0.15))
	var label := "이번 주: 훈련 카드 선택 대기" if not st()["weekTrained"] else ("경기일" if st().get("pendingFixture") != null else "연습 중")
	scene.draw_rect(Rect2(2, 70, UI.font_small.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6, 12), Color(0, 0, 0, 0.45))
	scene.draw_string(UI.font_small, Vector2(4, 80), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffffffcc"))
