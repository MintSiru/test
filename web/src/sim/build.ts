import { compileFx } from '../core/abilities';
import { breakingScore, name } from '../core/player';
import { autoLineup, canPitchOn, pickStarter } from '../core/lineup';
import { clamp } from '../core/rng';
import type { LineupSlot, Player, Team } from '../core/types';
import type { SideInput, SimPlayer } from './types';

/** 선수 → 경기용 능력 (컨디션 ±3%/단계, 피로 페널티) */
export function toSim(p: Player, date: string, condBonus = 0): SimPlayer {
  const cond = Math.min(2, p.cond + condBonus);
  const m = 1 + cond * 0.03 - Math.max(0, p.fatigue - 50) * 0.002;
  const f = (v: number) => clamp(v * m, 1, 110);
  return {
    id: p.id,
    name: name(p),
    pos: p.pos,
    sub: p.sub,
    bats: p.bats,
    throws: p.throws,
    con: f(p.r.contact),
    pow: f(p.r.power),
    eye: f(p.r.eye),
    spd: f(p.r.speed),
    arm: f(p.r.arm),
    fld: f(p.r.fielding),
    velo: p.r.velo + cond * 0.8,
    ctl: f(p.r.control),
    sta: f(p.r.stamina),
    stuff: breakingScore(p.r.pitches),
    pitches: p.r.pitches,
    abil: p.abilities,
    fx: compileFx(p.abilities),
    canPitch: canPitchOn(p, date),
  };
}

export function buildSide(team: Team, roster: Player[], date: string, opts: { lineup?: LineupSlot[]; starterId?: string; condBonus?: number } = {}): SideInput {
  const healthy = roster.filter((p) => p.injury <= 0);
  const starter = (opts.starterId && healthy.find((p) => p.id === opts.starterId)) || pickStarter(healthy, date, team.rotation) || healthy[0];
  let lineup = opts.lineup ?? team.lineup;
  const valid =
    lineup &&
    lineup.length === 9 &&
    lineup.every((s) => healthy.some((p) => p.id === s.playerId) && s.playerId !== starter.id) &&
    new Set(lineup.map((s) => s.pos)).size === 9;
  if (!valid) lineup = autoLineup(healthy, date, [starter.id]);
  return {
    teamId: team.id,
    name: team.name,
    colors: team.colors,
    players: healthy.map((p) => toSim(p, date, opts.condBonus ?? 0)),
    lineup: lineup!,
    pitcherId: starter.id,
    isUser: team.isUser,
  };
}
