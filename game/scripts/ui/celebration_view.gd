class_name CelebrationView
extends FieldView
## 우승 연출: 마운드에 모인 선수 9명이 감독을 헹가래, 색종이가 흩날린다 (도트 구장 배경은 FieldView 것을 쓴다)

var title_text := ""
var sub_text := ""
var cols: Array = [Color.WHITE, Color.RED, Color.WHITE]
var _ct := 0.0
var confetti: Array = []
const CONF_COLORS := [Color("#f4d35e"), Color("#ef6f6c"), Color("#6fd08c"), Color("#7fd0ff"), Color("#ffffff")]


func setup_celebration(team: Dictionary, title: String, sub: String) -> void:
	custom_minimum_size = Vector2(W, H)
	title_text = title
	sub_text = sub
	cols = [Color(team["colors"][0]), Color(team["colors"][1]), Color.WHITE]
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 70:
		confetti.append({"p": Vector2(r.randf() * W, r.randf() * -H), "v": r.randf_range(25, 55), "c": CONF_COLORS[i % CONF_COLORS.size()], "w": r.randf_range(0, TAU)})


func _process(delta: float) -> void:
	super._process(delta)
	_ct += delta
	for c in confetti:
		c["p"] += Vector2(sin(_ct * 2.0 + c["w"]) * 12.0, c["v"]) * delta
		if c["p"].y > H:
			c["p"] = Vector2(c["p"].x, -4)
	queue_redraw()


func _draw() -> void:
	super._draw()
	var center := to_screen(0, 18.4)
	# 감독 헹가래: 튀어 오르는 높이 (0.9초 주기)
	var ph := fmod(_ct, 0.9) / 0.9
	var up := sin(ph * PI) * 34.0
	# 마운드 위 무리를 2배로 크게 그린다 (좌표는 마운드 기준)
	draw_set_transform(center, 0.0, Vector2(2, 2))
	# 선수들이 원을 그리고 팔을 올렸다 내렸다 (뒤쪽 선수부터)
	var order := range(9)
	order.sort_custom(func(a, b): return sin(TAU * a / 9.0) < sin(TAU * b / 9.0))
	for i in order:
		var a: float = TAU * i / 9.0
		var feet := Vector2(cos(a) * 14, sin(a) * 6)
		var tex := PixelArt.sprite(cols[0], cols[1], cols[2], 1 + (int(_ct * 4 + i) % 2))
		draw_texture(tex, (feet - Vector2(4, 12)).round())
	# 감독 (흰 유니폼)
	var mt := PixelArt.sprite(Color("#e8e8f0"), Color("#2a2f4a"), Color("#f4d35e"), 0)
	draw_texture(mt, (Vector2(0, -8 - up * 0.5) - Vector2(4, 12)).round())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for c in confetti:
		draw_rect(Rect2(c["p"], Vector2(2, 3)), c["c"])
	var f: Font = UI.font_bold if UI.font_bold != null else UI.font
	var tw := f.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(f, Vector2((W - tw) / 2 + 2, 52), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#7a3b10"))
	draw_string(f, Vector2((W - tw) / 2, 50), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#f4d35e"))
	var sw := UI.font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(UI.font, Vector2((W - sw) / 2 + 1, 71), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.7))
	draw_string(UI.font, Vector2((W - sw) / 2, 70), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
