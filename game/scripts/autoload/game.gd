extends Node
## 전역 게임 상태 · 세이브/로드 · 화면 전환 (autoload "Game")

## v0.3 까지의 단일 세이브 (처음 실행 시 슬롯 1로 옮긴다)
const OLD_SAVE_PATH := "user://save.json"
const SLOT_COUNT := 3
## 슬롯 요약 (타이틀 화면에서 큰 세이브를 읽지 않고 보여 주기 위함)
const META_PATH := "user://slots.json"

## 지금 쓰는 저장 슬롯 (1~3)
var slot := 1

var state: Dictionary = {}
## 진행 중인 사용자 경기
var current_match: MatchEngine = null
## 메인 씬 (화면 전환 담당)
var main: Node = null
var _players: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _bgm_name := ""


func _ready() -> void:
	for i in 4:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		_players.append(ap)
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = -13.0
	add_child(_bgm)


func sound_on() -> bool:
	return state.is_empty() or state["settings"].get("sound", true)


## 배경음악 ("title", "match", "" = 정지)
func bgm(name: String) -> void:
	if not sound_on() or DisplayServer.get_name() == "headless":
		name = ""
	if name == _bgm_name:
		return
	_bgm_name = name
	_bgm.stop()
	if name != "":
		_bgm.stream = Music.get_stream(name)
		_bgm.play()


## 효과음 재생 (설정에서 끌 수 있음)
func sfx(name: String, volume_db := 0.0) -> void:
	if not state.is_empty() and not state["settings"].get("sound", true):
		return
	for ap in _players:
		if not ap.playing:
			ap.stream = Sfx.get_stream(name)
			ap.volume_db = volume_db
			ap.play()
			return


static func slot_path(n: int) -> String:
	return "user://save_%d.json" % n


func has_save() -> bool:
	_migrate_old_save()
	for n in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(n)):
			return true
	return false


func slot_used(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))


## 슬롯 요약 {school, date, year, reputation, record, inMatch} (없으면 빈 Dictionary)
func slot_info(n: int) -> Dictionary:
	if not slot_used(n):
		return {}
	return _read_meta().get(str(n), {"school": "(알 수 없음)", "date": ""})


func _read_meta() -> Dictionary:
	if not FileAccess.file_exists(META_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _write_meta(n: int, info: Dictionary) -> void:
	var meta := _read_meta()
	if info.is_empty():
		meta.erase(str(n))
	else:
		meta[str(n)] = info
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta))


func _summary(s: Dictionary) -> Dictionary:
	var t: Dictionary = s["teams"][s["userTeamId"]]
	var rec: Dictionary = t["seasonRecord"]
	return {"school": t["name"], "date": s["date"], "year": s["year"], "reputation": s["reputation"],
		"record": "%d승 %d패 %d무" % [rec["w"], rec["l"], rec["d"]], "inMatch": s.get("matchSave") != null}


## 옛 단일 세이브를 슬롯 1로 옮긴다 (슬롯 1이 비어 있을 때만)
func _migrate_old_save() -> void:
	if not FileAccess.file_exists(OLD_SAVE_PATH) or FileAccess.file_exists(slot_path(1)):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	DirAccess.rename_absolute(OLD_SAVE_PATH, slot_path(1))
	_write_meta(1, _summary(normalize(d)))


func delete_slot(n: int) -> void:
	if slot_used(n):
		DirAccess.remove_absolute(slot_path(n))
	_write_meta(n, {})


func save_game() -> void:
	if state.is_empty():
		return
	# 진행 중인 사용자 경기는 입력 기록(저널)으로 함께 저장한다 → 불러오면 같은 상황부터 재개
	if current_match != null and current_match.journal_on:
		state["matchSave"] = current_match.save_data()
	else:
		state.erase("matchSave")
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
		_write_meta(slot, _summary(state))


func load_game(n := slot) -> bool:
	_migrate_old_save()
	if not slot_used(n):
		return false
	slot = n
	var f := FileAccess.open(slot_path(n), FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	state = normalize(d)
	# 이전 버전 세이브 호환: 새로 생긴 항목 기본값
	# v0.2 예산(만원) → 포인트, 이전 세이브의 프로 명단은 가상 명단
	if not state.has("points"):
		state["points"] = int(state.get("budget", 0)) / 10 + int(Shop.data()["startPoints"])
		state.erase("budget")
	if state.get("inventory") == null:
		state["inventory"] = {}
	if not state.has("prosMode"):
		state["prosMode"] = "fictional"
	if state.get("facilities") == null:
		state["facilities"] = {}
	if not state.has("rivalId"):
		Rival.init_rival(state)
	# v0.4 튜토리얼: 이전 세이브는 첫 안내를 이미 본 것으로
	if state.get("tutorial") == null:
		state["tutorial"] = {"welcome": true}
	current_match = null
	# 경기 도중 저장했으면 그 상황까지 다시 만든다
	var ms = state.get("matchSave")
	if ms != null:
		current_match = MatchEngine.resume(state, ms)
		if current_match == null:
			state.erase("matchSave")
	return true


func new_game(school: String, manager: String, group_id: String, pros_mode := "real", slot_n := slot) -> void:
	slot = slot_n
	state = Season.start_new_game({"schoolName": school, "managerName": manager, "groupId": group_id, "prosMode": pros_mode})
	current_match = null
	save_game()


## JSON 은 숫자를 모두 float 로 읽으므로 정수값은 int 로 되돌린다
static func normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v.keys():
				v[k] = normalize(v[k])
			return v
		TYPE_ARRAY:
			for i in v.size():
				v[i] = normalize(v[i])
			return v
		TYPE_FLOAT:
			if is_equal_approx(v, roundf(v)) and absf(v) < 1e15:
				return int(v)
			return v
	return v


func goto(screen: String, params := {}) -> void:
	if main:
		main.show_screen(screen, params)


func user_team() -> Dictionary:
	return state["teams"][state["userTeamId"]]
