extends Node
## 웹 빌드 성능 측정. 브라우저에서 index.html?bench 로 열거나, 데스크톱에서 -- --webbench
## 결과는 콘솔에 "BENCH {...}" 한 줄로 출력하고, 웹에서는 문서 제목에도 넣는다 (자동 측정 스크립트가 읽음)


func _ready() -> void:
	await get_tree().process_frame
	var res := {}
	var t0 := Time.get_ticks_msec()
	var s := Season.start_new_game({"schoolName": "한빛고", "managerName": "bench", "groupId": "seoulA", "seed": 7})
	res["newGameMs"] = Time.get_ticks_msec() - t0
	# 1) CPU끼리 경기 60개 (실황 생략 모드)
	var fx: Array = []
	for c in s["competitions"]:
		if c["key"] == "league1":
			fx = c["fixtures"].slice(0, 60)
	var rng := Rng.new(1)
	t0 = Time.get_ticks_usec()
	for f in fx:
		var m := Season.create_match(s, f, rng)
		m.quiet = true
		MatchAI.play_out(m)
	res["msPerCpuGame"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0 / fx.size(), 0.01)
	# 2) 경기가 가장 많은 주말 하루(주말리그 첫날) 진행: 전날까지 이동 후 그날 하루
	var s2 := Season.start_new_game({"schoolName": "한빛고", "managerName": "bench", "groupId": "seoulA", "seed": 7})
	var busy := "2026-03-07"
	for guard in 3000:
		if s2["date"] >= busy:
			break
		_step(s2)
	var games_before := _played(s2)
	t0 = Time.get_ticks_msec()
	var user_ms := 0
	for guard in 3000:
		if s2["date"] > busy:
			break
		user_ms += _step(s2)
	res["busyDay"] = busy
	res["busyDayGames"] = _played(s2) - games_before
	res["busyDayMs"] = Time.get_ticks_msec() - t0 - user_ms
	res["userMatchMs"] = user_ms
	# 3) 저장
	t0 = Time.get_ticks_msec()
	var js := JSON.stringify(s2)
	res["saveStringifyMs"] = Time.get_ticks_msec() - t0
	res["saveKB"] = js.length() / 1024
	res["platform"] = OS.get_name()
	var line := JSON.stringify(res)
	print("BENCH ", line)
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("document.title = 'BENCH ' + %s" % JSON.stringify(line))
	else:
		get_tree().quit()


## 하루 진행 한 걸음. 사용자 경기를 위임으로 처리했으면 그 시간(ms)을 돌려준다
func _step(s: Dictionary) -> int:
	var r := Season.advance(s, 1)
	if r == "training":
		Season.use_card(s, s["hand"][0]["id"])
	elif r == "popup":
		s["popups"].clear()
	elif r == "match":
		var t := Time.get_ticks_msec()
		Season.auto_play_user_match(s)
		return Time.get_ticks_msec() - t
	return 0


func _played(s: Dictionary) -> int:
	var n := 0
	for c in s["competitions"]:
		for f in c["fixtures"]:
			if f.get("result") != null:
				n += 1
	return n
