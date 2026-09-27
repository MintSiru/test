extends BaseScreen
## 스카우트: 중학 유망주 방문 (9월 드래프트 후 ~ 2월)

var list: VBoxContainer
var info: Label


func setup(_p := {}) -> void:
	add_top_bar("스카우트")
	info = UI.label("", UI.TEXT, true)
	UI.place(info, 6, 22, 628, 14)
	add_child(info)
	var p := UI.panel()
	UI.place(p, 4, 38, 632, 318)
	add_child(p)
	list = UI.vbox(2)
	p.add_child(UI.scroll(list))
	_fill()


func _fill() -> void:
	var s := st()
	info.text = "행동력 %d — 방문할수록 입학 의향이 오르고 정보가 공개됩니다. 3월 입학식 때 의향만큼의 확률로 입학합니다. (명성이 높을수록 유리)" % s["scoutPoints"]
	UI.clear(list)
	if s["prospects"].is_empty():
		list.add_child(UI.label("유망주 명단은 9월 KBO 신인 드래프트 이후 공개됩니다.", UI.DIM, true))
		return
	for pr in s["prospects"]:
		var pl: Dictionary = pr["player"]
		var row := UI.hbox(6)
		var face := TextureRect.new()
		face.texture = PixelArt.portrait(int(pl["faceSeed"]), Color("#555a70"), Color("#cccccc"))
		face.custom_minimum_size = Vector2(24, 24)
		row.add_child(face)
		var v := UI.vbox(0)
		v.custom_minimum_size.x = 380
		row.add_child(v)
		var rv: int = pr["revealed"]
		v.add_child(UI.label("%s  %s  %s  (경쟁: %s)" % [PlayerUtil.full_name(pl), PlayerUtil.POS_KO[pl["pos"]], pl["middleSchool"], pr["rival"]], UI.TEXT, true))
		var detail := "재능 %s · 종합 %s" % [Text.stars(pl["talent"]) if rv >= 1 else "?", str(PlayerUtil.overall(pl)) if rv >= 2 else "?"]
		if rv >= 3:
			var idol := Idol.idol_of(s, pl)
			detail += " · 동경: " + (Idol.pro_name(idol) + (" (우리 OB!)" if idol.get("alumniOf") == s["userTeamId"] else "") if not idol.is_empty() else "없음")
		else:
			detail += " · 동경: ?"
		v.add_child(UI.label(detail, UI.IDOL if rv >= 3 and pl.get("idolId") != null else UI.DIM, true))
		var iv := UI.hbox(4)
		var il := UI.label("의향 %d%%" % pr["interest"], UI.GOOD if pr["interest"] >= 70 else UI.TEXT, true)
		il.custom_minimum_size.x = 56
		iv.add_child(il)
		iv.add_child(UI.bar(pr["interest"], 100, 80, UI.GOOD))
		row.add_child(iv)
		var id: String = pr["id"]
		var b := UI.button("방문", func():
			var rng := Season.rng_of(s)
			var msg := Scouting.visit(s, id, rng)
			Season.save_rng(s, rng)
			s["news"].append({"date": s["date"], "kind": "info", "text": msg})
			_fill(), 0, true)
		b.disabled = s["scoutPoints"] <= 0
		row.add_child(b)
		list.add_child(row)
