extends Control
## 루트 화면: 화면 전환 + 팝업(모달) 표시

const SCREENS := {
	"title": "res://scripts/ui/screens/title_screen.gd",
	"new_game": "res://scripts/ui/screens/new_game_screen.gd",
	"hub": "res://scripts/ui/screens/hub_screen.gd",
	"roster": "res://scripts/ui/screens/roster_screen.gd",
	"lineup": "res://scripts/ui/screens/lineup_screen.gd",
	"schedule": "res://scripts/ui/screens/schedule_screen.gd",
	"scout": "res://scripts/ui/screens/scout_screen.gd",
	"records": "res://scripts/ui/screens/records_screen.gd",
	"shop": "res://scripts/ui/screens/shop_screen.gd",
	"bag": "res://scripts/ui/screens/bag_screen.gd",
	"prematch": "res://scripts/ui/screens/prematch_screen.gd",
	"match": "res://scripts/ui/screens/match_screen.gd",
}

var host: Control
var modal_layer: Control
var current: Control
var current_name := ""
var shot_delay := 0.0


func _ready() -> void:
	theme = UI.init_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = UI.bg_pattern()
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)
	Game.main = self
	# 개발용: -- --newgame --screen=hub --shot=경로.png --days=N
	var start := "title"
	var shot := ""
	var days := 0
	var pitches := -1
	shot_delay = 0.0
	for a in dev_args():
		if a.begins_with("--screen="):
			start = a.substr(9)
		elif a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--delay="):
			shot_delay = a.substr(8).to_float()
		elif a == "--watch" and not Game.state.is_empty():
			Game.state["settings"]["pauseMode"] = "watch"
			Game.state["settings"]["speed"] = 3
		elif a.begins_with("--pitches="):
			pitches = a.substr(10).to_int()
		elif a == "--notut" and not Game.state.is_empty():
			Game.state["settings"]["tutorial"] = false
		elif a == "--newgame":
			Game.state = Season.start_new_game({"schoolName": "한빛고", "managerName": "테스트", "groupId": "seoulA", "seed": 7})
	if days > 0:
		_debug_advance(days)
	if pitches >= 0:
		_debug_match(pitches)
	var params := {}
	for a3 in dev_args():
		if a3.begins_with("--tab="):
			params["tab"] = a3.substr(6)
	show_screen(start, params)
	if "--boxscore" in dev_args() and Game.current_match != null:
		MatchAI.play_out(Game.current_match)
		show_panel("박스스코어", BoxScore.build(Game.current_match))
	if "--night" in dev_args() and current.get("field") != null:
		current.field.night = true
		current.field.weather = "가랑비"
	# 개발용: 비시즌 선택 팝업 보기 (--choice=camp / --choice=counsel)
	for a2 in dev_args():
		if a2.begins_with("--choice=") and not Game.state.is_empty():
			if a2.ends_with("camp"):
				Offseason.camp_event(Game.state)
			elif a2.ends_with("talk"):
				Stories.monthly_talk(Game.state, Rng.new(3))
			else:
				Offseason.counsel_event(Game.state)
			drain_popups()
	if "--catalog" in dev_args():
		show_panel("특수능력 도감", UI.ability_catalog())
	# 개발용: 졸업 앨범 미리보기 (--album, 지금 3학년으로)
	if "--album" in dev_args() and not Game.state.is_empty():
		var al := []
		for p in WorldGen.team_players(Game.state, Game.state["userTeamId"]):
			if PlayerUtil.grade(p, Game.state["year"]) == 3:
				al.append(Season.album_entry(Game.state, p, "대학 진학" if al.size() % 2 else "프로 입단", al.size() % 2 == 0))
		show_album({"title": "졸업 앨범 (미리보기)", "album": al}, Callable())
	# 개발용: 우승 연출 보기 (--trophy)
	if "--trophy" in dev_args() and not Game.state.is_empty():
		show_trophy({"title": "청룡기 우승!", "sub": "결승 vs 남산고 5:3", "body": "한빛고, 청룡기 우승!!\n전국에 이름을 떨쳤다. (명성 +10)"}, Callable())
	# 개발용: 기록실에서 가장 최근 명장면 다시 보기 (--screen=records --replay)
	if "--replay" in dev_args() and current.has_method("_replay") and not Game.state.get("highlights", []).is_empty():
		var hls: Array = Game.state["highlights"]
		var pick: Dictionary = hls[hls.size() - 1]
		for h in hls:
			if h.has("b") and h["b"]["result"] == "HR":
				pick = h
		current._replay(pick)
	if "--usecard" in dev_args() and current.has_method("_use_card"):
		current._use_card(Game.state["hand"][0]["id"])
	if shot != "":
		_take_shot(shot)
	if "--uitest" in dev_args():
		add_child(load("res://tests/ui_flow_test.gd").new())
	# 성능 측정: 웹은 index.html?bench, 데스크톱은 -- --webbench
	if "--webbench" in dev_args() or "--bench" in dev_args():
		add_child(load("res://scripts/dev/web_bench.gd").new())
	if "--uiseason" in dev_args():
		add_child(load("res://tests/ui_season_test.gd").new())


# ───────────── 길게 누르기 → 설명 (터치 화면에는 마우스 올리기가 없다) ─────────────

var _press_pos := Vector2.ZERO
var _press_ms := -1
var _long_fired := false


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_press_pos = e.position
			_press_ms = Time.get_ticks_msec()
			_long_fired = false
		else:
			_press_ms = -1
			if _long_fired:
				get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if _press_ms >= 0 and e.position.distance_to(_press_pos) > 10:
			_press_ms = -1
	elif e is InputEventMouseButton and not e.pressed and _long_fired:
		# 길게 눌러 설명을 봤으면 손을 뗄 때 버튼이 눌리지 않게
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _press_ms >= 0 and Time.get_ticks_msec() - _press_ms > 550:
		_press_ms = -1
		var c := _tip_control(self, _press_pos)
		if c != null:
			_long_fired = true
			# 닫으면 화면의 버튼을 다시 그린다 (눌린 모양으로 남지 않게)
			show_modal("설명", c.tooltip_text, "info", func():
				if current != null and current.has_method("_refresh_tactics"):
					current._refresh_tactics())


## 그 위치에 있는, 설명(tooltip)이 달린 가장 안쪽 컨트롤
func _tip_control(n: Node, pos: Vector2) -> Control:
	var found: Control = null
	for ch in n.get_children():
		if ch is CanvasItem and not ch.visible:
			continue
		var sub := _tip_control(ch, pos)
		if sub != null:
			found = sub
		elif ch is Control and ch.tooltip_text != "" and ch.get_global_rect().has_point(pos):
			found = ch
	return found


## 개발용 인자: 데스크톱은 명령줄(-- --newgame …), 웹은 주소 뒤 ?newgame&days=5&screen=match 도 같은 뜻
## (모바일 화면 자동 점검 tools/mobile_check.mjs 가 쓴다)
static var _dev_args: Array = []


static func dev_args() -> Array:
	if not _dev_args.is_empty():
		return _dev_args
	var out: Array = Array(OS.get_cmdline_user_args())
	if OS.get_name() == "Web":
		var q := str(JavaScriptBridge.eval("location.search"))
		for part in q.trim_prefix("?").split("&", false):
			out.append("--" + part.uri_decode())
	_dev_args = out
	if _dev_args.is_empty():
		_dev_args = [""]
	return _dev_args


func _debug_advance(days: int) -> void:
	var s: Dictionary = Game.state
	var target := Cal.add_days(s["date"], days)
	for guard in 5000:
		var r := Season.advance(s, 1)
		if r == "training":
			Season.use_card(s, s["hand"][0]["id"])
		elif r == "popup":
			s["popups"].clear()
		elif r == "match":
			if s["date"] >= target:
				break
			Season.auto_play_user_match(s)
		elif s["date"] > target:
			break


func _debug_match(n: int) -> void:
	var fx := Season.find_fixture(Game.state, Game.state.get("pendingFixture", ""))
	if fx.is_empty():
		return
	var m := Season.create_match(Game.state, fx["f"], Rng.new(3))
	Game.current_match = m
	for i in n:
		if m.over:
			break
		MatchAI.pitching_change(m, m.def())
		m.step(MatchAI.orders(m))


func _take_shot(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	if shot_delay > 0:
		await get_tree().create_timer(shot_delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func show_screen(screen: String, params := {}) -> void:
	if current:
		host.remove_child(current)
		current.queue_free()
	var s: Control = load(SCREENS[screen]).new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	current = s
	current_name = screen
	print("SCREEN ", screen) # 자동 점검 도구(tools/mobile_check.mjs)가 화면 전환을 읽는다
	host.add_child(s)
	if s.has_method("setup"):
		s.setup(params)
	# 화면 전환: 짧은 페이드 인
	s.modulate.a = 0.0
	create_tween().tween_property(s, "modulate:a", 1.0, 0.15)
	Game.bgm(bgm_for(screen))


## 화면별 배경음악: 경기 · 경기 전 · 비시즌(11~2월) · 기본
static func bgm_for(screen: String) -> String:
	match screen:
		"match": return "match"
		"prematch": return "pregame"
	if not Game.state.is_empty() and Cal.month_of(Game.state["date"]) in [11, 12, 1, 2]:
		return "offseason"
	return "title"


## 모달 대화상자. on_close 는 닫힐 때 호출
## 팝업 등장: 배경이 서서히 어두워지고 창이 살짝 아래에서 떠오른다
func _pop_in(shade: ColorRect, p: Control) -> void:
	var a := shade.color.a
	shade.color.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(shade, "color:a", a, 0.12)
	p.modulate.a = 0.0
	var y := p.position.y
	p.position.y = y + 8
	tw.tween_property(p, "modulate:a", 1.0, 0.14)
	tw.tween_property(p, "position:y", y, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_modal(title: String, body: String, kind := "info", on_close: Callable = Callable(), buttons: Array = []) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(shade)
	var border: Color = UI.KIND_COLORS.get(kind, UI.ACCENT)
	var p := UI.panel(UI.PANEL, border, 8)
	var v := UI.vbox(6)
	p.add_child(v)
	var t := UI.title_label(title)
	t.add_theme_color_override("font_color", border if kind != "info" else UI.ACCENT)
	v.add_child(t)
	var body_l := UI.wrap_label(body, 360)
	var sc := UI.scroll(body_l, Vector2(372, mini(220, 16 + body.count("\n") * 15 + body.length() / 30 * 15)))
	v.add_child(sc)
	var row := UI.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var close := func():
		modal_layer.remove_child(shade)
		shade.queue_free()
		if on_close.is_valid():
			on_close.call()
	if buttons.is_empty():
		row.add_child(UI.button("확인", close, 60))
	else:
		for b in buttons:
			var cb: Callable = b[1]
			row.add_child(UI.button(b[0], func():
				close.call()
				cb.call(), 60))
	shade.add_child(p)
	p.modulate.a = 0.0
	p.reset_size()
	await get_tree().process_frame
	if is_instance_valid(p):
		p.position = ((Vector2(640, 360) - p.size) / 2).floor()
		_pop_in(shade, p)


## 임의의 컨트롤을 담는 모달 (스크롤)
func show_panel(title: String, content: Control, on_close: Callable = Callable()) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(shade)
	var p := UI.panel(UI.PANEL, UI.ACCENT, 6)
	UI.place(p, 40, 16, 560, 328)
	shade.add_child(p)
	_pop_in(shade, p)
	var v := UI.vbox(4)
	p.add_child(v)
	v.add_child(UI.title_label(title))
	v.add_child(UI.scroll(content, Vector2(546, 270)))
	var row := UI.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UI.button("확인", func():
		modal_layer.remove_child(shade)
		shade.queue_free()
		if on_close.is_valid():
			on_close.call(), 60))


## 경기 결과 → (박스스코어) → 쌓인 팝업 → done
func show_match_result(m: MatchEngine, done: Callable) -> void:
	var u := m.user_side()
	if m.winner == u.team_id:
		Game.sfx("fanfare")
	var after := func(): drain_popups(done)
	var body := BoxScore.summary(m)
	if not m.highlights.is_empty():
		body += "\n\n[명장면]\n" + "\n".join(m.highlights.map(func(h): return "· %d회%s %s" % [h["inning"], "초" if h["top"] else "말", h["text"]]))
	show_modal("경기 종료", body, "good" if m.winner == u.team_id else "info", Callable(), [
		["박스스코어", func(): show_panel("박스스코어", BoxScore.build(m), after)],
		["확인", after],
	])


## state.popups 를 차례로 보여 주고 끝나면 done 호출
func drain_popups(done: Callable = Callable()) -> void:
	var st: Dictionary = Game.state
	if st.is_empty() or st["popups"].is_empty():
		if done.is_valid():
			done.call()
		return
	var pop: Dictionary = st["popups"].pop_front()
	if pop.get("kind", "") == "choice":
		show_choice(pop, func(): drain_popups(done))
		return
	if pop.get("kind", "") == "trophy":
		show_trophy(pop, func(): drain_popups(done))
		return
	if pop.get("kind", "") == "album":
		show_album(pop, func(): drain_popups(done))
		return
	show_modal(pop["title"], pop["body"], pop.get("kind", "info"), func(): drain_popups(done))


## 졸업 앨범: 3학년마다 얼굴·포지션·3년 통산·타이틀·금특·진로
func show_album(pop: Dictionary, done: Callable) -> void:
	var v := UI.vbox(3)
	v.add_child(UI.label("3년간 함께한 3학년들이 야구부를 떠난다. 고마웠다!", UI.TEXT, true))
	var team := WorldGen.user_team(Game.state)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for a in pop.get("album", []):
		var card := UI.panel(UI.PANEL2, UI.TIER_COLORS["gold"] if a["pro"] else UI.LINE, 3)
		card.custom_minimum_size = Vector2(266, 58)
		var h := UI.hbox(4)
		card.add_child(h)
		var face := TextureRect.new()
		face.texture = PixelArt.portrait(int(a["face"]), Color(team["colors"][0]), Color(team["colors"][1]))
		face.custom_minimum_size = Vector2(24, 24)
		face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		h.add_child(face)
		var info := UI.vbox(0)
		h.add_child(info)
		info.add_child(UI.label("%s %s%s" % [PlayerUtil.POS_KO[a["pos"]], a["name"], "  [주장]" if a.get("captain", false) else ""], UI.ACCENT, true))
		info.add_child(UI.label(a["line"], UI.TEXT, true))
		var extra: Array = a.get("titles", [])
		info.add_child(UI.label("→ " + a["dest"] + (("  · " + ", ".join(extra)) if not extra.is_empty() else ""), UI.GOOD if a["pro"] else UI.DIM, true))
		if not a.get("gold", []).is_empty():
			var fl := UI.hbox(2)
			for id in a["gold"]:
				fl.add_child(UI.ability_chip(id, false))
			info.add_child(fl)
		grid.add_child(card)
	show_panel(pop["title"], v, done)


## 우승 연출: 헹가래 도트 화면 + 우승 문구, 확인을 누르면 done
func show_trophy(pop: Dictionary, done: Callable) -> void:
	Game.sfx("fanfare")
	Game.sfx("cheer", 2.0)
	var v := UI.vbox(4)
	var cv := CelebrationView.new()
	cv.setup_celebration(WorldGen.user_team(Game.state), pop["title"], pop.get("sub", ""))
	v.add_child(cv)
	v.add_child(UI.wrap_label(str(pop["body"]).replace("\n", " "), 540, UI.GOOD, true))
	show_panel("우승!", v, done)


## 선택 팝업 (비시즌 합숙 장소·진로 상담 등): 버튼을 세로로 늘어놓고, 고르면 결과를 보여 준 뒤 done
func show_choice(pop: Dictionary, done: Callable) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(shade)
	var p := UI.panel(UI.PANEL, UI.ACCENT, 8)
	UI.place(p, 110, 30, 420, 300)
	shade.add_child(p)
	_pop_in(shade, p)
	var v := UI.vbox(5)
	p.add_child(v)
	v.add_child(UI.title_label(pop["title"]))
	v.add_child(UI.scroll(UI.wrap_label(pop["body"], 390, UI.TEXT, true), Vector2(404, 170)))
	for o in pop["options"]:
		var key: String = o[0]
		v.add_child(UI.button(o[1], func():
			modal_layer.remove_child(shade)
			shade.queue_free()
			var msg := Offseason.choose(Game.state, pop["choice"], key)
			Game.save_game()
			if msg != "":
				show_modal(pop["title"], msg, "good", done)
			else:
				done.call(), 400, true))
