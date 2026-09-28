class_name Shop
extends RefCounted
## 야구부 포인트와 장터 (web/src/core/shop.ts 이식, 원본 데이터 data/shop.json)
##  - 포인트는 경기 결과로만 얻는다 (승·무·패, 득점, 대회 성적, 리그 1위, 프로 지명)
##  - 장터는 매월 1일부터 7일간, 물건 구성이 매번 바뀐다
##  - 시설 기물은 방학·비시즌 달(1·2·7·8·12월) 장터에서만 설치
##  - 산 물건은 가방에 두었다가 원하는 때에 선수에게 쓴다


static func data() -> Dictionary:
	return GameData.load_json("shop")


static func facilities() -> Array:
	return data()["facilities"]


static func items() -> Array:
	return data()["items"]


static func item_def(key: String) -> Dictionary:
	for i in items():
		if i["key"] == key:
			return i
	return {}


# ───────────── 시설 ─────────────

static func level(state: Dictionary, key: String) -> int:
	return level_of(state.get("facilities"), key)


static func level_of(fac, key: String) -> int:
	if fac == null:
		return 0
	return int(fac.get(key, 0))


## 주간 훈련 성장 배율
static func growth(fac, k: String) -> float:
	if fac == null:
		return 1.0
	var m := 1.0
	for f in facilities():
		if k in f["stats"]:
			m += f["growth"] * level_of(fac, f["key"])
	return m


static func facility_cost(state: Dictionary, key: String) -> int:
	for f in facilities():
		if f["key"] == key:
			var lv := level(state, key)
			return -1 if lv >= f["costs"].size() else int(f["costs"][lv])
	return -1


# ───────────── 포인트 ─────────────

static func points(state: Dictionary) -> int:
	return int(state.get("points", 0))


static func earn(state: Dictionary, pts: int, reason: String) -> void:
	if pts <= 0:
		return
	state["points"] = points(state) + pts
	state["news"].append({"date": state["date"], "kind": "good", "text": "%s +%dP (보유 %dP)" % [reason, pts, state["points"]]})


static func match_points(friendly: bool, won: bool, drew: bool, runs: int, called: bool) -> int:
	var e: Dictionary = data()["earn"]
	if friendly:
		return int(e["friendlyWin"] if won else e["friendlyPlay"])
	return int((e["win"] if won else (e["draw"] if drew else e["loss"])) + runs * e["perRun"] + (e["coldWin"] if won and called else 0))


static func placing_points(result: String) -> int:
	return int(data()["earn"]["placing"].get(result, 0))


# ───────────── 장터 ─────────────

static func market_open(state: Dictionary) -> bool:
	var sh = state.get("shop")
	return sh != null and state["date"] <= sh["openUntil"]


static func facility_month(state: Dictionary) -> bool:
	# JSON 숫자는 float 로 읽히므로 int 로 바꿔 비교한다 (7 in [7.0] 은 false)
	var m := Cal.month_of(state["date"])
	for x in data()["market"]["facilityMonths"]:
		if int(x) == m:
			return true
	return false


## 다음 장터 날짜
static func next_market(state: Dictionary) -> String:
	var d: String = state["date"]
	var y := d.substr(0, 4).to_int()
	var m := d.substr(5, 2).to_int() + 1
	if m > 12:
		m = 1
		y += 1
	return "%04d-%02d-01" % [y, m]


static func _in_months(arr, m: int) -> bool:
	for x in arr:
		if int(x) == m:
			return true
	return false


## 이번 달 장터 행사 (없으면 빈 Dictionary). 여름 대회 대비 특가 · 연말 대바겐
static func sale_of(date: String) -> Dictionary:
	var m := Cal.month_of(date)
	for sl in data()["market"].get("sales", []):
		if _in_months(sl["months"], m):
			return sl
	return {}


## 이 달에 진열될 수 있는 아이템 (시기 한정 아이템은 그 달에만)
static func month_pool(date: String) -> Array:
	var m := Cal.month_of(date)
	return items().filter(func(x): return not x.has("months") or _in_months(x["months"], m))


static func open_market(state: Dictionary, rng: Rng) -> void:
	var mk: Dictionary = data()["market"]
	var sale := sale_of(state["date"])
	var discount: float = float(sale.get("discount", 0.0))
	var size := int(mk["stockSize"]) + int(sale.get("extra", 0))
	var stock := []
	var pool: Array = month_pool(state["date"])
	# 행사 달에는 시기 한정 상품을 먼저 진열
	if not sale.is_empty():
		for it in pool.filter(func(x): return x.has("months")):
			pool.erase(it)
			stock.append(_slot(it, discount, rng))
	while stock.size() < size and not pool.is_empty():
		var it: Dictionary = rng.weighted(pool, pool.map(func(x): return x["weight"]))
		pool.erase(it)
		stock.append(_slot(it, discount, rng))
	state["shop"] = {"openUntil": Cal.add_days(state["date"], int(mk["days"]) - 1), "stock": stock, "sale": sale.get("name", "")}
	var extra := ""
	if not sale.is_empty():
		extra = " · %s! %s" % [sale["name"], sale["desc"]]
	state["news"].append({"date": state["date"], "kind": "good",
		"text": "장터가 열렸다! (%d일간%s)%s" % [mk["days"], " · 이번 달은 시설 기물 설치 가능" if facility_month(state) else "", extra]})


static func _slot(it: Dictionary, discount: float, rng: Rng) -> Dictionary:
	var sl := {"key": it["key"], "qty": 1 if it["type"] in ["ability", "gold"] else rng.irange(1, 3)}
	if discount > 0.0:
		sl["price"] = int(round(float(it["price"]) * (1.0 - discount) / 5.0)) * 5
	return sl


## 진열 상품의 가격 (할인 반영)
static func slot_price(sl: Dictionary) -> int:
	return int(sl["price"]) if sl.has("price") else int(item_def(sl["key"]).get("price", 0))


## 구매. 실패하면 이유, 성공하면 ""
static func buy_item(state: Dictionary, key: String) -> String:
	if not market_open(state):
		return "장터가 열려 있지 않다."
	var slot = null
	for s in state["shop"]["stock"]:
		if s["key"] == key:
			slot = s
	var def := item_def(key)
	if slot == null or def.is_empty() or int(slot["qty"]) <= 0:
		return "품절이다."
	var price := slot_price(slot)
	if points(state) < price:
		return "포인트가 부족하다."
	state["points"] = points(state) - price
	slot["qty"] = int(slot["qty"]) - 1
	if state.get("inventory") == null:
		state["inventory"] = {}
	state["inventory"][key] = int(state["inventory"].get(key, 0)) + 1
	return ""


static func buy_facility(state: Dictionary, key: String) -> String:
	if not market_open(state) or not facility_month(state):
		return "시설 기물은 방학·비시즌(1·2·7·8·12월) 장터에서만 설치할 수 있다."
	var cost := facility_cost(state, key)
	if cost < 0:
		return "이미 최고 단계다."
	if points(state) < cost:
		return "포인트가 부족하다."
	state["points"] = points(state) - cost
	if state.get("facilities") == null:
		state["facilities"] = {}
	state["facilities"][key] = level(state, key) + 1
	for f in facilities():
		if f["key"] == key:
			state["news"].append({"date": state["date"], "kind": "good", "text": "%s Lv%d 설치! (-%dP)" % [f["name"], state["facilities"][key], cost]})
	return ""


# ───────────── 아이템 사용 ─────────────

static func needs_player(def: Dictionary) -> bool:
	return def["type"] in ["stat", "ability", "gold", "fix", "heal", "idol", "cond"]


## 쓸 수 없으면 이유, 쓸 수 있으면 ""
static func cannot_use(def: Dictionary, p: Dictionary) -> String:
	var is_p: bool = p["pos"] == "P"
	match def["type"]:
		"stat":
			if def.get("pitcher", false) and not is_p:
				return "투수 전용"
			if def["stat"] == "velo" and int(p["r"]["velo"]) >= 158:
				return "더 오를 수 없음"
		"ability":
			return Abilities.cannot_learn(p, def["ability"])
		"gold":
			return "" if not Abilities.gold_targets(p).is_empty() else "진화할 능력이 없음"
		"fix":
			for a in p["abilities"]:
				if Abilities.is_bad(a):
					return ""
			return "고칠 버릇이 없음"
		"heal":
			return "" if p["injury"] > 0 else "부상이 없음"
		"idol":
			return "" if p.get("idolId") != null else "동경하는 선수가 없음"
	return ""


## 사용 결과 {ok, msg}
static func use_item(state: Dictionary, key: String, target_id: String, rng: Rng) -> Dictionary:
	var def := item_def(key)
	var inv = state.get("inventory")
	var have := 0 if inv == null else int(inv.get(key, 0))
	if def.is_empty() or have <= 0:
		return {"ok": false, "msg": "가지고 있지 않다."}
	var msg := ""
	if needs_player(def):
		var p = state["players"].get(target_id)
		if p == null or p["teamId"] != state["userTeamId"]:
			return {"ok": false, "msg": "대상 선수를 고르세요."}
		var why := cannot_use(def, p)
		if why != "":
			return {"ok": false, "msg": why}
		var n := PlayerUtil.full_name(p)
		var r: Dictionary = p["r"]
		match def["type"]:
			"stat":
				var k: String = def["stat"]
				if k == "velo":
					r["velo"] = int(r["velo"]) + int(def["amount"])
					p["cap"]["velo"] = maxi(int(p["cap"]["velo"]), int(r["velo"]))
				elif k == "breaking":
					var target = null
					for x in r["pitches"]:
						if x["type"] != "FB" and int(x["lv"]) < 7 and (target == null or x["lv"] < target["lv"]):
							target = x
					if target != null:
						target["lv"] = int(target["lv"]) + 1
					else:
						var pool := ["SL", "CB", "CH", "FK", "SI", "CT"].filter(func(t): return r["pitches"].all(func(x): return x["type"] != t))
						if not pool.is_empty():
							r["pitches"].append({"type": rng.pick(pool), "lv": 1})
				else:
					r[k] = mini(99, int(r[k]) + int(def["amount"]))
					p["cap"][k] = maxi(int(p["cap"][k]), int(r[k]))
				msg = "%s %s(으)로 한층 성장했다!" % [Text.josa(n, "은/는"), def["name"]]
			"ability":
				var removed: Array = Abilities.learn(p, def["ability"]).filter(func(x): return Abilities.is_bad(x))
				msg = "%s %s을(를) 독파하고 「%s」을(를) 익혔다!%s" % [Text.josa(n, "은/는"), def["name"], Abilities.name_of(def["ability"]),
					" (「%s」 극복)" % Abilities.name_of(removed[0]) if not removed.is_empty() else ""]
			"gold":
				var g: String = rng.pick(Abilities.gold_targets(p))
				var old := ""
				for x in Abilities.learn(p, g):
					if not Abilities.is_bad(x):
						old = x
				msg = "%s의 「%s」이(가) 금특 「%s」(으)로 진화했다!" % [n, Abilities.name_of(old), Abilities.name_of(g)]
			"fix":
				var b: String = rng.pick(p["abilities"].filter(func(a): return Abilities.is_bad(a)))
				p["abilities"] = p["abilities"].filter(func(a): return a != b)
				msg = "%s의 나쁜 버릇 「%s」이(가) 고쳐졌다." % [n, Abilities.name_of(b)]
			"heal":
				p["injury"] = maxi(0, int(p["injury"]) - int(def["amount"]))
				msg = "%s의 부상이 빨리 나아지고 있다. (남은 기간 %d일)" % [n, p["injury"]]
			"idol":
				p["idolBond"] = clampi(int(p["idolBond"]) + int(def["amount"]), 0, 100)
				msg = "%s 사인볼을 품에 안고 잠들었다. (동경도 %d)" % [Text.josa(n, "은/는"), p["idolBond"]]
				var pop = Idol.check_milestones(state, p)
				if pop != null:
					state["popups"].append(pop)
			"cond":
				p["cond"] = 2
				msg = "%s, 부적 덕분인지 몸이 가볍다! (절호조)" % n
	else:
		var roster := WorldGen.team_players(state, state["userTeamId"])
		match def["type"]:
			"teamFatigue":
				for p in roster:
					p["fatigue"] = maxf(0.0, p["fatigue"] - int(def["amount"]))
				msg = "선수단 전원의 피로가 풀렸다."
			"teamCond":
				for p in roster:
					p["cond"] = mini(2, int(p["cond"]) + 1)
				msg = "보양식으로 선수단 전원의 기운이 넘친다!"
			"prospect":
				var pr = null
				for x in state["prospects"]:
					if x["id"] == target_id:
						pr = x
				if pr == null:
					return {"ok": false, "msg": "유망주를 고르세요." if not state["prospects"].is_empty() else "지금은 유망주 명단이 없다. (9월 드래프트 이후)"}
				pr["interest"] = clampi(int(pr["interest"]) + int(def["amount"]), 0, 100)
				msg = "%s에게 추천서를 보냈다. (입학 의향 %d%%)" % [PlayerUtil.full_name(pr["player"]), pr["interest"]]
			"cards":
				for c in state["hand"]:
					c["value"] = maxi(3, int(c["value"]))
					c["age"] = 0
				msg = "훈련 카드가 모두 좋은 카드로 바뀌었다!"
			"lucky":
				# 이 달 진열 가능한 일반 아이템 중에서 (복주머니·시기 한정 제외)
				var pool: Array = items().filter(func(x): return not x.has("months"))
				var got := []
				for i in int(def["amount"]):
					var it: Dictionary = rng.weighted(pool, pool.map(func(x): return x["weight"]))
					inv[it["key"]] = int(inv.get(it["key"], 0)) + 1
					got.append(it["name"])
				msg = "복주머니를 열었더니 %s이(가) 나왔다!" % ", ".join(got)
	inv[key] = have - 1
	if inv[key] <= 0:
		inv.erase(key)
	state["news"].append({"date": state["date"], "kind": "good", "text": msg})
	return {"ok": true, "msg": msg}


# ───────────── 일괄 사용 ─────────────

## 한 번에 여러 선수에게 쓸 수 있는 아이템 (부적·구급 상자·사인볼)
const BULK_TYPES := ["cond", "heal", "idol"]


## 일괄 사용 대상 (효과가 있는 선수, 우선순위 순, 가진 개수만큼)
static func bulk_targets(state: Dictionary, key: String) -> Array:
	var def := item_def(key)
	var inv = state.get("inventory")
	var have := 0 if inv == null else int(inv.get(key, 0))
	if def.is_empty() or not def["type"] in BULK_TYPES or have <= 0:
		return []
	var ps: Array = WorldGen.team_players(state, state["userTeamId"]).filter(func(p):
		if cannot_use(def, p) != "":
			return false
		match def["type"]:
			"cond": return int(p["cond"]) < 2 and int(p["injury"]) <= 0
			"idol": return int(p["idolBond"]) < 100
		return true)
	match def["type"]:
		"heal": ps.sort_custom(func(a, b): return int(a["injury"]) > int(b["injury"]))
		"cond": ps.sort_custom(func(a, b): return PlayerUtil.overall(a) > PlayerUtil.overall(b))
		"idol": ps.sort_custom(func(a, b): return int(a["idolBond"]) > int(b["idolBond"]))
	return ps.slice(0, have)


## 일괄 사용. {ok, msg, n}
static func use_bulk(state: Dictionary, key: String, rng: Rng) -> Dictionary:
	var targets := bulk_targets(state, key)
	if targets.is_empty():
		return {"ok": false, "msg": "지금 쓸 만한 선수가 없다.", "n": 0}
	var news_n: int = state["news"].size()
	var names := []
	for p in targets:
		if use_item(state, key, p["id"], rng)["ok"]:
			names.append(PlayerUtil.full_name(p))
	# 선수마다 쌓인 소식은 한 줄로 합친다
	state["news"].resize(news_n)
	var msg := "%s ×%d 사용: %s" % [item_def(key)["name"], names.size(), ", ".join(names)]
	state["news"].append({"date": state["date"], "kind": "good", "text": msg})
	return {"ok": true, "msg": msg, "n": names.size()}
