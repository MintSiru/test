import { describe, expect, it } from 'vitest';
import pros from '../../game/data/pros.json';
import prosFictional from '../../game/data/pros_fictional.json';

// 프로 명단 검사: 매년 pros.json 을 갱신할 때 형식 실수를 잡는다 (CLAUDE.md 「프로 명단 연 1회 갱신」)
const POS = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];
const PIT_STYLES = ['파이어볼러', '제구파', '변화구', '철완'];
const BAT_STYLES = ['파워히터', '교타자', '준족', '강견', '명수비', '클러치'];
const HANGUL = /^[가-힣]{1,2}$/;

interface ProRow { sur: string; given: string; team: string; pos: string; style: string; age: number }
interface ProFile { teams: { id: string; name: string; colors: string[] }[]; players: ProRow[]; teamMap?: Record<string, string> }

function problems(file: ProFile, minTotal: number): string[] {
  const out: string[] = [];
  const teamIds = file.teams.map((t) => t.id);
  if (file.teams.length !== 10) out.push(`구단 수 ${file.teams.length} (10이어야 함)`);
  for (const t of file.teams) if (!t.name || t.colors?.length !== 2) out.push(`구단 ${t.id}: 이름·색 2개 필요`);
  if (file.teamMap) for (const id of Object.keys(file.teamMap)) if (!teamIds.includes(id)) out.push(`teamMap 에 없는 구단 ${id}`);
  const seen = new Set<string>();
  for (const p of file.players) {
    const who = `${p.sur}${p.given}`;
    if (!HANGUL.test(p.sur) || !HANGUL.test(p.given)) out.push(`${who}: 성·이름은 한글 1~2자`);
    if (seen.has(who)) out.push(`${who}: 중복`);
    seen.add(who);
    if (!teamIds.includes(p.team)) out.push(`${who}: 알 수 없는 구단 ${p.team}`);
    if (!POS.includes(p.pos)) out.push(`${who}: 알 수 없는 포지션 ${p.pos}`);
    const styles = p.pos === 'P' ? PIT_STYLES : BAT_STYLES;
    if (!styles.includes(p.style)) out.push(`${who}: ${p.pos === 'P' ? '투수' : '타자'} 스타일은 ${styles.join('·')} 중 하나 (${p.style})`);
    if (!(p.age >= 18 && p.age <= 45)) out.push(`${who}: 나이 ${p.age}`);
  }
  if (file.players.length < minTotal) out.push(`선수 ${file.players.length}명 (${minTotal}명 이상 권장)`);
  for (const id of teamIds) if (file.players.filter((p) => p.team === id).length < 3) out.push(`${id}: 선수 3명 미만`);
  const pit = file.players.filter((p) => p.pos === 'P').length / file.players.length;
  if (pit < 0.25 || pit > 0.55) out.push(`투수 비율 ${(pit * 100).toFixed(0)}% (25~55%)`);
  return out;
}

describe('프로 명단 데이터', () => {
  it('실명 명단 (pros.json) 형식', () => {
    expect(problems(pros as ProFile, 60)).toEqual([]);
  });
  it('가상 명단 (pros_fictional.json) 형식', () => {
    expect(problems(prosFictional as ProFile, 30)).toEqual([]);
  });
  it('이름(given)이 다양해야 동경 선수가 생긴다', () => {
    const given = new Set((pros as ProFile).players.map((p) => p.given));
    expect(given.size).toBeGreaterThanOrEqual(40);
  });
});
