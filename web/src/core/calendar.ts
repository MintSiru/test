import type { CompDef } from './types';
import schedule from '../../../game/data/schedule.json';

// ─────────────────────────────────────────────────────────────
// 날짜 유틸 (모든 날짜는 'YYYY-MM-DD' 문자열, UTC 기준으로 계산)
// ─────────────────────────────────────────────────────────────

export function toDate(s: string): Date {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

export function fmt(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function addDays(s: string, n: number): string {
  const d = toDate(s);
  d.setUTCDate(d.getUTCDate() + n);
  return fmt(d);
}

export function diffDays(a: string, b: string): number {
  return Math.round((toDate(b).getTime() - toDate(a).getTime()) / 86400000);
}

/** 0=일 ... 6=토 */
export function weekday(s: string): number {
  return toDate(s).getUTCDay();
}

export const WEEKDAY_KO = ['일', '월', '화', '수', '목', '금', '토'];

export function prettyDate(s: string, withYear = false): string {
  const d = toDate(s);
  const base = `${d.getUTCMonth() + 1}월 ${d.getUTCDate()}일 (${WEEKDAY_KO[d.getUTCDay()]})`;
  return withYear ? `${d.getUTCFullYear()}년 ${base}` : base;
}

export function monthOf(s: string): number {
  return toDate(s).getUTCMonth() + 1;
}

/** 시즌 연도(3월 시작)의 MM-DD → 실제 날짜. 1~2월은 다음 해로 넘어간다. */
export function seasonDate(year: number, mmdd: string): string {
  const m = Number(mmdd.slice(0, 2));
  const y = m <= 2 ? year + 1 : year;
  return `${y}-${mmdd}`;
}

/**
 * 기준 연도(2026)의 날짜를 다른 연도로 옮길 때 같은 요일이 되도록 보정한다.
 * (대회는 보통 주말 개막 등 요일에 맞춰 편성되므로)
 */
export function shiftToYear(baseDate: string, year: number): string {
  const base = toDate(baseDate);
  // 1~2월 날짜는 시즌 다음 해에 속하므로 연도 차이를 유지한다
  const targetYear = year + (base.getUTCFullYear() - BASE_YEAR);
  const cand = new Date(Date.UTC(targetYear, base.getUTCMonth(), base.getUTCDate()));
  // 요일 맞추기: -3 ~ +3일 범위에서 가장 가까운 같은 요일
  let delta = base.getUTCDay() - cand.getUTCDay();
  if (delta > 3) delta -= 7;
  if (delta < -3) delta += 7;
  cand.setUTCDate(cand.getUTCDate() + delta);
  return fmt(cand);
}

export const BASE_YEAR: number = schedule.baseYear;

// ─────────────────────────────────────────────────────────────
// 실제 한국 고교야구 대회 일정 (2026 시즌 기준, 대한야구소프트볼협회 발표 일정)
//  - 주말리그 전반기 3/7~4/26 (15개 권역, 103개 팀) → 황금사자기·청룡기 출전권
//  - 신세계 이마트배 3/25~4/13
//  - 제80회 황금사자기 5/2~5/16 (목동·신월)
//  - 주말리그 후반기 5/23~6/21 → 대통령배 출전권
//  - 제81회 청룡기 6/27~7/11 (목동·신월)
//  - 제60회 대통령배 7/18~7/30
//  - 제54회 봉황대기 8/6~8/29 (전 팀 참가)
//  - KBO 신인 드래프트 9/21
//  - 제107회 전국체육대회 10/16~10/22 (시·도 대표)
// 다음 해부터는 같은 날짜 근처의 같은 요일로 옮겨 사용한다.
// ─────────────────────────────────────────────────────────────

export const COMP_DEFS = schedule.competitions as CompDef[];

export function compDef(key: string): CompDef {
  const d = COMP_DEFS.find((c) => c.key === key);
  if (!d) throw new Error('unknown comp ' + key);
  return d;
}

/** 해당 시즌 연도의 대회 시작/종료일 */
export function compDates(key: string, year: number): { start: string; end: string } {
  const d = compDef(key);
  const s = shiftToYear(`${BASE_YEAR}-${d.start}`, year);
  const e = shiftToYear(`${BASE_YEAR}-${d.end}`, year);
  return { start: s, end: e };
}

/** 연간 주요 이벤트 (대회 외) */
export interface YearEvent {
  key: string;
  label: string;
  date: string;
}

export function yearEvents(year: number): YearEvent[] {
  return schedule.events.map((e) => ({
    key: e.key,
    label: e.label,
    date: Number(e.date.slice(0, 2)) <= 2 ? seasonDate(year, e.date) : shiftToYear(`${BASE_YEAR}-${e.date}`, year),
  }));
}

export function seasonStart(year: number): string {
  return shiftToYear(`${BASE_YEAR}-03-02`, year);
}

/** 시즌 연도 판정: 3월 2일 이전이면 전년도 시즌 */
export function seasonYearOf(date: string): number {
  const d = toDate(date);
  const y = d.getUTCFullYear();
  return date < seasonStart(y) ? y - 1 : y;
}
