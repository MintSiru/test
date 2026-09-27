import { seasonStart } from './calendar';
import { LEAGUE_GROUPS, PRO_PLAYER_DEFS, PRO_TEAM_DEFS, TEAM_COLORS } from './data';
import { genPlayer } from './player';
import { Rng } from './rng';
import { FAC_DATA } from './facilities';
import { drawCard } from './training';
import type { GameState, Player, Pos, ProPlayer, Team } from './types';

export const SAVE_VERSION = 1;

/** 학년별 입학 인원 포지션 구성 (CPU 팀 기준 6명) */
const INTAKE_POS: Pos[][] = [
  ['P', 'P', 'C', 'SS', 'CF', '2B'],
  ['P', 'P', '3B', '1B', 'LF', 'RF'],
  ['P', 'P', 'C', 'SS', 'CF', '3B'],
  ['P', 'P', '2B', 'RF', 'LF', 'SS'],
];

export function uid(state: GameState, prefix: string): string {
  return `${prefix}${(state.nextId++).toString(36)}`;
}

export interface NewGameOpts {
  schoolName: string;
  managerName: string;
  groupId: string;
  seed?: number;
  year?: number;
}

export function createPros(rng: Rng, year: number): ProPlayer[] {
  return PRO_PLAYER_DEFS.map((d, i) => ({
    id: `pro${i}`,
    sur: d.sur,
    given: d.given,
    teamId: d.team,
    pos: d.pos,
    style: d.style,
    number: rng.int(1, 99),
    birthYear: year - d.age,
    line: '',
  }));
}

export function intakeFor(state: GameState, rng: Rng, team: Team, enrollYear: number, count: number, quality: number): Player[] {
  const out: Player[] = [];
  const posSet = INTAKE_POS[rng.int(0, INTAKE_POS.length - 1)];
  for (let i = 0; i < count; i++) {
    const pos = i < posSet.length ? posSet[i] : undefined;
    const p = genPlayer(rng, {
      id: uid(state, 'p'),
      teamId: team.id,
      enrollYear,
      year: state.year,
      quality: quality + rng.gauss() * 10,
      pos,
      province: team.province,
      pros: state.pros,
    });
    out.push(p);
  }
  return out;
}

export function newGame(o: NewGameOpts): GameState {
  const seed = o.seed ?? Math.floor(Math.random() * 2 ** 31);
  const rng = new Rng(seed);
  const year = o.year ?? 2026;
  const state: GameState = {
    version: SAVE_VERSION,
    seed,
    rngState: 0,
    date: seasonStart(year),
    year,
    userTeamId: 'user',
    managerName: o.managerName || '감독',
    reputation: 20,
    teams: {},
    players: {},
    proTeams: PRO_TEAM_DEFS.map((t) => ({ ...t })),
    pros: createPros(rng, year),
    competitions: [],
    hand: [],
    weekTrained: false,
    scoutPoints: 0,
    prospects: [],
    news: [],
    popups: [],
    history: [],
    alumni: [],
    settings: { speed: 2, pauseMode: 'pa', sound: true },
    nextId: 1,
    budget: FAC_DATA.startBudget,
    facilities: {},
  };

  let colorIdx = 0;
  for (const g of LEAGUE_GROUPS) {
    g.schools.forEach((s, i) => {
      const isUser = g.id === o.groupId && i === g.schools.length - 1;
      const id = isUser ? 'user' : `t${g.id}${i}`;
      // 몇몇 전통 강호 + 대부분 중위권
      const prestige = isUser ? 25 : Math.round(Math.min(92, Math.max(15, 45 + rng.gauss() * 15 + (rng.chance(0.08) ? 25 : 0))));
      const team: Team = {
        id,
        name: isUser ? o.schoolName || '한빛고' : s.name,
        province: s.province,
        leagueGroup: g.id,
        colors: isUser ? ['#1d4e89', '#f4d35e'] : TEAM_COLORS[colorIdx++ % TEAM_COLORS.length],
        prestige,
        playerIds: [],
        isUser,
        seasonPoints: 0,
        seasonRecord: { w: 0, l: 0, d: 0 },
      };
      state.teams[id] = team;
      // 3개 학년 선수 생성
      const perGrade = 6;
      for (let gr = 0; gr < 3; gr++) {
        const q = isUser ? 34 : prestige;
        for (const p of intakeFor(state, rng, team, year - gr, perGrade, q)) {
          state.players[p.id] = p;
          team.playerIds.push(p.id);
        }
      }
    });
  }
  for (let i = 0; i < 5; i++) state.hand.push(drawCard(rng, uid(state, 'c')));
  state.rngState = rng.state;
  state.news.push({ date: state.date, kind: 'info', text: `${state.teams.user.name} 야구부 감독으로 부임했다. 목표는 전국 제패!` });
  return state;
}

export function teamPlayers(state: GameState, teamId: string): Player[] {
  return state.teams[teamId].playerIds.map((id) => state.players[id]).filter(Boolean);
}

export function userTeam(state: GameState): Team {
  return state.teams[state.userTeamId];
}
