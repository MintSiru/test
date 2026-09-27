extends BaseScreen
## 시설 · 예산: 후원금·상금으로 시설을 증축해 성장·스카우트를 강화한다

var list: VBoxContainer
var head: Label


func setup(_p := {}) -> void:
	add_top_bar("시설 · 예산")
	head = UI.label("", UI.ACCENT)
	UI.place(head, 6, 22, 628, 14)
	add_child(head)
	var info := UI.label("", UI.DIM, true)
	UI.place(info, 6, 38, 628, 12)
	add_child(info)
	var d := Facilities.data()
	var prizes := []
	for k in d["prizes"]:
		prizes.append("%s %d" % [k, d["prizes"][k]])
	info.text = "수입: 매월 1일 후원회 지원금 (%d + 명성×%d) · 전국대회 격려금 (%s) · 프로 지명 OB 기부 %d  (단위 만원)" % [d["monthlyBase"], d["monthlyPerReputation"], ", ".join(prizes), d["draftDonation"]]
	var p := UI.panel()
	UI.place(p, 4, 54, 632, 302)
	add_child(p)
	list = UI.vbox(4)
	p.add_child(UI.scroll(list))
	_fill()


func _fill() -> void:
	var s := st()
	head.text = "예산 %d만원   ·   이번 달 후원금 약 %d만원" % [int(s.get("budget", 0)), roundi(Facilities.data()["monthlyBase"] + s["reputation"] * Facilities.data()["monthlyPerReputation"])]
	UI.clear(list)
	for f in Facilities.defs():
		var key: String = f["key"]
		var lv := Facilities.level(s, key)
		var row := UI.hbox(8)
		var v := UI.vbox(0)
		v.custom_minimum_size.x = 440
		row.add_child(v)
		var pips := "■".repeat(lv) + "□".repeat(f["costs"].size() - lv)
		v.add_child(UI.label("%s  %s  Lv%d" % [f["name"], pips, lv], UI.ACCENT if lv > 0 else UI.TEXT))
		var eff: String = f["desc"]
		if f["growth"] > 0:
			eff += "  (현재 성장 +%d%%, 다음 +%d%%)" % [roundi(f["growth"] * lv * 100), roundi(f["growth"] * mini(lv + 1, 3) * 100)]
		v.add_child(UI.label(eff, UI.DIM, true))
		var cost := Facilities.upgrade_cost(s, key)
		var b := UI.button("증축 (%d만원)" % cost if cost >= 0 else "최고 레벨", func():
			if Facilities.upgrade(s, key):
				Game.sfx("fanfare", -6.0)
				Game.save_game()
			_fill(), 150)
		b.disabled = cost < 0 or int(s.get("budget", 0)) < cost
		row.add_child(b)
		list.add_child(row)
