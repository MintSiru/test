class_name GameData
extends RefCounted
## 공용 데이터 로더 (res://data/*.json). 웹 기반 시스템(web/)도 같은 파일을 읽는다.

const FAN_MADE_NOTICE := "본 게임은 비상업적 비공식 팬메이드 게임이며, 실존 선수·구단·KBO와 관련이 없습니다. 게임 속 성적과 사건은 모두 가상입니다."

static var _cache := {}


static func load_json(file: String) -> Variant:
	if _cache.has(file):
		return _cache[file]
	var f := FileAccess.open("res://data/%s.json" % file, FileAccess.READ)
	if f == null:
		push_error("데이터 파일을 열 수 없음: " + file)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	_cache[file] = d
	return d


static func schools() -> Dictionary:
	return load_json("schools")


static func pros() -> Dictionary:
	return load_json("pros")


static func names() -> Dictionary:
	return load_json("names")


static func schedule() -> Dictionary:
	return load_json("schedule")


static func abilities() -> Array:
	return load_json("abilities")["abilities"]


static func styles() -> Dictionary:
	return load_json("abilities")["styles"]


static func ability_name(id: String) -> String:
	for a in abilities():
		if a["id"] == id:
			return a["name"]
	return id


static func ability_def(id: String) -> Dictionary:
	for a in abilities():
		if a["id"] == id:
			return a
	return {}


static func group_name(id: String) -> String:
	for g in schools()["groups"]:
		if g["id"] == id:
			return g["name"]
	return id
