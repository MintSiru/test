class_name Stories
extends RefCounted
## 선수 이야기 (Godot 전용): 불방망이·슬럼프, 긴 부상 뒤 복귀, 라이벌 학교 에이스 소식

const RECENT_N := 5


## 우리 경기 뒤: 타자별 최근 5경기 [타수, 안타, 홈런] 을 쌓고 불방망이·슬럼프 판정
static func after_match(state: Dictionary, side: MatchEngine.TeamSide) -> void:
	for id in side.box:
		var p = state["players"].get(id)
		if p == null:
			continue
		var bat: Dictionary = side.box[id]["bat"]
		if int(bat["pa"]) == 0:
			continue
		var rec: Array = p.get("recent", [])
		rec.append([int(bat["ab"]), int(bat["h"]), int(bat["hr"])])
		if rec.size() > RECENT_N:
			rec = rec.slice(rec.size() - RECENT_N)
		p["recent"] = rec
		var n := PlayerUtil.full_name(p)
		# 슬럼프 탈출: 슬럼프 중 멀티히트
		if p.get("slump", false) and int(bat["h"]) >= 2:
			p.erase("slump")
			p["cond"] = mini(2, int(p["cond"]) + 1)
			TeamMood.change(state, 2)
			_news(state, "good", "%s, %d안타로 슬럼프 탈출! 더그아웃이 들썩였다." % [n, bat["h"]])
			continue
		if rec.size() >= 3:
			var last3 := rec.slice(rec.size() - 3)
			var h3 := 0
			for g in last3:
				h3 += int(g[1])
			if h3 >= 7 and state["date"] >= str(p.get("hotUntil", "")):
				p["hotUntil"] = Cal.add_days(state["date"], 21)
				p["cond"] = mini(2, int(p["cond"]) + 1)
				_news(state, "good", "%s, 최근 3경기 %d안타 불방망이! (컨디션 상승)" % [n, h3])
		if rec.size() >= 4 and not p.get("slump", false):
			var ab := 0
			var h := 0
			for g in rec.slice(rec.size() - 4):
				ab += int(g[0])
				h += int(g[1])
			if ab >= 12 and h == 0:
				p["slump"] = true
				p["cond"] = maxi(-2, int(p["cond"]) - 1)
				_news(state, "bad", "%s, 4경기 %d타수 무안타... 슬럼프에 빠졌다. (컨디션 하락)" % [n, ab])


## 매일: 14일 넘는 부상은 재활로 표시, 다 나으면 복귀 이야기
static func daily(state: Dictionary) -> void:
	for p in WorldGen.team_players(state, state["userTeamId"]):
		var inj := int(p["injury"])
		if inj >= 14:
			p["rehab"] = true
		elif inj == 0 and p.get("rehab", false):
			p.erase("rehab")
			p["cond"] = 2
			var n := PlayerUtil.full_name(p)
			state["popups"].append({"kind": "good", "title": "재활 완료", "body": "%s 긴 재활을 마치고 그라운드에 돌아왔다!\n\"다시 뛸 수 있어서 행복합니다.\"\n(절호조)" % Text.josa(n, "이/가")})
			_news(state, "good", "%s, 재활을 마치고 복귀!" % n)


## 라이벌 학교 에이스 (종합 능력치가 가장 높은 선수)
static func rival_ace(state: Dictionary) -> Dictionary:
	var rid = state.get("rivalId")
	if rid == null or not state["teams"].has(rid):
		return {}
	var best := {}
	for p in WorldGen.team_players(state, rid):
		if best.is_empty() or PlayerUtil.overall(p) > PlayerUtil.overall(best):
			best = p
	return best


## 매달 첫 주: 라이벌 에이스 소식 (시즌 3~10월, 기록이 쌓였을 때)
static func monthly_rival_news(state: Dictionary) -> void:
	var m := Cal.month_of(state["date"])
	if m < 4 or m > 10 or Cal.day_of(state["date"]) > 7:
		return
	var ace := rival_ace(state)
	if ace.is_empty():
		return
	var school: String = state["teams"][ace["teamId"]]["name"]
	var line := ""
	if ace["pos"] == "P" and int(ace["season"]["pit"]["outs"]) >= 15:
		var pt: Dictionary = ace["season"]["pit"]
		line = "%d승 %d패 평균자책점 %s, 탈삼진 %d" % [pt["w"], pt["l"], PlayerUtil.era_str(pt), pt["so"]]
	elif int(ace["season"]["bat"]["ab"]) >= 15:
		var b: Dictionary = ace["season"]["bat"]
		line = "타율 %s %d홈런 %d타점" % [PlayerUtil.avg_str(b), b["hr"], b["rbi"]]
	if line == "":
		return
	_news(state, "info", "[라이벌] %s 에이스 %s(%d학년 %s) — %s" % [school, PlayerUtil.full_name(ace), PlayerUtil.grade(ace, state["year"]), PlayerUtil.POS_KO[ace["pos"]], line])


## 라이벌전 뒤: 라이벌 에이스가 우리 상대로 낸 성적 누적 (state.rivalAceLog[선수 id] = {g, bat, pit})
static func after_rival_match(state: Dictionary, m: MatchEngine) -> void:
	var rid = state.get("rivalId")
	if rid == null:
		return
	var opp := m.home if m.home.team_id == rid else (m.away if m.away.team_id == rid else null)
	if opp == null:
		return
	var ace := rival_ace(state)
	if ace.is_empty() or not opp.box.has(ace["id"]):
		return
	if state.get("rivalAceLog") == null:
		state["rivalAceLog"] = {}
	var alog: Dictionary = state["rivalAceLog"]
	if not alog.has(ace["id"]):
		alog[ace["id"]] = {"g": 0, "bat": PlayerUtil.empty_bat(), "pit": PlayerUtil.empty_pit()}
	var rec: Dictionary = alog[ace["id"]]
	rec["g"] = int(rec["g"]) + 1
	PlayerUtil.add_line(rec["bat"], opp.box[ace["id"]]["bat"])
	PlayerUtil.add_line(rec["pit"], opp.box[ace["id"]]["pit"])


## 라이벌 에이스의 우리 상대 통산 한 줄 (기록 없으면 "")
static func ace_record_text(state: Dictionary, ace: Dictionary) -> String:
	var alog = state.get("rivalAceLog")
	if alog == null or not alog.has(ace["id"]):
		return ""
	var rec: Dictionary = alog[ace["id"]]
	var pt: Dictionary = rec["pit"]
	var b: Dictionary = rec["bat"]
	if ace["pos"] == "P" and int(pt["outs"]) > 0:
		return "우리 상대 %d경기 %d승 %d패 평균자책점 %s 탈삼진 %d" % [rec["g"], pt["w"], pt["l"], PlayerUtil.era_str(pt), pt["so"]]
	return "우리 상대 %d경기 %d타수 %d안타 %d홈런 %d타점" % [rec["g"], b["ab"], b["h"], b["hr"], b["rbi"]]


## 드래프트 뒤: 라이벌 에이스가 지명됐으면 소식
static func rival_draft_news(state: Dictionary) -> void:
	var ace := rival_ace(state)
	if ace.is_empty() or ace.get("draft") == null:
		return
	var rec := ace_record_text(state, ace)
	_news(state, "info", "[라이벌] %s 에이스 %s, %s %d라운드 지명.%s" % [state["teams"][ace["teamId"]]["name"], PlayerUtil.full_name(ace),
		Season.pro_team_name(state, ace["draft"]["teamId"]), ace["draft"]["round"], (" (" + rec + ")") if rec != "" else ""])


# ───────────── 선수 면담 (매달 첫 주) ─────────────

const TALK_OPTS := [["praise", "격려한다"], ["scold", "따끔하게 혼낸다"], ["idol", "동경하는 선수 이야기를 한다"], ["rest", "푹 쉬게 한다"]]


## 면담 대상: 슬럼프 → 재활 중 → 컨디션 나쁨 → 무작위 (우리 선수)
static func talk_target(state: Dictionary, rng: Rng) -> Dictionary:
	var roster := WorldGen.team_players(state, state["userTeamId"])
	if roster.is_empty():
		return {}
	for f in [func(p): return p.get("slump", false), func(p): return p.get("rehab", false), func(p): return int(p["cond"]) <= -1]:
		var c: Array = roster.filter(f)
		if not c.is_empty():
			return rng.pick(c)
	return rng.pick(roster)


static func monthly_talk(state: Dictionary, rng: Rng) -> void:
	if Cal.day_of(state["date"]) > 7:
		return
	var p := talk_target(state, rng)
	if p.is_empty():
		return
	var n := PlayerUtil.full_name(p)
	var why := "요즘 방망이가 안 맞아 고민이 많다." if p.get("slump", false) else ("재활 중이라 마음이 조급하다." if p.get("rehab", false) else ("컨디션이 안 좋아 보인다." if int(p["cond"]) <= -1 else "감독과 이야기하고 싶어 한다."))
	var opts := []
	for o in TALK_OPTS:
		if o[0] == "idol" and p.get("idolId") == null:
			continue
		opts.append([p["id"] + ":" + o[0], o[1]])
	# 기본값(격려)을 먼저 적용하고, 다른 걸 고르면 되돌린 뒤 적용
	state["talkUndo"] = {"id": p["id"], "cond": p["cond"], "fatigue": p["fatigue"], "idolBond": p["idolBond"], "mood": TeamMood.mood(state), "slump": p.get("slump", false)}
	_talk_apply(state, p, "praise", rng)
	state["popups"].append({"kind": "choice", "choice": "talk", "title": "선수 면담: " + n, "options": opts,
		"body": "%s(%d학년 %s, 성격 %s) %s\n지금: 컨디션 %s · 피로 %d%s\n\n어떻게 할까? (열혈·노력파는 꾸중에 힘을 내고, 소심한 선수는 풀이 죽는다)" % [n, PlayerUtil.grade(p, state["year"]), PlayerUtil.POS_KO[p["pos"]], p["personality"], why,
			["최악", "나쁨", "보통", "좋음", "절호조"][int(p["cond"]) + 2], int(p["fatigue"]), (" · 동경도 %d" % int(p["idolBond"])) if p.get("idolId") != null else ""]})


## 면담 효과. 결과 문구
static func _talk_apply(state: Dictionary, p: Dictionary, key: String, rng: Rng) -> String:
	var n := PlayerUtil.full_name(p)
	match key:
		"praise":
			p["cond"] = mini(2, int(p["cond"]) + 1)
			if p.get("slump", false) and rng.chance(0.5):
				p.erase("slump")
				return "%s 「감독님 말씀에 힘이 났어요!」 (컨디션 +1, 슬럼프 탈출)" % Text.josa(n, "은/는")
			return "%s 고개를 끄덕였다. (컨디션 +1)" % Text.josa(n, "은/는")
		"scold":
			if p["personality"] in ["열혈", "노력파"]:
				p["cond"] = mini(2, int(p["cond"]) + 2)
				p.erase("slump")
				var fs := Training.focus_stats(p)
				for k in fs:
					Training.apply_exp(p, k, 6.0 * fs[k], Training.growth_mult(p, k, state["pros"]), rng)
				return "%s 눈빛이 달라졌다! 「다시 해 보겠습니다!」 (컨디션 +2, 개인 연습 성장)" % Text.josa(n, "은/는")
			if p["personality"] == "소심":
				p["cond"] = maxi(-2, int(p["cond"]) - 1)
				TeamMood.change(state, -2)
				return "%s 풀이 죽었다... (컨디션 -1, 팀 분위기 -2)" % Text.josa(n, "은/는")
			return "%s 묵묵히 들었다. (변화 없음)" % Text.josa(n, "은/는")
		"idol":
			p["idolBond"] = clampi(int(p["idolBond"]) + 8, 0, 100)
			var pop = Idol.check_milestones(state, p)
			if pop != null:
				state["popups"].append(pop)
			return "%s 동경하는 선수 이야기에 신이 났다. (동경도 +8)" % Text.josa(n, "은/는")
		"rest":
			p["fatigue"] = maxf(0.0, p["fatigue"] - 30.0)
			return "%s 오랜만에 푹 쉬었다. (피로 -30)" % Text.josa(n, "은/는")
	return ""


static func choose_talk(state: Dictionary, choice_key: String) -> String:
	var parts := choice_key.split(":")
	var undo = state.get("talkUndo")
	state.erase("talkUndo")
	if parts.size() != 2 or undo == null or undo["id"] != parts[0]:
		return ""
	var p = state["players"].get(parts[0])
	if p == null:
		return ""
	if parts[1] == "praise":
		return "%s 고개를 끄덕였다." % Text.josa(PlayerUtil.full_name(p), "은/는")
	# 기본값(격려) 되돌리기
	p["cond"] = int(undo["cond"])
	p["fatigue"] = float(undo["fatigue"])
	p["idolBond"] = int(undo["idolBond"])
	state["teamMood"] = int(undo["mood"])
	if undo["slump"]:
		p["slump"] = true
	var rng := Season.rng_of(state)
	var msg := _talk_apply(state, p, parts[1], rng)
	Season.save_rng(state, rng)
	state["news"].append({"date": state["date"], "kind": "info", "text": "[면담] " + msg})
	return msg


static func _news(state: Dictionary, kind: String, text: String) -> void:
	state["news"].append({"date": state["date"], "kind": kind, "text": text})
