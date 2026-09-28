class_name HighlightReplay
extends FieldView
## 명장면 다시 보기: 도트 야구장 위로 저장된 타구(방향·거리·종류)만 다시 날려 보낸다 (선수·주자 없음)

var hl: Dictionary = {}
var _ct := 0.0
var _flash := 0.0


func setup_replay(h: Dictionary) -> void:
	hl = h
	custom_minimum_size = Vector2(W, H)
	_ct = -0.4


func _process(delta: float) -> void:
	super._process(delta)
	_ct += delta
	# 한 번 날아간 뒤 잠시 멈췄다가 되풀이
	if _ct > _dur() + 1.4:
		_ct = -0.4
	queue_redraw()


func _dur() -> float:
	var b: Dictionary = hl.get("b", {})
	if b.is_empty():
		return 0.6
	if b["type"] == "PU":
		return 1.2
	return 0.5 + float(b["dist"]) / 90.0


func _draw() -> void:
	super._draw()
	var b: Dictionary = hl.get("b", {})
	var plate := HOME + Vector2(0, -5)
	var t := clampf(_ct / _dur(), 0.0, 1.0)
	if _ct < 0:
		t = 0.0
	if b.is_empty():
		# 타구가 없는 장면(삼진·볼넷 끝내기 등): 투구가 미트에 꽂힌다
		var from := to_screen(0, 18.4)
		var p := from.lerp(plate, t)
		draw_circle(p, 2.0, Color.WHITE)
		if t >= 1.0:
			_label(hl.get("text", ""), Vector2(20, 20))
		return
	var land := to_screen(float(b["angle"]), float(b["dist"]) if b["result"] != "HR" else 150.0)
	var peak: float = {"GB": 0.0, "LD": 10.0, "FB": 46.0, "PU": 60.0, "BUNT": 2.0}.get(b["type"], 20.0)
	if b["result"] == "HR":
		peak = 70.0
	# 궤적 (지나온 길은 점선)
	for i in 20:
		var s := float(i) / 20.0
		if s > t:
			break
		var gp := plate.lerp(land, s)
		draw_rect(Rect2(gp - Vector2(1, 1) + Vector2(0, -peak * 4.0 * s * (1.0 - s)), Vector2(2, 2)), Color(1, 0.95, 0.6, 0.75))
	var g := plate.lerp(land, t)
	var h := peak * 4.0 * t * (1.0 - t)
	draw_circle(g, 2.0, Color(0, 0, 0, 0.45))
	draw_circle(g + Vector2(0, -h), 3.0, Color.WHITE)
	if t >= 1.0:
		var word: String = {"HR": "홈런!!", "1B": "안타!", "2B": "2루타!", "3B": "3루타!", "SF": "희생플라이", "E": "실책!"}.get(b["result"], "")
		if word != "":
			_label(word, land + Vector2(-16, -26))
		_label(hl.get("text", ""), Vector2(20, 20))


func _label(txt: String, pos: Vector2) -> void:
	var f: Font = UI.font
	draw_string(f, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.7))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f4d35e"))
