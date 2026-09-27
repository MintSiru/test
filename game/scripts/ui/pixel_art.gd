class_name PixelArt
extends RefCounted
## 코드로 만드는 도트 그래픽: 선수 얼굴(24×24), 필드 선수 스프라이트(8×12).
## 외부 이미지 파일 없이 시드와 팀 컬러만으로 생성하고 캐시한다.

const SKINS := [Color("#f2cfae"), Color("#e8bd96"), Color("#d9a87f"), Color("#c99470")]
const HAIRS := [Color("#1b1b22"), Color("#2a211c"), Color("#3a2c22")]
const OUTLINE := Color("#1a1320")

static var _cache := {}


static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## 선수 얼굴 24×24. 모자는 팀 주색, 로고는 보조색
static func portrait(seed_val: int, cap: Color, accent: Color) -> Texture2D:
	var key := "face%d%s%s" % [seed_val, cap.to_html(), accent.to_html()]
	if _cache.has(key):
		return _cache[key]
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	var img := _img(24, 24)
	var bg := Color(cap.darkened(0.55), 1)
	_rect(img, 0, 0, 24, 24, bg)
	# 배경 줄무늬
	for y in range(0, 24, 4):
		_rect(img, 0, y, 24, 1, bg.lightened(0.06))
	var skin: Color = SKINS[r.randi_range(0, SKINS.size() - 1)]
	var shade := skin.darkened(0.15)
	var hair: Color = HAIRS[r.randi_range(0, HAIRS.size() - 1)]
	var face_w := r.randi_range(10, 12)
	var fx := 12 - face_w / 2
	# 유니폼 (어깨)
	var jersey := Color("#f4f4f4")
	_rect(img, 3, 20, 18, 4, jersey)
	_rect(img, 2, 21, 20, 3, jersey)
	_rect(img, 10, 20, 4, 2, cap)  # 칼라
	_rect(img, 11, 22, 2, 2, accent)
	# 목
	_rect(img, 10, 17, 4, 3, shade)
	# 얼굴
	_rect(img, fx, 7, face_w, 11, skin)
	_rect(img, fx + 1, 18, face_w - 2, 1, skin)
	_rect(img, fx - 1, 11, 1, 3, skin)  # 귀
	_rect(img, fx + face_w, 11, 1, 3, skin)
	_rect(img, fx, 17, face_w, 1, shade)
	# 옆머리 (짧은 머리)
	_rect(img, fx, 7, 1, 4, hair)
	_rect(img, fx + face_w - 1, 7, 1, 4, hair)
	if r.randf() < 0.5:
		_rect(img, fx + 1, 7, face_w - 2, 1, hair)
	# 모자
	_rect(img, fx - 1, 3, face_w + 2, 4, cap)
	_rect(img, fx, 2, face_w, 1, cap)
	_rect(img, fx - 1, 7, face_w + 4, 1, cap.darkened(0.35))  # 챙
	_rect(img, 11, 4, 2, 2, accent)  # 로고
	# 눈썹 · 눈
	var eye_y := 11 + r.randi_range(0, 1)
	var brow_thick := r.randf() < 0.4
	var lx := fx + 2
	var rx := fx + face_w - 4
	_rect(img, lx, eye_y - 2, 2, 1, hair)
	_rect(img, rx, eye_y - 2, 2, 1, hair)
	if brow_thick:
		_rect(img, lx, eye_y - 3, 2, 1, hair)
		_rect(img, rx, eye_y - 3, 2, 1, hair)
	var eye_style := r.randi_range(0, 2)
	match eye_style:
		0:
			_rect(img, lx, eye_y, 2, 1, OUTLINE)
			_rect(img, rx, eye_y, 2, 1, OUTLINE)
		1:
			_rect(img, lx, eye_y, 1, 2, OUTLINE)
			_rect(img, rx + 1, eye_y, 1, 2, OUTLINE)
		_:
			_rect(img, lx, eye_y, 2, 2, OUTLINE)
			_px(img, lx, eye_y, Color.WHITE)
			_rect(img, rx, eye_y, 2, 2, OUTLINE)
			_px(img, rx, eye_y, Color.WHITE)
	# 코
	_px(img, 12, eye_y + 2, shade)
	# 입
	var my := eye_y + 4
	match r.randi_range(0, 2):
		0: _rect(img, 11, my, 3, 1, Color("#9a4a42"))
		1:
			_rect(img, 10, my, 4, 1, Color("#9a4a42"))
			_px(img, 10, my - 1, Color("#9a4a42"))
			_px(img, 13, my - 1, Color("#9a4a42"))
		_:
			_rect(img, 11, my, 2, 2, Color("#7a2f2a"))
	# 볼 홍조 / 반창고
	if r.randf() < 0.3:
		_px(img, lx - 1, eye_y + 2, Color("#e89a8a"))
		_px(img, rx + 2, eye_y + 2, Color("#e89a8a"))
	if r.randf() < 0.12:
		_rect(img, rx, eye_y + 2, 2, 1, Color("#f0e0c0"))
	# 테두리
	for x in 24:
		_px(img, x, 0, OUTLINE)
		_px(img, x, 23, OUTLINE)
	for y in 24:
		_px(img, 0, y, OUTLINE)
		_px(img, 23, y, OUTLINE)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# 필드 선수 스프라이트 8×12 (C=모자, S=피부, J=유니폼, A=포인트색, P=바지, K=양말·신발)
const BODY := [
	"..CCCC..",
	".CCCCCC.",
	"..SSSS..",
	"..SSSS..",
	".JJAJJJ.",
	"SJJJJJJS",
	".JJJJJJ.",
	"..PPPP..",
]
const LEGS := [
	["..P..P..", "..P..P..", "..K..K..", ".KK..KK."],
	[".P....P.", ".P...P..", "KK...K..", "......KK"],
	["..P.P...", ".P...P..", ".K....K.", "KK....KK"],
]


## frame: 0 서 있음, 1·2 달리기
static func sprite(jersey: Color, cap: Color, accent: Color, frame := 0) -> Texture2D:
	var key := "spr%s%s%s%d" % [jersey.to_html(), cap.to_html(), accent.to_html(), frame]
	if _cache.has(key):
		return _cache[key]
	var img := _img(8, 12)
	var rows: Array = BODY + LEGS[frame]
	var pal := {"C": cap, "S": SKINS[1], "J": jersey, "A": accent, "P": jersey.darkened(0.1) if jersey.v > 0.8 else Color("#e8e8e8"), "K": cap.darkened(0.2)}
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## 공 아이콘 (타이틀 등)
static func ball(size := 16) -> Texture2D:
	var key := "ball%d" % size
	if _cache.has(key):
		return _cache[key]
	var img := _img(size, size)
	var c := Vector2(size / 2.0 - 0.5, size / 2.0 - 0.5)
	var rad := size / 2.0 - 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c)
			if d <= rad:
				img.set_pixel(x, y, Color("#f4f4f4") if d < rad - 1 else Color("#b8b8c8"))
	for y in range(2, size - 2):
		var off := int(abs(y - size / 2.0) * 0.35)
		img.set_pixel(3 + off, y, Color("#d23c3c"))
		img.set_pixel(size - 4 - off, y, Color("#d23c3c"))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
