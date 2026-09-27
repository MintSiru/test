import { addDays, monthOf } from './calendar';
import { hashStr } from './rng';
import type { Competition, Fixture, GameState } from './types';

// 날씨: 날짜와 시드로 정해진다 (다시 불러와도 같다). 장마철(6~7월)에 비가 잦다.
// 비가 오면 그날 경기는 다음 날로 연기 (같은 경기는 최대 2번까지 연기, 그 뒤엔 강행)

export type Weather = '맑음' | '흐림' | '가랑비' | '비';

const RAIN: Record<number, number> = { 1: 0.05, 2: 0.05, 3: 0.08, 4: 0.1, 5: 0.1, 6: 0.2, 7: 0.28, 8: 0.18, 9: 0.1, 10: 0.07, 11: 0.07, 12: 0.05 };

export function weatherOn(seed: number, date: string): Weather {
  const h = hashStr(`${seed}:${date}`) / 4294967296;
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
  if (moved) {
    state.news.push({ date: state.date, kind: userMoved ? 'bad' : 'info', text: `비로 오늘 경기 ${moved}개가 내일로 연기됐다.${userMoved ? ' 우리 경기도 순연! 투수진이 하루 더 쉴 수 있다.' : ''}` });
  }
  return moved > 0;
}
