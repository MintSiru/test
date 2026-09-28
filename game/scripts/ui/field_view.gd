class_name FieldView
extends Control
## 경기 관전용 도트 야구장 (400×250). 홈플레이트가 아래, 외야가 위인 부감 시점.
## play(ev) 로 투구·타구·주루를 애니메이션하고, sync(m) 로 현재 상황에 맞춰 배치한다.

const W := 400
const H := 250
const HOME := Vector2(200, 236)
const DEFAULT_POS := {
	"P": [0.0, 18.4], "C": [0.0, -3.0], "1B": [40.0, 27.0], "2B": [15.0, 36.0], "SS": [-15.0, 36.0], "3B": [-40.0, 27.0],
	"LF": [-30.0, 80.0], "CF": [0.0, 92.0], "RF": [30.0, 80.0],
}

var m: MatchEngine
var fielders := {} # pos -> Vector2
var runners := {} # base(1..3) -> {id, pos: Vector2}
var extra_runners := [] # 애니메이션 중 이동하는 주자 [{pos, frame}]
var batter_pos := Vector2.ZERO
var batter_side := -1
var swing_t := -1.0
var ball_pos := Vector2(-100, -100)
var ball_h := 0.0
var ball_visible := false
var texts := [] # [{text, pos, color, big}]
var zone_loc := Vector2(99, 99)
var zone_call := ""
var pitch_info := ""
var anim_frame := 0
var off_colors := [Color.WHITE, Color.RED, Color.WHITE]
var def_colors := [Color.WHITE, Color.BLUE, Color.WHITE]
var crowd_seed := 1
## 야간 경기 / 날씨 ("맑음", "흐림", "가랑비", "비")
var night := false
var weather := "맑음"
var drops: Array = []
var _t := 0.0
static var _bg: ImageTexture


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	clip_contents = true


static func to_screen(angle_deg: float, dist_m: float) -> Vector2:
	var r := dist_m * 3.0 if dist_m <= 40.0 else 120.0 + (dist_m - 40.0) * 1.25
	var a := deg_to_rad(angle_deg)
	return HOME + Vector2(sin(a) * r, -cos(a) * r)


static func base_pos(b: int) -> Vector2:
	match b:
		1: return to_screen(45, 27.4)
		2: return to_screen(0, 38.8)
		3: return to_screen(-45, 27.4)
	return HOME


func _team_colors(side: MatchEngine.TeamSide, is_home: bool) -> Array:
	var cap := Color(side.colors[0])
	var acc := Color(side.colors[1])
	var jersey := Color("#f4f4f4") if is_home else cap.lightened(0.25)
	return [jersey, cap, acc]


## 관중 함성 크기: 후반(7회 이후) 접전이면 크게, 큰 점수 차면 작게
func crowd_db(base: float) -> float:
	if m == null:
		return base
	var diff := absi(m.home.score - m.away.score)
	var db := base
	if m.inning >= 7 and diff <= 2:
		db += 3.0 + (2.0 if m.inning >= 9 and diff <= 1 else 0.0)
	elif diff >= 6:
		db -= 5.0
	return minf(db, 4.0)


func sync(match_: MatchEngine, shift := "normal") -> void:
	m = match_
	off_colors = _team_colors(m.off(), m.off() == m.home)
	def_colors = _team_colors(m.def(), m.def() == m.home)
	fielders.clear()
	for pos in DEFAULT_POS:
		var a: float = DEFAULT_POS[pos][0]
		var d: float = DEFAULT_POS[pos][1]
		if shift == "infieldIn" and pos in ["1B", "2B", "SS", "3B"]:
			d -= 6 if pos in ["2B", "SS"] else 4
		if shift == "buntShift" and pos in ["1B", "3B"]:
			d = 18
		if shift == "deep" and pos in ["LF", "CF", "RF"]:
			d += 10
		fielders[pos] = to_screen(a, d) if pos != "C" else HOME + Vector2(0, 9)
	runners.clear()
	for i in 3:
		if m.bases[i] != null:
			runners[i + 1] = {"id": m.bases[i]["id"], "pos": base_pos(i + 1)}
	extra_runners.clear()
	if not m.over:
		var b := m.batter()
		batter_side = 1 if b.bats == "L" or (b.bats == "S" and m.pitcher().throws == "R") else -1
		batter_pos = HOME + Vector2(9 * batter_side, -2)
	ball_visible = false
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if weather in ["가랑비", "비"]:
		var want := 50 if weather == "가랑비" else 130
		while drops.size() < want:
			drops.append(Vector2(randf() * W, randf() * H))
		for i in drops.size():
			var d: Vector2 = drops[i] + Vector2(-40, 220) * delta
			if d.y > H or d.x < 0:
				d = Vector2(randf() * (W + 60), -4)
			drops[i] = d
	anim_frame = int(_t * 8) % 2
	for t in texts:
		t["ttl"] -= delta
	texts = texts.filter(func(t): return t["ttl"] > 0)
	queue_redraw()


func add_text(text: String, pos: Vector2, color: Color = Color.WHITE, big := false, ttl := 1.2) -> void:
	texts.append({"text": text, "pos": pos, "color": color, "big": big, "ttl": ttl})


# ───────────── 애니메이션 ─────────────

func _tween_ball(from: Vector2, to: Vector2, dur: float, peak: float) -> void:
	ball_visible = true
	var tw := create_tween()
	tw.tween_method(func(t: float):
		ball_pos = from.lerp(to, t)
		ball_h = peak * 4.0 * t * (1.0 - t), 0.0, 1.0, maxf(0.01, dur))
	await tw.finished


func _move_fielder(pos: String, target: Vector2, dur: float) -> void:
	if not fielders.has(pos):
		return
	var from: Vector2 = fielders[pos]
	var max_dist := 26.0 + dur * 60.0
	var dest := from + (target - from).limit_length(max_dist)
	var tw := create_tween()
	tw.tween_method(func(t: float): fielders[pos] = from.lerp(dest, t), 0.0, 1.0, maxf(0.01, dur))


## 주자 이동: from/to 는 0(타석)~3, 4=홈, -1=아웃
func _run(move: Dictionary, dur_per_base: float) -> void:
	var from: int = move["from"]
	var to: int = move["to"]
	var start: Vector2 = batter_pos if from == 0 else base_pos(from)
	if from > 0:
		runners.erase(from)
	var r := {"pos": start, "out": false}
	extra_runners.append(r)
	var path := []
	if to == -1:
		var nxt := base_pos(mini(from + 1, 4) if from < 4 else 4)
		path.append(start.lerp(nxt, 0.5))
	else:
		for b in range(from + 1, to + 1):
			path.append(base_pos(b if b < 4 else 0))
	var tw := create_tween()
	var prev := start
	for p in path:
		var seg_from: Vector2 = prev
		var seg_to: Vector2 = p
		tw.tween_method(func(t: float): r["pos"] = seg_from.lerp(seg_to, t), 0.0, 1.0, maxf(0.01, dur_per_base))
		prev = p
	await tw.finished
	if to == -1:
		add_text("OUT", r["pos"] + Vector2(-8, -18), Color("#ef6f6c"), false, 0.8)
	elif to == 4:
		add_text("+1", r["pos"] + Vector2(-6, -18), Color("#f4d35e"), false, 0.8)
		Game.sfx("cheer", crowd_db(-6.0))


func play(ev: Dictionary, speed: float) -> void:
	if speed >= 8.0:
		return
	var k := 1.0 / speed
	var p_from: Vector2 = fielders.get("P", to_screen(0, 18.4)) + Vector2(0, -8)
	var plate := HOME + Vector2(0, -5)
	pitch_info = "%dkm %s" % [ev["kmh"], PlayerUtil.PITCH_KO.get(ev["pitchType"], "")] if ev["kmh"] > 0 else ""
	zone_loc = ev["loc"]
	zone_call = ev["call"]
	if ev["call"] == "ibb":
		add_text("고의사구", HOME + Vector2(-24, -40), Color("#f4d35e"))
		await get_tree().create_timer(0.5 * k).timeout
		await _animate_moves(ev, 0.25 * k)
		return
	# 투구
	await _tween_ball(p_from, plate + Vector2(ev["loc"].x * 3, 0), 0.42 * k, 3.0)
	var call: String = ev["call"]
	if call in ["ball", "called", "swinging", "buntMiss"]:
		Game.sfx("mitt", -4.0)
	elif call in ["foul", "buntFoul"]:
		Game.sfx("foul", -4.0)
	elif call == "inplay":
		Game.sfx("hit", -2.0)
	elif call == "hbp":
		Game.sfx("hbp", -2.0)
	match call:
		"ball":
			add_text("볼", HOME + Vector2(-8, -30), Color("#7fd0ff"), false, 0.7 * k + 0.2)
		"called":
			add_text("스트라이크!", HOME + Vector2(-26, -30), Color("#f4d35e"), false, 0.7 * k + 0.2)
		"swinging", "buntMiss":
			swing_t = _t
			add_text("헛스윙!", HOME + Vector2(-20, -30), Color("#f4d35e"), false, 0.7 * k + 0.2)
		"hbp":
			add_text("사구!", HOME + Vector2(-12, -30), Color("#ef6f6c"))
		"foul", "buntFoul":
			swing_t = _t
			var fa := 55.0 * (1 if randf() < 0.5 else -1)
			await _tween_ball(plate, to_screen(fa, randf_range(20, 45)), 0.35 * k, 30.0)
			add_text("파울", HOME + Vector2(-12, -30), Color.WHITE, false, 0.6 * k + 0.2)
		"inplay":
			swing_t = _t
			await _animate_batted(ev, k)
	ball_visible = call == "inplay" and ev["batted"] != null and ev["batted"]["caught"]
	if call != "inplay" and not ev["moves"].is_empty():
		await _animate_moves(ev, 0.3 * k)
	if ev.get("steal") != null:
		Game.sfx("slide", -3.0)
		add_text("도루 성공!" if ev["steal"]["success"] else "도루 실패", base_pos(ev["steal"]["from"] + 1) + Vector2(-20, -20), Color("#6fd08c") if ev["steal"]["success"] else Color("#ef6f6c"))
	await get_tree().create_timer(0.18 * k).timeout


func _animate_batted(ev: Dictionary, k: float) -> void:
	var b: Dictionary = ev["batted"]
	var type: String = b["type"]
	var plate := HOME + Vector2(0, -5)
	var dist: float = b["dist"]
	var angle: float = b["angle"]
	var land := to_screen(angle, dist) if b["result"] != "HR" else to_screen(angle, 150)
	var peak: float = {"GB": 0.0, "LD": 10.0, "FB": 46.0, "PU": 60.0, "BUNT": 2.0}[type]
	var dur := (0.25 + dist / 130.0) * k
	if type == "PU":
		dur = 0.9 * k
	var fpos: String = b["fielder"]
	var target := land
	if fielders.has(fpos):
		_move_fielder(fpos, target, dur)
	# 주자는 타구와 동시에 출발
	var t0 := _t
	var run_time := _start_moves(ev, maxf(0.22, dur * 0.8) if b["result"] != "HR" else 0.45 * k)
	if type == "GB" and fielders.has(fpos) and b["result"] in ["OUT", "DP", "FC", "E"]:
		land = fielders[fpos].lerp(land, 0.3)
	await _tween_ball(plate, land, dur, peak)
	match b["result"]:
		"HR":
			add_text("홈런!!", Vector2(160, 70), Color("#f4d35e"), true, 1.6)
			Game.sfx("cheer", crowd_db(0.0))
		"1B", "2B", "3B":
			add_text({"1B": "안타!", "2B": "2루타!", "3B": "3루타!"}[b["result"]], land + Vector2(-16, -24), Color("#6fd08c"))
			# 장타는 관중이 들썩인다 (접전·후반일수록 크게)
			if b["result"] != "1B" and crowd_db(0.0) > 0.0:
				Game.sfx("cheer", crowd_db(-10.0))
			# 굴러가는 공 → 야수 송구
			var roll := land + (land - HOME).normalized() * 12.0
			await _tween_ball(land, roll, 0.2 * k, 0.0)
			if fielders.has(fpos):
				fielders[fpos] = roll + Vector2(0, 2)
			await _tween_ball(roll, base_pos(2) if b["result"] == "1B" else base_pos(3), 0.35 * k, 8.0)
		"E":
			add_text("실책!", land + Vector2(-12, -24), Color("#ef6f6c"))
		"SAC", "FC":
			await _tween_ball(land, base_pos(1), 0.3 * k, 4.0)
		"DP":
			await _tween_ball(land, base_pos(2), 0.25 * k, 4.0)
			await _tween_ball(base_pos(2), base_pos(1), 0.25 * k, 4.0)
		_:
			if b["caught"]:
				ball_pos = fielders.get(fpos, land) + Vector2(0, -6)
				ball_h = 0
				add_text("아웃", ball_pos + Vector2(-10, -20), Color.WHITE, false, 0.8)
			elif type == "GB":
				await _tween_ball(land, base_pos(1), 0.3 * k, 4.0)
	var remain := run_time - (_t - t0)
	if remain > 0:
		await get_tree().create_timer(remain + 0.05).timeout


## 주자 이동을 시작하고 가장 긴 이동 시간을 돌려준다 (기다리지 않음)
func _start_moves(ev: Dictionary, dur_per_base: float) -> float:
	var longest := 0.0
	for mv in ev["moves"]:
		var n: int = 1 if mv["to"] == -1 else maxi(1, int(mv["to"]) - int(mv["from"]))
		longest = maxf(longest, n * dur_per_base)
		_run(mv, dur_per_base)
	return longest


func _animate_moves(ev: Dictionary, dur_per_base: float) -> void:
	var longest := _start_moves(ev, dur_per_base)
	if longest > 0:
		await get_tree().create_timer(longest + 0.05).timeout


# ───────────── 그리기 ─────────────

func _ready() -> void:
	if _bg == null:
		_bg = _render_background()


func _render_background() -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var sky := Color("#1b2140")
	img.fill(sky)
	var r := RandomNumberGenerator.new()
	r.seed = crowd_seed
	for y in H:
		for x in W:
			var p := Vector2(x, y)
			var d := p.distance_to(HOME)
			var ang := rad_to_deg(atan2(p.x - HOME.x, HOME.y - p.y))
			var fair := absf(ang) <= 45.0
			var fence_r := 120.0 + (98.0 + (1.0 - absf(ang) / 45.0) * 20.0 - 40.0) * 1.25
			var c := sky
			if d > fence_r + 4 or (not fair and y < HOME.y - 150):
				# 관중석
				c = Color("#232948") if (y / 3) % 2 == 0 else Color("#1f2542")
				if (y / 3) % 2 == 0 and x % 3 != 0 and r.randf() < 0.3:
					c = [Color("#ef6f6c"), Color("#f4d35e"), Color("#7fa6ff"), Color("#e8e8f0"), Color("#6fd08c")][r.randi_range(0, 4)].darkened(0.5)
			elif d > fence_r and fair:
				c = Color("#16482a")  # 펜스
				if d < fence_r + 1.2:
					c = Color("#f4d35e")
			else:
				var band := int(d / 10.0) % 2
				c = Color("#2f7a3f") if band == 0 else Color("#2a7039")
				if not fair:
					c = c.darkened(0.08)
				# 내야 흙
				if d < 122 and d > 70 and fair:
					c = Color("#b07a4a") if band == 0 else Color("#a87346")
				if d < 70 and fair:
					c = Color("#3a8a48")
				# 베이스 라인 주변 흙길
				if absf(absf(ang) - 45.0) < 1.6 and d < 90:
					c = Color("#b07a4a")
				# 마운드
				if p.distance_to(to_screen(0, 18.4)) < 9:
					c = Color("#b8824f")
				# 홈 주변
				if d < 16:
					c = Color("#b07a4a")
				# 파울 라인
				if absf(absf(ang) - 45.0) < 0.45 and d > 3:
					c = Color("#f4f4f4")
			img.set_pixel(x, y, c)
	# 베이스
	for b in [1, 2, 3]:
		var bp := base_pos(b)
		for yy in range(-2, 3):
			for xx in range(-2, 3):
				if absi(xx) + absi(yy) <= 2:
					img.set_pixel(int(bp.x) + xx, int(bp.y) + yy, Color.WHITE)
	# 홈플레이트 · 투수판
	for xx in range(-2, 3):
		img.set_pixel(int(HOME.x) + xx, int(HOME.y), Color.WHITE)
		img.set_pixel(int(HOME.x) + xx, int(HOME.y) + 1, Color.WHITE)
	img.set_pixel(int(HOME.x), int(HOME.y) + 2, Color.WHITE)
	var mound := to_screen(0, 18.4)
	for xx in range(-2, 3):
		img.set_pixel(int(mound.x) + xx, int(mound.y), Color.WHITE)
	# 타석 박스
	for side in [-1, 1]:
		var bx: int = int(HOME.x) + side * 9 - 3
		for yy in range(-6, 5):
			img.set_pixel(bx, int(HOME.y) + yy, Color("#e0e0e0"))
			img.set_pixel(bx + 6, int(HOME.y) + yy, Color("#e0e0e0"))
		for xx in range(0, 7):
			img.set_pixel(bx + xx, int(HOME.y) - 6, Color("#e0e0e0"))
			img.set_pixel(bx + xx, int(HOME.y) + 4, Color("#e0e0e0"))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	if _bg:
		draw_texture(_bg, Vector2.ZERO)
	# 조명 · 날씨 분위기
	if night:
		draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.03, 0.12, 0.5))
		for lx in [18, 382]:
			draw_rect(Rect2(lx - 1, 4, 3, 40), Color("#3a3f5c"))
			draw_rect(Rect2(lx - 8, 0, 17, 6), Color("#fff6c8"))
			for rr in [40, 28, 16]:
				draw_circle(Vector2(lx, 3), rr, Color(1, 0.97, 0.8, 0.05))
		draw_circle(HOME + Vector2(0, -90), 150, Color(1, 1, 0.9, 0.06))
	elif weather != "맑음":
		draw_rect(Rect2(0, 0, W, H), Color(0.25, 0.27, 0.32, 0.22 if weather == "흐림" else 0.32))
	if m == null:
		return
	# 수비수
	for pos in fielders:
		var fp: Vector2 = fielders[pos]
		_draw_sprite(def_colors, fp, 0)
	# 주자
	for b in runners:
		_draw_sprite(off_colors, runners[b]["pos"], 0)
	for r in extra_runners:
		_draw_sprite(off_colors, r["pos"], 1 + anim_frame)
	# 타자
	if not m.over and extra_runners.is_empty():
		_draw_sprite(off_colors, batter_pos, 0)
		var swinging := swing_t >= 0 and _t - swing_t < 0.25
		var bat_from := batter_pos + Vector2(-3 * batter_side, -9)
		var bat_to := bat_from + (Vector2(10 * -batter_side, -2) if swinging else Vector2(2 * batter_side, -6))
		draw_line(bat_from, bat_to, Color("#c8a060"), 1.0)
	# 공
	if ball_visible:
		draw_rect(Rect2(ball_pos + Vector2(-1, 0), Vector2(3, 1)), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(ball_pos + Vector2(-1, -1 - ball_h), Vector2(2, 2)), Color.WHITE)
	# 빗줄기
	for d in drops:
		draw_line(d, d + Vector2(-2, 5), Color(0.75, 0.85, 1.0, 0.55), 1.0)
	# 스트라이크존 인셋
	var zr := Rect2(360, 6, 30, 36)
	draw_rect(zr.grow(3), Color(0, 0, 0, 0.55))
	draw_rect(zr, Color("#e8e8f0"), false, 1.0)
	for i in [1, 2]:
		draw_line(Vector2(zr.position.x + zr.size.x * i / 3.0, zr.position.y), Vector2(zr.position.x + zr.size.x * i / 3.0, zr.end.y), Color(1, 1, 1, 0.25))
		draw_line(Vector2(zr.position.x, zr.position.y + zr.size.y * i / 3.0), Vector2(zr.end.x, zr.position.y + zr.size.y * i / 3.0), Color(1, 1, 1, 0.25))
	if absf(zone_loc.x) < 5:
		var zc := zr.get_center() + Vector2(zone_loc.x * zr.size.x / 2.0, -zone_loc.y * zr.size.y / 2.0)
		var col := Color("#7fd0ff") if zone_call in ["ball", "hbp", "ibb"] else (Color("#f4d35e") if zone_call in ["called", "swinging", "buntMiss"] else Color("#6fd08c"))
		draw_rect(Rect2(zc - Vector2(2, 2), Vector2(4, 4)), col)
	if pitch_info != "":
		draw_string(UI.font_small, Vector2(318, 56), pitch_info, HORIZONTAL_ALIGNMENT_RIGHT, 76, 10, Color.WHITE)
	# 떠 있는 글자
	for t in texts:
		var sz := 24 if t["big"] else 12
		var f: Font = UI.font_bold if t["big"] else UI.font
		draw_string(f, t["pos"] + Vector2(1, 1), t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.8))
		draw_string(f, t["pos"], t["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, t["color"])


func _draw_sprite(cols: Array, feet: Vector2, frame: int) -> void:
	var tex := PixelArt.sprite(cols[0], cols[1], cols[2], frame)
	draw_texture(tex, (feet - Vector2(4, 12)).round())
