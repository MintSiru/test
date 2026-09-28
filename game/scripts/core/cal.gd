class_name Cal
extends RefCounted
## 날짜 유틸. 날짜는 모두 "YYYY-MM-DD" 문자열.
## 대회 일정 원본은 data/schedule.json (2026 시즌 실제 일정). 다른 해에는 같은 요일로 옮긴다.

const WEEKDAY_KO := ["일", "월", "화", "수", "목", "금", "토"]
const DAY := 86400


static func to_unix(s: String) -> int:
	return Time.get_unix_time_from_datetime_dict({
		"year": s.substr(0, 4).to_int(), "month": s.substr(5, 2).to_int(), "day": s.substr(8, 2).to_int(),
		"hour": 0, "minute": 0, "second": 0,
	})


static func from_unix(t: int) -> String:
	var d := Time.get_date_dict_from_unix_time(t)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func add_days(s: String, n: int) -> String:
	return from_unix(to_unix(s) + n * DAY)


static func diff_days(a: String, b: String) -> int:
	return roundi(float(to_unix(b) - to_unix(a)) / DAY)


## 0=일 ... 6=토
static func weekday(s: String) -> int:
	return Time.get_date_dict_from_unix_time(to_unix(s))["weekday"]


static func day_of(s: String) -> int:
	return s.substr(8, 2).to_int()


static func month_of(s: String) -> int:
	return s.substr(5, 2).to_int()


static func pretty(s: String, with_year := false) -> String:
	var base := "%d월 %d일 (%s)" % [s.substr(5, 2).to_int(), s.substr(8, 2).to_int(), WEEKDAY_KO[weekday(s)]]
	return ("%d년 " % s.substr(0, 4).to_int() + base) if with_year else base


static func short(s: String) -> String:
	return "%d/%d" % [s.substr(5, 2).to_int(), s.substr(8, 2).to_int()]


static func base_year() -> int:
	return int(GameData.schedule()["baseYear"])


## 시즌 연도의 MM-DD → 실제 날짜 (1~2월은 다음 해)
static func season_date(year: int, mmdd: String) -> String:
	var m := mmdd.substr(0, 2).to_int()
	return "%04d-%s" % [year + 1 if m <= 2 else year, mmdd]


## 기준 연도 날짜를 다른 시즌 연도로 옮기며 요일을 맞춘다
static func shift_to_year(base_date: String, year: int) -> String:
	var by := base_date.substr(0, 4).to_int()
	var target_year := year + (by - base_year())
	var cand := "%04d-%s" % [target_year, base_date.substr(5)]
	var delta := weekday(base_date) - weekday(cand)
	if delta > 3:
		delta -= 7
	if delta < -3:
		delta += 7
	return add_days(cand, delta)


static func comp_defs() -> Array:
	return GameData.schedule()["competitions"]


static func comp_def(key: String) -> Dictionary:
	for c in comp_defs():
		if c["key"] == key:
			return c
	push_error("unknown comp " + key)
	return {}


static func comp_dates(key: String, year: int) -> Dictionary:
	var d := comp_def(key)
	return {
		"start": shift_to_year("%d-%s" % [base_year(), d["start"]], year),
		"end": shift_to_year("%d-%s" % [base_year(), d["end"]], year),
	}


static func year_events(year: int) -> Array:
	var out := []
	for e in GameData.schedule()["events"]:
		var mmdd: String = e["date"]
		var date := season_date(year, mmdd) if mmdd.substr(0, 2).to_int() <= 2 else shift_to_year("%d-%s" % [base_year(), mmdd], year)
		out.append({"key": e["key"], "label": e["label"], "date": date})
	return out


static func season_start(year: int) -> String:
	return shift_to_year("%d-03-02" % base_year(), year)


static func season_year_of(date: String) -> int:
	var y := date.substr(0, 4).to_int()
	return y - 1 if date < season_start(y) else y


static func date_range(start: String, end: String) -> Array:
	var out := []
	var d := start
	while d <= end:
		out.append(d)
		d = add_days(d, 1)
	return out
