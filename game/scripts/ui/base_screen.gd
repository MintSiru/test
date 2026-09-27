class_name BaseScreen
extends Control
## 화면 공통: 상단 바(학교·날짜·명성) + 제목 + 뒤로가기


func st() -> Dictionary:
	return Game.state


var top_root: Control
var _top_title := ""
var _top_back := true


## 상단 정보 바 (높이 18). 다시 부르면 내용만 갱신한다
func add_top_bar(title := "", back := true) -> void:
	_top_title = title
	_top_back = back
	if top_root == null or not is_instance_valid(top_root):
		top_root = Control.new()
		UI.place(top_root, 0, 0, 640, 19)
		add_child(top_root)
	UI.clear(top_root)
	var bar := ColorRect.new()
	bar.color = UI.PANEL
	UI.place(bar, 0, 0, 640, 18)
	top_root.add_child(bar)
	var line := ColorRect.new()
	line.color = UI.LINE
	UI.place(line, 0, 18, 640, 1)
	top_root.add_child(line)
	var h := UI.hbox(10)
	UI.place(h, 4, 1, 632, 16)
	top_root.add_child(h)
	if back:
		h.add_child(UI.button("◀ 돌아가기", func(): Game.goto("hub"), 0, true))
	if title != "":
		h.add_child(UI.title_label(title))
	var s := st()
	if s.is_empty():
		return
	var t: Dictionary = s["teams"][s["userTeamId"]]
	h.add_child(UI.expand(UI.spacer()))
	h.add_child(UI.label(t["name"], UI.ACCENT, true))
	h.add_child(UI.label(Cal.pretty(s["date"], true), UI.TEXT, true))
	h.add_child(UI.label("명성 %d" % s["reputation"], UI.DIM, true))
	h.add_child(UI.label("%dP" % Shop.points(s), UI.GOOD, true))
	var rec: Dictionary = t["seasonRecord"]
	h.add_child(UI.label("%d승 %d패 %d무" % [rec["w"], rec["l"], rec["d"]], UI.DIM, true))


func refresh_top_bar() -> void:
	add_top_bar(_top_title, _top_back)


func pro_team_name(id: String) -> String:
	return Season.pro_team_name(st(), id)
