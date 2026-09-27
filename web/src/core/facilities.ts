import data from '../../../game/data/facilities.json';
import type { GameState, StatKey } from './types';

// 학교 시설과 예산 (원본 데이터: game/data/facilities.json, 금액 단위 만원)
//  - 매월 1일 후원회 지원금 (기본 + 명성 비례)
//  - 전국대회 성적 상금, 프로 지명 시 OB 기부금
//  - 시설 레벨(0~3)에 따라 주간 훈련 성장 배율·부상 위험·스카우트 등이 좋아진다

export interface FacilityDef {
  key: string;
  name: string;
  desc: string;
  stats: string[];
  growth: number;
  costs: number[];
}

export const FACILITIES = data.facilities as FacilityDef[];
export const FAC_DATA = data;

export type FacLevels = Record<string, number>;

export function facLevel(fac: FacLevels | undefined, key: string): number {
  return fac?.[key] ?? 0;
}

/** 주간 훈련 성장 배율 */
export function facilityGrowth(fac: FacLevels | undefined, k: StatKey): number {
  if (!fac) return 1;
  let m = 1;
  for (const f of FACILITIES) if (f.stats.includes(k)) m += f.growth * facLevel(fac, f.key);
  return m;
}

export function upgradeCost(state: GameState, key: string): number | null {
  const f = FACILITIES.find((x) => x.key === key);
  if (!f) return null;
  const lv = facLevel(state.facilities, key);
  return lv >= f.costs.length ? null : f.costs[lv];
}

export function upgradeFacility(state: GameState, key: string): boolean {
  const cost = upgradeCost(state, key);
  if (cost === null || (state.budget ?? 0) < cost) return false;
  state.budget = (state.budget ?? 0) - cost;
  state.facilities = { ...(state.facilities ?? {}), [key]: facLevel(state.facilities, key) + 1 };
  const f = FACILITIES.find((x) => x.key === key)!;
  state.news.push({ date: state.date, kind: 'good', text: `${f.name} Lv${state.facilities[key]} 완공! (-${cost}만원)` });
  return true;
}

export function monthlyIncome(state: GameState) {
  const amt = Math.round(data.monthlyBase + state.reputation * data.monthlyPerReputation);
  state.budget = (state.budget ?? 0) + amt;
  state.news.push({ date: state.date, kind: 'info', text: `후원회 지원금 +${amt}만원 (예산 ${state.budget}만원)` });
}

export function addPrize(state: GameState, result: string, label: string) {
  const amt = (data.prizes as Record<string, number>)[result];
  if (!amt) return;
  state.budget = (state.budget ?? 0) + amt;
  state.news.push({ date: state.date, kind: 'good', text: `${label} ${result} 격려금 +${amt}만원` });
}
