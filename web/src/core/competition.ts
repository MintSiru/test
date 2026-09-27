import { addDays, compDates, compDef, diffDays, weekday } from './calendar';
import type { Rng } from './rng';
import type { Competition, Fixture, GameState, LeagueGroup } from './types';

// 대회 생성 · 대진 · 순위 계산

export function dateRange(start: string, end: string): string[] {
  const out: string[] = [];
  for (let d = start; d <= end; d = addDays(d, 1)) out.push(d);
  return out;
}

/** 리그전 (권역별 풀리그) 생성. 경기는 토·일에 편성 */
export function createLeague(state: GameState, key: string, groups: LeagueGroup[]): Competition {
  const def = compDef(key);
  const { start, end } = compDates(key, state.year);
  const id = `${key}-${state.year}`;
  const weekend = dateRange(start, end).filter((d) => weekday(d) === 0 || weekday(d) === 6);
  const fixtures: Fixture[] = [];
  for (const g of groups) {
    const teams: (string | null)[] = [...g.teamIds];
    if (teams.length % 2) teams.push(null);
    const n = teams.length;
    const rounds = n - 1;
    const step = Math.max(1, Math.floor(weekend.length / rounds));
    for (let r = 0; r < rounds; r++) {
      const date = weekend[Math.min(weekend.length - 1, r * step)];
      for (let i = 0; i < n / 2; i++) {
        const a = teams[i];
        const b = teams[n - 1 - i];
        if (a && b) {
          const home = r % 2 ? a : b;
          const away = r % 2 ? b : a;
          fixtures.push({ id: `${id}-${g.id}-${r}-${i}`, compId: id, date, home, away, group: g.id, round: r });
        }
      }
      // circle method 회전 (첫 팀 고정)
      teams.splice(1, 0, teams.pop()!);
    }
  }
  return { id, key, name: def.name, kind: 'league', year: state.year, start, end, status: 'upcoming', fixtures, groups };
}

export interface Standing {
  teamId: string;
  w: number;
  l: number;
  d: number;
  rs: number;
  ra: number;
}

export function standings(comp: Competition, groupId: string): Standing[] {
  const g = comp.groups!.find((x) => x.id === groupId)!;
  const table = new Map<string, Standing>();
  for (const t of g.teamIds) table.set(t, { teamId: t, w: 0, l: 0, d: 0, rs: 0, ra: 0 });
  for (const f of comp.fixtures) {
    if (f.group !== groupId || !f.result) continue;
    const h = table.get(f.home)!;
    const a = table.get(f.away)!;
    h.rs += f.result.homeScore; h.ra += f.result.awayScore;
    a.rs += f.result.awayScore; a.ra += f.result.homeScore;
    if (!f.result.winner) { h.d++; a.d++; }
    else if (f.result.winner === f.home) { h.w++; a.l++; }
    else { a.w++; h.l++; }
  }
  return [...table.values()].sort((x, y) => {
    const px = x.w + x.d * 0.5;
    const py = y.w + y.d * 0.5;
    if (py !== px) return py - px;
    return y.rs - y.ra - (x.rs - x.ra);
  });
}

// ───────────────────────── 토너먼트 ─────────────────────────

export function createTournament(state: GameState, key: string, entrants: string[], rng: Rng, blockedDates: Set<string> = new Set()): Competition {
  const def = compDef(key);
  const { start, end } = compDates(key, state.year);
  const id = `${key}-${state.year}`;
  const n = entrants.length;
  let size = 2;
  while (size < n) size *= 2;
  const shuffled = rng.shuffle([...entrants]);
  // 부전승 배분: 앞쪽 (n - size/2) 개 쌍만 2팀, 나머지는 1팀 + 부전승
  const pairs: (string | null)[][] = [];
  const full = n - size / 2;
  let k = 0;
  for (let i = 0; i < size / 2; i++) {
    if (i < full) pairs.push([shuffled[k++], shuffled[k++]]);
    else pairs.push([shuffled[k++] ?? null, null]);
  }
  rng.shuffle(pairs);
  const first = pairs.flat();
  const rounds = Math.log2(size);
  const bracket: (string | null)[][] = [first];
  for (let r = 1; r <= rounds; r++) bracket.push(new Array(size / 2 ** r).fill(null));

  // 라운드별 날짜 배정: 뒤의 세 라운드(8강·4강·결승)는 하루씩 하루 간격, 앞 라운드는 경기 수 비례
  const days = dateRange(start, end);
  const usable = days.filter((d) => !blockedDates.has(d));
  const pool = usable.length >= rounds ? usable : days;
  const roundDates: string[][] = new Array(rounds).fill(null).map(() => []);
  let cursor = pool.length - 1;
  const lateRounds = Math.min(3, rounds);
  for (let i = 0; i < lateRounds; i++) {
    const r = rounds - 1 - i;
    roundDates[r] = [pool[Math.max(0, cursor)]];
    cursor -= 2;
  }
  const early = rounds - lateRounds;
  if (early > 0) {
    const avail = pool.slice(0, Math.max(early, cursor + 1));
    const games = new Array(early).fill(0).map((_, r) => size / 2 ** (r + 1));
    const total = games.reduce((a, b) => a + b, 0);
    let idx = 0;
    for (let r = 0; r < early; r++) {
      const remainRounds = early - r - 1;
      const share = Math.max(1, Math.round((games[r] / total) * avail.length));
      const take = Math.max(1, Math.min(share, avail.length - idx - remainRounds));
      roundDates[r] = avail.slice(idx, idx + take);
      idx += take;
      if (roundDates[r].length === 0) roundDates[r] = [avail[avail.length - 1]];
    }
  }
  const comp: Competition = {
    id, key, name: def.name, kind: 'tournament', year: state.year, start, end, status: 'upcoming',
    fixtures: [], bracket, roundDates, entrants: [...entrants],
  };
  scheduleRound(comp, 0);
  return comp;
}

/** r 라운드 대진을 확정해 fixture 생성 (부전승은 즉시 진출) */
export function scheduleRound(comp: Competition, r: number) {
  const br = comp.bracket!;
  const slots = br[r];
  const dates = comp.roundDates![r];
  let gi = 0;
  for (let i = 0; i < slots.length / 2; i++) {
    const a = slots[2 * i];
    const b = slots[2 * i + 1];
    if (a && b) {
      const date = dates[gi % dates.length];
      gi++;
      comp.fixtures.push({ id: `${comp.id}-r${r}-${i}`, compId: comp.id, date, home: a, away: b, round: r, slot: i });
    } else {
      br[r + 1][i] = a ?? b ?? null;
    }
  }
  // 한 라운드가 모두 부전승이면 다음 라운드로
  if (gi === 0 && r + 1 < br.length - 1) scheduleRound(comp, r + 1);
}

export function roundName(comp: Competition, r: number): string {
  const size = comp.bracket![r].length;
  if (size === 2) return '결승';
  if (size === 4) return '준결승';
  if (size === 8) return '8강';
  if (size === 16) return '16강';
  if (size === 32) return '32강';
  return `${r + 1}회전`;
}

/** 경기 결과 반영 후 토너먼트 진행. 라운드가 끝나면 다음 라운드 편성 */
export function advanceTournament(comp: Competition, f: Fixture) {
  if (f.round === undefined || f.slot === undefined || !f.result?.winner) return;
  const br = comp.bracket!;
  br[f.round + 1][f.slot] = f.result.winner;
  const roundFixtures = comp.fixtures.filter((x) => x.round === f.round);
  if (roundFixtures.every((x) => x.result)) {
    if (f.round + 1 === br.length - 1) {
      comp.champion = f.result.winner;
      comp.runnerUp = f.result.winner === f.home ? f.away : f.home;
      comp.status = 'done';
    } else {
      scheduleRound(comp, f.round + 1);
    }
  }
}

/** 사용자 팀 탈락/성적 문구 */
export function tournamentResultFor(comp: Competition, teamId: string): string | null {
  if (!comp.entrants?.includes(teamId)) return null;
  if (comp.champion === teamId) return '우승';
  if (comp.runnerUp === teamId) return '준우승';
  const lost = comp.fixtures.find((f) => f.result && f.result.winner !== teamId && (f.home === teamId || f.away === teamId));
  if (lost) return roundName(comp, lost.round!) === '준결승' ? '4강' : roundName(comp, lost.round!) + (roundName(comp, lost.round!).endsWith('강') ? '' : ' 탈락');
  return null;
}

export function daysUntil(from: string, to: string): number {
  return diffDays(from, to);
}
