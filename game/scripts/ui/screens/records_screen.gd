extends BaseScreen
## 기록실: 연도별 성적, 졸업생(프로 진출), 프로야구(가상 리그)


func setup(_p := {}) -> void:
	add_top_bar("기록실")
	var s := st()
	var a := UI.panel()
	UI.place(a, 4, 22, 314, 160)
	add_child(a)
	var av := UI.vbox(1)
	a.add_child(UI.scroll(av))
	av.add_child(UI.title_label("연도별 성적"))
	if s["history"].is_empty():
		av.add_child(UI.label("아직 기록이 없습니다.", UI.DIM, true))
	for y in s["history"]:
		av.add_child(UI.label("%d 시즌" % y["year"], UI.ACCENT, true))
		for r in y["results"]:
			av.add_child(UI.label("  %s: %s" % [r["comp"], r["result"]], UI.TEXT, true))
	var h2h = s.get("h2h")
	if h2h != null and not h2h.is_empty():
		av.add_child(UI.title_label("상대 전적 (많이 만난 순)"))
		var ids: Array = h2h.keys()
		ids.sort_custom(func(a, b2): return (h2h[a]["w"] + h2h[a]["l"]) > (h2h[b2]["w"] + h2h[b2]["l"]))
		for id in ids.slice(0, 8):
			if not s["teams"].has(id):
				continue
			var rec: Dictionary = h2h[id]
			av.add_child(UI.label("  %s%s  %d승 %d패 %d무" % [s["teams"][id]["name"], " (라이벌)" if id == s.get("rivalId") else "", rec["w"], rec["l"], rec["d"]], UI.BAD if id == s.get("rivalId") else UI.TEXT, true))
	var b := UI.panel()
	UI.place(b, 4, 186, 314, 170)
	add_child(b)
	var bv := UI.vbox(1)
	b.add_child(UI.scroll(bv))
	bv.add_child(UI.title_label("졸업생 · 프로 진출"))
	if s["alumni"].is_empty():
		bv.add_child(UI.label("-", UI.DIM, true))
	for al in s["alumni"]:
		var d = al.get("draft")
		var txt := "%d 졸업 %s (%s)" % [al["gradYear"], al["name"], PlayerUtil.POS_KO[al["pos"]]]
		if d != null:
			txt += " → %s %d라운드" % [Season.pro_team_name(s, d["teamId"]), d["round"]]
		bv.add_child(UI.label(txt, UI.GOOD if d != null else UI.TEXT, true))
	var c := UI.panel()
	UI.place(c, 322, 22, 314, 334)
	add_child(c)
	var cv := UI.vbox(1)
	c.add_child(UI.scroll(cv))
	cv.add_child(UI.title_label("프로야구 (가상 리그)"))
	cv.add_child(UI.wrap_label("선수들이 동경하는 프로 선수들. 이름이 같은 후배들이 전국에 있다.", 300, UI.DIM, true))
	for t in s["proTeams"]:
		cv.add_child(UI.label(t["name"], Color(t["colors"][0]).lightened(0.4), true))
		for p in s["pros"]:
			if p["teamId"] != t["id"] or p.get("retired", false):
				continue
			var fans := 0
			for id in s["teams"][s["userTeamId"]]["playerIds"]:
				var pl = s["players"].get(id)
				if pl != null and pl.get("idolId") == p["id"]:
					fans += 1
			var txt := "  %s %s %s %s" % [Idol.pro_name(p), PlayerUtil.POS_SHORT[p["pos"]], p["style"], p.get("line", "")]
			if p.get("alumniOf") == s["userTeamId"]:
				txt += " [OB]"
			if fans > 0:
				txt += " ♥%d" % fans
			cv.add_child(UI.label(txt, UI.IDOL if fans > 0 else (UI.GOOD if p.get("alumniOf") == s["userTeamId"] else UI.TEXT), true))
