# CLAUDE.md — AI 개발 가이드

이 저장소는 사용자가 **AI 만으로** 개발을 이어가는 한국 고교야구 육성 시뮬레이션이다.
사용자는 게임 개발 지식이 없으므로, 변경 후에는 반드시 테스트로 동작을 확인하고 결과를 쉬운 말로 설명한다.

## 구조

- `game/` — **실제 게임** (Godot 4.7, GDScript). 여기가 주 개발 대상.
- `web/` — **기반 시스템** (TypeScript). 규칙·밸런스의 원형이자 빠른 실험장. 텍스트 UI 만 있다.
- `game/data/*.json` — 두 쪽이 함께 읽는 **단일 데이터 원본** (학교·권역, 프로 리그, 대회 일정, 특수능력, 장터, 후원회 목표, 이름). `help.json`(도움말 문구)은 Godot 만 쓴다.
- 게임 상태는 양쪽 모두 **JSON 형태의 Dictionary/객체** 이고 키 이름이 같다 (`enrollYear`, `seasonRecord` …).
  로직 파일도 1:1 대응한다:

| web/src | game/scripts |
|---|---|
| core/player.ts | core/player_util.gd |
| core/lineup.ts | core/lineup.gd |
| core/training.ts | core/training.gd |
| core/competition.ts | core/competition.gd |
| core/idol.ts | core/idol.gd |
| core/scouting.ts | core/scouting.gd |
| core/events.ts | core/weekly_events.gd |
| core/world.ts | core/world_gen.gd |
| core/shop.ts | core/shop.gd |
| core/rival.ts | core/rival.gd |
| core/abilities.ts | core/abilities.gd |
| core/goals.ts | core/goals.gd |
| core/weather.ts | core/weather.gd |
| core/season.ts | core/season.gd |
| sim/engine.ts | sim/match_engine.gd |
| sim/ai.ts | sim/match_ai.gd |
| sim/build.ts | sim/side_builder.gd + sim/sim_player.gd |

규칙(확률·수치)을 바꾸면 **양쪽을 같이** 고치고 양쪽 테스트를 돌린다. 새 기능은 Godot 쪽만 있어도 되지만,
경기 엔진·성장 수치처럼 밸런스에 영향을 주는 것은 web 에서 먼저 실험하는 편이 빠르다.

## 테스트 (변경 후 항상 실행)

```bash
cd web && npm test                                   # vitest: 밸런스 + 2시즌
GODOT=/path/to/godot game/tests/run_tests.sh         # Godot 헤드리스: 파스 검사 + 밸런스·특수능력 + 1년 시즌 + 경기 중 저장
# UI 통합 테스트 (화면 필요: xvfb). 주의: 시작할 때 이 컴퓨터의 저장 슬롯 1~3을 지운다
xvfb-run -a godot --path game --rendering-driver opengl3 -- --uitest
# 1시즌 전체를 실제 화면으로 자동 플레이 (약 80초, 스크린샷 저장)
xvfb-run -a godot --path game --rendering-driver opengl3 -- --uiseason --shots=/tmp/shots
# 스크린샷: -- --newgame --days=40 --screen=roster --shot=/tmp/a.png  (main.gd 개발용 인자)
#   --pitches=N : 경기일에 경기를 만들고 N구 진행 / --watch : 자동 관전 / --delay=초
#   --usecard : 훈련 카드 사용 직후 / --boxscore : 경기 후 박스스코어 / --night : 야간·가랑비 연출
#   --notut : 처음 안내 팝업 끄기 (스크린샷용) / --catalog : 특수능력 도감 열기
# 성능: godot --headless --path game -s tests/bench.gd
# 파스 검사만: godot --headless --path game --check-only --script 파일.gd
# 웹 빌드 성능: godot --headless --path game --export-release "Web" build/web/index.html
#   node tools/web_bench.mjs build/web [--throttle=4]   (헤드리스 Chromium, 전역 playwright 사용)
#   데스크톱 비교: godot --headless --path game -- --webbench
```

Godot 바이너리가 없으면 `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` 에서 받는다.

## GDScript 주의사항 (실제로 겪은 문제)

- 새 `class_name` 을 추가하면 `godot --headless --path game --import` 로 클래스 캐시를 갱신해야 `-s` 스크립트에서 보인다.
- `-s` 테스트 스크립트는 참조하는 스크립트에 파스 오류가 있으면 **멈춘 것처럼 보인다** → 항상 `timeout` 을 걸고 `SCRIPT ERROR` 를 찾는다.
- Dictionary 값에서 `:=` 로 타입 추론하면 파스 오류가 난다 → `var x: float = d["k"]` 처럼 타입을 적는다.
- 내장 이름과 충돌 주의: 전역 enum `Side`, `Control.rotation`, 전역 함수 `log` 등을 멤버 이름으로 쓰지 말 것.
- JSON 은 숫자를 float 로 읽는다 → 로드 시 `Game.normalize()` 로 정수화. 배열 인덱스에는 `int()`.
- 코루틴을 `await` 없이 부르면 반환값을 나중에 `await` 할 수 없다 (field_view 의 `_start_moves` 방식 참고).
- `null` 을 돌려줄 수 있는 함수 결과는 분석기가 `null` 타입으로 보고 오류를 낸다 → 빈 Dictionary 를 반환 (`Idol.idol_of`).
- GDScript 스레드(WorkerThreadPool/Thread)는 이 프로젝트 측정에서 병렬 이득이 없었다 (릴리스 빌드 포함). 속도는 알고리즘으로 개선할 것.
- 32비트 해시 곱셈은 64비트 정수에서 넘친다 → `Weather._imul` 처럼 16비트로 나눠 곱한다. 웹과 같은 값이 나와야 하는 계산은 테스트로 값 일치를 확인.
- `Control` 에는 `rotation`, `scale`, `position` 같은 속성이 이미 있다 → 화면 스크립트 멤버 이름으로 쓰지 말 것.
- 데이터 JSON 의 숫자는 float 다. `7 in [7.0]` 은 **false** → 숫자 목록 비교는 `int()` 로 바꿔서 (`Shop.facility_month` 참고).
- `--check-only` 파스 검사를 통과해도 실제 실행에서 `var x := d.get(...) + 1` 같은 타입 추론 오류가 날 수 있다 (의존 스크립트의 클래스 캐시가 오래됐을 때).
  `run_tests.sh` 는 테스트 출력에 `SCRIPT ERROR` 가 보이면 바로 중단한다. 결국 **테스트를 실제로 돌려야** 안전하다.
- 웹 내보내기에서 `tests/` 는 빠진다 (`export_presets.cfg` exclude). 게임이 실행 중에 불러오는 개발용 스크립트는 `scripts/dev/` 에 둔다.

## 특수능력 추가·수정 (v0.4)

- `game/data/abilities.json` 에 항목만 추가하면 된다. `tier`(gold/good/bad), `for`(bat/pit/all), `group`(같은 종류 하나만), `fx`(경기 효과), `season`(시즌 효과), `upgrade`(금특 id), `pos`(포수 전용 등).
- `fx` 의 조건(`when`)과 수치 키는 정해진 목록만 쓴다 (`docs/GDD.md` 2-5, 웹 `tests/abilities.test.ts` 의 KNOWN). 새 조건·키가 필요하면
  웹 `sim/engine.ts`(cond, 해당 계산)와 Godot `sim/match_engine.gd`(`_cond`, **`step()` 과 `_fast_pa()` 둘 다**), `Abilities.COND`/`PIT_KEYS` 를 함께 고친다.
- 부정 능력을 새로 만들면 같은 `group` 에 긍정 능력을 두면 각성으로 극복할 수 있다.
- 장터 교본은 `shop.json` 의 `type: "ability"` 항목.

## 경기 엔진 주의 (v0.4)

- Godot 의 CPU끼리 경기(quiet)는 작전 없는 타석을 `_fast_pa()` 빠른 경로로 처리한다. **투구 규칙·확률을 바꾸면 `step()` 과 `_fast_pa()` 를 같이 고친다.**
  `test_balance.gd` 가 두 경로의 통계를 비교한다.
- 경기 중 저장은 입력 기록 재생 방식이다: 엔진 상태를 바꾸는 공개 함수(`step`, `change_pitcher`, `mound_visit`, `pinch_hit`, `pinch_run`, `def_sub`)는
  맨 앞에서 `_rec()` 로 기록한다. 새 작전 함수를 추가하면 `_rec()` 와 `replay()` 에도 넣고 `tests/test_save.gd` 를 돌린다.

## UI 규칙

- 화면은 코드로 조립한다 (`scripts/ui/ui.gd` 헬퍼, `BaseScreen`). 640×360 좌표를 `UI.place()` 로 직접 배치.
- 폰트: Galmuri11(12px) 기본, Galmuri9(10px) 작은 글씨. 이모지는 폰트에 없으니 쓰지 않는다.
- 도트 그래픽은 `PixelArt` 에서 코드로 생성·캐시한다. 외부 이미지를 추가하면 `default_texture_filter=0`(Nearest) 유지.
- 새 화면: `scripts/ui/screens/xxx_screen.gd` (extends BaseScreen, `setup(params)`) + `main.gd` 의 `SCREENS` 에 등록.
  `data/help.json` 의 `topics` 에 화면 이름과 같은 키로 도움말을 넣으면 상단 「?」 버튼이 그 도움말을 보여 준다.
- 특수능력 표시는 `UI.ability_chip()` / `UI.ability_flow()` 로 (색: 금특 노랑 · 긍정 파랑 · 부정 빨강). 처음 한 번 안내는 `Help.once(key)`.

## 데이터·내용 원칙

- 대회 이름·일정은 실제를 따른다 (`schedule.json`, 출처는 docs/GDD.md). 다른 해는 같은 요일로 자동 이동.
- 고교·고교 선수·프로 구단은 **가상**. 프로 선수는 사용자 결정에 따라 **실명**(`pros.json`)을 쓰고, 가상 명단(`pros_fictional.json`)을 선택지로 남긴다.
  실명을 쓰는 한 「비상업적 비공식 팬메이드」 고지(`GameData.FAN_MADE_NOTICE`, 웹 `FAN_MADE_NOTICE`)를 타이틀·새 게임 화면에 유지할 것. 상업적 이용 금지.
- 게임 재화는 **야구부 포인트**(경기 결과로만 획득)이고 장터는 매월 1~7일. 시설 기물은 1·2·7·8·12월에만.
- 텍스트는 한국어. 조사는 `Text.josa(word, "은/는")` 사용.

## 작업 방식

- 로드맵은 `docs/ROADMAP.md`. 항목마다 근거와 검증 기준을 적고, 끝나면 결과(측정값)를 남긴다.
- 기능을 넣은 뒤에는 수치 검증(웹 vitest 의 다년 시뮬레이션 등)과 화면 검증(스크린샷, `--uiseason`)을 함께 한다.
- 밸런스를 바꾸면 `tests/balance.test.ts`, `tests/test_balance.gd` 의 기준 범위를 확인한다.

## 배포

- `.github/workflows/ci.yml`: 푸시마다 web·Godot 테스트. 기본 브랜치에서는 Godot 웹 빌드 + 기반 시스템을 GitHub Pages 로 배포.
- Pages 는 저장소 Settings → Pages → Source 를 **GitHub Actions** 로 한 번 설정해야 한다 (사용자 작업).
