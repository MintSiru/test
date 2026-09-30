class_name Icons
extends RefCounted
## 10×10 도트 아이콘 (코드로 그림). 글자: k 외곽선 · w 흰색 · y 노랑 · o 주황 · r 빨강 · b 파랑 · n 갈색 · s 살색 · d 회색 · g 초록 · . 투명

const PAL := {"k": Color("#0c0f22"), "w": Color("#f4f4f4"), "y": Color("#f4d35e"), "o": Color("#c98a1e"), "r": Color("#d94c4c"),
	"b": Color("#5fa8ff"), "n": Color("#8a5a2b"), "s": Color("#f0c090"), "d": Color("#9aa0c0"), "g": Color("#6fd08c")}

const DATA := {
	"coin": ["..kkkkkk..", ".kyyyyyyk.", "kyywwyyyyk", "kyywyyyyyk", "kyyyyyyyok", "kyyyyyyyok", "kyyyyyyook", "kyyyyyoook", ".kyoooook.", "..kkkkkk.."],
	"star": ["....kk....", "...kyyk...", "...kyyk...", "kkkkyykkkk", "kyyyyyyyyk", ".kyyyyyyk.", "..kyyyyk..", ".kyykkyyk.", "kyyk..kyyk", "kkk....kkk"],
	"cal": ["kkkkkkkkkk", "krrrrrrrrk", "krwkrrkwrk", "kkkkkkkkkk", "kwwwwwwwwk", "kwkwkwkwwk", "kwwwwwwwwk", "kwkwkwkwwk", "kwwwwwwwwk", "kkkkkkkkkk"],
	"people": ["...kkk....", "..kssk....", "..kssk.kk.", "..kkkkkssk", ".kbbbbkssk", "kbbbbbbkkk", "kbbbbbbbbk", "kbbbbbbbbk", "kbbbbbbbbk", "kkkkkkkkkk"],
	"lineup": ["...kkkk...", ".kkdwwdkk.", ".knkkkknk.", ".knwwwwnk.", ".knwkkwnk.", ".knwwwwnk.", ".knwkkwnk.", ".knwwwwnk.", ".knnnnnnk.", ".kkkkkkkk."],
	"scout": ["..kkkk....", ".kbwbbk...", "kbwbbbbk..", "kbbbbbbk..", "kbbbbbbk..", ".kbbbbk...", "..kkkkkk..", "......kdk.", ".......kdk", "........kk"],
	"trophy": ["kkkkkkkkkk", "kywyyyyyok", ".kyyyyyok.", ".kyyyyyok.", "..kyyyok..", "...kyok...", "....kk....", "...kyyk...", "..kkkkkk..", "..kooook.."],
	"bag": ["...kkkk...", "..kn..nk..", ".kkkkkkkk.", "knnnnnnnnk", "knkkkkkknk", "knkyyyyknk", "knkkkkkknk", "knnnnnnnnk", "knnnnnnnnk", ".kkkkkkkk."],
	"shop": ["kkkkkkkkkk", "krwrwrwrwk", "krwrwrwrwk", "kkkkkkkkkk", ".kwwwwwwk.", ".kwkkkwwk.", ".kwkbkwyk.", ".kwkbkwwk.", ".kwkbkwwk.", ".kkkkkkkk."],
	"sound": ["....kk....", "...kwk..k.", "kkkwwk.k..", "kwwwwk.k.k", "kwwwwk.k.k", "kwwwwk.k.k", "kkkwwk.k..", "...kwk..k.", "....kk....", ".........."],
	"mute": ["....kk....", "...kwk....", "kkkwwk....", "kwwwwkr..r", "kwwwwk.rr.", "kwwwwk.rr.", "kkkwwkr..r", "...kwk....", "....kk....", ".........."],
	"save": ["kkkkkkkkk.", "kbbwwwwbkk", "kbbwwkwbbk", "kbbwwwwbbk", "kbbbbbbbbk", "kbwwwwwwbk", "kbwkkkkwbk", "kbwwwwwwbk", "kbwkkkkwbk", "kkkkkkkkkk"],
	"home": ["....kk....", "...krrk...", "..krrrrk..", ".krrrrrrk.", "kkkkkkkkkk", ".kwwwwwwk.", ".kwnkwbbk.", ".kwnkwbbk.", ".kwnkwwwk.", ".kkkkkkkkk"],
	"ball": ["..kkkkkk..", ".kwwwwwwk.", "kwrwwwwrwk", "kwwrwwrwwk", "kwwrwwrwwk", "kwwrwwrwwk", "kwwrwwrwwk", "kwrwwwwrwk", ".kwwwwwwk.", "..kkkkkk.."],
	"flag": ["kk........", "kyyyyk....", "kyyyyyyk..", "kyyyyyyyyk", "kyyyyyyk..", "kyyyyk....", "kk........", "kk........", "kk........", "kk........"],
}

static var _cache := {}


## 아이콘 텍스처 (없는 이름이면 null)
static func get_icon(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	if not DATA.has(name):
		return null
	var rows: Array = DATA[name]
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 10:
		var row: String = rows[y]
		for x in 10:
			var ch := row[x]
			if PAL.has(ch):
				img.set_pixel(x, y, PAL[ch])
	var t := ImageTexture.create_from_image(img)
	_cache[name] = t
	return t
