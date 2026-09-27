class_name Music
extends RefCounted
## 코드로 합성하는 칩튠 배경음악 (외부 음원·라이선스 없음)
## 곡: "title" (메뉴 행진곡), "match" (응원가풍 경기 음악)

const RATE := 22050
static var _cache := {}

# [midi 음높이(0=쉼표), 박자] — 한 마디 4박
const SONGS := {
	"title": {
		"bpm": 118,
		"melody": [[72, 1], [76, 1], [79, 1], [76, 1], [77, 1], [81, 1], [79, 2],
			[76, 1], [79, 1], [84, 1], [79, 1], [81, 1], [79, 1], [76, 2],
			[77, 1], [76, 1], [74, 1], [72, 1], [74, 1], [76, 1], [77, 1], [81, 1],
			[79, 1], [76, 1], [74, 1], [67, 1], [72, 4]],
		"bass": [48, 53, 48, 45, 53, 50, 55, 48],
	},
	"match": {
		"bpm": 146,
		"melody": [[67, 1], [67, 1], [71, 1], [74, 1], [76, 1], [74, 1], [71, 2],
			[72, 1], [72, 1], [76, 1], [79, 1], [78, 1], [76, 1], [74, 2],
			[79, 1], [78, 1], [76, 1], [74, 1], [72, 1], [71, 1], [69, 1], [67, 1],
			[69, 1], [71, 1], [72, 1], [69, 1], [67, 2], [74, 2]],
		"bass": [43, 43, 48, 50, 52, 48, 50, 43],
	},
}


static func _freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var song: Dictionary = SONGS[name]
	var beat: float = 60.0 / song["bpm"]
	var bars: int = song["bass"].size()
	var total := int(RATE * beat * 4 * bars)
	var buf := PackedFloat32Array()
	buf.resize(total)
	# 멜로디 (25% 펄스파)
	var t0 := 0.0
	for n in song["melody"]:
		var len_s: float = n[1] * beat
		var start := int(t0 * RATE)
		var cnt := int(len_s * RATE * 0.92)
		if n[0] > 0:
			var f := _freq(n[0])
			for i in cnt:
				if start + i >= total:
					break
				var ph := fmod(i * f / RATE, 1.0)
				var env := minf(1.0, i / 200.0) * (1.0 - 0.5 * float(i) / cnt)
				buf[start + i] += (0.16 if ph < 0.25 else -0.16) * env
		t0 += len_s
	# 베이스 (삼각파, 8분음표로 근음-5도)
	for b in bars:
		var root: int = song["bass"][b]
		for e in 8:
			var midi := root + (7 if e % 2 == 1 else 0)
			var f := _freq(midi)
			var start := int((b * 4 + e * 0.5) * beat * RATE)
			var cnt := int(0.45 * beat * RATE)
			for i in cnt:
				var ph := fmod(i * f / RATE, 1.0)
				var tri := 4.0 * absf(ph - 0.5) - 1.0
				buf[start + i] += tri * 0.14 * (1.0 - float(i) / cnt * 0.6)
	# 드럼 (킥 1·3박, 스네어 2·4박, 하이햇 8분)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for b in bars * 4:
		var start := int(b * beat * RATE)
		var kick := b % 2 == 0
		var cnt := int(0.12 * RATE)
		for i in cnt:
			var t := float(i) / RATE
			var v := 0.0
			if kick:
				v = sin(TAU * (60 + 90 * exp(-t * 30)) * t) * exp(-t * 18) * 0.3
			else:
				v = r.randf_range(-1, 1) * exp(-t * 25) * 0.12
			buf[start + i] += v
		for h in 2:
			var hs := start + int(h * 0.5 * beat * RATE)
			for i in int(0.03 * RATE):
				if hs + i < total:
					buf[hs + i] += r.randf_range(-1, 1) * 0.04 * (1.0 - i / (0.03 * RATE))
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 28000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = total
	_cache[name] = w
	return w
