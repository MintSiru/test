import { describe, expect, it } from 'vitest';
import { Rng } from '../src/core/rng';
import { emptyBat, emptyPit, addBat, addPit } from '../src/core/player';
import { Match } from '../src/sim/engine';
import { buildSide } from '../src/sim/build';
import { playOut } from '../src/sim/ai';
import { makeTeam } from './helpers';

function runMany(n: number, qa: number, qb: number, seed = 1) {
  const rng = new Rng(seed);
  const bat = emptyBat();
  const pit = emptyPit();
  let runs = 0, games = 0, errors = 0, called = 0, extra = 0, winsA = 0, sb = 0, cs = 0;
  for (let i = 0; i < n; i++) {
    const a = makeTeam(rng, 'A' + i, qa);
    const b = makeTeam(rng, 'B' + i, qb);
    const m = new Match(buildSide(a.team, a.players, '2026-05-01'), buildSide(b.team, b.players, '2026-05-01'), rng);
    playOut(m);
    games++;
    runs += m.home.score + m.away.score;
    errors += m.home.errors + m.away.errors;
    if (m.called) called++;
    if (m.inning > 9) extra++;
    if (m.winner === 'A' + i) winsA++;
    for (const s of [m.home, m.away]) for (const e of Object.values(s.box)) { addBat(bat, e.bat); addPit(pit, e.pit); sb += e.bat.sb; cs += e.bat.cs; }
  }
  const avg = bat.h / bat.ab;
  const obp = (bat.h + bat.bb) / bat.pa;
  return {
    runsPerTeamGame: runs / games / 2, avg, obp,
    hrPerTeamGame: bat.hr / games / 2, kPct: bat.so / bat.pa, bbPct: bat.bb / bat.pa,
    errPerTeamGame: errors / games / 2, calledPct: called / games, extraPct: extra / games,
    winPctA: winsA / games, sbPerGame: sb / games, csPerGame: cs / games,
    pitchesPerTeamGame: pit.np / games / 2, sh: bat.sh / games, dpish: 0,
    outsCheck: pit.outs / games,
  };
}

describe('match engine balance (고교 수준)', () => {
  it('evenly matched teams produce realistic stat lines', () => {
    const r = runMany(400, 55, 55);
    console.log('even', r);
    expect(r.runsPerTeamGame).toBeGreaterThan(3);
    expect(r.runsPerTeamGame).toBeLessThan(7.5);
    expect(r.avg).toBeGreaterThan(0.24);
    expect(r.avg).toBeLessThan(0.33);
    expect(r.hrPerTeamGame).toBeLessThan(0.8);
    expect(r.kPct).toBeGreaterThan(0.11);
    expect(r.kPct).toBeLessThan(0.26);
    expect(r.bbPct).toBeGreaterThan(0.06);
    expect(r.bbPct).toBeLessThan(0.15);
  });
  it('stronger team wins more often', () => {
    const r = runMany(300, 80, 35, 7);
    console.log('strong vs weak', r);
    expect(r.winPctA).toBeGreaterThan(0.7);
  });
});
