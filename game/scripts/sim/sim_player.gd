class_name SimPlayer
extends RefCounted
## 경기용으로 평탄화한 선수 능력 (컨디션·피로 반영 완료)

var id: String
var name: String
var pos: String
var sub: Array = []
var bats: String = "R"
var throws: String = "R"
var con: float
var pow: float
var eye: float
var spd: float
var arm: float
var fld: float
var velo: float
var ctl: float
var sta: float
var stuff: float
var pitches: Array = []
## 변화구 목록과 선택 가중치 (매 투구 계산하지 않도록 미리 준비)
var breaking: Array = []
var breaking_w: Array = []
var abil: Array = []
## 특수능력 효과 (Abilities.compile): 조건별 타격·투구 효과와 항상 적용되는 수비·주루 수치
var fx_bat: Dictionary = {}
var fx_bat_cond: Array = []
var fx_pit: Dictionary = {}
var fx_pit_cond: Array = []
var f_fld := 0.0
var f_arm := 0.0
var f_err := 0.0
var f_lead := 0.0
var f_block := 0.0
var f_steal := 0.0
var f_run := 0.0
var can_pitch: bool = true
var face_seed: int = 0


func has(ab: String) -> bool:
	return ab in abil


## 선수 Dictionary → SimPlayer. 컨디션 단계당 ±3%, 피로 50 초과분 페널티
static func from_player(p: Dictionary, date: String, cond_bonus := 0) -> SimPlayer:
	var s := SimPlayer.new()
	var cond := mini(2, int(p["cond"]) + cond_bonus)
	var m: float = 1.0 + cond * 0.03 - maxf(0.0, p["fatigue"] - 50.0) * 0.002
	var r: Dictionary = p["r"]
	s.id = p["id"]
	s.name = PlayerUtil.full_name(p)
	s.pos = p["pos"]
	s.sub = p["sub"]
	s.bats = p["bats"]
	s.throws = p["throws"]
	s.con = clampf(r["contact"] * m, 1, 110)
	s.pow = clampf(r["power"] * m, 1, 110)
	s.eye = clampf(r["eye"] * m, 1, 110)
	s.spd = clampf(r["speed"] * m, 1, 110)
	s.arm = clampf(r["arm"] * m, 1, 110)
	s.fld = clampf(r["fielding"] * m, 1, 110)
	s.velo = r["velo"] + cond * 0.8
	s.ctl = clampf(r["control"] * m, 1, 110)
	s.sta = clampf(r["stamina"] * m, 1, 110)
	s.stuff = PlayerUtil.breaking_score(r["pitches"])
	s.pitches = r["pitches"]
	for x in s.pitches:
		if x["type"] != "FB":
			s.breaking.append(x)
			s.breaking_w.append(x["lv"] + 1)
	s.abil = p["abilities"]
	var fx := Abilities.compile(s.abil)
	s.fx_bat = fx["bat"]
	s.fx_bat_cond = fx["bat_cond"]
	s.fx_pit = fx["pit"]
	s.fx_pit_cond = fx["pit_cond"]
	var fl: Dictionary = fx["flat"]
	s.f_fld = fl["fld"]
	s.f_arm = fl["arm"]
	s.f_err = fl["err"]
	s.f_lead = fl["lead"]
	s.f_block = fl["block"]
	s.f_steal = fl["steal"]
	s.f_run = fl["run"]
	s.can_pitch = Lineup.can_pitch_on(p, date)
	s.face_seed = int(p.get("faceSeed", 0))
	return s
