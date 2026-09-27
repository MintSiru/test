import { batterOverall, pitcherOverall, posAptitude } from './player';
import type { LineupSlot, Player, Pos } from './types';

// 자동 편성: 수비 위치 → 지명타자 → 타순 순서로 정한다.

const FILL_ORDER: Pos[] = ['C', 'SS', 'CF', '2B', '3B', 'RF', 'LF', '1B'];

export function batValue(p: Player): number {
  return p.r.contact * 0.36 + p.r.power * 0.32 + p.r.eye * 0.14 + p.r.speed * 0.18;
}

function slotValue(p: Player, pos: Pos): number {
  const apt = posAptitude(p, pos);
  const def = (p.r.fielding * 0.6 + p.r.arm * 0.4) * apt;
  const w = pos === 'C' || pos === 'SS' ? 0.45 : pos === '2B' || pos === 'CF' ? 0.35 : 0.2;
  return batValue(p) * (1 - w) + def * w - (apt < 0.6 ? 30 : 0);
}

export function available(p: Player, date: string): boolean {
  void date;
  return p.injury <= 0;
}

export function canPitchOn(p: Player, date: string): boolean {
  return p.injury <= 0 && (!p.restUntil || p.restUntil <= date);
}

/** 수비 위치와 타순 자동 결정 (투수는 지명타자 제도로 타석에 서지 않는다) */
export function autoLineup(players: Player[], date: string, excludeIds: string[] = []): LineupSlot[] {
  const pool = players.filter((p) => available(p, date) && !excludeIds.includes(p.id));
  const fielders = pool.filter((p) => p.pos !== 'P');
  const chosen = new Map<Pos, Player>();
  const used = new Set<string>();
  for (const pos of FILL_ORDER) {
    let best: Player | null = null;
    let bv = -Infinity;
    for (const p of fielders) {
      if (used.has(p.id)) continue;
      const v = slotValue(p, pos);
      if (v > bv) { bv = v; best = p; }
    }
    if (!best) {
      // 야수가 모자라면 투수라도 채운다
      best = pool.find((p) => !used.has(p.id)) ?? null;
    }
    if (best) { chosen.set(pos, best); used.add(best.id); }
  }
  // 지명타자: 남은 야수 중 타격 최고 (야수가 없을 때만 투수)
  const restDh = pool.filter((p) => !used.has(p.id)).sort((a, b) => batValue(b) - batValue(a));
  const dh = restDh.find((p) => p.pos !== 'P') ?? restDh[0];
  const nine: { p: Player; pos: Pos | 'DH' }[] = [...chosen.entries()].map(([pos, p]) => ({ p, pos }));
  if (dh) nine.push({ p: dh, pos: 'DH' });
  return battingOrder(nine).map((x) => ({ playerId: x.p.id, pos: x.pos }));
}

/** 타순: 1번 출루+주력, 2번 컨택, 3번 최고 타자, 4번 파워, 5번 파워, 6~9 타격순 */
export function battingOrder<T extends { p: Player }>(nine: T[]): T[] {
  const rest = [...nine];
  const take = (score: (p: Player) => number): T | undefined => {
    if (!rest.length) return undefined;
    rest.sort((a, b) => score(b.p) - score(a.p));
    return rest.shift();
  };
  const cleanup = [...rest].sort((a, b) => batValue(b.p) - batValue(a.p)).slice(0, 3);
  const no3 = cleanup[0];
  const no4 = cleanup.filter((c) => c !== no3).sort((a, b) => b.p.r.power - a.p.r.power)[0];
  const no5 = cleanup.find((c) => c !== no3 && c !== no4);
  for (const c of [no3, no4, no5]) {
    const i = rest.indexOf(c!);
    if (i >= 0) rest.splice(i, 1);
  }
  const no1 = take((p) => p.r.speed * 0.5 + p.r.eye * 0.3 + p.r.contact * 0.4);
  const no2 = take((p) => p.r.contact * 0.7 + p.r.speed * 0.2);
  const tail: T[] = [];
  let t: T | undefined;
  while ((t = take(batValue))) tail.push(t);
  return [no1, no2, no3, no4, no5, ...tail].filter((x): x is T => !!x);
}

/** 선발 투수 결정: 휴식 규정을 지킨 투수 중 능력 최고 (로테이션이 있으면 우선) */
export function pickStarter(players: Player[], date: string, rotation?: string[]): Player | undefined {
  const ok = players.filter((p) => p.pos === 'P' && canPitchOn(p, date));
  if (rotation) {
    for (const id of rotation) {
      const p = ok.find((x) => x.id === id);
      if (p) return p;
    }
  }
  const sorted = ok.sort((a, b) => starterScore(b) - starterScore(a));
  if (sorted.length) return sorted[0];
  // 투수가 없으면 어깨 좋은 야수
  return players.filter((p) => canPitchOn(p, date)).sort((a, b) => b.r.arm - a.r.arm)[0];
}

export function starterScore(p: Player): number {
  return pitcherOverall(p.r) + p.r.stamina * 0.2 - p.fatigue * 0.2;
}

export function fielderScore(p: Player): number {
  return batterOverall(p.r, p.pos);
}
