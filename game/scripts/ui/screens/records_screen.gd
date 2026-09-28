extends BaseScreen
## 기록실: 연도별 성적 · 개인 타이틀 · 학교 기록 · 명예의 전당(졸업생) · 프로야구(가상 리그)

const TABS := [["years", "연도별 성적"], ["titles", "개인 타이틀"], ["school", "학교 기록"], ["highlights", "명장면"], ["achieve", "업적"], ["hall", "명예의 전당"], ["pro", "프로야구"]]

var tab := "years"
var body: VBoxContainer
var tab_row: HBoxContainer


func setup(p := {}) -> void:
	add_top_bar("기록실")
	tab = p.get("tab", "years")
	tab_row = UI.hbox(3)
	UI.place(tab_row, 4, 22, 632, 16)
	add_child(tab_row)
	var panel := UI.panel()
	UI.place(panel, 4, 40, 632, 316)
	add_child(panel)
	body = UI.vbox(1)
	panel.add_child(UI.scroll(body))
	_fill()


func _fill() -> void:
	UI.clear(tab_row)
	for t in TABS:
		var key: String = t[0]
		var b := UI.button(t[1], func():
			tab = key
			_fill(), 0, true)
		if key == tab:
			b.add_theme_color_override("font_color", UI.ACCENT)
			b.add_theme_stylebox_override("normal", UI.sb(UI.PANEL2, UI.ACCENT))
		tab_row.add_child(b)
	UI.clear(body)
	match tab:
		"years": _years()
		"titles": _titles()
		"school": _school()
		"hall": _hall()
		"highlights": _highlights()
		"achieve": _achieve()
		"pro": _pro()


func _years() -> void:
	var s := st()
	body.add_child(UI.title_label("연도별 성적"))
	if s["history"].is_empty():
		body.add_child(UI.label("아직 기록이 없습니다. (첫 시즌이 끝나면 쌓입니다)", UI.DIM, true))
	for y in s["history"]:
		body.add_child(UI.label("%d 시즌%s" % [y["year"], ("  · 후원회 목표 %s" % y["goals"]) if y.get("goals") != null else ""], UI.ACCENT, true))
		for r in y["results"]:
			body.add_child(UI.label("  %s: %s" % [r["comp"], r["result"]], UI.TEXT, true))
		if not y.get("drafted", []).is_empty():
			body.add_child(UI.label("  프로 지명: " + ", ".join(y["drafted"]), UI.GOOD, true))
	var h2h = s.get("h2h")
	if h2h != null and not h2h.is_empty():
		body.add_child(UI.spacer(0, 4))
		body.add_child(UI.title_label("상대 전적 (많이 만난 순)"))
		var ids: Array = h2h.keys()
		ids.sort_custom(func(a, b2): return (h2h[a]["w"] + h2h[a]["l"]) > (h2h[b2]["w"] + h2h[b2]["l"]))
		for id in ids.slice(0, 10):
			if not s["teams"].has(id):
				continue
			var rec: Dictionary = h2h[id]
			body.add_child(UI.label("  %s%s  %d승 %d패 %d무" % [s["teams"][id]["name"], " (라이벌)" if id == s.get("rivalId") else "", rec["w"], rec["l"], rec["d"]], UI.BAD if id == s.get("rivalId") else UI.TEXT, true))


func _titles() -> void:
	var s := st()
	body.add_child(UI.title_label("전국 개인 타이틀"))
	body.add_child(UI.label("매년 3학년 은퇴식(10월 말) 직전에 정해집니다. 우리 선수가 받으면 +%dP, 명성 +1." % Records.TITLE_POINTS, UI.DIM, true))
	var titles = s.get("titles")
	# 올해 결산 전이면 지금까지의 1위
	if titles == null or not titles.has(str(s["year"])):
		body.add_child(UI.label("%d 시즌 현재 1위 (진행 중)" % s["year"], UI.ACCENT, true))
		for x in Records.season_titles(s):
			_title_row(x)
	if titles != null:
		var years: Array = titles.keys()
		years.sort()
		years.reverse()
		for y in years:
			body.add_child(UI.spacer(0, 3))
			body.add_child(UI.label("%s 시즌" % y, UI.ACCENT, true))
			for x in titles[y]:
				_title_row(x)


func _title_row(x: Dictionary) -> void:
	var mine: bool = x["teamId"] == st()["userTeamId"]
	body.add_child(UI.label("  %-7s %s (%s) %s" % [x["title"], x["name"], x["school"], x["value"]], UI.GOOD if mine else UI.TEXT, true))


func _school() -> void:
	var s := st()
	body.add_child(UI.title_label("학교 기록 (한 시즌 최고)"))
	var recs = s.get("schoolRecords")
	if recs == null or recs.is_empty():
		body.add_child(UI.label("첫 시즌이 끝나면 기록이 생깁니다.", UI.DIM, true))
	else:
		for t in Records.TITLES:
			var r = recs.get(t["key"])
			if r == null:
				continue
			body.add_child(UI.label("  %s  %s — %s (%d)" % [t["name"].replace("왕", ""), r["value"], r["name"], r["year"]], UI.TEXT, true))
	# 올해 우리 팀 선두
	body.add_child(UI.spacer(0, 4))
	body.add_child(UI.label("%d 시즌 우리 팀 선두" % s["year"], UI.ACCENT, true))
	for t in Records.TITLES:
		var best = null
		var best_v := 0.0
		for p in WorldGen.team_players(s, s["userTeamId"]):
			var v = Records.stat_value(p["season"][t["kind"]], t)
			if v != null and (best == null or (v > best_v if t["better"] == "high" else v < best_v)):
				best = p
				best_v = v
		if best != null:
			body.add_child(UI.label("  %s  %s %s" % [t["name"].replace("왕", ""), PlayerUtil.full_name(best), Records.fmt(t, best_v)], UI.TEXT, true))


func _achieve() -> void:
	var s := st()
	var all_: Array = Achievements.data()["list"]
	body.add_child(UI.title_label("업적 %d/%d" % [Achievements.count(s), all_.size()]))
	var cat := UI.hbox(6)
	cat.add_child(UI.label("특수능력 수집 %d/%d" % [Achievements.seen_count(s), Abilities.all().size()], UI.TEXT, true))
	cat.add_child(UI.button("도감 보기", func(): Game.main.show_panel("특수능력 도감", UI.ability_catalog()), 0, true))
	body.add_child(cat)
	for a in all_:
		var got: bool = Achievements.done(s, a["key"])
		body.add_child(UI.label("%s %s — %s  (+%dP)%s" % ["■" if got else "□", a["name"], a["desc"], a["points"], ("  " + Cal.short(s["achievements"][a["key"]])) if got else ""],
			UI.GOOD if got else UI.DIM, true))


func _highlights() -> void:
	var s := st()
	body.add_child(UI.title_label("명장면 앨범"))
	var hl = s.get("highlights")
	if hl == null or hl.is_empty():
		body.add_child(UI.label("우리 경기의 홈런·끝내기·역전 결승타·위기 탈출 삼진이 여기에 모입니다.", UI.DIM, true))
		return
	var list: Array = hl.duplicate()
	list.reverse()
	for h in list:
		var col: Color = UI.TIER_COLORS["gold"] if h["kind"] == "walkoff" else (UI.GOOD if h["kind"] in ["hr", "clutch"] else UI.IDOL)
		var row := UI.hbox(4)
		var hh: Dictionary = h
		var vb := UI.button("보기", func(): _replay(hh), 36, true)
		vb.tooltip_text = "명장면 다시 보기 (공의 궤적)"
		row.add_child(vb)
		row.add_child(UI.label("%s %s vs %s  %s  [%s] %s" % [Cal.short(h["date"]), h["comp"], h["opp"], h["inning"], Records.HIGHLIGHT_KO.get(h["kind"], ""), h["text"]], col, true))
		body.add_child(row)


func _replay(h: Dictionary) -> void:
	var v := UI.vbox(4)
	var rp := HighlightReplay.new()
	rp.setup_replay(h)
	v.add_child(rp)
	v.add_child(UI.label("%s %s vs %s  %s" % [Cal.pretty(h["date"]), h["comp"], h["opp"], h["inning"]], UI.DIM, true))
	Game.main.show_panel("명장면 다시 보기", v)


func _hall() -> void:
	var s := st()
	body.add_child(UI.title_label("명예의 전당 · 졸업생"))
	if s["alumni"].is_empty():
		body.add_child(UI.label("아직 졸업생이 없습니다. (3학년 은퇴식 10월 말)", UI.DIM, true))
		return
	var list: Array = s["alumni"].duplicate()
	list.reverse()
	for al in list:
		var d = al.get("draft")
		var hs: Dictionary = al.get("hs", {})
		var head := "%d 졸업 %s (%s)" % [al["gradYear"], al["name"], PlayerUtil.POS_KO[al["pos"]]]
		if d != null:
			head += " → %s %d라운드%s" % [Season.pro_team_name(s, d["teamId"]), d["round"], (" (%d년 %s 거쳐)" % [int(al["gradYear"]) + int(Offseason.data()["afterSchool"]["collegeDraftYears"]), Offseason.path_text(al.get("path"))]) if d.get("late", false) else ""]
		elif al.get("path") != null:
			head += " → " + Offseason.path_text(al["path"])
		var star: bool = d != null or not hs.get("titles", []).is_empty()
		body.add_child(UI.label(("★ " if star else "  ") + head, UI.GOOD if d != null else (UI.ACCENT if star else UI.TEXT), true))
		if not hs.is_empty():
			var line: String = hs.get("pit", "") if al["pos"] == "P" and hs.has("pit") else hs.get("bat", "")
			body.add_child(UI.label("     고교 통산: " + line, UI.DIM, true))
			if not hs.get("titles", []).is_empty():
				body.add_child(UI.label("     타이틀: " + ", ".join(hs["titles"]), UI.ACCENT, true))
			if not hs.get("gold", []).is_empty():
				var fl := UI.hbox(2)
				fl.add_child(UI.label("     ", UI.DIM, true))
				for id in hs["gold"]:
					fl.add_child(UI.ability_chip(id))
				body.add_child(fl)
		var pro := Records.pro_of(s, al)
		if not pro.is_empty():
			var yrs: int = int(s["year"]) - int(al["gradYear"]) - (int(Offseason.data()["afterSchool"]["collegeDraftYears"]) if d.get("late", false) else 0)
			body.add_child(UI.label("     프로 %s: %s%s" % ["신인" if yrs <= 0 else "%d년차" % (yrs + 1), pro.get("line", "-"), " (은퇴)" if pro.get("retired", false) else ""], UI.IDOL, true))


func _pro() -> void:
	var s := st()
	body.add_child(UI.title_label("프로야구 (가상 리그)"))
	body.add_child(UI.wrap_label("선수들이 동경하는 프로 선수들. 이름이 같은 후배들이 전국에 있다. [OB] = 우리 학교 출신, ♥ = 우리 선수가 동경", 610, UI.DIM, true))
	for t in s["proTeams"]:
		body.add_child(UI.label(t["name"], Color(t["colors"][0]).lightened(0.4), true))
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
			body.add_child(UI.label(txt, UI.IDOL if fans > 0 else (UI.GOOD if p.get("alumniOf") == s["userTeamId"] else UI.TEXT), true))
