import { grade, overall } from './player';
import { type Rng } from './rng';
import type { GameState, Player } from './types';
import { teamPlayers } from './world';

// ─────────────────────────────────────────────────────────────
// 주장·팀 분위기 (Godot scripts/core/team_mood.gd 와 같은 규칙, 밸런스 실험용 원형)
//  - 분위기 0~100 (처음 50). 승 +6 / 패 -6, 3연승·3연패부터 ±3 더. 연습 경기는 절반
//  - 매주 「50 + 주장 보너스 (+ 감독 특기, Godot 전용)」 쪽으로 10% 복귀
//  - 65 이상이면 매주 선수마다 (분위기-58)% 확률로 컨디션 +1, 35 이하면 (42-분위기)% 확률로 -1
//  - 주장 보너스 = 3 + 성격(열혈 4·낙천 3·노력파 2·냉정 1) + 종합 능력치(50 넘는 10마다 1, 최대 4)
//  웹에는 주장 선택 팝업이 없어 1순위 후보를 자동으로 뽑는다.
// ─────────────────────────────────────────────────────────────

const LEAD_BONUS: Record<string, number> = { 열혈: 4, 낙천: 3, 노력파: 2, 냉정: 1 };

export function mood(state: GameState): number {
  return state.teamMood ?? 50;
}

export function changeMood(state: GameState, d: number) {
  state.teamMood = Math.max(0, Math.min(100, mood(state) + d));
}

export function captainBonus(p: Player | undefined): number {
  if (!p) return 0;
  return 3 + (LEAD_BONUS[p.personality] ?? 0) + Math.max(0, Math.min(4, Math.trunc((overall(p) - 50) / 10)));
}

export function captainOf(state: GameState): Player | undefined {
  const p = state.captainId ? state.players[state.captainId] : undefined;
  return p && p.teamId === state.userTeamId ? p : undefined;
}

/** 우리 경기 뒤 */
export function moodAfterMatch(state: GameState, won: boolean, drew: boolean, official: boolean) {
  let st = state.streak ?? 0;
  if (drew) st = 0;
  else if (won) st = st >= 0 ? Math.max(1, st + 1) : 1;
  else st = st <= 0 ? Math.min(-1, st - 1) : -1;
  state.streak = st;
  let d = 0;
  if (won) d = 6 + (st >= 3 ? 3 : 0);
  else if (!drew) d = -6 - (st <= -3 ? 3 : 0);
  // GDScript 정수 나눗셈(0 쪽으로 버림)과 같게
  changeMood(state, official ? d : Math.trunc(d / 2));
}

/** 매주: 기준점으로 복귀(결정적) + 컨디션 영향(난수) */
export function moodWeek(state: GameState, roster: Player[], rng: Rng | null, extraTarget = 0) {
  const target = 50 + captainBonus(captainOf(state)) + extraTarget;
  const m = mood(state);
  // GDScript roundi 는 0.5 를 0 에서 먼 쪽으로 반올림
  const diff = (target - m) * 0.1;
  state.teamMood = Math.max(0, Math.min(100, m + Math.sign(diff) * Math.round(Math.abs(diff))));
  if (!rng) return;
  for (const p of roster) {
    if (m >= 65 && rng.chance((m - 58) / 100)) p.cond = Math.min(2, p.cond + 1);
    else if (m <= 35 && rng.chance((42 - m) / 100)) p.cond = Math.max(-2, p.cond - 1);
  }
}

function captainScore(p: Player): number {
  return overall(p) + (LEAD_BONUS[p.personality] ?? 0) * 3;
}

/** 주장 선출 (1순위 자동). g = 후보 학년 (은퇴식 직후 2, 새 게임 3) */
export function electCaptain(state: GameState, g: number) {
  const cand = teamPlayers(state, state.userTeamId).filter((p) => grade(p, state.year) === g);
  cand.sort((a, b) => captainScore(b) - captainScore(a));
  state.captainId = cand[0]?.id;
}
