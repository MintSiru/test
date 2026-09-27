import { LEAGUE_GROUPS } from './data';
import { facLevel } from './facilities';
import { josa } from './names';
import { genPlayer, name } from './player';
import { clamp, type Rng } from './rng';
import type { GameState, Player, Prospect } from './types';
import { intakeFor, uid, userTeam } from './world';

// ─────────────────────────────────────────────────────────────
// 스카우트: 드래프트 후(9월 말) 중학 3학년 유망주 명단이 공개된다.
// 매주 행동력 1 (스카우트 카드로 +2), 방문할 때마다 입학 의향이 오른다.
// 3월 입학식 때 의향에 비례한 확률로 입학한다. 그 밖에 일반 입부생이 몇 명 들어온다.
// ─────────────────────────────────────────────────────────────

export function generateProspects(state: GameState, rng: Rng) {
  const team = userTeam(state);
  const rivals = LEAGUE_GROUPS.flatMap((g) => g.schools.map((s) => s.name)).filter((n) => n !== team.name);
  const out: Prospect[] = [];
  const n = 12;
  for (let i = 0; i < n; i++) {
    const quality = clamp(35 + state.reputation * 0.35 + rng.gauss() * 18 + (i < 2 ? 15 : 0), 10, 100);
    const player = genPlayer(rng, {
      id: uid(state, 'p'),
      teamId: '',
      enrollYear: state.year + 1,
      year: state.year + 1,
      quality,
      province: team.province,
      pros: state.pros,
      idolChance: 0.3,
    });
    // 우리 학교 OB 프로 선수를 동경하면 처음부터 관심이 높다
    const idol = state.pros.find((x) => x.id === player.idolId);
    const alumniBonus = idol?.alumniOf === team.id ? 25 : 0;
    out.push({
      id: player.id,
      player,
      interest: clamp(Math.round(5 + state.reputation * 0.3 + rng.int(0, 20) - (quality - 50) * 0.3 + alumniBonus), 0, 90),
      visits: 0,
      revealed: 0,
      rival: state.rivalId && rng.chance(0.35) ? state.teams[state.rivalId].name : rng.pick(rivals),
    });
  }
  state.prospects = out.sort((a, b) => b.player.talent - a.player.talent);
}

export function visitProspect(state: GameState, id: string, rng: Rng): string {
  const pr = state.prospects.find((x) => x.id === id);
  if (!pr) return '';
  if (state.scoutPoints <= 0) return '스카우트 행동력이 부족하다.';
  state.scoutPoints--;
  pr.visits++;
  pr.revealed = Math.min(3, pr.revealed + 1 + (pr.visits === 1 && facLevel(state.facilities, 'analysis') > 0 ? 1 : 0));
  const gain = Math.round(10 + state.reputation * 0.15 + rng.int(0, 8) - pr.visits * 1.5 + 3 * facLevel(state.facilities, 'dorm'));
  pr.interest = clamp(pr.interest + Math.max(3, gain), 0, 100);
  return `${josa(name(pr.player), '을/를')} 만나고 왔다. 입학 의향 ${pr.interest}%`;
}

/** 입학식: 유망주 입학 + 일반 입부생 */
export function enrollNewPlayers(state: GameState, rng: Rng): Player[] {
  const team = userTeam(state);
  const joined: Player[] = [];
  // 선수단은 최대 40명 정도로 유지한다 (의향 높은 유망주부터)
  const room = Math.max(0, 40 - team.playerIds.length);
  const sorted = [...state.prospects].sort((a, b) => b.interest - a.interest);
  for (const pr of sorted) {
    if (joined.length >= room) break;
    if (rng.chance(pr.interest / 100) || pr.interest >= 90) {
      const p = pr.player;
      p.teamId = team.id;
      p.enrollYear = state.year;
      joined.push(p);
    }
  }
  state.prospects = [];
  const walkOns = Math.min(rng.int(3, 5), Math.max(0, 36 - team.playerIds.length - joined.length));
  joined.push(...intakeFor(state, rng, team, state.year, walkOns, 18 + state.reputation * 0.35));
  for (const p of joined) {
    state.players[p.id] = p;
    team.playerIds.push(p.id);
  }
  return joined;
}
