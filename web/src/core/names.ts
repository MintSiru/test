import type { Rng } from './rng';
import names from '../../../game/data/names.json';

// 이름 데이터 원본: game/data/names.json
export const SURNAMES = names.surnames as [string, number][];
export const GIVEN_NAMES: string[] = names.given;
const MIDDLE_PREFIX: string[] = names.middlePrefix;

export function pickSurname(rng: Rng, exclude?: string): string {
  for (;;) {
    const s = rng.weighted(
      SURNAMES.map((x) => x[0]),
      SURNAMES.map((x) => x[1]),
    );
    if (s !== exclude) return s;
  }
}

export function pickGiven(rng: Rng): string {
  return rng.pick(GIVEN_NAMES);
}

export function middleSchoolName(rng: Rng): string {
  return rng.pick(MIDDLE_PREFIX) + '중';
}

export function fullName(p: { sur: string; given: string }): string {
  return p.sur + p.given;
}

/** 한국어 조사 자동 선택: josa('민준', '은/는') → '민준은' */
export function josa(word: string, pair: '은/는' | '이/가' | '을/를' | '과/와' | '이/' | '으로/로' | '에게'): string {
  if (pair === '에게') return word + '에게';
  const code = word.charCodeAt(word.length - 1) - 0xac00;
  const has = code >= 0 && code <= 11171 && code % 28 !== 0;
  const [a, b] = pair.split('/');
  if (pair === '으로/로') return word + (has && code % 28 !== 8 ? a : b);
  return word + (has ? a : b);
}
