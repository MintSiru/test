extends BaseScreen
## 새 게임: 학교 이름 · 감독 이름 · 주말리그 권역 선택

var school: LineEdit
var manager: LineEdit
var group_idx := 0
var groups: Array


func setup(_p := {}) -> void:
	groups = GameData.schools()["groups"]
	var p := UI.panel(UI.PANEL, UI.ACCENT, 10)
	UI.place(p, 150, 50, 340, 250)
	add_child(p)
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.title_label("새 게임"))
	v.add_child(UI.wrap_label("약체 고교 야구부의 감독으로 부임했습니다. 3년 주기로 선수들을 키워 전국 대회 우승과 프로 선수 배출을 노려 보세요.", 316, UI.DIM, true))
	var g := UI.grid(2, 8, 6)
	v.add_child(g)
	g.add_child(UI.label("학교 이름"))
	school = LineEdit.new()
	school.text = "한빛고"
	school.max_length = 8
	school.custom_minimum_size.x = 160
	g.add_child(school)
	g.add_child(UI.label("감독 이름"))
	manager = LineEdit.new()
	manager.text = "김감독"
	manager.max_length = 8
	g.add_child(manager)
	g.add_child(UI.label("주말리그 권역"))
	var names := groups.map(func(x): return x["name"])
	g.add_child(UI.option(names, 0, func(i): group_idx = i, false))
	v.add_child(UI.wrap_label("권역 = 봄·여름 주말리그에서 겨룰 지역 리그입니다. 성적에 따라 황금사자기·청룡기·대통령배 출전권이 걸려 있습니다.", 316, UI.DIM, true))
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UI.button("취소", func(): Game.goto("title"), 70))
	row.add_child(UI.button("시작!", _start, 70))


func _start() -> void:
	var name_ := school.text.strip_edges()
	if name_ == "":
		name_ = "한빛고"
	if not name_.ends_with("고"):
		name_ += "고"
	Game.new_game(name_, manager.text.strip_edges(), groups[group_idx]["id"])
	Game.goto("hub")
