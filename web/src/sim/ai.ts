import type { Match } from './engine';
import type { OffOrder, Orders, PitchOrder, ShiftOrder, SideState, SimPlayer } from './types';

// CPU 감독 AI. 사용자 팀이 '위임' 상태일 때도 이 로직을 쓴다.

const paCache = new WeakMap<Match, { key: string; off: OffOrder; pitch: PitchOrder; shift: ShiftOrder }>();

function paKey(m: Match): string {
  return `${m.inning}${m.top}${m.off.batterIdx}${m.outs}${m.bases.map((b) => (b ? 1 : 0)).join('')}`;
}

function hitterScore(p: SimPlayer): number {
  return p.con + p.pow;
}

function decidePA(m: Match) {
  const key = paKey(m);
  const cached = paCache.get(m);
  if (cached && cached.key === key) return cached;
  const rng = m.rng;
  const b = m.batter();
  const offSide = m.off;
  const diff = m.scoreDiffFor(offSide);
  const late = m.inning >= 7;
  const close = diff >= -2 && diff <= 1;
  const [r1, r2, r3] = m.bases;
  let off: OffOrder = 'normal';
  const weak = hitterScore(b) < 105 && ![2, 3, 4].includes(offSide.batterIdx);
  if (!r3 && (r1 || r2) && m.outs === 0 && (weak || (late && close)) && rng.chance(0.35)) off = 'bunt';
  else if (r3 && m.outs < 2 && late && close && weak && rng.chance(0.2)) off = 'squeeze';
  else if (r1 && !r2 && m.outs < 2 && rng.chance(Math.max(0, (offSide.byId[r1.id].spd - 52) * 0.02))) off = 'steal';
  else if (r1 && !r2 && m.outs < 2 && hitterScore(b) > 100 && rng.chance(0.04)) off = 'hitRun';

  let pitch: PitchOrder = 'normal';
  let shift: ShiftOrder = 'normal';
  const defDiff = -diff;
  if (!r1 && (r2 || r3) && late && defDiff >= 0 && defDiff <= 1 && hitterScore(b) >= 145) {
    const next = offSide.byId[offSide.order[(offSide.batterIdx + 1) % 9]];
    if (hitterScore(next) < hitterScore(b) - 25 && rng.chance(0.5)) pitch = 'ibb';
  }
  if (r3 && m.outs < 2 && late && defDiff >= -1 && defDiff <= 2) shift = 'infieldIn';
  else if (r1 && !r3 && m.outs === 0 && weak && rng.chance(0.5)) shift = 'buntShift';
  else if (hitterScore(b) > 150 && rng.chance(0.3)) shift = 'deep';
  const res = { key, off, pitch, shift };
  paCache.set(m, res);
  return res;
}

export function aiOffense(m: Match): OffOrder {
  const d = decidePA(m);
  if (m.balls === 3 && m.strikes === 0 && d.off === 'normal') return 'wait';
  // 투 스트라이크 이후 번트는 거둔다 (스리번트는 드물게)
  if ((d.off === 'bunt' || d.off === 'squeeze') && m.strikes === 2) return 'normal';
  return d.off;
}

export function aiDefense(m: Match): { pitch: PitchOrder; shift: ShiftOrder } {
  const d = decidePA(m);
  return { pitch: m.balls === 0 && m.strikes === 0 ? d.pitch : d.pitch === 'ibb' ? 'normal' : d.pitch, shift: d.shift };
}

/** 구원 투수 후보 (사용하지 않았고 등판 가능한 투수, 능력순) */
export function relievers(side: SideState): SimPlayer[] {
  return side.input.players
    .filter((p) => !side.used.includes(p.id) && p.canPitch)
    .sort((a, b) => relieverScore(b) - relieverScore(a));
}

function relieverScore(p: SimPlayer): number {
  return (p.pos === 'P' ? 100 : 0) + (p.velo - 110) * 1.5 + p.ctl + p.stuff * 0.6;
}

/** 타석 시작 시 수비측 투수 교체 판단. 교체했으면 true */
export function aiPitchingChange(m: Match, side: SideState): boolean {
  if (m.balls !== 0 || m.strikes !== 0) return false;
  const p = side.byId[side.pitcherId];
  const np = side.pitchCount[p.id] ?? 0;
  const eff = m.pitcherEff(p, side);
  const runs = side.box[p.id].pit.r;
  const mustChange = np >= m.rules.pitchLimit;
  const tired = eff.tired > 10 + m.rng.next() * 10;
  const shelled = runs >= 6 && m.inning <= 7;
  if (!mustChange && !tired && !shelled) return false;
  const pen = relievers(side);
  const cand = pen.find((x) => x.pos === 'P') ?? (mustChange ? pen[0] : undefined);
  if (!cand) return false;
  m.changePitcher(side, cand.id);
  return true;
}

/** 한 투구에 들어갈 CPU 지시 */
export function aiOrders(m: Match): Orders {
  const d = aiDefense(m);
  return { off: aiOffense(m), pitch: d.pitch, shift: d.shift };
}

/** 양 팀 모두 AI 로 경기 끝까지 진행 */
export function playOut(m: Match): void {
  let guard = 0;
  while (!m.over && guard++ < 5000) {
    aiPitchingChange(m, m.def);
    m.step(aiOrders(m));
  }
}
