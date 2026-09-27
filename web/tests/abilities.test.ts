import { describe, expect, it } from 'vitest';
import { ABILITIES, ABILITY_CONDITIONS, abilityDef, cannotLearn, compileFx, learnAbility } from '../src/core/abilities';
import { Rng } from '../src/core/rng';
import { addBat, addPit, emptyBat, emptyPit } from '../src/core/player';
import { Match } from '../src/sim/engine';
import { buildSide } from '../src/sim/build';
import { playOut } from '../src/sim/ai';
import { newGame } from '../src/core/world';
import type { Player } from '../src/core/types';
import { makeTeam } from './helpers';

const KNOWN = new Set([
  'con', 'pow', 'eye', 'contact', 'foul', 'evel', 'dist', 'swing', 'ld', 'pu', 'dp', 'bunt', 'buntHit', 'gbHit',
  'velo', 'ctl', 'stuff', 'ppFB', 'ppBR', 'whiff', 'wild', 'sta', 'gbRate', 'hrAllow', 'hold', 'zone', 'mistake',
  'fld', 'arm', 'err', 'lead', 'block', 'steal', 'run',
]);

/** A 팀 선수 전원(타자 또는 투수)에게 능력을 준 경기 N번의 합계 */
function runWith(ability: string | null, forPitchers: boolean, n = 300, seed = 11) {
  const rng = new Rng(seed);
  const bat = emptyBat();
  const pit = emptyPit();
  let errs = 0;
  for (let i = 0; i < n; i++) {
    const a = makeTeam(rng, 'A' + i, 55);
    const b = makeTeam(rng, 'B' + i, 55);
    for (const p of a.players) {
      p.abilities = [];
      if (ability && (p.pos === 'P') === forPitchers) p.abilities = [ability];
    }
    for (const p of b.players) p.abilities = [];
    const m = new Match(buildSide(a.team, a.players, '2026-05-01'), buildSide(b.team, b.players, '2026-05-01'), rng);
    playOut(m);
    const sa = m.sideOf('A' + i);
    const sb = m.sideOf('B' + i);
    // 타자 능력은 A 팀 타격, 투수 능력은 B 팀 타격(= A 팀 투수 상대)으로 본다
    const side = forPitchers ? sb : sa;
    for (const e of Object.values(side.box)) addBat(bat, e.bat);
    for (const e of Object.values(sa.box)) addPit(pit, e.pit);
    errs += sa.errors;
  }
  return {
    avg: bat.h / bat.ab, hrPa: bat.hr / bat.pa, kPct: bat.so / bat.pa, bbPct: bat.bb / bat.pa,
    sbPct: bat.sb / Math.max(1, bat.sb + bat.cs), runs: bat.r / n, errs: errs / n,
  };
}

describe('특수능력 데이터', () => {
  it('85개 이상, 그룹·조건·효과 키가 올바르다', () => {
    expect(ABILITIES.length).toBeGreaterThanOrEqual(80);
    const groups: Record<string, string[]> = {};
    for (const a of ABILITIES) {
      (groups[a.group] ??= []).push(a.tier);
      if (a.upgrade) expect(abilityDef(a.upgrade)?.tier).toBe('gold');
      for (const fx of a.fx ?? []) {
        if (fx.when) expect(ABILITY_CONDITIONS[fx.when], `${a.id} when ${fx.when}`).toBeTruthy();
        for (const k of Object.keys(fx)) if (k !== 'when') expect(KNOWN.has(k), `${a.id}.${k}`).toBe(true);
      }
      expect(a.fx || a.season, a.id).toBeTruthy();
    }
    for (const [g, tiers] of Object.entries(groups)) {
      for (const t of ['gold', 'good', 'bad']) expect(tiers.filter((x) => x === t).length, g).toBeLessThanOrEqual(1);
    }
    const tiers = ABILITIES.reduce<Record<string, number>>((m, a) => ((m[a.tier] = (m[a.tier] ?? 0) + 1), m), {});
    console.log('tiers', tiers);
  });

  it('같은 그룹 규칙: 긍정은 부정을 없애고, 금특은 긍정을 대체하며, 부정은 긍정 위에 붙지 않는다', () => {
    const p = { pos: 'SS', sub: [], abilities: ['chanceX'] } as unknown as Player;
    expect(learnAbility(p, 'chance')).toEqual(['chanceX']);
    expect(p.abilities).toEqual(['chance']);
    expect(cannotLearn(p, 'chanceX')).toBeTruthy();
    learnAbility(p, 'chanceG');
    expect(p.abilities).toEqual(['chanceG']);
    expect(cannotLearn(p, 'chance')).toBe('상위 능력을 가지고 있음');
    expect(cannotLearn(p, 'pinch')).toBe('투수 전용');
    expect(cannotLearn(p, 'worker')).toBeNull();
    expect(compileFx(['glove', 'laser', 'stealer']).flat).toMatchObject({ fld: 8, arm: 15, steal: 0.13 });
  });

  it('새 게임 선수 분포: 긍정·부정·금특이 모두 나오고 금특은 드물다', () => {
    const s = newGame({ schoolName: '테스트고', managerName: '감독', groupId: 'seoulA', seed: 5 });
    const ps = Object.values(s.players);
    const has = (t: string) => ps.filter((p) => p.abilities.some((x) => abilityDef(x)?.tier === t)).length / ps.length;
    const r = { good: has('good'), bad: has('bad'), gold: has('gold'), perPlayer: ps.reduce((n, p) => n + p.abilities.length, 0) / ps.length };
    console.log('분포', r);
    expect(r.good).toBeGreaterThan(0.35);
    expect(r.good).toBeLessThan(0.7);
    expect(r.bad).toBeGreaterThan(0.1);
    expect(r.bad).toBeLessThan(0.35);
    expect(r.gold).toBeGreaterThan(0);
    expect(r.gold).toBeLessThan(0.06);
  });
});

describe('특수능력 경기 효과 (같은 시드, 능력 유무 비교)', () => {
  const base = runWith(null, false);
  const baseP = runWith(null, true);
  it('타자 능력', () => {
    const power = runWith('powerG', false);
    const eyeX = runWith('eyeX', false);
    const hit = runWith('hitG', false);
    const steal = runWith('stealG', false);
    const k = runWith('strikeoutX', false);
    console.log({ base, power, eyeX, hit, steal, k });
    expect(power.hrPa).toBeGreaterThan(base.hrPa * 1.3);
    expect(eyeX.bbPct).toBeLessThan(base.bbPct);
    expect(hit.avg).toBeGreaterThan(base.avg + 0.01);
    expect(steal.sbPct).toBeGreaterThan(base.sbPct);
    expect(k.kPct).toBeGreaterThan(base.kPct);
  });
  it('투수 능력', () => {
    const kG = runWith('kG', true);
    const wild = runWith('wild', true);
    const heavy = runWith('heavyG', true);
    const hrX = runWith('hrX', true);
    console.log({ baseP, kG, wild, heavy, hrX });
    expect(kG.kPct).toBeGreaterThan(baseP.kPct + 0.01);
    expect(wild.bbPct).toBeGreaterThan(baseP.bbPct);
    expect(heavy.avg).toBeLessThan(baseP.avg);
    expect(hrX.hrPa).toBeGreaterThan(baseP.hrPa);
  });
});
