import { ABILITIES, STYLE_INFO } from './abilities';
import { middleSchoolName, pickGiven, pickSurname } from './names';
import { clamp, type Rng } from './rng';
import type {
  BatLine, Personality, PitchSkill, PitchType, PitLine, Player, Pos, ProPlayer, Ratings, StatKey,
} from './types';

export const POS_KO: Record<Pos, string> = {
  P: '투수', C: '포수', '1B': '1루수', '2B': '2루수', '3B': '3루수', SS: '유격수', LF: '좌익수', CF: '중견수', RF: '우익수',
};
export const POS_SHORT: Record<Pos, string> = {
  P: '투', C: '포', '1B': '1', '2B': '2', '3B': '3', SS: '유', LF: '좌', CF: '중', RF: '우',
};
export const PITCH_KO: Record<PitchType, string> = {
  FB: '직구', SL: '슬라이더', CB: '커브', CH: '체인지업', FK: '포크', SI: '투심', CT: '커터',
};
export const STAT_KO: Record<StatKey, string> = {
  contact: '컨택', power: '파워', eye: '선구안', speed: '주력', arm: '어깨', fielding: '수비',
  velo: '구속', control: '제구', stamina: '스태미나', breaking: '변화구',
};
export const COND_KO = ['절불조', '불조', '보통', '호조', '절호조'];

export function emptyBat(): BatLine {
  return { g: 0, pa: 0, ab: 0, h: 0, d2: 0, d3: 0, hr: 0, rbi: 0, r: 0, bb: 0, so: 0, sb: 0, cs: 0, sh: 0, sf: 0, e: 0 };
}
export function emptyPit(): PitLine {
  return { g: 0, gs: 0, outs: 0, h: 0, r: 0, er: 0, bb: 0, so: 0, hr: 0, w: 0, l: 0, np: 0 };
}
export function addBat(a: BatLine, b: BatLine) {
  for (const k of Object.keys(a) as (keyof BatLine)[]) a[k] += b[k];
}
export function addPit(a: PitLine, b: PitLine) {
  for (const k of Object.keys(a) as (keyof PitLine)[]) a[k] += b[k];
}

export function grade(p: Player, year: number): number {
  return year - p.enrollYear + 1;
}

export function name(p: { sur: string; given: string }): string {
  return p.sur + p.given;
}

export function isPitcher(p: Player): boolean {
  return p.pos === 'P';
}

/** 능력치 → 등급 문자 */
export function letter(v: number): string {
  if (v >= 90) return 'S';
  if (v >= 80) return 'A';
  if (v >= 70) return 'B';
  if (v >= 60) return 'C';
  if (v >= 50) return 'D';
  if (v >= 40) return 'E';
  if (v >= 20) return 'F';
  return 'G';
}

export function letterClass(v: number): string {
  return 'g-' + letter(v);
}

/** 구속을 1~100 스케일로 */
export function veloScore(kmh: number): number {
  return clamp((kmh - 110) * 2, 1, 100);
}

export function breakingScore(pitches: PitchSkill[]): number {
  const b = pitches.filter((p) => p.type !== 'FB');
  if (b.length === 0) return 5;
  const total = b.reduce((s, p) => s + p.lv, 0);
  const best = Math.max(...b.map((p) => p.lv));
  return clamp(best * 8 + total * 4 + 8, 1, 100);
}

export function statValue(r: Ratings, k: StatKey): number {
  if (k === 'velo') return veloScore(r.velo);
  if (k === 'breaking') return breakingScore(r.pitches);
  return r[k];
}

export function pitcherOverall(r: Ratings): number {
  return Math.round(veloScore(r.velo) * 0.3 + r.control * 0.3 + r.stamina * 0.15 + breakingScore(r.pitches) * 0.25);
}

const DEF_WEIGHT: Record<Pos, number> = { P: 0.1, C: 0.4, '1B': 0.12, '2B': 0.32, '3B': 0.25, SS: 0.38, LF: 0.15, CF: 0.3, RF: 0.18 };

export function batterOverall(r: Ratings, pos: Pos): number {
  const bat = r.contact * 0.36 + r.power * 0.32 + r.eye * 0.14 + r.speed * 0.18;
  const def = r.fielding * 0.6 + r.arm * 0.4;
  const w = DEF_WEIGHT[pos];
  return Math.round(bat * (1 - w) + def * w);
}

export function overall(p: Player): number {
  return isPitcher(p) ? pitcherOverall(p.r) : batterOverall(p.r, p.pos);
}

/** 해당 포지션 적성 (1.0 = 주 포지션) */
export function posAptitude(p: Player, pos: Pos): number {
  if (p.pos === pos) return 1;
  if (p.sub.includes(pos)) return 0.85;
  if (pos === 'P') return 0.3;
  if (p.pos === 'P') return 0.55;
  const inf: Pos[] = ['1B', '2B', '3B', 'SS'];
  const of: Pos[] = ['LF', 'CF', 'RF'];
  if (pos === '1B') return 0.8;
  if (inf.includes(pos) && inf.includes(p.pos)) return 0.7;
  if (of.includes(pos) && of.includes(p.pos)) return 0.8;
  if (pos === 'C') return 0.4;
  return 0.55;
}

// ─────────────────────────────────────────────────────────────
// 선수 생성
// ─────────────────────────────────────────────────────────────

const PERSONALITIES: Personality[] = ['열혈', '냉정', '노력파', '천재', '낙천', '소심'];

export interface GenOpts {
  id: string;
  teamId: string;
  enrollYear: number;
  /** 현재 시즌 연도 (학년 반영 능력치 결정) */
  year: number;
  /** 0~100 선수 품질 기준 */
  quality: number;
  pos?: Pos;
  province: string;
  pros?: ProPlayer[];
  /** 동경 선수 부여 확률 */
  idolChance?: number;
}

function genPitches(rng: Rng, skill: number): PitchSkill[] {
  const list: PitchSkill[] = [{ type: 'FB', lv: 0 }];
  const pool: PitchType[] = ['SL', 'CB', 'CH', 'FK', 'SI', 'CT'];
  const weights = [30, 25, 15, 10, 10, 10];
  const n = skill > 60 ? rng.int(2, 3) : skill > 35 ? rng.int(1, 2) : 1;
  for (let i = 0; i < n; i++) {
    const t = rng.weighted(pool, weights);
    if (list.some((p) => p.type === t)) continue;
    list.push({ type: t, lv: clamp(Math.round(1 + skill / 25 + rng.gauss() * 0.8), 1, 5) });
  }
  return list;
}

const POS_POOL: Pos[] = ['P', 'P', 'P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];

export function genPlayer(rng: Rng, o: GenOpts): Player {
  const gradeNow = o.year - o.enrollYear + 1; // 0 = 입학 예정 중학생
  const pos: Pos = o.pos ?? rng.pick(POS_POOL);
  const talent = clamp(Math.round(1 + (o.quality / 100) * 2.2 + rng.gauss() * 0.9 + (rng.chance(0.04) ? 1.5 : 0)), 1, 5);
  // 현재 능력 기준치: 품질 + 학년 보정
  const base = 22 + o.quality * 0.22 + Math.max(0, gradeNow - 1) * 7 + (talent - 3) * 3;
  const g = (spread = 9) => clamp(Math.round(base + rng.gauss() * spread), 5, 92);

  const r: Ratings = {
    contact: g(), power: g(11), eye: g(), speed: g(12), arm: g(), fielding: g(),
    velo: 0, control: 0, stamina: 0, pitches: [],
  };
  if (pos === 'P') {
    r.velo = clamp(Math.round(120 + (base - 22) * 0.45 + rng.gauss() * 5), 110, 152);
    r.control = g();
    r.stamina = g(12);
    r.pitches = genPitches(rng, g());
    // 투수의 타격은 약하다
    r.contact = clamp(r.contact - 15, 5, 80);
    r.power = clamp(r.power - 10, 5, 80);
  } else {
    r.velo = clamp(Math.round(112 + (base - 22) * 0.3 + rng.gauss() * 4), 105, 140);
    r.control = clamp(g() - 20, 5, 60);
    r.stamina = clamp(g() - 15, 5, 60);
    r.pitches = [{ type: 'FB', lv: 0 }];
    if (pos === 'C') { r.arm += 5; r.fielding += 3; }
    if (pos === 'SS' || pos === '2B' || pos === 'CF') { r.fielding += 4; r.speed += 4; }
    if (pos === '1B' || pos === 'LF') { r.power += 5; r.fielding -= 4; }
    if (pos === 'RF') r.arm += 5;
    r.arm = clamp(r.arm, 5, 95);
    r.fielding = clamp(r.fielding, 5, 95);
    r.speed = clamp(r.speed, 5, 95);
    r.power = clamp(r.power, 5, 95);
  }

  // 잠재 한계: 재능이 높을수록 높다
  const capOf = (cur: number) => clamp(Math.round(cur + 12 + talent * 7 + rng.int(-4, 10)), cur + 5, 99);
  const cap: Record<StatKey, number> = {
    contact: capOf(r.contact), power: capOf(r.power), eye: capOf(r.eye), speed: clamp(r.speed + rng.int(3, 12) + talent * 2, r.speed + 3, 99),
    arm: capOf(r.arm), fielding: capOf(r.fielding),
    velo: pos === 'P' ? clamp(r.velo + 6 + talent * 3 + rng.int(-2, 6), r.velo + 3, 158) : clamp(r.velo + 8, r.velo, 142),
    control: capOf(r.control), stamina: capOf(r.stamina), breaking: clamp(breakingScore(r.pitches) + 15 + talent * 6, 20, 99),
  };

  const bats: Player['bats'] = rng.chance(0.03) ? 'S' : rng.chance(pos === 'P' ? 0.22 : 0.33) ? 'L' : 'R';
  const throws: Player['throws'] = pos === 'P' ? (rng.chance(0.28) ? 'L' : 'R') : ['C', '2B', '3B', 'SS'].includes(pos) ? 'R' : rng.chance(0.2) ? 'L' : 'R';

  const sub: Pos[] = [];
  if (pos !== 'P' && rng.chance(0.45)) {
    const cand: Pos[] = pos === 'SS' || pos === '2B' || pos === '3B' ? ['2B', '3B', 'SS', '1B'] : pos === 'C' ? ['1B', '3B'] : ['LF', 'CF', 'RF', '1B'];
    const s = rng.pick(cand.filter((c) => c !== pos));
    sub.push(s);
  }
  if (pos === 'P' && rng.chance(0.15)) sub.push(rng.pick<Pos>(['1B', 'RF', 'LF']));

  const p: Player = {
    id: o.id,
    sur: pickSurname(rng),
    given: pickGiven(rng),
    teamId: o.teamId,
    enrollYear: o.enrollYear,
    pos,
    sub,
    bats,
    throws,
    r,
    talent,
    cap,
    exp: {},
    abilities: [],
    personality: rng.pick(PERSONALITIES),
    hometown: o.province,
    focus: 'auto',
    idolBond: 0,
    cond: 0,
    fatigue: 0,
    injury: 0,
    season: { bat: emptyBat(), pit: emptyPit() },
    career: { bat: emptyBat(), pit: emptyPit() },
    faceSeed: rng.int(1, 2 ** 30),
    middleSchool: middleSchoolName(rng),
  };

  // 특수능력 부여
  const abilityPool = ABILITIES.filter((a) => a.forPitcher === (pos === 'P'));
  const nAb = rng.chance(0.25 + talent * 0.08) ? (rng.chance(0.25) ? 2 : 1) : 0;
  for (let i = 0; i < nAb; i++) {
    const a = rng.pick(abilityPool);
    if (!a.good && rng.chance(0.5)) continue;
    if (!p.abilities.includes(a.id)) p.abilities.push(a.id);
  }

  // 동경하는 프로 선수: 이름이 같고 성이 다른 선수
  if (o.pros && o.pros.length && rng.chance(o.idolChance ?? 0.22)) {
    assignIdol(rng, p, o.pros);
  }
  return p;
}

/** 포지션 성향이 맞는 프로 선수를 골라 동경 관계를 만든다. 이름을 프로 선수와 같게 바꾼다. */
export function assignIdol(rng: Rng, p: Player, pros: ProPlayer[]) {
  const active = pros.filter((x) => !x.retired);
  const matching = active.filter((x) => STYLE_INFO[x.style].pitcher === (p.pos === 'P'));
  const pool = matching.length ? matching : active;
  if (!pool.length) return;
  const idol = rng.pick(pool);
  p.idolId = idol.id;
  p.given = idol.given;
  if (p.sur === idol.sur) p.sur = pickSurname(rng, idol.sur);
  p.idolBond = rng.int(20, 45);
}

// ─────────────────────────────────────────────────────────────
// 기록 표시
// ─────────────────────────────────────────────────────────────

export function avg(b: BatLine): string {
  if (b.ab === 0) return '-.---';
  return (b.h / b.ab).toFixed(3).replace(/^0/, '');
}

export function ops(b: BatLine): string {
  if (b.pa === 0) return '-';
  const obp = (b.h + b.bb) / Math.max(1, b.ab + b.bb + b.sf);
  const tb = b.h + b.d2 + b.d3 * 2 + b.hr * 3;
  const slg = tb / Math.max(1, b.ab);
  return (obp + slg).toFixed(3);
}

export function era(p: PitLine): string {
  if (p.outs === 0) return p.er > 0 ? '∞' : '-.--';
  return ((p.er * 27) / p.outs).toFixed(2);
}

export function ipStr(outs: number): string {
  const i = Math.floor(outs / 3);
  const f = outs % 3;
  return f ? `${i} ${f}/3` : `${i}`;
}
