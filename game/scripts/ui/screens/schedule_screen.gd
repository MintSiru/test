extends BaseScreen
## 일정 · 대진표 · 순위

var sel_key := ""
var right: VBoxContainer


func setup(_p := {}) -> void:
	add_top_bar("일정 · 대진표")
	var lp := UI.panel()
	UI.place(lp, 4, 22, 196, 334)
	add_child(lp)
	var lv := UI.vbox(2)
	lp.add_child(lv)
	lv.add_child(UI.label("%d 시즌 대회 (실제 일정 기준)" % st()["year"], UI.DIM, true))
	for e in Season.year_schedule(st()):
		if e["comp"] == "":
			continue
		var key: String = e["comp"]
		var comp := _comp(key)
		var status := "예정"
		var col := UI.TEXT
		if not comp.is_empty():
			status = {"upcoming": "예정", "active": "진행 중", "done": "종료"}[comp["status"]]
			col = UI.GOOD if comp["status"] == "active" else (UI.DIM if comp["status"] == "done" else UI.TEXT)
		elif e["date"] < st()["date"]:
			status = "불참"
			col = UI.DIM
		var b := UI.button("%s  %s~%s  %s" % [e["label"], Cal.short(e["date"]), Cal.short(e["end"]), status], func():
			sel_key = key
			_fill(), 186, true)
		b.add_theme_color_override("font_color", col)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lv.add_child(b)
		if sel_key == "" and not comp.is_empty() and comp["status"] != "done":
			sel_key = key
	lv.add_child(UI.spacer(0, 6))
	lv.add_child(UI.button("우리 경기 일정", func():
		sel_key = "mine"
		_fill(), 186, true))
	lv.add_child(UI.wrap_label("출전 자격: 주말리그 전반기 → 황금사자기·청룡기, 후반기 → 대통령배, 이마트배·봉황대기는 전 팀, 전국체전은 시·도 대표", 186, UI.DIM, true))
	var rp := UI.panel()
	UI.place(rp, 204, 22, 432, 334)
	add_child(rp)
	right = UI.vbox(1)
	rp.add_child(UI.scroll(right))
	if sel_key == "":
		sel_key = "mine"
	_fill()


func _comp(key: String) -> Dictionary:
	for c in st()["competitions"]:
		if c["key"] == key and c["year"] == st()["year"]:
			return c
	return {}


func _tname(id) -> String:
	if id == null:
		return "-"
	return st()["teams"][id]["name"]


func _fill() -> void:
	UI.clear(right)
	var s := st()
	var u: String = s["userTeamId"]
	if sel_key == "mine":
		right.add_child(UI.title_label("우리 경기"))
		for x in Season.user_fixtures(s):
			var f: Dictionary = x["f"]
			var opp: String = f["away"] if f["home"] == u else f["home"]
			var txt := "%s  %s  vs %s" % [Cal.pretty(f["date"]), Season.fixture_label(x["comp"], f), _tname(opp)]
			var col := UI.TEXT
			if f.get("result") != null:
				var r: Dictionary = f["result"]
				var us: int = r["homeScore"] if f["home"] == u else r["awayScore"]
				var them: int = r["awayScore"] if f["home"] == u else r["homeScore"]
				txt += "  %d:%d %s" % [us, them, "승" if r["winner"] == u else ("패" if r["winner"] != null else "무")]
				col = UI.GOOD if r["winner"] == u else (UI.BAD if r["winner"] != null else UI.DIM)
			right.add_child(UI.label(txt, col, true))
		return
	var comp := _comp(sel_key)
	var def := Cal.comp_def(sel_key)
	right.add_child(UI.title_label(def["name"]))
	var dates := Cal.comp_dates(sel_key, s["year"])
	right.add_child(UI.label("%s ~ %s" % [Cal.pretty(dates["start"]), Cal.pretty(dates["end"])], UI.TEXT, true))
	right.add_child(UI.wrap_label("참가: " + def["entry"], 420, UI.DIM, true))
	if comp.is_empty():
		right.add_child(UI.label("아직 대진이 정해지지 않았습니다.", UI.DIM, true))
		return
	if comp.get("userResult") != null:
		right.add_child(UI.label("우리 성적: " + comp["userResult"], UI.ACCENT, true))
	if comp["kind"] == "league":
		var gid: String = s["teams"][u]["leagueGroup"]
		right.add_child(UI.label("%s 권역 순위" % GameData.group_name(gid), UI.ACCENT, true))
		var g := UI.grid(7, 10, 1)
		right.add_child(g)
		for h in ["순위", "팀", "승", "패", "무", "득", "실"]:
			g.add_child(UI.label(h, UI.DIM, true))
		var rows := Competition.standings(comp, gid)
		for i in rows.size():
			var r: Dictionary = rows[i]
			var col := UI.GOOD if r["teamId"] == u else UI.TEXT
			for v in [str(i + 1), _tname(r["teamId"]), str(r["w"]), str(r["l"]), str(r["d"]), str(r["rs"]), str(r["ra"])]:
				g.add_child(UI.label(v, col, true))
		return
	if comp.get("champion") != null:
		right.add_child(UI.label("★ 우승: %s   준우승: %s" % [_tname(comp["champion"]), _tname(comp.get("runnerUp"))], UI.ACCENT, true))
	if not u in comp["entrants"]:
		right.add_child(UI.label("우리 학교는 이 대회에 출전하지 못했습니다.", UI.DIM, true))
	right.add_child(UI.label("참가 %d팀" % comp["entrants"].size(), UI.DIM, true))
	# 8강 이후 대진
	var br: Array = comp["bracket"]
	var rounds := br.size() - 1
	for r in range(maxi(0, rounds - 3), rounds):
		var rd: Array = comp["roundDates"][r]
		right.add_child(UI.label("%s (%s)" % [Competition.round_name(comp, r), Cal.short(rd[0])], UI.ACCENT, true))
		var slots: Array = br[r]
		for i in slots.size() / 2:
			var a = slots[2 * i]
			var b = slots[2 * i + 1]
			var res := ""
			for f in comp["fixtures"]:
				if int(f.get("round", -1)) == r and int(f.get("slot", -1)) == i and f.get("result") != null:
					res = "  %d:%d" % [f["result"]["homeScore"], f["result"]["awayScore"]]
			var col := UI.GOOD if a == u or b == u else UI.TEXT
			right.add_child(UI.label("  %s vs %s%s" % [_tname(a), _tname(b), res], col, true))
	# 우리 경로
	right.add_child(UI.label("우리 학교 경기", UI.ACCENT, true))
	for f in comp["fixtures"]:
		if f["home"] != u and f["away"] != u:
			continue
		var opp: String = f["away"] if f["home"] == u else f["home"]
		var txt := "  %s %s vs %s" % [Cal.short(f["date"]), Competition.round_name(comp, int(f["round"])), _tname(opp)]
		if f.get("result") != null:
			txt += "  %s" % ("승" if f["result"]["winner"] == u else "패")
		right.add_child(UI.label(txt, UI.TEXT, true))
