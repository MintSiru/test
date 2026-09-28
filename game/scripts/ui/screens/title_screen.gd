class_name TitleScreen
extends BaseScreen
## 타이틀 화면

var t := 0.0
var sky: Control
var update_btn: Button
var _upd_check := 0.0


func setup(_p := {}) -> void:
	sky = Control.new()
	UI.place(sky, 0, 0, 640, 360)
	sky.draw.connect(_draw_bg)
	add_child(sky)
	var ball := TextureRect.new()
	ball.texture = PixelArt.ball(32)
	UI.place(ball, 176, 70, 32, 32)
	add_child(ball)
	var title := UI.label("청춘나인", UI.ACCENT, false, true)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_shadow_color", Color("#7a3b10"))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	UI.place(title, 216, 64, 260, 44)
	add_child(title)
	var sub := UI.label("한국 고교야구부 육성 시뮬레이션", UI.TEXT)
	UI.place(sub, 222, 112, 260, 16)
	add_child(sub)
	var v := UI.vbox(6)
	UI.place(v, 250, 170, 140, 120)
	add_child(v)
	# 개발용 --splash: 버튼 없는 화면 → 웹 로딩 이미지(assets/splash.png) 만들기
	v.visible = not "--splash" in load("res://scripts/main.gd").dev_args()
	if Game.has_save():
		v.add_child(UI.button("이어하기", _continue, 140))
	v.add_child(UI.button("새 게임", func(): Game.goto("new_game"), 140))
	v.add_child(UI.button("도움말", func(): Help.index_panel(), 140))
	# 안드로이드 브라우저: 주소창을 없애 화면을 넓게 (iPhone Safari 는 전체 화면을 지원하지 않는다)
	# 휴대폰 브라우저: 홈 화면에 추가하면 주소창 없이 꽉 찬 화면으로, 다음부터 빨리 열린다
	if Game.is_mobile_web() and not _installed():
		v.add_child(UI.button("앱처럼 설치", _install_help, 140))
	if OS.has_feature("web_android"):
		v.add_child(UI.button("전체 화면", func(): Game.toggle_fullscreen(), 140))
	if OS.get_name() != "Web":
		v.add_child(UI.button("종료", func(): get_tree().quit(), 140))
	var note := UI.label("주말리그 · 이마트배 · 황금사자기 · 청룡기 · 대통령배 · 봉황대기 · 전국체전", UI.DIM, true)
	UI.place(note, 150, 320, 400, 12)
	add_child(note)
	var ver := UI.label("v0.7  폰트: Galmuri (OFL)", UI.DIM, true)
	UI.place(ver, 6, 344, 200, 12)
	add_child(ver)
	var notice := UI.wrap_label(GameData.FAN_MADE_NOTICE, 620, Color("#c8c8d8"), true)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(notice, 10, 132, 620, 24)
	add_child(notice)


func _continue() -> void:
	var v := UI.vbox(6)
	v.add_child(UI.label("불러올 슬롯을 고르세요.", UI.DIM, true))
	for n in range(1, Game.SLOT_COUNT + 1):
		v.add_child(slot_row(n, true))
	Game.main.show_panel("이어하기", v)


## 슬롯 한 줄: 요약 + 불러오기(또는 선택) / 삭제
static func slot_row(n: int, load_mode: bool, on_pick: Callable = Callable()) -> Control:
	var info := Game.slot_info(n)
	var row := UI.hbox(8)
	var txt := "슬롯 %d  " % n
	if info.is_empty():
		txt += "(비어 있음)"
	else:
		txt += "%s · %s · 명성 %s · %s%s" % [info.get("school", "?"), Cal.pretty(info["date"]) if str(info.get("date", "")) != "" else "?", info.get("reputation", "?"), info.get("record", ""), "  [경기 중]" if info.get("inMatch", false) else ""]
	row.add_child(UI.expand(UI.label(txt, UI.TEXT if not info.is_empty() else UI.DIM, true)))
	if load_mode:
		var b := UI.button("불러오기", func():
			if Game.load_game(n):
				Game.main.modal_layer.get_children().map(func(c): c.queue_free())
				Game.goto("match" if Game.current_match != null else "hub"), 80, true)
		b.disabled = info.is_empty()
		row.add_child(b)
		var d := UI.button("삭제", func():
			Game.main.show_modal("슬롯 %d 삭제" % n, "이 슬롯의 저장 데이터를 지울까요? 되돌릴 수 없습니다.", "bad", Callable(), [["취소", func(): pass], ["삭제", func():
				Game.delete_slot(n)
				Game.main.modal_layer.get_children().map(func(c): c.queue_free())
				Game.goto("title")]]), 50, true)
		d.disabled = info.is_empty()
		row.add_child(d)
	else:
		row.add_child(UI.button("여기에 시작" if info.is_empty() else "덮어쓰기", func(): on_pick.call(n), 80, true))
	return row


static func _installed() -> bool:
	return bool(JavaScriptBridge.eval("window.matchMedia('(display-mode: fullscreen)').matches || window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true", true))


func _install_help() -> void:
	var ios := OS.has_feature("web_ios")
	Game.main.show_modal("앱처럼 설치", ("아이폰 Safari:\n1. 아래(또는 위)의 공유 버튼(네모에 화살표)을 누릅니다.\n2. 「홈 화면에 추가」를 누릅니다.\n" if ios
		else "안드로이드 Chrome:\n1. 오른쪽 위 점 세 개 메뉴를 누릅니다.\n2. 「홈 화면에 추가」 또는 「앱 설치」를 누릅니다.\n")
		+ "\n홈 화면의 「청춘나인」 아이콘으로 열면 주소창 없이 화면이 꽉 차고, 두 번째부터는 인터넷이 없어도 빨리 열립니다.\n저장된 진행은 그대로 이어집니다 (같은 브라우저 기준).")


func _process(delta: float) -> void:
	t += delta
	sky.queue_redraw()
	# 웹(홈 화면 앱): 새 버전을 받아 두었으면 타이틀에서만 「새 버전」 버튼 (경기 중 새로고침으로 진행을 잃지 않도록)
	_upd_check += delta
	if OS.get_name() == "Web" and update_btn == null and _upd_check > 2.0:
		_upd_check = 0.0
		if JavaScriptBridge.eval("window.__cnUpdate === true", true):
			update_btn = UI.button("새 버전으로 업데이트", func(): JavaScriptBridge.eval("window.__cnApplyUpdate()", true), 150)
			update_btn.tooltip_text = "게임이 업데이트됐어요. 누르면 새로 불러옵니다. (저장된 진행은 그대로)"
			update_btn.add_theme_color_override("font_color", UI.ACCENT)
			UI.place(update_btn, 480, 8, 150, 18)
			add_child(update_btn)


func _draw_bg() -> void:
	# 밤하늘 + 조명탑 + 관중석 + 그라운드
	sky.draw_rect(Rect2(0, 0, 640, 360), Color("#101430"))
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 60:
		var x := r.randi_range(0, 639)
		var y := r.randi_range(0, 150)
		var tw := 0.5 + 0.5 * sin(t * 2.0 + i)
		sky.draw_rect(Rect2(x, y, 1, 1), Color(1, 1, 1, 0.3 + 0.5 * tw))
	for lx in [60, 580]:
		sky.draw_rect(Rect2(lx - 1, 90, 3, 150), Color("#3a3f5c"))
		sky.draw_rect(Rect2(lx - 12, 80, 25, 12), Color("#fff6c8"))
		sky.draw_rect(Rect2(lx - 12, 92, 25, 2), Color("#3a3f5c"))
	sky.draw_rect(Rect2(0, 230, 640, 40), Color("#26304f"))
	for i in 300:
		var cx := r.randi_range(0, 639)
		var cy := r.randi_range(232, 266)
		sky.draw_rect(Rect2(cx, cy, 1, 1), [Color("#ef6f6c"), Color("#f4d35e"), Color("#7fa6ff"), Color("#e8e8f0")][i % 4])
	sky.draw_rect(Rect2(0, 270, 640, 4), Color("#1d4d2b"))
	for y in range(274, 360, 6):
		sky.draw_rect(Rect2(0, y, 640, 3), Color("#2f7a3f"))
		sky.draw_rect(Rect2(0, y + 3, 640, 3), Color("#2a6e39"))
	sky.draw_colored_polygon(PackedVector2Array([Vector2(250, 360), Vector2(320, 300), Vector2(390, 360)]), Color("#b07a4a"))
