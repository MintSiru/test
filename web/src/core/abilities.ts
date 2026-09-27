import type { Player, Pos, ProStyle, StatKey } from './types';
import abilityData from '../../../game/data/abilities.json';

// 원본 데이터: game/data/abilities.json
//  - tier: gold(금특·상위 능력) / good(긍정·파랑) / bad(부정·빨강)
//  - for: bat(타자) / pit(투수) / all(공통)
//  - 같은 group 안에서는 하나만 가진다 (good 을 얻으면 bad 가 사라지고, gold 는 good 을 대체)
//  - fx: 경기 효과 (when 조건 + 수치). 구현은 sim/engine.ts
//  - season: 훈련 성장(growth)·부상(injury)·피로 회복(recover)·컨디션 기복(mood)

export type Tier = 'gold' | 'good' | 'bad';
export type AbilityFor = 'bat' | 'pit' | 'all';

export interface AbilityFx {
  when?: string;
  [k: string]: number | string | undefined;
}

export interface AbilityDef {
  id: string;
  name: string;
  desc: string;
  tier: Tier;
  good: boolean;
  for: AbilityFor;
  group: string;
  fx?: AbilityFx[];
  season?: Record<string, number>;
  upgrade?: string;
  pos?: Pos[];
}

export const ABILITIES = abilityData.abilities as unknown as AbilityDef[];
export const ABILITY_CONDITIONS = abilityData.conditions as Record<string, string>;
const BY_ID: Record<string, AbilityDef> = Object.fromEntries(ABILITIES.map((a) => [a.id, a]));

export function abilityName(id: string): string {
  return BY_ID[id]?.name ?? id;
}

export function abilityDef(id: string): AbilityDef | undefined {
  return BY_ID[id];
}

export function isBad(id: string): boolean {
  return BY_ID[id]?.tier === 'bad';
}

/** 이 선수(타자/투수, 포지션)가 가질 수 있는 능력인가 */
export function fitsPlayer(a: AbilityDef, p: Pick<Player, 'pos' | 'sub'>): boolean {
  if (a.for !== 'all' && (a.for === 'pit') !== (p.pos === 'P')) return false;
  if (a.pos && !a.pos.includes(p.pos) && !p.sub.some((s) => a.pos!.includes(s))) return false;
  return true;
}

/** 새로 익힐 수 없으면 이유, 익힐 수 있으면 null */
export function cannotLearn(p: Pick<Player, 'pos' | 'sub' | 'abilities'>, id: string): string | null {
  const a = BY_ID[id];
  if (!a) return '알 수 없는 능력';
  if (a.for !== 'all' && (a.for === 'pit') !== (p.pos === 'P')) return a.for === 'pit' ? '투수 전용' : '타자 전용';
  if (p.abilities.includes(id)) return '이미 가지고 있음';
  const rank = { bad: 0, good: 1, gold: 2 };
  for (const x of p.abilities) {
    const o = BY_ID[x];
    if (o && o.group === a.group && rank[o.tier] >= rank[a.tier]) return o.tier === 'gold' ? '상위 능력을 가지고 있음' : '이미 가지고 있음';
  }
  return null;
}

/** 능력 습득: 같은 그룹의 하위 능력(부정 능력 포함)은 사라진다. 사라진 능력 id 목록 반환 */
export function learnAbility(p: Pick<Player, 'abilities'>, id: string): string[] {
  const a = BY_ID[id];
  if (!a || p.abilities.includes(id)) return [];
  const removed = p.abilities.filter((x) => BY_ID[x]?.group === a.group);
  p.abilities = p.abilities.filter((x) => BY_ID[x]?.group !== a.group);
  p.abilities.push(id);
  return removed;
}

/** 상위(금특) 능력 */
export function goldOf(id: string): string | undefined {
  return BY_ID[id]?.upgrade;
}

/** 시즌 효과 합계 (growth, injury, recover, mood) */
export function seasonFx(p: Pick<Player, 'abilities'>, key: string): number {
  let v = 0;
  for (const id of p.abilities) v += BY_ID[id]?.season?.[key] ?? 0;
  return v;
}

/** 정렬: 금특 → 긍정 → 부정 */
export function sortAbilities(ids: string[]): string[] {
  const rank = { gold: 0, good: 1, bad: 2 };
  return [...ids].sort((a, b) => rank[BY_ID[a]?.tier ?? 'good'] - rank[BY_ID[b]?.tier ?? 'good']);
}

// ───────────── 경기용으로 미리 정리한 효과 ─────────────

export interface FxEntry {
  c: string;
  m: Record<string, number>;
}

/** 조건 없이 항상 적용되는 수비·주루 효과 */
export const FLAT_KEYS = ['fld', 'arm', 'err', 'lead', 'block', 'steal', 'run'] as const;
export type FlatKey = (typeof FLAT_KEYS)[number];
const PIT_KEYS = new Set(['velo', 'ctl', 'stuff', 'ppFB', 'ppBR', 'whiff', 'wild', 'sta', 'gbRate', 'hrAllow', 'hold', 'zone', 'mistake']);

export interface CompiledFx {
  bat: FxEntry[];
  pit: FxEntry[];
  flat: Record<FlatKey, number>;
}

export function compileFx(ids: string[]): CompiledFx {
  const out: CompiledFx = { bat: [], pit: [], flat: { fld: 0, arm: 0, err: 0, lead: 0, block: 0, steal: 0, run: 0 } };
  for (const id of ids) {
    for (const fx of BY_ID[id]?.fx ?? []) {
      const bat: Record<string, number> = {};
      const pit: Record<string, number> = {};
      for (const [k, v] of Object.entries(fx)) {
        if (k === 'when' || typeof v !== 'number') continue;
        if ((FLAT_KEYS as readonly string[]).includes(k)) out.flat[k as FlatKey] += v;
        else if (PIT_KEYS.has(k)) pit[k] = v;
        else bat[k] = v;
      }
      const c = fx.when ?? 'always';
      if (Object.keys(bat).length) out.bat.push({ c, m: bat });
      if (Object.keys(pit).length) out.pit.push({ c, m: pit });
    }
  }
  return out;
}

// 동경하는 프로 선수의 스타일 → 성장 보너스 능력치 / 전수 가능한 대표 특수능력
export const STYLE_INFO = abilityData.styles as Record<ProStyle, { stats: StatKey[]; ability: string; pitcher: boolean; desc: string }>;
