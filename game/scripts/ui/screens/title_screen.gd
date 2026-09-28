class_name TitleScreen
extends BaseScreen
## 타이틀 화면

var t := 0.0
var sky: Control


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
	if Game.has_save():
		v.add_child(UI.button("이어하기", _continue, 140))
	v.add_child(UI.button("새 게임", func(): Game.goto("new_game"), 140))
	v.add_child(UI.button("도움말", func(): Help.index_panel(), 140))
	# 안드로이드 브라우저: 주소창을 없애 화면을 넓게 (iPhone Safari 는 전체 화면을 지원하지 않는다)
	if OS.has_feature("web_android"):
		v.add_child(UI.button("전체 화면", func(): Game.toggle_fullscreen(), 140))
	if OS.get_name() != "Web":
		v.add_child(UI.button("종료", func(): get_tree().quit(), 140))
	var note := UI.label("주말리그 · 이마트배 · 황금사자기 · 청룡기 · 대통령배 · 봉황대기 · 전국체전", UI.DIM, true)
	UI.place(note, 150, 320, 400, 12)
	add_child(note)
	var ver := UI.label("v0.5  폰트: Galmuri (OFL)", UI.DIM, true)
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


func _process(delta: float) -> void:
	t += delta
	sky.queue_redraw()


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
