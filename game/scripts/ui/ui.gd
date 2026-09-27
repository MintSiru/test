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
	t.set_stylebox("normal", "Button", sb(BTN, LINE))
	t.set_stylebox("hover", "Button", sb(BTN.lightened(0.08), ACCENT))
	t.set_stylebox("pressed", "Button", sb(ACCENT, ACCENT))
	t.set_stylebox("disabled", "Button", sb(Color(BTN, 0.5), Color(LINE, 0.5)))
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
	t.set_stylebox("hover", "PopupMenu", sb(PANEL2, PANEL2, 0))
	t.set_stylebox("panel", "TooltipPanel", sb(PANEL, ACCENT))
	t.set_stylebox("scroll", "VScrollBar", sb(PANEL, PANEL, 0))
	t.set_stylebox("grabber", "VScrollBar", sb(LINE, LINE, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(ACCENT, ACCENT, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", sb(ACCENT, ACCENT, 0))
	t.set_stylebox("scroll", "HScrollBar", sb(PANEL, PANEL, 0))
	t.set_stylebox("grabber", "HScrollBar", sb(LINE, LINE, 0))
	t.set_constant("separation", "HBoxContainer", 4)
	t.set_constant("separation", "VBoxContainer", 2)
	theme = t
	return t


static func sb(bg: Color, border: Color, bw := 1, pad := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.content_margin_top = pad - 1
	s.content_margin_bottom = pad - 1
	s.anti_aliasing = false
	return s


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


static func title_label(text: String) -> Label:
	var l := label(text, ACCENT, false, true)
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
