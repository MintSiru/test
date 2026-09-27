import { clamp } from './rng';
import type { Fixture, GameState } from './types';

// 라이벌 학교 · 상대 전적
//  - 시작 시 같은 권역에서 전통이 가장 강한 학교가 라이벌
//  - 한 시즌에 2번 이상 진 학교가 있으면 다음 시즌 새 라이벌이 된다
//  - 라이벌전: 우리 선수 컨디션 한 단계 상승(투지), 이기면 명성 +2

export function initRival(state: GameState) {
  const u = state.teams[state.userTeamId];
  const same = Object.values(state.teams).filter((t) => t.leagueGroup === u.leagueGroup && t.id !== u.id);
  same.sort((a, b) => b.prestige - a.prestige);
  state.rivalId = same[0]?.id;
  state.h2h = {};
  state.rivalLoss = {};
}

export function isRivalGame(state: GameState, f: Fixture): boolean {
  if (!state.rivalId) return false;
  const u = state.userTeamId;
  return (f.home === u && f.away === state.rivalId) || (f.away === u && f.home === state.rivalId);
}

export function recordH2H(state: GameState, oppId: string, winner: string | null) {
  state.h2h = state.h2h ?? {};
  state.rivalLoss = state.rivalLoss ?? {};
  const rec = (state.h2h[oppId] = state.h2h[oppId] ?? { w: 0, l: 0, d: 0 });
  if (!winner) rec.d++;
  else if (winner === state.userTeamId) rec.w++;
  else {
    rec.l++;
    state.rivalLoss[oppId] = (state.rivalLoss[oppId] ?? 0) + 1;
  }
  if (oppId === state.rivalId) {
    if (winner === state.userTeamId) {
      state.reputation = clamp(state.reputation + 2, 0, 100);
      state.news.push({ date: state.date, kind: 'good', text: `라이벌 ${state.teams[oppId].name} 격파! 교내가 들썩인다. (명성 +2)` });
    } else if (winner) {
      state.news.push({ date: state.date, kind: 'bad', text: `라이벌 ${state.teams[oppId].name}에게 졌다... 다음엔 반드시!` });
    }
  }
}

/** 새 시즌: 올해 가장 많이 진 상대(2패 이상)가 새 라이벌 */
export function seasonRivalUpdate(state: GameState) {
  const loss = state.rivalLoss ?? {};
  let best: string | undefined;
  let bl = 1;
  for (const [id, n] of Object.entries(loss)) if (n > bl && state.teams[id]) { bl = n; best = id; }
  if (best && best !== state.rivalId) {
    state.rivalId = best;
    state.popups.push({ kind: 'bad', title: '새로운 라이벌', body: `지난 시즌 ${state.teams[best].name}에게 ${bl}번이나 졌다.\n올해는 저 학교를 넘어서야 한다!` });
  }
  state.rivalLoss = {};
}

/** 팀 시즌 기록 요약 (상대 분석용) */
export function teamSeasonStats(state: GameState, teamId: string) {
  let ab = 0, h = 0, hr = 0, sb = 0, outs = 0, er = 0;
  for (const id of state.teams[teamId].playerIds) {
    const p = state.players[id];
    if (!p) continue;
    ab += p.season.bat.ab; h += p.season.bat.h; hr += p.season.bat.hr; sb += p.season.bat.sb;
    outs += p.season.pit.outs; er += p.season.pit.er;
  }
  return { avg: ab ? h / ab : 0, hr, sb, era: outs ? (er * 27) / outs : 0 };
}
