import data from '../../../game/data/goals.json';
import { clamp } from './rng';
import type { GameState } from './types';

// ─────────────────────────────────────────────────────────────
// 후원회 연간 목표 (원본 데이터: game/data/goals.json)
//  - 매년 시즌 시작에 명성에 맞춰 3개. 달성 즉시 포인트·명성 보상
//  - 진행 상황은 경기 결과·리그 종료·전국대회 성적·드래프트에서 갱신
// ─────────────────────────────────────────────────────────────

export type GoalKind = 'seasonWins' | 'leagueRank' | 'nationalWins' | 'nationalBest' | 'draft';

export interface Goal {
  kind: GoalKind;
  target: number;
  /** 누적형은 현재 값, 순위형(leagueRank·nationalBest)은 지금까지 최고 순위 (0 = 아직 없음) */
  progress: number;
  done: boolean;
}

export interface Goals {
  year: number;
  tier: string;
  points: number;
  rep: number;
  list: Goal[];
}

const TIERS = data.tiers as { minRep: number; name: string; points: number; rep: number; goals: { kind: GoalKind; target: number }[] }[];
const RANK_KINDS: GoalKind[] = ['leagueRank', 'nationalBest'];

/** 전국대회 성적 → 순위 숫자 (우승 1, 준우승 2, 4강 4, 8강 8, 16강 16, 그 밖 99) */
export function placingRank(r: string): number {
  return ({ 우승: 1, 준우승: 2, '4강': 4, '8강': 8, '16강': 16 } as Record<string, number>)[r] ?? 99;
}

export function goalText(g: Goal): string {
  const t = (data.kinds as Record<string, string>)[g.kind];
  return t.replace('{n}', String(g.target)).replace('{r}', g.target <= 1 ? '우승' : g.target === 2 ? '결승' : `${g.target}강`);
}

export function goalProgressText(g: Goal): string {
  if (g.done) return '달성';
  if (RANK_KINDS.includes(g.kind)) return g.progress ? `최고 ${g.kind === 'leagueRank' ? `${g.progress}위` : g.progress >= 99 ? '초반 탈락' : `${g.progress}강`}` : '-';
  return `${g.progress}/${g.target}`;
}

/** 올해 목표 정하기 */
export function setGoals(state: GameState) {
  let tier = TIERS[0];
  for (const t of TIERS) if (state.reputation >= t.minRep) tier = t;
  state.goals = {
    year: state.year, tier: tier.name, points: tier.points, rep: tier.rep,
    list: tier.goals.map((g) => ({ kind: g.kind, target: g.target, progress: 0, done: false })),
  };
  state.news.push({ date: state.date, kind: 'info', text: `후원회 올해 목표(${tier.name}): ${state.goals.list.map(goalText).join(' · ')}` });
}

/**
 * 목표 진행 갱신. 누적형은 value 만큼 더하고, 순위형은 더 좋은(작은) 순위를 기록한다.
 * 달성하면 보상하고 팝업을 띄운다.
 */
export function goalEvent(state: GameState, kind: GoalKind, value: number) {
  const gs = state.goals;
  if (!gs) return;
  for (const g of gs.list) {
    if (g.kind !== kind || g.done) continue;
    if (RANK_KINDS.includes(kind)) g.progress = g.progress ? Math.min(g.progress, value) : value;
    else g.progress += value;
    const ok = RANK_KINDS.includes(kind) ? g.progress <= g.target : g.progress >= g.target;
    if (!ok) continue;
    g.done = true;
    state.points = (state.points ?? 0) + gs.points;
    state.reputation = clamp(state.reputation + gs.rep, 0, 100);
    const all = gs.list.every((x) => x.done);
    state.news.push({ date: state.date, kind: 'good', text: `후원회 목표 달성: ${goalText(g)} +${gs.points}P` });
    state.popups.push({
      kind: 'good', title: '후원회 목표 달성!',
      body: `「${goalText(g)}」 달성!\n후원회에서 격려금을 보내왔다. (+${gs.points}P, 명성 +${gs.rep})${all ? '\n\n올해 목표를 모두 이뤘다!' : ''}`,
    });
  }
}

/** 시즌 끝: 달성 수 반환하고 소식 남기기 */
export function closeGoals(state: GameState): number {
  const gs = state.goals;
  if (!gs) return 0;
  const n = gs.list.filter((g) => g.done).length;
  state.news.push({ date: state.date, kind: n ? 'good' : 'info', text: `${gs.year} 후원회 목표 ${n}/${gs.list.length} 달성` });
  return n;
}
