import { STYLE_INFO } from './abilities';
import { addDays, compDates, compDef, monthOf, prettyDate, seasonYearOf, weekday, yearEvents } from './calendar';
import {
  advanceTournament, createLeague, createTournament, roundName, standings, tournamentResultFor,
} from './competition';
import { LEAGUE_GROUPS } from './data';
import { weeklyEvent } from './events';
import { initRival, isRivalGame, recordH2H, seasonRivalUpdate } from './rival';
import { addPrize, FAC_DATA, facLevel, monthlyIncome } from './facilities';
import { checkIdolMilestones, idolOf, proName, proSeasonEnd, proTeamName, weeklyProNews } from './idol';
import { josa } from './names';
import { addBat, addPit, emptyBat, emptyPit, grade, name, overall, statValue } from './player';
import { Rng, clamp } from './rng';
import { enrollNewPlayers, generateProspects } from './scouting';
import { CARD_INFO, applyExp, drawCard, growthMult, trainPlayer, weeklyCondition, type TrainingReport } from './training';
import type { Card, Competition, Fixture, GameState, MatchResult, Player, ProStyle, StatKey } from './types';
import { intakeFor, newGame, teamPlayers, uid, userTeam, type NewGameOpts } from './world';
import { playOut } from '../sim/ai';
import { buildSide } from '../sim/build';
import { Match } from '../sim/engine';
import type { MatchRules } from '../sim/types';
import { DEFAULT_RULES } from '../sim/types';

// ─────────────────────────────────────────────────────────────
// 시즌 진행 (하루 단위)
//  advance() 는 '사용자가 무언가 해야 하는 시점'까지 날짜를 진행한다.
//   - 'training' : 월요일, 이번 주 훈련 카드를 골라야 함
//   - 'match'    : 오늘 우리 팀 경기
//   - 'popup'    : 보여 줄 이벤트 팝업이 있음
// ─────────────────────────────────────────────────────────────

export type StopReason = 'training' | 'match' | 'popup';

export function rngOf(state: GameState): Rng {
  return new Rng(state.rngState || state.seed);
}

export function startNewGame(o: NewGameOpts): GameState {
  const state = newGame(o);
  initRival(state);
  const rng = rngOf(state);
  createSeasonCompetitions(state, rng);
  state.rngState = rng.state;
  state.dayEventsDone = undefined;
  return state;
}

function blockedByLeagues(state: GameState): Set<string> {
  const s = new Set<string>();
  for (const c of state.competitions) if (c.kind === 'league' && c.year === state.year) for (const f of c.fixtures) s.add(f.date);
  return s;
}

function leagueGroupsNow(state: GameState) {
  return LEAGUE_GROUPS.map((g) => ({
    id: g.id,
    name: g.name,
    teamIds: Object.values(state.teams).filter((t) => t.leagueGroup === g.id).map((t) => t.id),
  }));
}

export function createSeasonCompetitions(state: GameState, rng: Rng) {
  const groups = leagueGroupsNow(state);
  state.competitions = [createLeague(state, 'league1', groups), createLeague(state, 'league2', groups)];
  const all = Object.keys(state.teams);
  state.competitions.push(createTournament(state, 'emart', all, rng, blockedByLeagues(state)));
  state.competitions.push(createTournament(state, 'bonghwang', all, rng));
}

export function compByKey(state: GameState, key: string): Competition | undefined {
  return state.competitions.find((c) => c.key === key && c.year === state.year);
}

export function findFixture(state: GameState, id: string): { comp: Competition; f: Fixture } | null {
  for (const comp of state.competitions) {
    const f = comp.fixtures.find((x) => x.id === id);
    if (f) return { comp, f };
  }
  return null;
}

export function fixturesOn(state: GameState, date: string): { comp: Competition; f: Fixture }[] {
  const out: { comp: Competition; f: Fixture }[] = [];
  for (const comp of state.competitions) for (const f of comp.fixtures) if (f.date === date) out.push({ comp, f });
  return out;
}

export function userFixtures(state: GameState): { comp: Competition; f: Fixture }[] {
  const out: { comp: Competition; f: Fixture }[] = [];
  for (const comp of state.competitions) for (const f of comp.fixtures) if (f.home === state.userTeamId || f.away === state.userTeamId) out.push({ comp, f });
  return out.sort((a, b) => (a.f.date < b.f.date ? -1 : 1));
}

export function nextUserFixture(state: GameState) {
  return userFixtures(state).find((x) => !x.f.result);
}

// ───────────────────────── 메인 루프 ─────────────────────────

export function advance(state: GameState, maxDays = 800): StopReason {
  for (let i = 0; i < maxDays; i++) {
    if (state.popups.length) return 'popup';
    if (!state.weekTrained) return 'training';
    if (state.pendingFixture) return 'match';
    const rng = rngOf(state);
    const r = processDay(state, rng);
    state.rngState = rng.state;
    if (r === 'match') return 'match';
  }
  return 'popup';
}

/** 하루 처리. 우리 팀 경기가 있으면 'match' 를 돌려주고 날짜를 넘기지 않는다 */
function processDay(state: GameState, rng: Rng): 'match' | 'next' {
  const d = state.date;
  if (state.dayEventsDone !== d) {
    state.dayEventsDone = d;
    dayStartEvents(state, rng);
    if (state.popups.length) return 'next';
  }
  for (const c of state.competitions) if (c.status === 'upcoming' && c.start <= d) c.status = 'active';

  const today = fixturesOn(state, d).filter((x) => !x.f.result);
  const mine = today.find((x) => x.f.home === state.userTeamId || x.f.away === state.userTeamId);
  if (mine) {
    state.pendingFixture = mine.f.id;
    return 'match';
  }
  for (const { comp, f } of today) {
    if (f.result) continue;
    const m = createMatch(state, f, rng);
    playOut(m);
    applyResult(state, comp, f, m, rng);
  }
  endOfDay(state, rng);
  state.date = addDays(d, 1);
  if (seasonYearOf(state.date) > state.year) newSeason(state, rng);
  if (weekday(state.date) === 1) weekStart(state, rng);
  return 'next';
}

function dayStartEvents(state: GameState, rng: Rng) {
  const d = state.date;
  if (d.endsWith('-01')) monthlyIncome(state);
  for (const ev of yearEvents(state.year)) {
    if (ev.date !== d) continue;
    switch (ev.key) {
      case 'allstar':
        state.news.push({ date: d, kind: 'info', text: '고교-대학 올스타전이 열렸다. 전국의 스타 선수들이 한자리에!' });
        break;
      case 'sportsSelect':
        createSportsFestival(state, rng);
        break;
      case 'draft':
        runDraft(state, rng);
        generateProspects(state, rng);
        state.news.push({ date: d, kind: 'info', text: '중학 유망주 명단이 공개됐다. 스카우트 활동을 시작하자.' });
        break;
      case 'retire':
        retireSeniors(state);
        break;
      case 'proSeason':
        proSeasonEnd(state, rng);
        state.news.push({ date: d, kind: 'idol', text: '프로야구 시즌이 막을 내렸다.' });
        break;
      case 'camp':
        state.trainingBonus = 1.6;
        state.popups.push({ kind: 'good', title: '동계 전지훈련', body: '따뜻한 남쪽으로 전지훈련을 떠났다!\n이번 주 훈련 효과가 크게 오른다.' });
        break;
      case 'graduate':
        state.news.push({ date: d, kind: 'info', text: '졸업식. 한 시즌이 끝났다.' });
        break;
    }
  }
}

function endOfDay(state: GameState, rng: Rng) {
  void rng;
  for (const p of Object.values(state.players)) {
    if (p.injury > 0) p.injury--;
    if (p.fatigue > 0) p.fatigue = Math.max(0, p.fatigue - 2);
  }
  // 리그 종료 → 전국대회 출전팀 결정
  for (const c of state.competitions) {
    if (c.kind !== 'league' || c.status === 'done') continue;
    if (c.fixtures.every((f) => f.result) && state.date >= c.end) finishLeague(state, c, rngOf(state));
  }
}

function weekStart(state: GameState, rng: Rng) {
  state.weekTrained = false;
  const m = monthOf(state.date);
  if ((m >= 9 || m <= 2) && state.prospects.length) state.scoutPoints = Math.min(6, state.scoutPoints + 1);
  weeklyProNews(state, rng);
  const roster = teamPlayers(state, state.userTeamId);
  for (const p of Object.values(state.players)) weeklyCondition(p, rng);
  const dorm = facLevel(state.facilities, 'dorm');
  if (dorm) for (const p of roster) p.fatigue = Math.max(0, p.fatigue - 5 * dorm);
  const ev = weeklyEvent(state, roster, rng);
  if (ev?.news) state.news.push(ev.news);
  if (ev?.popup) state.popups.push(ev.popup);
  for (const p of roster) {
    const pop = checkIdolMilestones(state, p, rng);
    if (pop) state.popups.push(pop);
  }
  // CPU 팀 주간 훈련 (무작위 카드)
  for (const t of Object.values(state.teams)) {
    if (t.isUser) continue;
    const card = drawCard(rng, 'cpu');
    for (const p of teamPlayers(state, t.id)) trainPlayer(p, card, state.pros, rng, undefined, true);
  }
  trimNews(state);
}

function trimNews(state: GameState) {
  if (state.news.length > 300) state.news.splice(0, state.news.length - 300);
}

// ───────────────────────── 훈련 ─────────────────────────

export function useCard(state: GameState, cardId: string): TrainingReport {
  const rng = rngOf(state);
  const idx = state.hand.findIndex((c) => c.id === cardId);
  const card: Card = idx >= 0 ? state.hand[idx] : state.hand[0];
  const report: TrainingReport = { gains: {}, injuries: [], awakenings: [] };
  const bonus = state.trainingBonus ?? 1;
  const effCard = { ...card, value: card.value * bonus };
  for (const p of teamPlayers(state, state.userTeamId)) trainPlayer(p, effCard, state.pros, rng, report, false, state.facilities);
  state.trainingBonus = undefined;
  if (card.kind === 'scout') state.scoutPoints = Math.min(8, state.scoutPoints + 2);
  state.hand.splice(state.hand.indexOf(card), 1);
  state.hand.push(drawCard(rng, uid(state, 'c')));
  state.weekTrained = true;
  const info = CARD_INFO[card.kind];
  state.news.push({ date: state.date, kind: 'info', text: `이번 주 훈련: ${info.name} Lv${card.value}` });
  for (const id of report.injuries) state.news.push({ date: state.date, kind: 'bad', text: `${name(state.players[id])}, 훈련 중 부상! (${state.players[id].injury}일)` });
  for (const a of report.awakenings) {
    state.popups.push({ kind: 'good', playerId: a.playerId, title: '특수능력 습득', body: `${josa(name(state.players[a.playerId]), '이/가')} 새로운 능력에 눈을 떴다!` });
  }
  state.rngState = rng.state;
  return report;
}

// ───────────────────────── 경기 ─────────────────────────

export function rulesFor(comp: Competition): MatchRules {
  return comp.kind === 'league' ? { ...DEFAULT_RULES, allowDraw: true, maxInnings: 12 } : DEFAULT_RULES;
}

export function createMatch(state: GameState, f: Fixture, rng: Rng, userOpts: { lineup?: Player['id'][]; starterId?: string } = {}): Match {
  const home = state.teams[f.home];
  const away = state.teams[f.away];
  const comp = state.competitions.find((c) => c.id === f.compId)!;
  const bonus = isRivalGame(state, f) ? 1 : 0; // 라이벌전 투지
  const hs = buildSide(home, teamPlayers(state, home.id), f.date, home.isUser ? { starterId: userOpts.starterId, condBonus: bonus } : {});
  const as = buildSide(away, teamPlayers(state, away.id), f.date, away.isUser ? { starterId: userOpts.starterId, condBonus: bonus } : {});
  return new Match(hs, as, rng, rulesFor(comp));
}

/** 투구수에 따른 의무 휴식일 (대한야구소프트볼협회 투구수 제한 규정) */
export function restDays(np: number): number {
  if (np <= 30) return 0;
  if (np <= 45) return 1;
  if (np <= 60) return 2;
  if (np <= 75) return 3;
  return 4;
}

export function applyResult(state: GameState, comp: Competition, f: Fixture, m: Match, rng: Rng) {
  const res: MatchResult = {
    homeScore: m.home.score,
    awayScore: m.away.score,
    innings: m.inning,
    winner: m.winner,
    lineScore: { home: [...m.home.line], away: [...m.away.line] },
    hits: { home: m.home.hits, away: m.away.hits },
    errors: { home: m.home.errors, away: m.away.errors },
    called: m.called,
  };
  f.result = res;
  const isUserGame = f.home === state.userTeamId || f.away === state.userTeamId;

  for (const side of [m.home, m.away]) {
    const team = state.teams[side.input.teamId];
    const won = m.winner === team.id;
    const drew = !m.winner;
    if (won) team.seasonRecord.w++;
    else if (drew) team.seasonRecord.d++;
    else team.seasonRecord.l++;
    if (won) team.seasonPoints += comp.kind === 'league' ? 1 : 3;
    // 선수 기록 반영
    for (const [id, box] of Object.entries(side.box)) {
      const p = state.players[id];
      if (!p) continue;
      addBat(p.season.bat, box.bat);
      addBat(p.career.bat, box.bat);
      addPit(p.season.pit, box.pit);
      addPit(p.career.pit, box.pit);
      p.fatigue = clamp(p.fatigue + 4 + box.pit.np / 4, 0, 100);
      if (box.pit.np > 0) p.restUntil = addDays(f.date, restDays(box.pit.np) + 1);
      // 실전 경험치 (사용자 팀만 — CPU 팀은 주간 훈련으로 대체)
      if (team.isUser) {
        const g = (k: StatKey, v: number) => trainGain(state, p, k, v, rng);
        if (box.bat.pa) { g('contact', 0.6); g('eye', 0.4); if (box.bat.h) g('power', 0.4); }
        if (box.pit.outs) { g('control', box.pit.outs / 12); g('stamina', box.pit.outs / 15); }
        const good = box.bat.h >= 2 || box.bat.hr > 0 || (box.pit.outs >= 15 && box.pit.er <= 2);
        if (good && p.idolId) {
          p.idolBond = clamp(p.idolBond + 2, 0, 100);
          const pop = checkIdolMilestones(state, p, rng);
          if (pop) state.popups.push(pop);
        }
      }
    }
  }

  if (comp.kind === 'tournament') advanceTournament(comp, f);
  if (comp.status === 'done' && comp.champion) {
    state.teams[comp.champion].seasonPoints += 5;
    state.teams[comp.champion].prestige = clamp(state.teams[comp.champion].prestige + 3, 0, 95);
  }

  if (isUserGame) {
    state.pendingFixture = undefined;
    const u = state.userTeamId;
    const opp = state.teams[f.home === u ? f.away : f.home];
    recordH2H(state, opp.id, res.winner);
    const us = f.home === u ? res.homeScore : res.awayScore;
    const them = f.home === u ? res.awayScore : res.homeScore;
    const label = comp.kind === 'league' ? compDef(comp.key).short : `${compDef(comp.key).short} ${roundName(comp, f.round!)}`;
    const outcome = res.winner === u ? '승리' : res.winner ? '패배' : '무승부';
    state.news.push({ date: f.date, kind: res.winner === u ? 'good' : res.winner ? 'bad' : 'info', text: `[${label}] vs ${opp.name} ${us}:${them} ${outcome}${res.called ? ' (콜드)' : ''}` });
    if (comp.kind === 'tournament') {
      if (res.winner === u) state.reputation = clamp(state.reputation + 1, 0, 100);
      const r = tournamentResultFor(comp, u);
      if (r && (comp.champion || res.winner !== u)) {
        comp.userResult = r;
        const def = compDef(comp.key);
        addPrize(state, r, def.short);
        if (r === '우승') {
          state.reputation = clamp(state.reputation + def.repWin, 0, 100);
          state.popups.push({ kind: 'good', title: `${def.short} 우승!`, body: `${userTeam(state).name}, ${def.name} 우승!!\n전국에 이름을 떨쳤다. (명성 +${def.repWin})` });
        } else {
          const bonus = r === '준우승' ? Math.round(def.repWin / 2) : r === '4강' ? 4 : r === '8강' ? 2 : 0;
          state.reputation = clamp(state.reputation + bonus, 0, 100);
          state.popups.push({ kind: r === '준우승' || r === '4강' ? 'good' : 'info', title: `${def.short} ${r}`, body: `${def.name}에서 ${r}${r.endsWith('탈락') ? '했다.' : '의 성적을 거뒀다.'}${bonus ? ` (명성 +${bonus})` : ''}` });
        }
      }
    }
  }
}

function trainGain(state: GameState, p: Player, k: StatKey, pts: number, rng: Rng) {
  applyExp(p, k, pts, growthMult(p, k, state.pros), rng);
}

/** 사용자 경기를 위임(자동 진행) */
export function autoPlayUserMatch(state: GameState): Match | null {
  if (!state.pendingFixture) return null;
  const found = findFixture(state, state.pendingFixture);
  if (!found) return null;
  const rng = rngOf(state);
  const m = createMatch(state, found.f, rng);
  playOut(m);
  applyResult(state, found.comp, found.f, m, rng);
  state.rngState = rng.state;
  return m;
}

/** UI 에서 직접 진행한 경기 결과 반영 */
export function finishUserMatch(state: GameState, m: Match) {
  if (!state.pendingFixture) return;
  const found = findFixture(state, state.pendingFixture);
  if (!found) return;
  const rng = rngOf(state);
  applyResult(state, found.comp, found.f, m, rng);
  state.rngState = rng.state;
}

// ───────────────────────── 대회 전환 ─────────────────────────

function finishLeague(state: GameState, c: Competition, rng: Rng) {
  c.status = 'done';
  const u = state.userTeamId;
  const hw: string[] = [];
  const cr: string[] = [];
  const pres: string[] = [];
  for (const g of c.groups!) {
    const table = standings(c, g.id);
    table.forEach((row, i) => {
      const rank = i + 1;
      if (rank === 1) { hw.push(row.teamId); cr.push(row.teamId); state.teams[row.teamId].seasonPoints += 3; }
      else if (rank % 2 === 0) hw.push(row.teamId);
      else cr.push(row.teamId);
      if (rank <= 4) pres.push(row.teamId);
      if (row.teamId === u) {
        c.userResult = `${g.name} ${rank}위 (${row.w}승 ${row.l}패${row.d ? ` ${row.d}무` : ''})`;
        if (rank === 1) state.reputation = clamp(state.reputation + 3, 0, 100);
      }
    });
  }
  const r2 = new Rng(rng.state);
  if (c.key === 'league1') {
    state.competitions.push(createTournament(state, 'hwanggeum', hw, r2));
    state.competitions.push(createTournament(state, 'cheongryong', cr, r2));
    const inHw = hw.includes(u);
    const inCr = cr.includes(u);
    state.popups.push({
      kind: inHw || inCr ? 'good' : 'info',
      title: '주말리그 전반기 종료',
      body: `최종 성적: ${c.userResult}\n${inHw && inCr ? '황금사자기와 청룡기 동시 출전권 획득!' : inHw ? '황금사자기 출전권 획득!' : '청룡기 출전권 획득!'}`,
    });
  } else {
    state.competitions.push(createTournament(state, 'president', pres, r2));
    const inP = pres.includes(u);
    state.popups.push({ kind: inP ? 'good' : 'info', title: '주말리그 후반기 종료', body: `최종 성적: ${c.userResult}\n${inP ? '대통령배 출전권 획득!' : '아쉽게도 대통령배 출전권을 놓쳤다...'}` });
  }
  state.rngState = r2.state;
}

function createSportsFestival(state: GameState, rng: Rng) {
  const byProv = new Map<string, string>();
  for (const t of Object.values(state.teams)) {
    const cur = byProv.get(t.province);
    const score = (x: string) => state.teams[x].seasonPoints * 10 + state.teams[x].prestige * 0.1;
    if (!cur || score(t.id) > score(cur)) byProv.set(t.province, t.id);
  }
  const entrants = [...byProv.values()];
  state.competitions.push(createTournament(state, 'sports', entrants, rng));
  const u = userTeam(state);
  const rep = byProv.get(u.province);
  if (rep === u.id) state.popups.push({ kind: 'good', title: '전국체전 대표 선발', body: `${u.province} 대표로 전국체육대회에 출전하게 됐다!` });
  else state.news.push({ date: state.date, kind: 'info', text: `전국체전 ${u.province} 대표로 ${josa(state.teams[rep!].name, '이/가')} 선발됐다.` });
}

// ───────────────────────── 드래프트 / 은퇴 / 새 시즌 ─────────────────────────

function styleFromPlayer(p: Player): ProStyle {
  if (p.pos === 'P') {
    const opts: [ProStyle, StatKey][] = [['파이어볼러', 'velo'], ['제구파', 'control'], ['변화구', 'breaking'], ['철완', 'stamina']];
    return opts.sort((a, b) => statValue(p.r, b[1]) - statValue(p.r, a[1]))[0][0];
  }
  const opts: [ProStyle, StatKey][] = [['파워히터', 'power'], ['교타자', 'contact'], ['준족', 'speed'], ['강견', 'arm'], ['명수비', 'fielding']];
  return opts.sort((a, b) => statValue(p.r, b[1]) - statValue(p.r, a[1]))[0][0];
}

export function runDraft(state: GameState, rng: Rng) {
  const seniors = Object.values(state.players).filter((p) => p.teamId && grade(p, state.year) === 3);
  const scored = seniors.map((p) => ({ p, s: overall(p) + p.talent * 4 + rng.next() * 8 + (p.pos === 'P' ? 3 : 0) })).sort((a, b) => b.s - a.s);
  const picks = scored.slice(0, 70);
  const lines: string[] = [];
  picks.forEach(({ p }, i) => {
    const round = Math.floor((i * 11) / picks.length) + 1;
    const team = rng.pick(state.proTeams);
    p.draft = { year: state.year, teamId: team.id, round };
    if (p.teamId === state.userTeamId) {
      const idol = idolOf(state, p);
      let line = `${name(p)} — ${team.name} ${round}라운드 지명!`;
      if (idol && idol.teamId === team.id && !idol.retired) line += `\n   ★ 동경하던 ${josa(proName(idol), '과/와')} 같은 유니폼을 입게 됐다! "${idol.given} 선배, 이제 동료예요!"`;
      lines.push(line);
      state.reputation = clamp(state.reputation + (round === 1 ? 6 : round <= 3 ? 4 : 2), 0, 100);
      state.budget = (state.budget ?? 0) + FAC_DATA.draftDonation;
      state.pros.push({
        id: `pro${uid(state, 'x')}`,
        sur: p.sur,
        given: p.given,
        teamId: team.id,
        pos: p.pos,
        style: styleFromPlayer(p),
        number: rng.int(1, 99),
        birthYear: state.year - 18,
        line: '신인',
        alumniOf: state.userTeamId,
      });
    }
  });
  const top = picks[0]?.p;
  state.news.push({ date: state.date, kind: 'info', text: `KBO 신인 드래프트 개최. 전체 1순위: ${top ? `${state.teams[top.teamId].name} ${name(top)}` : '-'}` });
  state.popups.push({
    kind: lines.length ? 'good' : 'info',
    title: 'KBO 신인 드래프트',
    body: lines.length ? `우리 학교에서 프로 선수가 탄생했다!\n\n${lines.join('\n')}` : '올해는 우리 학교에서 지명된 선수가 없었다...\n3학년들은 대학 진학을 준비한다.',
  });
}

function retireSeniors(state: GameState) {
  const names: string[] = [];
  for (const t of Object.values(state.teams)) {
    const keep: string[] = [];
    for (const id of t.playerIds) {
      const p = state.players[id];
      if (!p) continue;
      if (grade(p, state.year) >= 3) {
        if (t.isUser) {
          names.push(`${name(p)} (${p.draft ? `${state.proTeams.find((x) => x.id === p.draft!.teamId)?.name} 입단` : '대학 진학'})`);
          state.alumni.push({
            playerId: p.id, name: name(p), gradYear: state.year, pos: p.pos,
            draft: p.draft ? { teamId: p.draft.teamId, round: p.draft.round } : undefined,
          });
        }
        delete state.players[id];
      } else keep.push(id);
    }
    t.playerIds = keep;
  }
  if (names.length) state.popups.push({ kind: 'info', title: '3학년 은퇴식', body: `3년간 함께한 3학년들이 야구부를 떠난다. 고마웠다!\n\n${names.join('\n')}` });
}

function newSeason(state: GameState, rng: Rng) {
  const prevYear = state.year;
  state.history.push({
    year: prevYear,
    results: state.competitions.filter((c) => c.userResult).map((c) => ({ comp: compDef(c.key).short, result: c.userResult! })),
    drafted: state.alumni.filter((a) => a.gradYear === prevYear && a.draft).map((a) => a.name),
  });
  state.year = seasonYearOf(state.date);
  for (const p of Object.values(state.players)) {
    p.season = { bat: emptyBat(), pit: emptyPit() };
    p.fatigue = 0;
    p.restUntil = undefined;
  }
  for (const t of Object.values(state.teams)) {
    t.seasonPoints = 0;
    t.seasonRecord = { w: 0, l: 0, d: 0 };
    if (t.isUser) continue;
    for (const p of intakeFor(state, rng, t, state.year, 6, t.prestige)) {
      state.players[p.id] = p;
      t.playerIds.push(p.id);
    }
    t.prestige = clamp(Math.round(t.prestige * 0.9 + 45 * 0.1), 10, 95);
  }
  seasonRivalUpdate(state);
  const joined = enrollNewPlayers(state, rng);
  userTeam(state).lineup = undefined;
  state.reputation = clamp(Math.round(state.reputation * 0.92 + 20 * 0.08), 0, 100);
  createSeasonCompetitions(state, rng);
  state.news.push({ date: state.date, kind: 'info', text: `${state.year} 시즌 개막! 신입생 ${joined.length}명이 입부했다.` });
  state.popups.push({
    kind: 'good',
    title: `${state.year} 시즌 개막`,
    body: `신입생이 입부했다!\n\n${joined.map((p) => `${name(p)} (${p.pos}, 재능 ${'★'.repeat(p.talent)})${p.idolId ? ` — 동경: ${proName(state.pros.find((x) => x.id === p.idolId)!)}` : ''}`).join('\n')}`,
  });
}

// ───────────────────────── UI 헬퍼 ─────────────────────────

export function upcomingSchedule(state: GameState) {
  const items: { date: string; label: string }[] = [];
  for (const k of ['league1', 'emart', 'hwanggeum', 'league2', 'cheongryong', 'president', 'bonghwang', 'sports']) {
    const { start, end } = compDates(k, state.year);
    items.push({ date: start, label: `${compDef(k).short} (${prettyDate(start)} ~ ${prettyDate(end)})` });
  }
  for (const e of yearEvents(state.year)) items.push({ date: e.date, label: e.label });
  return items.sort((a, b) => (a.date < b.date ? -1 : 1));
}

export function idolLabel(state: GameState, p: Player): string | null {
  const idol = idolOf(state, p);
  if (!idol) return null;
  return `${proTeamName(state, idol)} ${proName(idol)} (${STYLE_INFO[idol.style].desc})${idol.retired ? ' · 은퇴' : ''}`;
}
