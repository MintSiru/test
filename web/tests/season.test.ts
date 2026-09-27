import { describe, expect, it } from 'vitest';
import { advance, autoPlayUserMatch, friendlyDate, friendlyOpponents, rngOf, scheduleFriendly, startNewGame, useCard, userFixtures } from '../src/core/season';
import { addDays } from '../src/core/calendar';
import { mix32 } from '../src/core/weather';
import { hashStr } from '../src/core/rng';
import { teamPlayers } from '../src/core/world';
import { grade, name, overall } from '../src/core/player';
import { compDates } from '../src/core/calendar';
import type { GameState } from '../src/core/types';

function playUntil(state: GameState, untilDate: string) {
  const popups: string[] = [];
  let guard = 0;
  while (state.date < untilDate && guard++ < 20000) {
    const r = advance(state);
    if (r === 'training') useCard(state, state.hand[0].id);
    else if (r === 'match') autoPlayUserMatch(state);
    else if (r === 'popup') popups.push(...state.popups.splice(0).map((p) => p.title));
  }
  return popups;
}

describe('calendar', () => {
  it('uses the real 2026 schedule', () => {
    expect(compDates('hwanggeum', 2026)).toEqual({ start: '2026-05-02', end: '2026-05-16' });
    expect(compDates('cheongryong', 2026)).toEqual({ start: '2026-06-27', end: '2026-07-11' });
    expect(compDates('bonghwang', 2026)).toEqual({ start: '2026-08-06', end: '2026-08-29' });
    // 다음 해엔 같은 요일로 이동
    const next = compDates('hwanggeum', 2027);
    expect(new Date(next.start).getUTCDay()).toBe(new Date('2026-05-02').getUTCDay());
  });
});

describe('weather', () => {
  it('rain postponements never leave a competition unfinished', () => {
    const state = startNewGame({ schoolName: '한빛고', managerName: '테스트', groupId: 'seoulB', seed: 77 });
    playUntil(state, '2026-11-01');
    const rain = state.competitions.flatMap((c) => c.fixtures).filter((f) => (f.postponed ?? 0) > 0).length;
    const total = state.competitions.flatMap((c) => c.fixtures).length;
    const twice = state.competitions.flatMap((c) => c.fixtures).filter((f) => (f.postponed ?? 0) >= 2).length;
    console.log('우천 연기된 경기', rain, '/', total, '두 번 연기', twice);
    expect(rain).toBeGreaterThan(0);
    // 장마철 포함 연기율은 5~25% (비 오는 주말 하루에 50경기가 한꺼번에 밀려 편차가 크다), 이틀 연속 비로 두 번 밀리는 경기는 드물어야 한다
    expect(rain / total).toBeGreaterThan(0.05);
    expect(rain / total).toBeLessThan(0.25);
    expect(twice / total).toBeLessThan(0.05);
    for (const c of state.competitions) {
      expect(c.status, c.name).toBe('done');
      if (c.kind === 'tournament') expect(c.champion, c.name).toBeTruthy();
    }
  }, 120000);
});

describe('full season simulation', () => {
  it('runs two seasons without errors', () => {
    const t0 = Date.now();
    const state = startNewGame({ schoolName: '한빛고', managerName: '테스트', groupId: 'seoulA', seed: 42 });
    expect(Object.keys(state.teams).length).toBe(103);
    const popups = playUntil(state, '2027-03-03');
    const t1 = Date.now();
    console.log('year1 ms', t1 - t0, 'popups', popups);
    console.log('history', JSON.stringify(state.history));
    console.log('rep', state.reputation, 'alumni', state.alumni.length, 'pros', state.pros.length);
    expect(state.year).toBe(2027);
    expect(state.history.length).toBe(1);
    expect(popups).toContain('KBO 신인 드래프트');
    const roster = teamPlayers(state, 'user');
    expect(roster.length).toBeGreaterThanOrEqual(12);
    console.log(roster.map((p) => `${name(p)} ${grade(p, state.year)}학년 ${p.pos} ovr${overall(p)} ★${p.talent}${p.idolId ? ' idol' : ''}`).join('\n'));
    playUntil(state, '2028-03-03');
    console.log('history2', JSON.stringify(state.history));
    console.log('size KB', Math.round(JSON.stringify(state).length / 1024), 'players', Object.keys(state.players).length);
    expect(state.year).toBe(2028);
    expect(state.history.length).toBe(2);
    expect(state.history[1].results.length).toBeGreaterThanOrEqual(4);
    // 새 시즌 대회가 편성되어 있어야 한다
    expect(userFixtures(state).length).toBeGreaterThan(5);
  }, 120000);
});

describe('friendly games', () => {
  it('can schedule a practice game in the off-season without touching official records', () => {
    const state = startNewGame({ schoolName: '한빛고', managerName: '테스트', groupId: 'seoulA', seed: 3 });
    playUntil(state, '2026-11-03');
    const recBefore = { ...state.teams.user.seasonRecord };
    const date = friendlyDate(state);
    expect(date).toBeTruthy();
    const rng = rngOf(state);
    const opp = friendlyOpponents(state, rng)[0];
    const f = scheduleFriendly(state, opp)!;
    expect(friendlyDate(state)).toBeNull(); // 같은 주에 두 번은 안 됨
    playUntil(state, addDays(f.date, 1));
    expect(f.result).toBeTruthy();
    expect(state.teams.user.seasonRecord).toEqual(recBefore);
  }, 120000);
});

describe('weather hash parity', () => {
  it('matches known values (Godot 쪽 weather.gd 와 같아야 함)', () => {
    // Godot 테스트(test_season.gd)에서도 같은 값을 확인한다
    expect(mix32(hashStr('42:2026-07-01'))).toBe(3842815896);
  });
});

describe('long run (10년)', () => {
  it('keeps enough active pro players for the idol system', () => {
    const state = startNewGame({ schoolName: '한빛고', managerName: '테스트', groupId: 'honamA', seed: 11 });
    playUntil(state, '2036-03-10');
    const active = state.pros.filter((p) => !p.retired).length;
    const fans = Object.values(state.players).filter((p) => p.idolId).length;
    const retiredOrig = state.pros.filter((p) => p.retired).length;
    console.log('10년 후 현역 프로', active, '전체 명단', state.pros.length, '은퇴(유지)', retiredOrig, '동경 선수 수', fans, '세이브 KB', Math.round(JSON.stringify(state).length / 1024));
    expect(active).toBeGreaterThanOrEqual(35);
    expect(fans).toBeGreaterThan(200);
    expect(state.year).toBe(2036);
  }, 600000);
});
