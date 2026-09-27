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
	"facilities": "res://scripts/ui/screens/facilities_screen.gd",
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
	var bg := ColorRect.new()
	bg.color = UI.BG
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
	for a in OS.get_cmdline_user_args():
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
		elif a == "--newgame":
			Game.state = Season.start_new_game({"schoolName": "한빛고", "managerName": "테스트", "groupId": "seoulA", "seed": 7})
	if days > 0:
		_debug_advance(days)
	if pitches >= 0:
		_debug_match(pitches)
	show_screen(start)
	if "--boxscore" in OS.get_cmdline_user_args() and Game.current_match != null:
		MatchAI.play_out(Game.current_match)
		show_panel("박스스코어", BoxScore.build(Game.current_match))
	if "--night" in OS.get_cmdline_user_args() and current.get("field") != null:
		current.field.night = true
		current.field.weather = "가랑비"
	if "--usecard" in OS.get_cmdline_user_args() and current.has_method("_use_card"):
		current._use_card(Game.state["hand"][0]["id"])
	if shot != "":
		_take_shot(shot)
	if "--uitest" in OS.get_cmdline_user_args():
		add_child(load("res://tests/ui_flow_test.gd").new())


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
	host.add_child(s)
	if s.has_method("setup"):
		s.setup(params)
	Game.bgm("match" if screen == "match" else "title")


## 모달 대화상자. on_close 는 닫힐 때 호출
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
	p.reset_size()
	await get_tree().process_frame
	if is_instance_valid(p):
		p.position = ((Vector2(640, 360) - p.size) / 2).floor()


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
	show_modal("경기 종료", BoxScore.summary(m), "good" if m.winner == u.team_id else "info", Callable(), [
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
	show_modal(pop["title"], pop["body"], pop.get("kind", "info"), func(): drain_popups(done))
