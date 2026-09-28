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
	# 화면 배율: 창(휴대폰 화면) 크기가 바뀔 때마다 다시 정한다
	get_tree().root.size_changed.connect(fit_screen)
	fit_screen.call_deferred()


## 640×360 화면을 창에 맞춘다.
## 정수 배율(도트가 고르게 보임)로 창을 90% 이상 채우면 정수 배율, 아니면 소수 배율로 꽉 채운다.
## 휴대폰 가로 화면(예: 2250×1026)은 정수 2배면 57% 만 쓰므로 소수 배율(2.85배)이 된다.
func fit_screen() -> void:
	var root := get_tree().root
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var f := minf(win.x / 640.0, win.y / 360.0)
	var k := floorf(f)
	var integer := k >= 1.0 and k / f >= 0.9
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if integer else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	var scale := k if integer else f
	var cover := (640.0 * scale) * (360.0 * scale) / (win.x * win.y)
	print("LAYOUT %dx%d %s %.2fx 화면 사용 %d%%" % [win.x, win.y, "정수" if integer else "소수", scale, roundi(cover * 100)])


## 웹 모바일 여부 (안드로이드·iOS 브라우저)
func is_mobile_web() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


## 전체 화면 전환 (웹은 사용자 터치 안에서만 가능. 안드로이드는 가로 고정도 시도)
func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if not full and OS.get_name() == "Web":
		JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}")


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
	if FileAccess.file_exists(match_path(n)):
		DirAccess.remove_absolute(match_path(n))
	_write_meta(n, {})


func save_game() -> void:
	if state.is_empty():
		return
	# 진행 중인 사용자 경기는 입력 기록(저널)으로 함께 저장한다 → 불러오면 같은 상황부터 재개
	if current_match != null and current_match.journal_on:
		state["matchSave"] = current_match.save_data()
	else:
		state.erase("matchSave")
	# 저장 번호: 경기 중 저장 파일(match_path)이 이 저장본에 딸린 것인지 확인하는 데 쓴다
	state["saveSeq"] = int(state.get("saveSeq", 0)) + 1
	# Godot 바이너리 + zstd 압축: JSON 보다 저장이 2배 빠르고 파일은 1/8 (v0.6)
	var f := FileAccess.open_compressed(slot_path(slot), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f:
		f.store_var(state)
		f.close()
		_write_meta(slot, _summary(state))
	if FileAccess.file_exists(match_path(slot)):
		DirAccess.remove_absolute(match_path(slot))


static func match_path(n: int) -> String:
	return "user://save_%d_match.bin" % n


## 경기 중 자동 저장 (이닝마다): 경기 동안 게임 상태는 바뀌지 않으므로 입력 기록만 작은 파일로.
## 경기 시작 때의 전체 저장본(saveSeq)에 딸린 것으로 표시해 두고, 불러올 때 번호가 같을 때만 쓴다.
func save_match() -> void:
	if state.is_empty() or current_match == null or not current_match.journal_on:
		return
	var f := FileAccess.open_compressed(match_path(slot), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f:
		f.store_var({"seq": int(state.get("saveSeq", 0)), "matchSave": current_match.save_data()})
		f.close()


## 세이브 파일 읽기: v0.6 부터 압축 바이너리, 그 전은 JSON 텍스트. 실패하면 빈 Dictionary
static func read_save(path: String) -> Dictionary:
	var head := FileAccess.open(path, FileAccess.READ)
	if head == null:
		return {}
	var magic := head.get_buffer(4).get_string_from_ascii()
	head.close()
	if magic == "GCPF":
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		var v = f.get_var() if f != null else null
		return v if typeof(v) == TYPE_DICTIONARY else {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return normalize(d) if typeof(d) == TYPE_DICTIONARY else {}


func load_game(n := slot) -> bool:
	_migrate_old_save()
	if not slot_used(n):
		return false
	slot = n
	var d := read_save(slot_path(n))
	if d.is_empty():
		return false
	# 경기 중 저장 파일이 이 저장본에 딸린 것이면 그 경기 기록을 쓴다 (이닝마다 저장한 최신 상황)
	if FileAccess.file_exists(match_path(n)):
		var mf := FileAccess.open_compressed(match_path(n), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		var mv = mf.get_var() if mf != null else null
		if typeof(mv) == TYPE_DICTIONARY and int(mv.get("seq", -1)) == int(d.get("saveSeq", 0)):
			d["matchSave"] = mv["matchSave"]
	state = d
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
	# v0.6 대졸 지명 버그: 프로 스타일이 목록에 없는 값이면 고친다
	var styles := GameData.styles()
	for pro in state.get("pros", []):
		if not styles.has(pro["style"]):
			pro["style"] = "제구파" if pro["pos"] == "P" else "교타자"
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
