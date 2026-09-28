import { describe, expect, it } from 'vitest';
import { advance, autoPlayUserMatch, startNewGame, useCard } from '../src/core/season';
import { goalProgressText, goalText } from '../src/core/goals';
import type { GameState } from '../src/core/types';

function playUntil(state: GameState, untilDate: string) {
  let guard = 0;
  while (state.date < untilDate && guard++ < 40000) {
    const r = advance(state);
    if (r === 'training') useCard(state, state.hand[0].id);
    else if (r === 'match') autoPlayUserMatch(state);
    else if (r === 'popup') state.popups.splice(0);
  }
}

describe('후원회 연간 목표', () => {
  it('1년 차 달성률 40~70% (여러 시드, 자동 플레이)', () => {
    let done = 0;
    let total = 0;
    const lines: string[] = [];
    for (const seed of [3, 11, 29, 47, 58, 71, 83, 97, 104, 120]) {
      const s = startNewGame({ schoolName: '한빛고', managerName: '테스트', groupId: 'seoulA', seed });
      expect(s.goals?.list.length).toBe(3);
      playUntil(s, '2027-03-03');
      const rec = s.history.find((h) => h.year === 2026)!;
      const [d, t] = rec.goals!.split('/').map(Number);
      done += d;
      total += t;
      lines.push(`seed ${seed}: ${rec.goals} / 2027 목표(${s.goals!.tier}): ${s.goals!.list.map(goalText).join(', ')}`);
    }
    console.log(lines.join('\n'), '\n1년 차 달성률', done / total);
    expect(done / total).toBeGreaterThanOrEqual(0.4);
    expect(done / total).toBeLessThanOrEqual(0.7);
  }, 600000);

  it('진행 문구', () => {
    expect(goalText({ kind: 'nationalBest', target: 8, progress: 0, done: false })).toBe('전국대회 8강 진출');
    expect(goalProgressText({ kind: 'seasonWins', target: 6, progress: 2, done: false })).toBe('2/6');
    expect(goalProgressText({ kind: 'leagueRank', target: 3, progress: 4, done: false })).toBe('최고 4위');
  });
});
