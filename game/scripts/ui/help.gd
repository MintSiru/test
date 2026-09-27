class_name Help
extends RefCounted
## 튜토리얼·도움말 (문구 원본: data/help.json)
##  - once(): 처음 한 번만 안내 팝업 (state.tutorial 에 본 항목 기록, 설정에서 끌 수 있음)
##  - show(): 화면 위 「?」 버튼 등에서 언제든 보기
##  - index_panel(): 도움말 목록 + 특수능력 도감


static func data() -> Dictionary:
	return GameData.load_json("help")


static func topic(key: String) -> Dictionary:
	return data()["topics"].get(key, {})


static func enabled() -> bool:
	var s: Dictionary = Game.state
	return not s.is_empty() and s["settings"].get("tutorial", true)


static func seen(key: String) -> bool:
	var s: Dictionary = Game.state
	return s.is_empty() or s.get("tutorial", {}).get(key, false)


## 처음 한 번만 안내. 보여 줬으면 true
static func once(key: String, on_close: Callable = Callable()) -> bool:
	if not enabled() or seen(key) or topic(key).is_empty():
		return false
	if Game.state.get("tutorial") == null:
		Game.state["tutorial"] = {}
	Game.state["tutorial"][key] = true
	show(key, on_close)
	return true


static func show(key: String, on_close: Callable = Callable()) -> void:
	var t := topic(key)
	if t.is_empty():
		index_panel()
		return
	Game.main.show_modal(t["title"], t["body"], "info", on_close, [["확인", func(): pass], ["도움말 목록", func(): index_panel()]])


## 도움말 목록
static func index_panel() -> void:
	var v := UI.vbox(3)
	v.add_child(UI.label("궁금한 항목을 누르세요.", UI.DIM, true))
	var g := UI.grid(3, 6, 3)
	v.add_child(g)
	for key in data()["index"]:
		var k: String = key
		g.add_child(UI.button(topic(k)["title"], func(): show(k), 176, true))
	var row := UI.hbox(6)
	v.add_child(row)
	row.add_child(UI.button("특수능력 도감 (%d종)" % Abilities.all().size(), func():
		Game.main.show_panel("특수능력 도감", UI.ability_catalog()), 0, true))
	if not Game.state.is_empty():
		var on: bool = enabled()
		row.add_child(UI.button("처음 안내 팝업: %s" % ("켜짐" if on else "꺼짐"), func():
			Game.state["settings"]["tutorial"] = not on
			Game.save_game()
			Game.main.show_modal("도움말", "처음 안내 팝업을 %s." % ("껐습니다" if on else "켰습니다")), 0, true))
	Game.main.show_panel("도움말", v)
