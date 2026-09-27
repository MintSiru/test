import type { BatHand, BatLine, Hand, LinePos, PitchSkill, PitchType, PitLine, Pos } from '../core/types';

/** 경기용으로 평탄화한 선수 능력 (컨디션·피로 반영 완료) */
export interface SimPlayer {
  id: string;
  name: string;
  pos: Pos;
  sub: Pos[];
  bats: BatHand;
  throws: Hand;
  con: number;
  pow: number;
  eye: number;
  spd: number;
  arm: number;
  fld: number;
  velo: number;
  ctl: number;
  sta: number;
  stuff: number;
  pitches: PitchSkill[];
  abil: string[];
  /** 투수 등판 가능 여부 (투구수 휴식 규정) */
  canPitch: boolean;
}

export interface SideInput {
  teamId: string;
  name: string;
  colors: [string, string];
  players: SimPlayer[];
  lineup: { playerId: string; pos: LinePos }[];
  pitcherId: string;
  isUser: boolean;
}

export interface MatchRules {
  innings: number;
  /** [이닝, 점수차] 콜드게임 기준 */
  mercy: [number, number][];
  /** 이 이닝부터 무사 1,2루 승부치기 */
  tiebreakFrom: number;
  pitchLimit: number;
  /** 무승부 허용 (리그전) — 최대 이닝 도달 시 */
  allowDraw: boolean;
  maxInnings: number;
}

export const DEFAULT_RULES: MatchRules = {
  innings: 9,
  mercy: [[5, 10], [7, 7]],
  tiebreakFrom: 10,
  pitchLimit: 105,
  allowDraw: false,
  maxInnings: 15,
};

export type OffOrder = 'normal' | 'wait' | 'aggressive' | 'bunt' | 'safetyBunt' | 'squeeze' | 'steal' | 'hitRun';
export type PitchOrder = 'normal' | 'zone' | 'edge' | 'ibb';
export type ShiftOrder = 'normal' | 'infieldIn' | 'buntShift' | 'deep';

export interface Orders {
  off?: OffOrder;
  pitch?: PitchOrder;
  shift?: ShiftOrder;
}

export interface Runner {
  id: string;
  /** 책임 투수 */
  resp: string;
  earned: boolean;
}

export type BattedType = 'GB' | 'LD' | 'FB' | 'PU' | 'BUNT';
export type PlayResult = 'OUT' | '1B' | '2B' | '3B' | 'HR' | 'E' | 'DP' | 'FC' | 'SAC' | 'SF';

export interface Move {
  runnerId: string;
  /** 0 = 타자 */
  from: number;
  /** 1~3 루, 4 = 홈인, -1 = 아웃 */
  to: number;
}

export interface PitchEvent {
  inning: number;
  top: boolean;
  pitcherId: string;
  batterId: string;
  pitchType: PitchType;
  kmh: number;
  /** 스트라이크존 기준 좌표 (-1~1 이 존 안) */
  loc: { x: number; y: number };
  call: 'ball' | 'called' | 'swinging' | 'foul' | 'inplay' | 'hbp' | 'ibb' | 'buntFoul' | 'buntMiss';
  batted?: { type: BattedType; angle: number; dist: number; result: PlayResult; fielder: Pos; caught: boolean };
  steal?: { runnerId: string; from: number; success: boolean };
  wildPitch?: boolean;
  moves: Move[];
  runs: number;
  /** 타석 종료 시 결과 문구 */
  paResult?: string;
  text: string;
  endHalf: boolean;
  gameOver: boolean;
}

export interface BoxEntry {
  bat: BatLine;
  pit: PitLine;
}

export interface SideState {
  input: SideInput;
  byId: Record<string, SimPlayer>;
  order: string[];
  posOf: Record<string, LinePos>;
  batterIdx: number;
  pitcherId: string;
  used: string[];
  pitchers: string[];
  pitchCount: Record<string, number>;
  score: number;
  hits: number;
  errors: number;
  line: number[];
  box: Record<string, BoxEntry>;
}
