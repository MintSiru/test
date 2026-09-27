extends Node
## 전역 게임 상태 · 세이브/로드 · 화면 전환 (autoload "Game")

const SAVE_PATH := "user://save.json"

var state: Dictionary = {}
## 진행 중인 사용자 경기
var current_match: MatchEngine = null
## 메인 씬 (화면 전환 담당)
var main: Node = null
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in 4:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		_players.append(ap)


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


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if state.is_empty():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	state = normalize(d)
	# 이전 버전 세이브 호환: 새로 생긴 항목 기본값
	if not state.has("budget"):
		state["budget"] = int(Facilities.data()["startBudget"])
	if state.get("facilities") == null:
		state["facilities"] = {}
	if not state.has("rivalId"):
		Rival.init_rival(state)
	current_match = null
	return true


func new_game(school: String, manager: String, group_id: String) -> void:
	state = Season.start_new_game({"schoolName": school, "managerName": manager, "groupId": group_id})
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
