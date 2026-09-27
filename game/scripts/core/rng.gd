class_name Rng
extends RefCounted
## 시드 기반 난수. 상태(state)를 문자열로 세이브에 저장해 이어서 쓸 수 있다.

var g := RandomNumberGenerator.new()


func _init(seed_val: int = 0, state_str: String = "") -> void:
	g.seed = seed_val
	if state_str != "":
		g.state = state_str.to_int()


func get_state_str() -> String:
	return str(g.state)


func next() -> float:
	return g.randf()


## [a, b] 정수
func irange(a: int, b: int) -> int:
	return g.randi_range(a, b)


func frange(a: float, b: float) -> float:
	return g.randf_range(a, b)


func chance(p: float) -> bool:
	return g.randf() < p


func pick(arr: Array) -> Variant:
	return arr[g.randi_range(0, arr.size() - 1)]


func weighted(items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	var r := g.randf() * total
	for i in items.size():
		r -= maxf(0.0, weights[i])
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]


func gauss() -> float:
	return g.randfn(0.0, 1.0)


func shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := g.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr
