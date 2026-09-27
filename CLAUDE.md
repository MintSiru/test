# CLAUDE.md — AI 개발 가이드

이 저장소는 사용자가 **AI 만으로** 개발을 이어가는 한국 고교야구 육성 시뮬레이션이다.
사용자는 게임 개발 지식이 없으므로, 변경 후에는 반드시 테스트로 동작을 확인하고 결과를 쉬운 말로 설명한다.

## 구조

- `game/` — **실제 게임** (Godot 4.7, GDScript). 여기가 주 개발 대상.
- `web/` — **기반 시스템** (TypeScript). 규칙·밸런스의 원형이자 빠른 실험장. 텍스트 UI 만 있다.
- `game/data/*.json` — 두 쪽이 함께 읽는 **단일 데이터 원본** (학교·권역, 프로 리그, 대회 일정, 특수능력, 이름).
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
| core/season.ts | core/season.gd |
| sim/engine.ts | sim/match_engine.gd |
| sim/ai.ts | sim/match_ai.gd |
| sim/build.ts | sim/side_builder.gd + sim/sim_player.gd |

규칙(확률·수치)을 바꾸면 **양쪽을 같이** 고치고 양쪽 테스트를 돌린다. 새 기능은 Godot 쪽만 있어도 되지만,
경기 엔진·성장 수치처럼 밸런스에 영향을 주는 것은 web 에서 먼저 실험하는 편이 빠르다.

## 테스트 (변경 후 항상 실행)

```bash
cd web && npm test                                   # vitest: 밸런스 + 2시즌
GODOT=/path/to/godot game/tests/run_tests.sh         # Godot 헤드리스: 밸런스 + 1년 시즌
# UI 통합 테스트 (화면 필요: xvfb)
xvfb-run -a godot --path game --rendering-driver opengl3 -- --uitest
# 스크린샷: -- --newgame --days=40 --screen=roster --shot=/tmp/a.png  (main.gd 개발용 인자)
#   --pitches=N : 경기일에 경기를 만들고 N구 진행 / --watch : 자동 관전 / --delay=초
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

## UI 규칙

- 화면은 코드로 조립한다 (`scripts/ui/ui.gd` 헬퍼, `BaseScreen`). 640×360 좌표를 `UI.place()` 로 직접 배치.
- 폰트: Galmuri11(12px) 기본, Galmuri9(10px) 작은 글씨. 이모지는 폰트에 없으니 쓰지 않는다.
- 도트 그래픽은 `PixelArt` 에서 코드로 생성·캐시한다. 외부 이미지를 추가하면 `default_texture_filter=0`(Nearest) 유지.
- 새 화면: `scripts/ui/screens/xxx_screen.gd` (extends BaseScreen, `setup(params)`) + `main.gd` 의 `SCREENS` 에 등록.

## 데이터·내용 원칙

- 대회 이름·일정은 실제를 따른다 (`schedule.json`, 출처는 docs/GDD.md). 다른 해는 같은 요일로 자동 이동.
- 학교·선수·프로 선수·프로 구단은 **가상**. 실존 선수 이름을 넣지 않는다 (성명권).
- 텍스트는 한국어. 조사는 `Text.josa(word, "은/는")` 사용.

## 배포

- `.github/workflows/ci.yml`: 푸시마다 web·Godot 테스트. 기본 브랜치에서는 Godot 웹 빌드 + 기반 시스템을 GitHub Pages 로 배포.
- Pages 는 저장소 Settings → Pages → Source 를 **GitHub Actions** 로 한 번 설정해야 한다 (사용자 작업).
