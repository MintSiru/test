import { addDays, monthOf } from './calendar';
import { hashStr } from './rng';
import type { Competition, Fixture, GameState } from './types';

// 날씨: 날짜와 시드로 정해진다 (다시 불러와도 같다). 장마철(6~7월)에 비가 잦다.
// 비가 오면 그날 경기는 다음 날로 연기 (같은 경기는 최대 2번까지 연기, 그 뒤엔 강행)

export type Weather = '맑음' | '흐림' | '가랑비' | '비';

const RAIN: Record<number, number> = { 1: 0.04, 2: 0.04, 3: 0.06, 4: 0.08, 5: 0.08, 6: 0.15, 7: 0.2, 8: 0.14, 9: 0.08, 10: 0.05, 11: 0.05, 12: 0.04 };

/** 해시 섞기 (MurmurHash3 fmix32). FNV 만 쓰면 이웃한 날짜의 값이 거의 같아 비가 며칠씩 이어졌다 */
export function mix32(h: number): number {
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h >>> 0;
}

export function weatherOn(seed: number, date: string): Weather {
  const h = mix32(hashStr(`${seed}:${date}`)) / 4294967296;
  const rain = RAIN[monthOf(date)] ?? 0.08;
  if (h < rain) return '비';
  if (h < rain + 0.07) return '가랑비';
  if (h < rain + 0.3) return '흐림';
  return '맑음';
}

/** 우천 연기. 연기한 경기가 있으면 true */
export function postponeRain(state: GameState, today: { comp: Competition; f: Fixture }[]): boolean {
  if (!today.length || weatherOn(state.seed, state.date) !== '비') return false;
  let moved = 0;
  let userMoved = false;
  for (const { f } of today) {
    if ((f.postponed ?? 0) >= 2) continue;
    f.postponed = (f.postponed ?? 0) + 1;
    f.date = addDays(f.date, 1);
    moved++;
    if (f.home === state.userTeamId || f.away === state.userTeamId) userMoved = true;
  }
  if (userMoved) {
    state.news.push({ date: state.date, kind: userMoved ? 'bad' : 'info', text: `비로 우리 경기가 내일로 순연됐다. 투수진이 하루 더 쉴 수 있다.` });
  }
  return moved > 0;
}
