extends BaseScreen
## 경기 화면: 도트 필드 관전 + 작전 지시 (공격/수비/교체)

const SPEEDS := [1.0, 2.0, 4.0, 8.0]
const SPEED_KO := ["×1", "×2", "×4", "결과만"]
const PAUSE_MODES := ["pitch", "pa", "chance", "watch"]
const PAUSE_KO := {"pitch": "매 투구", "pa": "타석마다", "chance": "찬스·위기만", "watch": "멈추지 않음"}
const OFF_ORDERS := [["normal", "자유 타격"], ["wait", "기다려"], ["aggressive", "적극 공략"], ["bunt", "희생 번트"], ["safetyBunt", "기습 번트"], ["squeeze", "스퀴즈"], ["steal", "도루"], ["hitRun", "히트앤런"]]
const PITCH_ORDERS := [["normal", "자유 투구"], ["zone", "정면 승부"], ["edge", "유인구 위주"], ["ibb", "고의사구"]]
const SHIFT_ORDERS := [["normal", "기본 수비"], ["infieldIn", "전진 수비"], ["buntShift", "번트 시프트"], ["deep", "장타 경계"]]

var m: MatchEngine
var field: FieldView
var board: Control
var info_box: VBoxContainer
var tactic_box: VBoxContainer
var log_label: RichTextLabel
var play_btn: Button
var speed_btn: Button
var pause_btn: Button
var waiting := true
var busy := false
var delegate := false
var speed_idx := 1
var off_order := "normal"
var pitch_order := "normal"
var shift_order := "normal"
var lines: Array = []
var overlay: Control


func setup(_p := {}) -> void:
	m = Game.current_match
	if m == null:
		Game.goto("hub")
		return
	speed_idx = clampi(int(st()["settings"].get("speed", 2)) - 1, 0, 3)
	board = Control.new()
	UI.place(board, 0, 0, 640, 35)
	board.draw.connect(_draw_board)
	add_child(board)
	field = FieldView.new()
	field.position = Vector2(0, 35)
	add_child(field)
	var rp := UI.panel(UI.PANEL, UI.LINE, 3)
	UI.place(rp, 402, 35, 236, 250)
	add_child(rp)
	var rv := UI.vbox(3)
	rp.add_child(rv)
	info_box = UI.vbox(1)
	rv.add_child(info_box)
	tactic_box = UI.vbox(2)
	rv.add_child(tactic_box)
	var lp := UI.panel(UI.PANEL, UI.LINE, 3)
	UI.place(lp, 2, 287, 636, 52)
	add_child(lp)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.add_theme_font_override("normal_font", UI.font_small)
	log_label.add_theme_font_size_override("normal_font_size", 10)
	log_label.custom_minimum_size = Vector2(628, 44)
	lp.add_child(log_label)
	var row := UI.hbox(4)
	UI.place(row, 2, 341, 636, 18)
	add_child(row)
	play_btn = UI.button("▶ 플레이", _toggle_play, 90)
	row.add_child(play_btn)
	speed_btn = UI.button("속도 " + SPEED_KO[speed_idx], _cycle_speed, 80, true)
	row.add_child(speed_btn)
	pause_btn = UI.button("", _cycle_pause, 130, true)
	row.add_child(pause_btn)
	row.add_child(UI.expand(UI.spacer()))
	row.add_child(UI.button("위임 (끝까지 자동)", _delegate_all, 0, true))
	field.sync(m)
	_add_line("[color=#f4d35e]%s vs %s — 플레이 볼![/color]" % [m.away.name, m.home.name])
	_refresh()
	if _pause_mode() == "watch":
		_toggle_play()


func _pause_mode() -> String:
	return st()["settings"].get("pauseMode", "pa")


func _user() -> MatchEngine.TeamSide:
	return m.user_side()


# ───────────── 진행 ─────────────

func _toggle_play() -> void:
	if m.over:
		_show_result()
		return
	if busy:
		waiting = true
		_refresh()
		return
	waiting = false
	_loop()


func _loop() -> void:
	busy = true
	_refresh()
	var guard := 0
	while not m.over and not waiting and guard < 2000:
		guard += 1
		var user := _user()
		if m.def() != user or delegate:
			if MatchAI.pitching_change(m, m.def()):
				_add_line("[color=#9aa0c0]%s[/color]" % m.game_log.back())
		elif m.balls == 0 and m.strikes == 0 and m.def().pitch_count.get(m.def().pitcher_id, 0) >= m.rules["pitchLimit"]:
			if MatchAI.pitching_change(m, m.def()):
				_add_line("[color=#ef6f6c][투구수 105구 제한] %s[/color]" % m.game_log.back())
		var ai := MatchAI.orders(m)
		var orders := ai
		if not delegate:
			if m.off() == user:
				orders = {"off": off_order, "pitch": ai["pitch"], "shift": ai["shift"]}
			else:
				orders = {"off": ai["off"], "pitch": pitch_order, "shift": shift_order}
		field.sync(m, orders["shift"])
		var inning_txt := "%d회%s" % [m.inning, "초" if m.top else "말"]
		var ev := m.step(orders)
		if SPEEDS[speed_idx] < 8.0:
			_refresh_info()
			await field.play(ev, SPEEDS[speed_idx])
		elif guard % 6 == 0:
			await get_tree().process_frame
		_log_event(ev, inning_txt)
		if ev["paResult"] != "":
			off_order = "normal"
			if pitch_order == "ibb":
				pitch_order = "normal"
		field.sync(m, shift_order if m.def() == user else "normal")
		board.queue_redraw()
		if m.over:
			break
		if _should_pause(ev):
			waiting = true
	busy = false
	_refresh()
	if m.over:
		_show_result()


func _should_pause(ev: Dictionary) -> bool:
	if delegate:
		return false
	var new_pa: bool = ev["paResult"] != "" or ev["endHalf"]
	match _pause_mode():
		"pitch": return true
		"pa": return new_pa
		"chance": return new_pa and (m.risp() or m.late_close())
	return false


func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	st()["settings"]["speed"] = speed_idx + 1
	speed_btn.text = "속도 " + SPEED_KO[speed_idx]


func _cycle_pause() -> void:
	var i := PAUSE_MODES.find(_pause_mode())
	st()["settings"]["pauseMode"] = PAUSE_MODES[(i + 1) % PAUSE_MODES.size()]
	_refresh()


func _delegate_all() -> void:
	delegate = true
	speed_idx = 3
	speed_btn.text = "속도 " + SPEED_KO[speed_idx]
	if not busy:
		waiting = false
		_loop()
	else:
		waiting = false


# ───────────── 로그 ─────────────

func _add_line(t: String) -> void:
	lines.append(t)
	if lines.size() > 60:
		lines.pop_front()
	log_label.text = "\n".join(lines)


func _log_event(ev: Dictionary, inning_txt: String) -> void:
	var off_user: bool = (m.away if ev["top"] else m.home) == _user()
	var col := "#e8e8f0"
	if ev["runs"] > 0:
		col = "#6fd08c" if off_user else "#ef6f6c"
	elif ev["paResult"] != "":
		col = "#f4d35e"
	var bn := ""
	var side := m.away if ev["top"] else m.home
	if side.by_id.has(ev["batterId"]):
		bn = side.by_id[ev["batterId"]].name
	if ev["paResult"] != "" or ev["runs"] > 0 or SPEEDS[speed_idx] < 8.0:
		_add_line("[color=#9aa0c0]%s[/color] %s [color=%s]%s[/color]%s" % [inning_txt, bn, col, ev["text"], ("  (+%d점)" % ev["runs"]) if ev["runs"] else ""])
	if ev["endHalf"] and not m.over:
		_add_line("[color=#9aa0c0]── %d회%s  %s %d : %d %s ──[/color]" % [m.inning, "초" if m.top else "말", m.away.name, m.away.score, m.home.score, m.home.name])


# ───────────── 화면 갱신 ─────────────

func _refresh() -> void:
	board.queue_redraw()
	_refresh_info()
	_refresh_tactics()
	play_btn.text = "❚❚ 일시정지" if busy and not waiting else ("결과 보기" if m.over else "▶ 플레이")
	pause_btn.text = "지시 타이밍: " + PAUSE_KO[_pause_mode()]


func _portrait(sp: SimPlayer, side: MatchEngine.TeamSide) -> TextureRect:
	var t := TextureRect.new()
	t.texture = PixelArt.portrait(sp.face_seed, Color(side.colors[0]), Color(side.colors[1]))
	t.custom_minimum_size = Vector2(24, 24)
	return t


func _refresh_info() -> void:
	UI.clear(info_box)
	if m.over:
		info_box.add_child(UI.title_label("경기 종료"))
		return
	var sit := UI.hbox(6)
	sit.add_child(UI.label("%d회%s %d아웃" % [m.inning, "초" if m.top else "말", m.outs], UI.ACCENT))
	var lights := Control.new()
	lights.custom_minimum_size = Vector2(110, 14)
	lights.draw.connect(func():
		var y := 3
		lights.draw_string(UI.font_small, Vector2(0, 11), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.DIM)
		for i in 3:
			lights.draw_rect(Rect2(8 + i * 7, y + 2, 5, 5), Color("#6fd08c") if i < m.balls else Color("#2c3563"))
		lights.draw_string(UI.font_small, Vector2(32, 11), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.DIM)
		for i in 2:
			lights.draw_rect(Rect2(40 + i * 7, y + 2, 5, 5), Color("#f4d35e") if i < m.strikes else Color("#2c3563"))
		# 루상 다이아몬드
		var c := Vector2(80, 7)
		var pts := [c + Vector2(6, 0), c + Vector2(0, -5), c + Vector2(-6, 0)]
		for i in 3:
			var col := Color("#f4d35e") if m.bases[i] != null else Color("#2c3563")
			lights.draw_rect(Rect2(pts[i] - Vector2(2, 2), Vector2(4, 4)), col))
	sit.add_child(lights)
	info_box.add_child(sit)
	# 타자
	var o := m.off()
	var b := m.batter()
	var bh := UI.hbox(4)
	bh.add_child(_portrait(b, o))
	var bv := UI.vbox(0)
	bh.add_child(bv)
	var today: Dictionary = o.box[b.id]["bat"]
	var pl = st()["players"].get(b.id)
	var season_avg := PlayerUtil.avg_str(pl["season"]["bat"]) if pl != null else "-"
	var idol := ""
	if pl != null and pl.get("idolId") != null:
		idol = " ♥"
	bv.add_child(UI.label("%d번 %s %s%s" % [o.batter_idx + 1, PlayerUtil.POS_KO.get(o.pos_of.get(b.id, "DH"), "지명타자"), b.name, idol], UI.IDOL if idol != "" else UI.TEXT, true))
	bv.add_child(UI.label("오늘 %d타수 %d안타 · 시즌 %s" % [today["ab"], today["h"], season_avg], UI.DIM, true))
	bv.add_child(UI.label("컨%s 파%s 선%s 주%s" % [PlayerUtil.letter(b.con), PlayerUtil.letter(b.pow), PlayerUtil.letter(b.eye), PlayerUtil.letter(b.spd)], UI.TEXT, true))
	info_box.add_child(bh)
	# 투수
	var d := m.def()
	var p := m.pitcher()
	var ph := UI.hbox(4)
	ph.add_child(_portrait(p, d))
	var pv := UI.vbox(0)
	ph.add_child(pv)
	var np: int = d.pitch_count.get(p.id, 0)
	var eff := m.pitcher_eff(p, d)
	pv.add_child(UI.label("투수 %s %s" % [p.name, "좌" if p.throws == "L" else "우"], UI.TEXT, true))
	pv.add_child(UI.label("%dkm 제%s 변%s 투구수 %d" % [roundi(eff["velo"]), PlayerUtil.letter(eff["ctl"]), PlayerUtil.letter(p.stuff), np], UI.BAD if np >= 90 else UI.DIM, true))
	var pool := 40.0 + p.sta * 0.85
	pv.add_child(UI.bar(maxf(0.0, pool - np), pool, 100, UI.GOOD if np < pool * 0.8 else UI.BAD))
	info_box.add_child(ph)


func _tb(label: String, active: bool, cb: Callable, enabled := true) -> Button:
	var b := UI.button(label, cb, 110, true)
	if active:
		b.add_theme_stylebox_override("normal", UI.sb(UI.ACCENT.darkened(0.35), UI.ACCENT))
		b.add_theme_color_override("font_color", UI.ACCENT.lightened(0.5))
	b.disabled = not enabled
	return b


func _refresh_tactics() -> void:
	UI.clear(tactic_box)
	if m.over:
		tactic_box.add_child(UI.button("결과 보기", _show_result, 220))
		return
	if delegate:
		tactic_box.add_child(UI.label("위임 중 — 감독 AI가 지휘합니다", UI.DIM, true))
		return
	var user := _user()
	var g := UI.grid(2, 2, 2)
	if m.off() == user:
		tactic_box.add_child(UI.label("공격 작전 (이번 타석)", UI.ACCENT, true))
		var r1: bool = m.bases[0] != null
		var r2: bool = m.bases[1] != null
		var r3: bool = m.bases[2] != null
		for o in OFF_ORDERS:
			var key: String = o[0]
			var ok := true
			match key:
				"squeeze": ok = r3
				"steal": ok = (r1 and not r2) or (r2 and not r3)
				"hitRun": ok = r1 and not r2
			g.add_child(_tb(o[1], off_order == key, func():
				off_order = key
				_refresh_tactics(), ok))
		tactic_box.add_child(g)
		var sub := UI.grid(2, 2, 2)
		sub.add_child(UI.button("대타", _pinch_hit, 110, true))
		sub.add_child(UI.button("대주자", _pinch_run, 110, true))
		tactic_box.add_child(sub)
	else:
		tactic_box.add_child(UI.label("투구 방침", UI.ACCENT, true))
		for o in PITCH_ORDERS:
			var key: String = o[0]
			g.add_child(_tb(o[1], pitch_order == key, func():
				pitch_order = key
				_refresh_tactics()))
		tactic_box.add_child(g)
		tactic_box.add_child(UI.label("수비 위치", UI.ACCENT, true))
		var g2 := UI.grid(2, 2, 2)
		for o in SHIFT_ORDERS:
			var key2: String = o[0]
			g2.add_child(_tb(o[1], shift_order == key2, func():
				shift_order = key2
				field.sync(m, shift_order)
				_refresh_tactics()))
		tactic_box.add_child(g2)
		tactic_box.add_child(UI.button("투수 교체", _change_pitcher, 222, true))


# ───────────── 교체 ─────────────

func _choose(title: String, items: Array, cb: Callable) -> void:
	if overlay:
		overlay.queue_free()
	overlay = UI.panel(UI.PANEL, UI.ACCENT, 6)
	UI.place(overlay, 120, 50, 400, 230)
	add_child(overlay)
	var v := UI.vbox(2)
	overlay.add_child(v)
	v.add_child(UI.title_label(title))
	var list := UI.vbox(1)
	v.add_child(UI.scroll(list, Vector2(386, 170)))
	if items.is_empty():
		list.add_child(UI.label("교체할 수 있는 선수가 없습니다.", UI.DIM, true))
	for it in items:
		var id: String = it[1]
		var b := UI.button(it[0], func():
			overlay.queue_free()
			overlay = null
			cb.call(id), 380, true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	v.add_child(UI.button("취소", func():
		overlay.queue_free()
		overlay = null, 80, true))


func _bench(side: MatchEngine.TeamSide, pitchers: bool) -> Array:
	return side.players.filter(func(p): return not p.id in side.used and ((p.pos == "P") == pitchers))


func _pinch_hit() -> void:
	var items := []
	for p in _bench(_user(), false):
		items.append(["%s %s  컨%s 파%s 선%s 주%s" % [PlayerUtil.POS_SHORT[p.pos], p.name, PlayerUtil.letter(p.con), PlayerUtil.letter(p.pow), PlayerUtil.letter(p.eye), PlayerUtil.letter(p.spd)], p.id])
	_choose("대타 — %s 대신" % m.batter().name, items, func(id):
		m.pinch_hit(m.off(), id)
		_add_line("[color=#c792ea]%s[/color]" % m.game_log.back())
		_refresh())


func _pinch_run() -> void:
	var occupied := []
	for i in 3:
		if m.bases[i] != null:
			occupied.append(i)
	if occupied.is_empty():
		_add_line("[color=#9aa0c0]주자가 없습니다.[/color]")
		return
	var base: int = occupied.back()
	var items := []
	for p in _bench(_user(), false):
		items.append(["%s %s  주력 %s(%d)" % [PlayerUtil.POS_SHORT[p.pos], p.name, PlayerUtil.letter(p.spd), roundi(p.spd)], p.id])
	_choose("대주자 — %d루 주자 %s 대신" % [base + 1, m.off().by_id[m.bases[base]["id"]].name], items, func(id):
		m.pinch_run(m.off(), base, id)
		_add_line("[color=#c792ea]%s[/color]" % m.game_log.back())
		field.sync(m)
		_refresh())


func _change_pitcher() -> void:
	var items := []
	for p in MatchAI.relievers(_user()):
		var tag := "" if p.pos == "P" else " (야수)"
		items.append(["%s%s  %dkm 제%s 변%s 스%s" % [p.name, tag, roundi(p.velo), PlayerUtil.letter(p.ctl), PlayerUtil.letter(p.stuff), PlayerUtil.letter(p.sta)], p.id])
	_choose("투수 교체 — 현재 %s (투구수 %d)" % [m.pitcher().name, m.def().pitch_count.get(m.def().pitcher_id, 0)], items, func(id):
		m.change_pitcher(m.def(), id)
		_add_line("[color=#c792ea]%s[/color]" % m.game_log.back())
		_refresh())


# ───────────── 결과 ─────────────

func _show_result() -> void:
	if Game.current_match != m:
		return
	Game.current_match = null
	MatchAI.forget(m)
	var s := st()
	Season.finish_user_match(s, m)
	Game.save_game()
	Game.main.show_match_result(m, func(): Game.goto("hub"))


# ───────────── 전광판 ─────────────

func _draw_board() -> void:
	board.draw_rect(Rect2(0, 0, 640, 35), Color("#0d2a1c"))
	board.draw_rect(Rect2(0, 34, 640, 1), UI.LINE)
	var inn := maxi(9, maxi(m.home.line.size(), m.away.line.size()))
	var cw := 16 if inn <= 12 else 13
	var x0 := 96
	var f := UI.font_small
	for i in inn:
		var x := x0 + i * cw
		var cur := i + 1 == m.inning and not m.over
		board.draw_string(f, Vector2(x, 10), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, cw, 10, UI.ACCENT if cur else UI.DIM)
	var rx := x0 + inn * cw + 8
	for j in 3:
		board.draw_string(f, Vector2(rx + j * 22, 10), ["R", "H", "E"][j], HORIZONTAL_ALIGNMENT_CENTER, 22, 10, UI.DIM)
	var rows := [m.away, m.home]
	for r in 2:
		var sd: MatchEngine.TeamSide = rows[r]
		var y := 21 + r * 11
		var batting := (r == 0) == m.top and not m.over
		board.draw_string(f, Vector2(4, y), ("▶" if batting else " ") + sd.name, HORIZONTAL_ALIGNMENT_LEFT, 90, 10, Color(sd.colors[0]).lightened(0.5) if not sd.is_user else UI.ACCENT)
		for i in inn:
			var txt := ""
			if i < sd.line.size():
				txt = str(sd.line[i])
			elif i + 1 == m.inning and batting:
				txt = "0"
			board.draw_string(f, Vector2(x0 + i * cw, y), txt, HORIZONTAL_ALIGNMENT_CENTER, cw, 10, Color("#f4f4f4"))
		board.draw_string(f, Vector2(rx, y), str(sd.score), HORIZONTAL_ALIGNMENT_CENTER, 22, 10, UI.ACCENT)
		board.draw_string(f, Vector2(rx + 22, y), str(sd.hits), HORIZONTAL_ALIGNMENT_CENTER, 22, 10, Color("#f4f4f4"))
		board.draw_string(f, Vector2(rx + 44, y), str(sd.errors), HORIZONTAL_ALIGNMENT_CENTER, 22, 10, Color("#f4f4f4"))
	var comp_txt := ""
	var found := Season.find_fixture(st(), st().get("pendingFixture", ""))
	if not found.is_empty():
		comp_txt = Season.fixture_label(found["comp"], found["f"])
	board.draw_string(f, Vector2(rx + 72, 10), comp_txt, HORIZONTAL_ALIGNMENT_LEFT, 640 - rx - 76, 10, UI.DIM)
