class_name BoxScore
extends RefCounted
## 경기 결과 요약 문구와 박스스코어 표


## 결과 요약 (점수, 수훈 선수)
static func summary(m: MatchEngine) -> String:
	var u := m.user_side()
	var o := m.away if u == m.home else m.home
	var res := "승리!" if m.winner == u.team_id else ("패배..." if m.winner != null else "무승부")
	var best := ""
	var best_v := -1.0
	for id in u.box:
		var bl: Dictionary = u.box[id]["bat"]
		var pt: Dictionary = u.box[id]["pit"]
		var v: float = bl["h"] * 2 + bl["hr"] * 4 + bl["rbi"] * 1.5 + pt["outs"] * 0.35 - pt["er"] * 1.5 + pt["so"] * 0.5
		if v > best_v:
			best_v = v
			best = "%s (%s)" % [u.by_id[id].name, ("%d타수 %d안타 %d타점" % [bl["ab"], bl["h"], bl["rbi"]]) if bl["pa"] > 0 else ("%s이닝 %d실점 %d탈삼진" % [PlayerUtil.ip_str(pt["outs"]), pt["r"], pt["so"]])]
	return "%s %d : %d %s  %s%s\n\n안타 %d · 실책 %d\n수훈 선수: %s" % [u.name, u.score, o.score, o.name, res, " (콜드)" if m.called else "", u.hits, u.errors, best]


static func _cell(t: String, w: int, c: Color = UI.TEXT) -> Label:
	var l := UI.label(t, c, true)
	l.custom_minimum_size.x = w
	return l


static func _side(side: MatchEngine.TeamSide, box: VBoxContainer) -> void:
	box.add_child(UI.label(side.name + ("  (우리 팀)" if side.is_user else ""), UI.ACCENT if side.is_user else UI.TEXT, true))
	var g := UI.grid(8, 4, 0)
	for h in [["타자", 70], ["위치", 26], ["타수", 26], ["안타", 26], ["홈런", 26], ["타점", 26], ["볼넷", 26], ["삼진", 26]]:
		g.add_child(_cell(h[0], h[1], UI.DIM))
	var seen := {}
	var ids: Array = side.order.duplicate()
	for id in side.box:
		if not id in ids and side.box[id]["bat"]["pa"] > 0:
			ids.append(id)
	for id in ids:
		if seen.has(id):
			continue
		seen[id] = true
		var b: Dictionary = side.box[id]["bat"]
		g.add_child(_cell(side.by_id[id].name, 70))
		g.add_child(_cell(PlayerUtil.POS_SHORT.get(side.pos_of.get(id, ""), "-"), 26, UI.DIM))
		for k in ["ab", "h", "hr", "rbi", "bb", "so"]:
			g.add_child(_cell(str(b[k]), 26, UI.GOOD if (k == "h" or k == "hr") and b[k] > 0 else UI.TEXT))
	box.add_child(g)
	var pg := UI.grid(8, 4, 0)
	for h in [["투수", 70], ["이닝", 34], ["투구", 26], ["피안타", 30], ["실점", 26], ["자책", 26], ["볼넷", 26], ["삼진", 26]]:
		pg.add_child(_cell(h[0], h[1], UI.DIM))
	for id in side.pitchers:
		var p: Dictionary = side.box[id]["pit"]
		var tag := " 승" if p["w"] else (" 패" if p["l"] else "")
		pg.add_child(_cell(side.by_id[id].name + tag, 70, UI.GOOD if p["w"] else (UI.BAD if p["l"] else UI.TEXT)))
		pg.add_child(_cell(PlayerUtil.ip_str(p["outs"]), 34))
		for k in ["np", "h", "r", "er", "bb", "so"]:
			pg.add_child(_cell(str(p[k]), 30 if k == "h" else 26))
	box.add_child(pg)


static func build(m: MatchEngine) -> Control:
	var v := UI.vbox(3)
	# 이닝별 점수
	var inn := maxi(m.home.line.size(), m.away.line.size())
	var lg := UI.grid(inn + 4, 3, 0)
	lg.add_child(_cell("", 60))
	for i in inn:
		lg.add_child(_cell(str(i + 1), 12, UI.DIM))
	for h in ["R", "H", "E"]:
		lg.add_child(_cell(h, 16, UI.DIM))
	for sd in [m.away, m.home]:
		lg.add_child(_cell(sd.name, 60, UI.ACCENT if sd.is_user else UI.TEXT))
		for i in inn:
			lg.add_child(_cell(str(sd.line[i]) if i < sd.line.size() else "-", 12))
		lg.add_child(_cell(str(sd.score), 16, UI.ACCENT))
		lg.add_child(_cell(str(sd.hits), 16))
		lg.add_child(_cell(str(sd.errors), 16))
	v.add_child(lg)
	_side(m.away, v)
	_side(m.home, v)
	return v
