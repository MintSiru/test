class_name Sfx
extends RefCounted
## 코드로 합성하는 8비트풍 효과음 (외부 음원 없음)

const RATE := 22050
static var _cache := {}


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var s := PackedFloat32Array()
	match name:
		"hit":  # 딱! 배트 소리
			var n := int(RATE * 0.12)
			s.resize(n)
			var prev := 0.0
			for i in n:
				var t := float(i) / RATE
				var noise := r.randf_range(-1, 1)
				var hp := noise - prev
				prev = noise
				s[i] = (hp * 0.6 + sin(TAU * 1800 * t) * 0.3) * exp(-t * 45)
		"mitt":  # 퍽! 미트
			var n := int(RATE * 0.08)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = (sin(TAU * 140 * t) * 0.8 + r.randf_range(-1, 1) * 0.3) * exp(-t * 60)
		"cheer":  # 와아— 관중
			var n := int(RATE * 1.2)
			s.resize(n)
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lp * 0.9 + r.randf_range(-1, 1) * 0.1
				var env := minf(1.0, t * 6.0) * exp(-t * 1.8)
				s[i] = lp * 3.0 * env * (0.8 + 0.2 * sin(TAU * 5 * t))
		"foul":  # 틱! 배트에 스친 파울 (hit 보다 짧고 높다)
			var n := int(RATE * 0.06)
			s.resize(n)
			var prev2 := 0.0
			for i in n:
				var t := float(i) / RATE
				var noise := r.randf_range(-1, 1)
				s[i] = ((noise - prev2) * 0.4 + sin(TAU * 2600 * t) * 0.25) * exp(-t * 70)
				prev2 = noise
		"hbp":  # 퍽… 몸에 맞는 공 (낮고 둔탁)
			var n := int(RATE * 0.15)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = (sin(TAU * (90 + 60 * exp(-t * 40)) * t) * 0.9 + r.randf_range(-1, 1) * 0.15) * exp(-t * 28)
		"slide":  # 쓱— 슬라이딩 (흙먼지: 낮게 거른 잡음이 점점 작아짐)
			var n := int(RATE * 0.35)
			s.resize(n)
			var lp2 := 0.0
			for i in n:
				var t := float(i) / RATE
				lp2 = lp2 * 0.8 + r.randf_range(-1, 1) * 0.2
				s[i] = lp2 * 2.2 * minf(1.0, t * 30.0) * exp(-t * 7.0)
		"click":
			var n := int(RATE * 0.03)
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = (1.0 if fmod(t * 900, 1.0) < 0.5 else -1.0) * 0.15 * (1.0 - float(i) / n)
		"fanfare":  # 승리 팡파레 (도-미-솔-도)
			var notes := [523.25, 659.25, 783.99, 1046.5]
			var dur := 0.14
			for k in notes.size():
				var nn := int(RATE * (dur if k < 3 else 0.45))
				for i in nn:
					var t := float(i) / RATE
					var sq := 1.0 if fmod(t * notes[k], 1.0) < 0.5 else -1.0
					s.append(sq * 0.18 * exp(-t * (3.0 if k == 3 else 8.0)))
		_:
			s.resize(1)
	var w := _wav(s)
	_cache[name] = w
	return w
