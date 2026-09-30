class_name UI
extends RefCounted
## 공용 UI 키트: 팔레트, 픽셀 폰트, 테마, 위젯 생성 헬퍼.
## 화면(640×360, 정수배 확대)은 전부 코드로 조립한다.

const BG := Color("#14182b")
const PANEL := Color("#1f2540")
const PANEL2 := Color("#29305a")
const LINE := Color("#3a4270")
const TEXT := Color("#e8e8f0")
const DIM := Color("#9aa0c0")
const ACCENT := Color("#f4d35e")
const GOOD := Color("#6fd08c")
const BAD := Color("#ef6f6c")
const IDOL := Color("#c792ea")
const BTN := Color("#2c3563")

const KIND_COLORS := {"info": TEXT, "good": GOOD, "bad": BAD, "idol": IDOL, "result": TEXT}
## 특수능력 등급 색: 금특(노랑) · 긍정(파랑) · 부정(빨강)
const TIER_COLORS := {"gold": Color("#f4c542"), "good": Color("#5fa8ff"), "bad": Color("#ef6f6c")}
const TIER_KO := {"gold": "금특", "good": "긍정", "bad": "부정"}
const FOR_KO := {"bat": "타자", "pit": "투수", "all": "공통"}

static var font: Font
static var font_bold: Font
static var font_small: Font
static var theme: Theme


static func init_theme() -> Theme:
	if theme != null:
		return theme
	font = load("res://assets/fonts/Galmuri11.ttf")
	font_bold = load("res://assets/fonts/Galmuri11-Bold.ttf")
	font_small = load("res://assets/fonts/Galmuri9.ttf")
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 12
	for cls in ["Label", "Button", "LineEdit", "OptionButton", "CheckBox", "RichTextLabel", "PopupMenu", "ItemList", "TooltipLabel"]:
		t.set_color("font_color", cls, TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_disabled_color", "Button", Color(DIM, 0.6))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_stylebox("normal", "Button", frame(BTN, Color("#0c0f22"), "raised"))
	t.set_stylebox("hover", "Button", frame(BTN.lightened(0.1), ACCENT, "raised"))
	t.set_stylebox("pressed", "Button", frame(ACCENT.darkened(0.05), ACCENT.darkened(0.55), "pressed"))
	t.set_stylebox("disabled", "Button", frame(BTN.darkened(0.35), Color("#0c0f22"), "panel"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for cls in ["OptionButton"]:
		t.set_stylebox("normal", cls, sb(PANEL2, LINE))
		t.set_stylebox("hover", cls, sb(PANEL2, ACCENT))
		t.set_stylebox("pressed", cls, sb(PANEL2, ACCENT))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, LINE))
	t.set_stylebox("panel", "Panel", sb(PANEL, LINE))
	t.set_stylebox("normal", "LineEdit", sb(PANEL2, LINE))
	t.set_stylebox("focus", "LineEdit", sb(PANEL2, ACCENT))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("panel", "PopupMenu", sb(PANEL, ACCENT))
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("hover", "PopupMenu", flat(PANEL2, PANEL2, 0))
	t.set_stylebox("panel", "TooltipPanel", sb(PANEL, ACCENT))
	t.set_stylebox("scroll", "VScrollBar", flat(PANEL, PANEL, 0))
	t.set_stylebox("grabber", "VScrollBar", flat(LINE, LINE, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(ACCENT, ACCENT, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT, ACCENT, 0))
	t.set_stylebox("scroll", "HScrollBar", flat(PANEL, PANEL, 0))
	t.set_stylebox("grabber", "HScrollBar", flat(LINE, LINE, 0))
	t.set_constant("separation", "HBoxContainer", 4)
	t.set_constant("separation", "VBoxContainer", 2)
	theme = t
	return t


## 패널·버튼 테두리. 테두리가 있으면 도트풍 입체 프레임(frame), 없으면 단색
static func sb(bg: Color, border: Color, bw := 1, pad := 3) -> StyleBox:
	if bw > 0:
		return frame(bg, border, "panel", pad)
	return flat(bg, border, bw, pad)


static func flat(bg: Color, border: Color, bw := 1, pad := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.content_margin_top = pad - 1
	s.content_margin_bottom = pad - 1
	s.anti_aliasing = false
	return s


static var _frames := {}


## 도트풍 입체 프레임 (9-slice 텍스처). kind:
##  panel   — 바깥 테두리 + 윗변·왼변 밝게, 아랫변·오른변 어둡게 + 오른쪽 아래 그림자 1px
##  raised  — 버튼: 입체감이 더 강하고 그림자
##  pressed — 눌린 버튼: 명암 반대, 그림자 없음, 글자가 1px 아래로
static func frame(fill: Color, outline: Color, kind := "panel", pad := 3) -> StyleBoxTexture:
	var key := "%s|%s|%s|%d" % [fill.to_html(), outline.to_html(), kind, pad]
	if _frames.has(key):
		return _frames[key]
	var n := 9
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var core := n - 1 # 마지막 줄·칸은 그림자 자리
	var hi := fill.lightened(0.22 if kind == "raised" else 0.12)
	var lo := fill.darkened(0.35 if kind == "raised" else 0.25)
	if kind == "pressed":
		hi = fill.darkened(0.3)
		lo = fill.lightened(0.08)
	for y in core:
		for x in core:
			var c := fill
			if x == 0 or y == 0 or x == core - 1 or y == core - 1:
				c = outline
			elif y == 1 or x == 1:
				c = hi
			elif y == core - 2 or x == core - 2:
				c = lo
			img.set_pixel(x, y, c)
	# 모서리 1px 깎기
	for p in [Vector2i(0, 0), Vector2i(core - 1, 0), Vector2i(0, core - 1), Vector2i(core - 1, core - 1)]:
		img.set_pixelv(p, Color(0, 0, 0, 0))
	# 그림자 (오른쪽·아래 1px)
	if kind != "pressed":
		var sh := Color(0, 0, 0, 0.45)
		for i in range(1, n):
			img.set_pixel(i, n - 1, sh)
			img.set_pixel(n - 1, i, sh)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = 3
	s.texture_margin_top = 3
	s.texture_margin_right = 4
	s.texture_margin_bottom = 4
	# 그림자 1px 은 칸 밖으로
	s.expand_margin_right = 1
	s.expand_margin_bottom = 1
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad - 1 + (1 if kind == "pressed" else 0)
	s.content_margin_bottom = pad - 1 - (1 if kind == "pressed" else 0)
	_frames[key] = s
	return s


## 화면 배경 무늬 (아주 옅은 대각선 점무늬, 타일)
static func bg_pattern() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var dot := BG.lightened(0.05)
	for i in 8:
		img.set_pixel(i, i, dot)
	img.set_pixel(4, 0, BG.lightened(0.03))
	return ImageTexture.create_from_image(img)


static func label(text: String, color: Color = TEXT, small := false, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if small:
		l.add_theme_font_override("font", font_small)
		l.add_theme_font_size_override("font_size", 10)
	elif bold:
		l.add_theme_font_override("font", font_bold)
	return l


static func wrap_label(text: String, width: int, color: Color = TEXT, small := false) -> Label:
	var l := label(text, color, small)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


static func button(text: String, cb: Callable, min_w := 0, small := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	if small:
		b.add_theme_font_override("font", font_small)
		b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(func(): Game.sfx("click", -8.0))
	b.pressed.connect(cb)
	return b


## 아이콘 + 글자 버튼 (왼쪽 정렬)
static func icon_button(text: String, icon_name: String, cb: Callable, min_w := 0, small := false) -> Button:
	var b := button(text, cb, min_w, small)
	b.icon = Icons.get_icon(icon_name)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("h_separation", 5)
	return b


## 아이콘 한 장 (TextureRect)
static func icon(icon_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.get_icon(icon_name)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(10, 12)
	return t


static func panel(bg: Color = PANEL, border: Color = LINE, pad := 4) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, 1, pad))
	return p


static func vbox(sep := 2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func grid(cols: int, hsep := 6, vsep := 1) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	return g


static func scroll(child: Control, min_size := Vector2.ZERO) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size = min_size
	s.add_child(child)
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


static func spacer(w := 0, h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	return c


static var _header_sb: StyleBoxFlat


## 제목 띠: 왼쪽 노란 막대 + 옅은 바탕 + 밑줄
static func title_label(text: String) -> Label:
	var l := label(text, ACCENT, false, true)
	if _header_sb == null:
		_header_sb = StyleBoxFlat.new()
		_header_sb.bg_color = Color(PANEL2, 0.85)
		_header_sb.border_color = ACCENT
		_header_sb.border_width_left = 3
		_header_sb.content_margin_left = 6
		_header_sb.content_margin_right = 4
		_header_sb.content_margin_top = 0
		_header_sb.content_margin_bottom = 1
		_header_sb.anti_aliasing = false
	l.add_theme_stylebox_override("normal", _header_sb)
	return l


## 능력치 등급 문자 + 수치
static func grade_label(v: float, show_num := true, small := true) -> Label:
	var txt := PlayerUtil.letter(v) + ((" %d" % roundi(v)) if show_num else "")
	return label(txt, PlayerUtil.letter_color(v), small)


static func bar(v: float, maxv: float, w: int, color: Color) -> Control:
	var c := ColorRect.new()
	c.color = PANEL2
	c.custom_minimum_size = Vector2(w, 5)
	var f := ColorRect.new()
	f.color = color
	f.size = Vector2(roundi(w * clampf(v / maxv, 0, 1)), 5)
	c.add_child(f)
	return c


static func option(items: Array, selected: int, cb: Callable, small := true) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.selected = selected
	if small:
		o.add_theme_font_override("font", font_small)
		o.add_theme_font_size_override("font_size", 10)
	o.item_selected.connect(cb)
	return o


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ───────────── 특수능력 칩 ─────────────

## 특수능력 한 개를 등급 색 칩으로. 누르면 설명 (clickable=false 면 표시만)
static func ability_chip(id: String, clickable := true) -> Button:
	var a := Abilities.info(id)
	var t: String = a.get("tier", "good")
	var col: Color = TIER_COLORS[t]
	var b := Button.new()
	b.text = ("★" if t == "gold" else "") + a.get("name", id)
	b.set_meta("abilityId", id)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_small)
	b.add_theme_font_size_override("font_size", 10)
	var bg := col.darkened(0.55) if t != "gold" else Color("#5a4510")
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, col.lightened(0.3) if t != "gold" else Color("#ffe27a"))
	b.add_theme_stylebox_override("normal", sb(bg, col, 1, 2))
	b.add_theme_stylebox_override("hover", sb(bg.lightened(0.12), col.lightened(0.3), 1, 2))
	b.add_theme_stylebox_override("pressed", sb(bg.lightened(0.2), col.lightened(0.3), 1, 2))
	if clickable:
		b.pressed.connect(func(): Game.main.show_modal(a.get("name", id), ability_text(id)))
	else:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## 특수능력 설명 (등급·대상·효과·진화)
static func ability_text(id: String) -> String:
	var a := Abilities.info(id)
	var t: String = a.get("tier", "good")
	var txt := "[%s · %s]\n%s" % [TIER_KO[t], FOR_KO[a.get("for", "bat")], a.get("desc", "")]
	var up := Abilities.gold_of(id)
	if up != "":
		txt += "\n\n금특 진화: 「%s」 — %s" % [Abilities.name_of(up), Abilities.info(up).get("desc", "")]
	if t == "bad":
		txt += "\n\n훈련 중 각성으로 극복하거나, 장터의 「나쁜 버릇 교정서」로 없앨 수 있다."
	return txt


## 여러 특수능력을 금특 → 긍정 → 부정 순으로 줄바꿈 배치
static func ability_flow(ids: Array, width: int, clickable := true) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.custom_minimum_size.x = width
	f.add_theme_constant_override("h_separation", 2)
	f.add_theme_constant_override("v_separation", 2)
	for id in Abilities.sorted(ids):
		f.add_child(ability_chip(id, clickable))
	return f


## 색 범례 한 줄
static func tier_legend() -> HBoxContainer:
	var h := hbox(6)
	for t in ["gold", "good", "bad"]:
		h.add_child(label("■ " + TIER_KO[t], TIER_COLORS[t], true))
	return h


## 특수능력 도감: 대상별로 금특 → 긍정 → 부정 칩 목록
static func ability_catalog() -> VBoxContainer:
	var v := vbox(4)
	var top := hbox(8)
	top.add_child(tier_legend())
	top.add_child(label("칩을 누르면 설명", DIM, true))
	# 게임 중이면 우리 팀에 나타난 적 있는 능력만 또렷하게 (수집률)
	var seen = Game.state.get("seenAbilities") if not Game.state.is_empty() else null
	if seen != null:
		top.add_child(label("수집 %d/%d (흐린 칩은 아직 우리 팀에 없던 능력)" % [seen.size(), Abilities.all().size()], ACCENT, true))
	v.add_child(top)
	for f in [["bat", "타자 (타격·주루·수비)"], ["pit", "투수"], ["all", "공통 (훈련·부상·피로·컨디션)"]]:
		var ids := []
		for a in Abilities.all():
			if a["for"] == f[0]:
				ids.append(a["id"])
		v.add_child(label("%s  %d종" % [f[1], ids.size()], ACCENT, true))
		var fl := ability_flow(ids, 540)
		if seen != null:
			for chip in fl.get_children():
				chip.modulate.a = 1.0 if seen.has(chip.get_meta("abilityId", "")) else 0.4
		v.add_child(fl)
	return v
