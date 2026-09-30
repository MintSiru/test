class_name TitleScreen
extends BaseScreen
## 타이틀 화면

var t := 0.0
var sky: Control
var ball_rect: TextureRect
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
	ball_rect = ball
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
	UI.place(v, 250, 172, 140, 120)
	add_child(v)
	# 개발용 --splash: 버튼 없는 화면 → 웹 로딩 이미지(assets/splash.png) 만들기
	v.visible = not "--splash" in load("res://scripts/main.gd").dev_args()
	if Game.has_save():
		v.add_child(UI.icon_button("이어하기", "save", _continue, 140))
	v.add_child(UI.icon_button("새 게임", "ball", func(): Game.goto("new_game"), 140))
	v.add_child(UI.icon_button("도움말", "lineup", func(): Help.index_panel(), 140))
	# 안드로이드 브라우저: 주소창을 없애 화면을 넓게 (iPhone Safari 는 전체 화면을 지원하지 않는다)
	# 휴대폰 브라우저: 홈 화면에 추가하면 주소창 없이 꽉 찬 화면으로, 다음부터 빨리 열린다
	if Game.is_mobile_web() and not _installed():
		v.add_child(UI.button("앱처럼 설치", _install_help, 140))
	if OS.has_feature("web_android"):
		v.add_child(UI.button("전체 화면", func(): Game.toggle_fullscreen(), 140))
	if OS.get_name() != "Web":
		v.add_child(UI.icon_button("종료", "home", func(): get_tree().quit(), 140))
	var note := UI.label("주말리그 · 이마트배 · 황금사자기 · 청룡기 · 대통령배 · 봉황대기 · 전국체전", UI.DIM, true)
	UI.place(note, 236, 345, 400, 12)
	add_child(note)
	var ver := UI.label("v0.9  폰트: Galmuri (OFL)", UI.DIM, true)
	UI.place(ver, 6, 344, 200, 12)
	add_child(ver)
	var notice := UI.wrap_label(GameData.FAN_MADE_NOTICE, 620, Color("#c8c8d8"), true)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(notice, 10, 144, 620, 24)
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
	# 공이 살짝 둥실거린다
	if is_instance_valid(ball_rect):
		ball_rect.position.y = 70 + roundf(sin(t * 2.2) * 2.0)
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
	# 밤하늘 (위는 짙고 지평선은 밝게, 띠 단계)
	var bands := [Color("#0a0d24"), Color("#0e1230"), Color("#12173a"), Color("#161c44"), Color("#1b224e"), Color("#212a5a")]
	for i in bands.size():
		sky.draw_rect(Rect2(0, i * 40, 640, 40), bands[i])
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 70:
		var x := r.randi_range(0, 639)
		var y := r.randi_range(0, 170)
		var tw := 0.5 + 0.5 * sin(t * (1.5 + (i % 5) * 0.4) + i)
		sky.draw_rect(Rect2(x, y, 1, 1), Color(1, 1, 1, 0.25 + 0.6 * tw))
		if i % 11 == 0 and tw > 0.8:
			sky.draw_rect(Rect2(x - 1, y, 3, 1), Color(1, 1, 1, 0.3))
			sky.draw_rect(Rect2(x, y - 1, 1, 3), Color(1, 1, 1, 0.3))
	# 가끔 지나가는 별똥별
	var st_t := fmod(t, 7.0)
	if st_t < 0.6:
		var sx := 420.0 + st_t * 260.0
		var sy := 20.0 + st_t * 70.0
		for k in 8:
			sky.draw_rect(Rect2(sx - k * 4, sy - k * 1.1, 2, 1), Color(1, 1, 0.85, 0.8 - k * 0.1))
	# 조명탑 + 빛줄기 (살짝 깜박임)
	var glow := 0.07 + 0.015 * sin(t * 3.0)
	for lx in [60, 580]:
		var cone := PackedVector2Array([Vector2(lx - 12, 92), Vector2(lx + 12, 92), Vector2(lx + (160 if lx < 320 else -40), 272), Vector2(lx + (40 if lx < 320 else -160), 272)])
		sky.draw_colored_polygon(cone, Color(1, 0.97, 0.75, glow))
		sky.draw_rect(Rect2(lx - 1, 90, 3, 150), Color("#3a3f5c"))
		sky.draw_rect(Rect2(lx - 14, 78, 29, 15), Color("#2a2f4a"))
		for gx in 3:
			for gy in 2:
				sky.draw_rect(Rect2(lx - 12 + gx * 9, 80 + gy * 6, 7, 5), Color("#fff6c8"))
		sky.draw_circle(Vector2(lx, 86), 22, Color(1, 0.97, 0.8, 0.06))
	# 관중석: 지붕선 + 좌석 줄 + 사람
	sky.draw_rect(Rect2(0, 226, 640, 3), Color("#3a4270"))
	sky.draw_rect(Rect2(0, 229, 640, 42), Color("#232a4c"))
	for row in 10:
		sky.draw_rect(Rect2(0, 230 + row * 4, 640, 1), Color("#1b2140"))
	for i in 520:
		var cx := r.randi_range(0, 319) * 2
		var cy := 231 + r.randi_range(0, 9) * 4
		var shirt: Color = [Color("#ef6f6c"), Color("#f4d35e"), Color("#7fa6ff"), Color("#e8e8f0"), Color("#6fd08c"), Color("#c792ea")][i % 6]
		var bob := 1 if sin(t * 6.0 + i * 0.7) > 0.93 else 0 # 가끔 들썩이는 관중
		sky.draw_rect(Rect2(cx, cy - bob, 1, 1), Color("#e0b08a").darkened(0.2))
		sky.draw_rect(Rect2(cx, cy + 1 - bob, 1, 2), shirt.darkened(0.25))
	# 외야 펜스
	sky.draw_rect(Rect2(0, 270, 640, 5), Color("#0f3a22"))
	sky.draw_rect(Rect2(0, 270, 640, 1), Color("#f4d35e"))
	# 잔디 (깎은 결)
	for y in range(275, 360, 6):
		sky.draw_rect(Rect2(0, y, 640, 3), Color("#3c8a45"))
		sky.draw_rect(Rect2(0, y + 3, 640, 3), Color("#337c3c"))
	# 내야 (원근: 홈이 아래 가운데)
	var home := Vector2(320, 356)
	sky.draw_colored_polygon(PackedVector2Array([home + Vector2(0, 4), Vector2(170, 312), Vector2(320, 284), Vector2(470, 312)]), Color("#b8804c"))
	sky.draw_colored_polygon(PackedVector2Array([home + Vector2(0, -14), Vector2(214, 314), Vector2(320, 296), Vector2(426, 314)]), Color("#46994f"))
	sky.draw_line(home, Vector2(40, 278), Color("#f4f4f4"), 1.0)
	sky.draw_line(home, Vector2(600, 278), Color("#f4f4f4"), 1.0)
	sky.draw_circle(Vector2(320, 318), 8, Color("#c68d56"))
	for b in [Vector2(170, 312), Vector2(320, 284), Vector2(470, 312)]:
		sky.draw_rect(Rect2(b - Vector2(2, 1), Vector2(5, 3)), Color.WHITE)
	sky.draw_rect(Rect2(home - Vector2(3, 3), Vector2(7, 3)), Color.WHITE)
	# 아래 정보 띠
	sky.draw_rect(Rect2(0, 341, 640, 19), Color(0, 0, 0, 0.5))
	# 로고 뒤 간판
	sky.draw_rect(Rect2(152, 56, 336, 84), Color(0, 0, 0, 0.35))
	sky.draw_rect(Rect2(150, 54, 336, 84), Color("#1a1f3e"))
	sky.draw_rect(Rect2(150, 54, 336, 84), Color("#f4d35e"), false)
	sky.draw_rect(Rect2(152, 56, 332, 80), Color("#7a5a1a"), false)

