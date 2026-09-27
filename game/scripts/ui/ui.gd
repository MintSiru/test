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


# ───────────── 특수능력 칩 ─────────────

## 특수능력 한 개를 등급 색 칩으로. 누르면 설명 (clickable=false 면 표시만)
static func ability_chip(id: String, clickable := true) -> Button:
	var a := Abilities.info(id)
	var t: String = a.get("tier", "good")
	var col: Color = TIER_COLORS[t]
	var b := Button.new()
	b.text = ("★" if t == "gold" else "") + a.get("name", id)
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
	v.add_child(top)
	for f in [["bat", "타자 (타격·주루·수비)"], ["pit", "투수"], ["all", "공통 (훈련·부상·피로·컨디션)"]]:
		var ids := []
		for a in Abilities.all():
			if a["for"] == f[0]:
				ids.append(a["id"])
		v.add_child(label("%s  %d종" % [f[1], ids.size()], ACCENT, true))
		v.add_child(ability_flow(ids, 540))
	return v
