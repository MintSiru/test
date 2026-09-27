import { josa } from './names';
import { name } from './player';
import { clamp, type Rng } from './rng';
import { applyExp, focusStats, growthMult } from './training';
import type { GameState, NewsItem, Player, Popup, StatKey } from './types';

// 주간 랜덤 이벤트 (사용자 팀). 중요한 것만 팝업, 나머지는 뉴스.

export function weeklyEvent(state: GameState, roster: Player[], rng: Rng): { news?: NewsItem; popup?: Popup } | null {
  if (!roster.length || !rng.chance(0.4)) return null;
  const p = rng.pick(roster);
  const date = state.date;
  const n = name(p);
  const roll = rng.weighted(
    ['selfTrain', 'slump', 'hot', 'ob', 'paper', 'talent', 'minorInjury', 'rival', 'lunch', 'idolCopy'],
    [20, 10, 12, state.alumni.length ? 6 : 0, 6, 2, 6, 10, 8, roster.some((x) => x.idolId) ? 12 : 0],
  );
  switch (roll) {
    case 'selfTrain': {
      const fs = focusStats(p);
      for (const [k, share] of Object.entries(fs) as [StatKey, number][]) applyExp(p, k, 6 * share, growthMult(p, k, state.pros), rng);
      return { news: { date, kind: 'good', text: `${josa(n, '이/가')} 밤늦게까지 자율 훈련에 매진했다. (능력 상승)` } };
    }
    case 'slump':
      p.cond = clamp(p.cond - 2, -2, 2);
      return { news: { date, kind: 'bad', text: `${n}, 요즘 뭘 해도 잘 안 풀린다... (컨디션 하락)` } };
    case 'hot':
      p.cond = 2;
      return { news: { date, kind: 'good', text: `${n}, 공이 수박만 하게 보인다! (절호조)` } };
    case 'ob':
      for (const x of roster) if (rng.chance(0.5)) x.cond = clamp(x.cond + 1, -2, 2);
      return { news: { date, kind: 'good', text: `졸업생 선배들이 간식을 들고 격려 방문했다. 팀 분위기 상승!` } };
    case 'paper':
      state.reputation = clamp(state.reputation + 1, 0, 100);
      return { news: { date, kind: 'info', text: `지역 신문에 우리 야구부 기사가 실렸다. (명성 +1)` } };
    case 'talent': {
      if (p.talent >= 5) return null;
      p.talent++;
      for (const k of Object.keys(p.cap) as StatKey[]) p.cap[k] = k === 'velo' ? p.cap[k] + 3 : Math.min(99, p.cap[k] + 6);
      return {
        popup: { kind: 'good', playerId: p.id, title: '재능 개화', body: `${josa(n, '이/가')} 무언가를 깨달은 듯하다!\n재능이 ★${p.talent}(으)로 올랐다.` },
      };
    }
    case 'minorInjury':
      if (p.injury > 0) return null;
      p.injury = rng.int(3, 8);
      return { news: { date, kind: 'bad', text: `${n}, 연습 중 발목을 삐끗했다. (부상 ${p.injury}일)` } };
    case 'rival': {
      const other = roster.find((x) => x !== p && x.pos === p.pos);
      if (!other) return null;
      for (const x of [p, other]) for (const [k, share] of Object.entries(focusStats(x)) as [StatKey, number][]) applyExp(x, k, 3 * share, growthMult(x, k, state.pros), rng);
      return { news: { date, kind: 'good', text: `${josa(n, '과/와')} ${josa(name(other), '이/가')} 주전 자리를 두고 불꽃 튀는 경쟁 중! (둘 다 능력 상승)` } };
    }
    case 'lunch':
      for (const x of roster) x.fatigue = clamp(x.fatigue - 10, 0, 100);
      return { news: { date, kind: 'good', text: `매니저가 도시락을 싸 왔다. 모두 기운이 난다! (피로 회복)` } };
    case 'idolCopy': {
      const q = rng.pick(roster.filter((x) => x.idolId));
      const idol = state.pros.find((x) => x.id === q.idolId);
      if (!idol) return null;
      q.idolBond = clamp(q.idolBond + 5, 0, 100);
      return { news: { date, kind: 'idol', text: `${josa(name(q), '이/가')} ${idol.sur}${idol.given}의 폼을 따라 하고 있다. "이름도 같으니까 나도 할 수 있어!" (동경도 ${q.idolBond})` } };
    }
  }
  return null;
}
