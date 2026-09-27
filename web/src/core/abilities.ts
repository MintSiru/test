import type { ProStyle, StatKey } from './types';
import abilityData from '../../../game/data/abilities.json';

// 원본 데이터: game/data/abilities.json (효과 구현은 sim/engine.ts)

// 특수능력 정의. 효과는 sim/engine.ts 에서 id 로 참조한다.
export interface AbilityDef {
  id: string;
  name: string;
  desc: string;
  good: boolean;
  forPitcher: boolean;
}

export const ABILITIES = abilityData.abilities as AbilityDef[];

export function abilityName(id: string): string {
  return ABILITIES.find((a) => a.id === id)?.name ?? id;
}

export function abilityDef(id: string): AbilityDef | undefined {
  return ABILITIES.find((a) => a.id === id);
}

// 동경하는 프로 선수의 스타일 → 성장 보너스 능력치 / 전수 가능한 대표 특수능력
export const STYLE_INFO = abilityData.styles as Record<ProStyle, { stats: StatKey[]; ability: string; pitcher: boolean; desc: string }>;
