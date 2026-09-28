import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { batterOverall, genPlayer, letter, overall, pitcherOverall, veloScore } from '../src/core/player';
import { growthMult } from '../src/core/training';
import { COMP_DEFS, compDates } from '../src/core/calendar';
import { FACILITIES, ITEMS, facilityGrowth, matchPoints, placingPoints, saleOf, SHOP } from '../src/core/shop';
import { toSim } from '../src/sim/build';
import { captainBonus, moodAfterMatch, moodWeek } from '../src/core/mood';
import { Rng } from '../src/core/rng';
import type { GameState, Player, ProPlayer, StatKey } from '../src/core/types';

// 웹 ↔ Godot 동등성: 난수를 쓰지 않는 규칙 함수들의 결과를 game/tests/parity.json 에 고정하고
// 양쪽 테스트(이 파일, game/tests/test_parity.gd)가 같은 값을 내는지 본다.
// 규칙을 일부러 바꿨으면: PARITY_UPDATE=1 npx vitest run tests/parity.test.ts 로 기준값을 다시 만든 뒤 Godot 쪽도 같은 값이 나오게 고친다.
const FILE = path.resolve(__dirname, '../../game/tests/parity.json');
const STATS: StatKey[] = ['contact', 'power', 'eye', 'speed', 'arm', 'fielding', 'velo', 'control', 'stamina', 'breaking'];
const r4 = (v: number) => Math.round(v * 10000) / 10000;

function fixturePlayers(): Player[] {
  const out: Player[] = [];
  for (let i = 0; i < 12; i++) {
    const p = genPlayer(new Rng(1000 + i), { id: `fx${i}`, teamId: 't', enrollYear: 2026 - (i % 3), year: 2026, quality: 20 + i * 6, province: '서울' });
    p.cond = (i % 5) - 2;
    p.fatigue = (i * 13) % 90;
    p.idolId = i % 2 === 0 ? `pro${i % 4}` : undefined;
    p.idolBond = (i * 17) % 100;
    out.push(p);
  }
  return out;
}

function compute(players: Player[], pros: ProPlayer[]) {
  return {
    overall: players.map((p) => overall(p)),
    batterOverallAsSS: players.map((p) => batterOverall(p.r, 'SS')),
    pitcherOverall: players.map((p) => pitcherOverall(p.r)),
    sim: players.map((p) => { const s = toSim(p, '2026-05-01'); return [s.con, s.pow, s.eye, s.spd, s.arm, s.fld, s.velo, s.ctl, s.sta, s.stuff].map(r4); }),
    growth: players.map((p) => STATS.map((k) => r4(growthMult(p, k, pros)))),
    letter: Array.from({ length: 15 }, (_, i) => letter(i * 7)),
    veloScore: Array.from({ length: 9 }, (_, i) => r4(veloScore(120 + i * 5))),
    matchPoints: [false, true].flatMap((fr) => [[true, false], [false, true], [false, false]].flatMap(([w, d]) => [0, 3, 11].map((runs) => matchPoints(fr, w, d, runs, runs > 10)))),
    placing: Object.keys(SHOP.earn.placing).map((k) => placingPoints(k)),
    facilityGrowth: [0, 1, 2, 3].map((lv) => STATS.map((k) => r4(facilityGrowth(Object.fromEntries(FACILITIES.map((f) => [f.key, lv])), k)))),
    compDates: [2026, 2027, 2028, 2029].flatMap((y) => COMP_DEFS.map((c) => { const d = compDates(c.key, y); return `${c.key}:${d.start}~${d.end}`; })),
    captainBonus: players.map((p) => captainBonus(p)),
    moodSeq: (() => {
      // 승승승패무패패패 (공식전) → 연습 경기 패 → 주간 복귀 3번 (주장 없음)
      const st = { teamMood: 50, streak: 0, players: {}, userTeamId: 'u' } as unknown as GameState;
      const out: number[] = [];
      for (const [w, d, o] of [[1, 0, 1], [1, 0, 1], [1, 0, 1], [0, 0, 1], [0, 1, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 0]]) {
        moodAfterMatch(st, !!w, !!d, !!o);
        out.push(st.teamMood!);
      }
      for (let i = 0; i < 3; i++) { moodWeek(st, [], null); out.push(st.teamMood!); }
      return out;
    })(),
    salePrices: ['2026-06-01', '2026-12-01', '2026-04-01'].map((d) => { const s = saleOf(d); return ITEMS.map((it) => (s && s.discount > 0 ? Math.round((it.price * (1 - s.discount)) / 5) * 5 : it.price)); }),
  };
}

describe('웹 ↔ Godot 동등성 기준값', () => {
  it('parity.json 과 같다', () => {
    const update = process.env.PARITY_UPDATE === '1' || !fs.existsSync(FILE);
    const players = update ? fixturePlayers() : (JSON.parse(fs.readFileSync(FILE, 'utf8')).players as Player[]);
    const pros = ['파워히터', '교타자', '파이어볼러', '준족'].map((style, i) => ({ id: `pro${i}`, style }) as unknown as ProPlayer);
    const actual = compute(players, pros);
    if (update) fs.writeFileSync(FILE, JSON.stringify({ note: '웹 tests/parity.test.ts 가 만든 기준값. Godot tests/test_parity.gd 도 같은 값을 내야 한다.', players, pros, expected: actual }, null, 1) + '\n');
    const golden = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    expect(actual).toEqual(golden.expected);
  });
});
