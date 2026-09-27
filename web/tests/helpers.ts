import { genPlayer } from '../src/core/player';
import { Rng } from '../src/core/rng';
import type { Player, Pos, Team } from '../src/core/types';

const ROSTER_POS: Pos[] = ['P', 'P', 'P', 'P', 'P', 'P', 'C', 'C', '1B', '2B', '3B', 'SS', 'SS', 'LF', 'CF', 'RF', 'CF', '2B'];

export function makeTeam(rng: Rng, id: string, quality: number, year = 2026): { team: Team; players: Player[] } {
  const players: Player[] = ROSTER_POS.map((pos, i) =>
    genPlayer(rng, { id: `${id}-${i}`, teamId: id, enrollYear: year - (i % 3), year, quality, pos, province: '서울' }),
  );
  const team: Team = {
    id, name: id, province: '서울', leagueGroup: 'x', colors: ['#000', '#fff'], prestige: quality,
    playerIds: players.map((p) => p.id), isUser: false, seasonPoints: 0, seasonRecord: { w: 0, l: 0, d: 0 },
  };
  return { team, players };
}
