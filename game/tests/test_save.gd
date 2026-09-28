extends SceneTree
## 경기 도중 저장 → 불러오기 재현 테스트. godot --headless -s tests/test_save.gd


func snapshot(m: MatchEngine) -> Dictionary:
	var bases := []
	for b in m.bases:
		bases.append(null if b == null else b["id"])
	return {
		"inning": m.inning, "top": m.top, "outs": m.outs, "balls": m.balls, "strikes": m.strikes, "bases": bases,
		"home": m.home.score, "away": m.away.score, "pitchNo": m.pitch_no, "homeP": m.home.pitcher_id, "awayP": m.away.pitcher_id,
		"homeCount": m.home.pitch_count.duplicate(), "awayCount": m.away.pitch_count.duplicate(), "homeOrder": m.home.order.duplicate(),
		"awayOrder": m.away.order.duplicate(), "over": m.over, "rng": m.rng.get_state_str(),
	}


func play(m: MatchEngine, n: int, user_orders: bool) -> void:
	for i in n:
		if m.over:
			return
		if not MatchAI.pitching_change(m, m.def()):
			MatchAI.mound_visit(m, m.def())
		var o := MatchAI.orders(m)
		if user_orders and i % 7 == 3 and m.bases[0] != null:
			o["off"] = "steal"
		m.step(o)


func _init() -> void:
	var fails := 0
	var state := Season.start_new_game({"schoolName": "한빛고", "managerName": "t", "groupId": "seoulA", "seed": 21})
	# 첫 사용자 경기일까지
	for guard in 3000:
		var r := Season.advance(state, 1)
		if r == "training":
			Season.use_card(state, state["hand"][0]["id"])
		elif r == "popup":
			state["popups"].clear()
		elif r == "match":
			break
	var fid: String = state["pendingFixture"]
	var fx := Season.find_fixture(state, fid)
	var seed_val := 12345
	var m := Season.create_match(state, fx["f"], Rng.new(seed_val), {})
	m.save_info = {"fixtureId": fid, "seed": seed_val, "starterId": null}
	m.journal_on = true
	play(m, 140, true)
	# 대타·수비 교체도 기록되는지
	var off_side := m.off()
	for p in off_side.players:
		if not p.id in off_side.used and p.pos != "P":
			m.pinch_hit(off_side, p.id)
			break
	play(m, 20, false)
	var before := snapshot(m)
	# 세이브 파일과 똑같이 JSON 으로 왕복
	state["matchSave"] = m.save_data()
	var loaded: Dictionary = _roundtrip(state)
	var r2 := MatchEngine.resume(loaded, loaded["matchSave"])
	if r2 == null:
		print("FAIL: resume returned null")
		quit(1)
		return
	var after := snapshot(r2)
	print("저장 시점 ", before["inning"], "회", "초" if before["top"] else "말", " ", before["away"], ":", before["home"], " 투구 ", before["pitchNo"], " 기록 ", m.journal.size())
	for k in before:
		if str(before[k]) != str(after[k]):
			print("FAIL: ", k, " ", before[k], " != ", after[k])
			fails += 1
	# 이어서 끝까지 같은 입력이면 같은 결과
	play(m, 2000, false)
	play(r2, 2000, false)
	var e1 := snapshot(m)
	var e2 := snapshot(r2)
	print("끝까지: ", e1["away"], ":", e1["home"], " / ", e2["away"], ":", e2["home"])
	if str(e1) != str(e2):
		print("FAIL: 이어서 진행한 결과가 다름")
		fails += 1
	# 다른 경기일이 되면 재개하지 않는다
	var stale := loaded.duplicate()
	stale.erase("pendingFixture")
	if MatchEngine.resume(stale, loaded["matchSave"]) != null:
		print("FAIL: 경기일이 아닌데 재개됨")
		fails += 1
	# 세이브 파일 형식: v0.6 압축 바이너리 + 이전 JSON 텍스트 둘 다 읽기
	var G = load("res://scripts/autoload/game.gd")
	var jf := FileAccess.open("user://_test_legacy.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(state))
	jf.close()
	var bf := FileAccess.open_compressed("user://_test_new.bin", FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	bf.store_var(state)
	bf.close()
	var a1: Dictionary = G.read_save("user://_test_legacy.json")
	var a2: Dictionary = G.read_save("user://_test_new.bin")
	var sz := FileAccess.open("user://_test_new.bin", FileAccess.READ).get_length()
	print("세이브 파일 %d KB (JSON %d KB)" % [sz / 1024, JSON.stringify(state).length() / 1024])
	if a1.get("date") != state["date"] or a2.get("date") != state["date"] or a2["players"].size() != state["players"].size() or typeof(a2["year"]) != TYPE_INT:
		print("FAIL: 세이브 형식 읽기")
		fails += 1
	DirAccess.remove_absolute("user://_test_legacy.json")
	DirAccess.remove_absolute("user://_test_new.bin")
	print("SAVE ", "OK" if fails == 0 else "FAILED")
	quit(1 if fails else 0)


## 세이브 파일처럼 JSON 문자열로 바꿨다가 다시 읽고 정수화 (Game.normalize 와 같은 처리)
func _roundtrip(s: Dictionary) -> Dictionary:
	var d = JSON.parse_string(JSON.stringify(s))
	return _norm(d)


func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v.keys():
				v[k] = _norm(v[k])
			return v
		TYPE_ARRAY:
			for i in v.size():
				v[i] = _norm(v[i])
			return v
		TYPE_FLOAT:
			if is_equal_approx(v, roundf(v)) and absf(v) < 1e15:
				return int(v)
	return v
