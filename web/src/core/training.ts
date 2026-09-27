import { STYLE_INFO } from './abilities';
import { ABILITIES } from './abilities';
import { breakingScore, veloScore } from './player';
import { clamp, type Rng } from './rng';
import type { Card, CardKind, Focus, PitchType, Player, ProPlayer, StatKey } from './types';

// ─────────────────────────────────────────────────────────────
// 훈련 & 성장 (영관나인의 '연습 카드'를 단순화)
//  - 매주 월요일 손패(5장)에서 카드 1장을 골라 팀 연습을 한다.
//  - 카드 숫자(1~5)가 클수록 효과가 크다.
//  - 각 선수는 개인 연습 방침(focus)에 따라 추가 경험치를 얻는다.
// ─────────────────────────────────────────────────────────────

export const CARD_INFO: Record<CardKind, { name: string; desc: string; fatigue: number; batter: Partial<Record<StatKey, number>>; pitcher: Partial<Record<StatKey, number>> }> = {
  batting: { name: '타격 연습', desc: '컨택·파워·선구안', fatigue: 7, batter: { contact: 0.45, power: 0.4, eye: 0.2 }, pitcher: { contact: 0.1 } },
  pitching: { name: '투구 연습', desc: '구속·제구·변화구 (야수는 어깨)', fatigue: 7, batter: { arm: 0.35 }, pitcher: { velo: 0.3, control: 0.4, breaking: 0.3 } },
  defense: { name: '수비 연습', desc: '수비·어깨', fatigue: 7, batter: { fielding: 0.55, arm: 0.3 }, pitcher: { control: 0.15, fielding: 0.2 } },
  running: { name: '주루 연습', desc: '주력', fatigue: 8, batter: { speed: 0.7 }, pitcher: { stamina: 0.3 } },
  stamina: { name: '체력 훈련', desc: '스태미나·파워·주력', fatigue: 11, batter: { power: 0.25, speed: 0.2 }, pitcher: { stamina: 0.6, velo: 0.1 } },
  rest: { name: '휴식', desc: '피로 회복, 컨디션 상승', fatigue: -35, batter: {}, pitcher: {} },
  practiceGame: { name: '연습 경기', desc: '모든 능력 소폭 + 특수능력 각성 기회', fatigue: 9, batter: { contact: 0.2, power: 0.15, eye: 0.15, fielding: 0.15, speed: 0.1 }, pitcher: { control: 0.2, velo: 0.1, breaking: 0.15, stamina: 0.15 } },
  meeting: { name: '작전 미팅', desc: '선구안·제구 + 특수능력 습득 기회', fatigue: 2, batter: { eye: 0.35 }, pitcher: { control: 0.3 } },
  scout: { name: '스카우트 활동', desc: '스카우트 행동력 +2', fatigue: 3, batter: { contact: 0.1 }, pitcher: { control: 0.1 } },
  special: { name: '특별 훈련', desc: '개인 연습 방침 효과 2배, 부상 위험', fatigue: 20, batter: {}, pitcher: {} },
};

const DRAW_KINDS: CardKind[] = ['batting', 'pitching', 'defense', 'running', 'stamina', 'rest', 'practiceGame', 'meeting', 'scout', 'special'];
const DRAW_WEIGHTS = [16, 16, 14, 10, 10, 10, 8, 6, 6, 4];

export function drawCard(rng: Rng, id: string): Card {
  const kind = rng.weighted(DRAW_KINDS, DRAW_WEIGHTS);
  const value = rng.weighted([1, 2, 3, 4, 5], [20, 30, 28, 15, 7]);
  return { id, kind, value };
}

export const FOCUS_KO: Record<Focus, string> = {
  auto: '자동', contact: '컨택', power: '파워', eye: '선구안', speed: '주력', defense: '수비',
  velo: '구속', control: '제구', breaking: '변화구', stamina: '스태미나',
};

export const BATTER_FOCUS: Focus[] = ['auto', 'contact', 'power', 'eye', 'speed', 'defense'];
export const PITCHER_FOCUS: Focus[] = ['auto', 'velo', 'control', 'breaking', 'stamina'];

/** 개인 방침 → 능력치 배분 */
export function focusStats(p: Player): Partial<Record<StatKey, number>> {
  let f = p.focus;
  if (f === 'auto') f = autoFocus(p);
  if (f === 'defense') return { fielding: 0.6, arm: 0.4 };
  return { [f]: 1 } as Partial<Record<StatKey, number>>;
}

/** 자동 방침: 한계 대비 여유가 가장 큰 핵심 능력 */
export function autoFocus(p: Player): Focus {
  const opts: [Focus, StatKey][] = p.pos === 'P'
    ? [['velo', 'velo'], ['control', 'control'], ['breaking', 'breaking'], ['stamina', 'stamina']]
    : [['contact', 'contact'], ['power', 'power'], ['speed', 'speed'], ['defense', 'fielding'], ['eye', 'eye']];
  let best: Focus = opts[0][0];
  let bv = -Infinity;
  for (const [f, k] of opts) {
    const cur = k === 'velo' ? veloScore(p.r.velo) : k === 'breaking' ? breakingScore(p.r.pitches) : p.r[k as keyof Player['r']] as number;
    const cap = k === 'velo' ? veloScore(p.cap.velo) : p.cap[k];
    const room = cap - cur;
    const v = room - cur * 0.3;
    if (v > bv) { bv = v; best = f; }
  }
  return best;
}

export function growthMult(p: Player, k: StatKey, pros: ProPlayer[]): number {
  let m = 0.6 + p.talent * 0.18;
  if (p.personality === '노력파') m *= 1.15;
  else if (p.personality === '천재') m *= 1.08;
  else if (p.personality === '소심') m *= 0.95;
  if (p.fatigue > 70) m *= 0.7;
  m *= 1 + p.cond * 0.05;
  if (p.idolId) {
    const idol = pros.find((x) => x.id === p.idolId);
    if (idol && STYLE_INFO[idol.style].stats.includes(k)) m *= p.idolBond >= 50 ? 1.4 : 1.25;
  }
  return m;
}

/** 경험치 적용: 한계에 가까울수록 오르기 어렵다. 오른 수치 반환 */
export function applyExp(p: Player, k: StatKey, pts: number, mult: number, rng: Rng): number {
  if (pts <= 0) return 0;
  p.exp[k] = (p.exp[k] ?? 0) + pts * mult;
  let gained = 0;
  for (let guard = 0; guard < 20; guard++) {
    const e: number = p.exp[k] ?? 0;
    if (k === 'breaking') {
      const br = p.r.pitches.filter((x) => x.type !== 'FB');
      const minLv = br.length ? Math.min(...br.map((x) => x.lv)) : 0;
      const cost = 10 + minLv * 3;
      if (e < cost || breakingScore(p.r.pitches) >= p.cap.breaking) break;
      p.exp[k] = e - cost;
      // 새 구종 습득 or 기존 구종 강화
      if ((br.length < 2 || (br.length < 4 && rng.chance(0.15))) && p.pos === 'P') {
        const pool: PitchType[] = (['SL', 'CB', 'CH', 'FK', 'SI', 'CT'] as PitchType[]).filter((t) => !p.r.pitches.some((x) => x.type === t));
        if (pool.length) p.r.pitches.push({ type: rng.pick(pool), lv: 1 });
      } else if (br.length) {
        const target = br.filter((x) => x.lv < 7).sort((a, b) => a.lv - b.lv)[0];
        if (target) target.lv++;
      }
      gained++;
      continue;
    }
    if (k === 'velo') {
      if (p.r.velo >= p.cap.velo) break;
      const cost = 4 + ((p.r.velo - 110) / Math.max(1, p.cap.velo - 110)) ** 2 * 6;
      if (e < cost) break;
      p.exp[k] = e - cost;
      p.r.velo++;
      gained++;
      continue;
    }
    const cur = p.r[k] as number;
    if (cur >= p.cap[k]) break;
    const cost = 2.2 + (cur / Math.max(1, p.cap[k])) ** 2 * 4;
    if (e < cost) break;
    p.exp[k] = e - cost;
    (p.r[k] as number) = cur + 1;
    gained++;
  }
  // 한계에 도달한 경험치는 버린다 (무한 누적 방지)
  if ((p.exp[k] ?? 0) > 40) p.exp[k] = 40;
  return gained;
}

export interface TrainingReport {
  gains: Record<string, Partial<Record<StatKey, number>>>;
  injuries: string[];
  awakenings: { playerId: string; ability: string }[];
}

/** 한 주 훈련 적용 */
export function trainPlayer(p: Player, card: Card, pros: ProPlayer[], rng: Rng, report?: TrainingReport, cpu = false) {
  const info = CARD_INFO[card.kind];
  const isP = p.pos === 'P';
  const dist = isP ? info.pitcher : info.batter;
  const gains: Partial<Record<StatKey, number>> = {};
  const give = (k: StatKey, pts: number) => {
    const g = applyExp(p, k, pts, growthMult(p, k, pros), rng);
    if (g) gains[k] = (gains[k] ?? 0) + g;
  };
  if (p.injury > 0) {
    // 부상자는 재활만
    p.fatigue = clamp(p.fatigue - 15, 0, 100);
    return;
  }
  for (const [k, share] of Object.entries(dist) as [StatKey, number][]) give(k, card.value * share * 1.1);
  const focusMul = card.kind === 'special' ? 2.2 + card.value * 0.25 : card.kind === 'rest' ? 0.2 : 1;
  for (const [k, share] of Object.entries(focusStats(p)) as [StatKey, number][]) give(k, 1.3 * share * focusMul);

  p.fatigue = clamp(p.fatigue + info.fatigue * (card.kind === 'rest' ? 1 : 0.6 + card.value * 0.12), 0, 100);
  if (card.kind === 'rest' && rng.chance(0.5 + card.value * 0.08)) p.cond = clamp(p.cond + 1, -2, 2);

  // 부상
  const risk = Math.max(0, p.fatigue - 60) * 0.004 + (card.kind === 'special' ? 0.01 : 0);
  if (!cpu && rng.chance(risk)) {
    p.injury = rng.int(5, 25);
    report?.injuries.push(p.id);
  }
  // 특수능력 각성
  const awakenP = card.kind === 'practiceGame' ? 0.02 + card.value * 0.004 : card.kind === 'meeting' ? 0.03 + card.value * 0.006 : 0;
  if (awakenP && rng.chance(awakenP * (0.6 + p.talent * 0.15))) {
    const pool = ABILITIES.filter((a) => a.good && a.forPitcher === isP && !p.abilities.includes(a.id));
    if (pool.length) {
      const a = rng.pick(pool);
      p.abilities.push(a.id);
      report?.awakenings.push({ playerId: p.id, ability: a.id });
    }
  }
  if (report && Object.keys(gains).length) report.gains[p.id] = gains;
}

/** 주간 컨디션 변동 */
export function weeklyCondition(p: Player, rng: Rng) {
  const vol = p.personality === '열혈' ? 0.45 : p.personality === '냉정' ? 0.2 : 0.32;
  if (rng.chance(vol)) p.cond = clamp(p.cond + (rng.chance(0.5) ? 1 : -1), -2, 2);
  else if (p.cond !== 0 && rng.chance(0.3)) p.cond += p.cond > 0 ? -1 : 1;
}
