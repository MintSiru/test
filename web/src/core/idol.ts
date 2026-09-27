import { STYLE_INFO, abilityName, cannotLearn, goldOf, learnAbility } from './abilities';
import { josa } from './names';
import { name } from './player';
import { clamp, type Rng } from './rng';
import type { GameState, Player, Popup, ProPlayer } from './types';

// ─────────────────────────────────────────────────────────────
// 동경 시스템
//  고교 선수 중 일부는 '이름이 같고 성이 다른' 프로 선수를 동경한다.
//  - 동경 선수의 스타일 능력치는 성장 보너스 (×1.25, 동경도 50 이상 ×1.4)
//  - 프로 선수의 활약 소식 → 동경도·컨디션 상승
//  - 동경도 70: 비결 전수 (대표 특수능력 습득)
//  - 동경도 100: 꿈의 만남 (스타일 능력치 대폭 상승)
//  - 드래프트에서 동경 선수의 구단에 지명되면 특별 이벤트
// ─────────────────────────────────────────────────────────────

export function idolOf(state: GameState, p: Player): ProPlayer | undefined {
  return p.idolId ? state.pros.find((x) => x.id === p.idolId) : undefined;
}

export function proName(pro: ProPlayer): string {
  return pro.sur + pro.given;
}

export function proTeamName(state: GameState, pro: ProPlayer): string {
  return state.proTeams.find((t) => t.id === pro.teamId)?.name ?? '';
}

const NEWS_TEMPLATES: Record<string, string[]> = {
  bat: ['3경기 연속 홈런!', '끝내기 안타로 팀을 구했다!', '4안타 맹타를 휘둘렀다!', '결승 2루타를 터뜨렸다!', '멀티 홈런 경기!', '월간 MVP에 선정됐다!'],
  run: ['한 경기 도루 3개!', '시즌 30도루 돌파!', '빠른 발로 결승 득점!'],
  def: ['몸을 날리는 호수비로 실점을 막았다!', '보살 2개로 흐름을 끊었다!', '무실책 행진을 이어가고 있다!'],
  pit: ['완봉승을 거뒀다!', '12탈삼진 호투!', '시즌 10승 달성!', '157km 강속구로 삼진 퍼레이드!', '7이닝 무실점 역투!', '세이브 행진을 이어가고 있다!'],
};

function newsFor(rng: Rng, pro: ProPlayer): string {
  const cat = STYLE_INFO[pro.style].pitcher ? 'pit' : pro.style === '준족' ? rng.pick(['run', 'bat']) : pro.style === '명수비' || pro.style === '강견' ? rng.pick(['def', 'bat']) : 'bat';
  return rng.pick(NEWS_TEMPLATES[cat]);
}

/** 프로 시즌(4~10월) 중 주간 프로야구 소식 */
export function weeklyProNews(state: GameState, rng: Rng) {
  const m = Number(state.date.slice(5, 7));
  if (m < 4 || m > 10) return;
  const active = state.pros.filter((p) => !p.retired);
  const users = state.teams[state.userTeamId].playerIds.map((id) => state.players[id]).filter((p) => p?.idolId);
  // 동경받는 선수 소식은 확률을 높인다
  const idolIds = new Set(users.map((p) => p.idolId!));
  const pro = idolIds.size && rng.chance(0.6) ? active.find((x) => x.id === rng.pick([...idolIds])) : rng.pick(active);
  if (!pro) return;
  const text = `[프로야구] ${proTeamName(state, pro)} ${proName(pro)}, ${newsFor(rng, pro)}`;
  state.news.push({ date: state.date, kind: 'idol', text });
  for (const p of users) {
    if (p.idolId !== pro.id) continue;
    p.idolBond = clamp(p.idolBond + rng.int(3, 7), 0, 100);
    if (rng.chance(0.5)) p.cond = clamp(p.cond + 1, -2, 2);
    state.news.push({ date: state.date, kind: 'idol', text: `${name(p)}: "${pro.given} 선배처럼 되고 싶어!" (동경도 ${p.idolBond})` });
  }
}

/** 동경도 단계 이벤트 */
export function checkIdolMilestones(state: GameState, p: Player, rng: Rng): Popup | null {
  const idol = idolOf(state, p);
  if (!idol) return null;
  const info = STYLE_INFO[idol.style];
  const flags = p.idolFlags ?? 0;
  if (p.idolBond >= 70 && !(flags & 1)) {
    p.idolFlags = flags | 1;
    const had = !!cannotLearn(p, info.ability);
    if (!had) learnAbility(p, info.ability);
    return {
      kind: 'idol',
      playerId: p.id,
      title: '동경의 비결',
      body: `${josa(name(p), '은/는')} ${proName(idol)}의 경기 영상을 수백 번 돌려 보며 그 비결을 깨달았다!\n${had ? '가지고 있던 특수능력이 더욱 단단해졌다.' : `특수능력 「${abilityName(info.ability)}」 습득!`}`,
    };
  }
  if (p.idolBond >= 100 && !(flags & 2)) {
    p.idolFlags = (p.idolFlags ?? 0) | 2;
    for (const k of info.stats) {
      if (k === 'velo') { p.r.velo = Math.min(p.cap.velo + 2, p.r.velo + 3); p.cap.velo += 2; }
      else if (k === 'breaking') { const b = p.r.pitches.find((x) => x.type !== 'FB'); if (b) b.lv = Math.min(7, b.lv + 1); }
      else { (p.r[k] as number) = Math.min(99, (p.r[k] as number) + 5); p.cap[k] = Math.min(99, p.cap[k] + 5); }
    }
    p.cond = 2;
    // 동경 선수의 대표 능력이 금특으로 진화
    const gold = goldOf(info.ability);
    const evolve = gold && p.abilities.includes(info.ability) && !cannotLearn(p, gold);
    if (evolve) learnAbility(p, gold);
    return {
      kind: 'idol',
      playerId: p.id,
      title: '꿈의 만남',
      body: `${proTeamName(state, idol)}의 ${josa(proName(idol), '이/가')} 모교 방문 행사로 근처에 왔다!\n"${p.given}? 나랑 이름이 같네. 열심히 해!"\n${josa(name(p), '은/는')} 사인볼을 품에 안고 누구보다 늦게까지 연습했다. (능력 대폭 상승)${evolve ? `\n「${abilityName(info.ability)}」이(가) 금특 「${abilityName(gold)}」(으)로 진화!` : ''}`,
    };
  }
  void rng;
  return null;
}

/** 시즌 종료 시 프로 선수 성적 결산 · 은퇴 */
export function proSeasonEnd(state: GameState, rng: Rng) {
  for (const pro of state.pros) {
    if (pro.retired) continue;
    const age = state.year - pro.birthYear;
    if (STYLE_INFO[pro.style].pitcher) {
      const w = rng.int(3, 16);
      const eraV = (2.2 + rng.next() * 3.2).toFixed(2);
      pro.line = `${w}승 ${rng.int(3, 12)}패 ERA ${eraV} ${rng.int(60, 190)}K`;
    } else {
      const avgV = (0.24 + rng.next() * 0.1).toFixed(3).replace(/^0/, '');
      const hr = pro.style === '파워히터' ? rng.int(18, 42) : rng.int(2, 20);
      pro.line = `타율 ${avgV} ${hr}홈런 ${rng.int(30, 110)}타점${pro.style === '준족' ? ` ${rng.int(20, 50)}도루` : ''}`;
    }
    if (age >= 37 && rng.chance((age - 35) * 0.15)) {
      pro.retired = true;
      state.news.push({ date: state.date, kind: 'idol', text: `[프로야구] ${proTeamName(state, pro)} ${proName(pro)} 현역 은퇴 발표` });
    }
  }
}
