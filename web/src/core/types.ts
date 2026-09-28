import type { Goals } from './goals';
// 게임 전역 데이터 타입. 세이브 파일(JSON)에 그대로 들어가므로 클래스가 아닌 순수 객체만 사용한다.

export type Pos = 'P' | 'C' | '1B' | '2B' | '3B' | 'SS' | 'LF' | 'CF' | 'RF';
export const FIELD_POSITIONS: Pos[] = ['C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF'];
export const ALL_POSITIONS: Pos[] = ['P', ...FIELD_POSITIONS];

export type Hand = 'L' | 'R';
export type BatHand = 'L' | 'R' | 'S';

/** 구종: 직구, 슬라이더, 커브, 체인지업, 포크, 투심(싱커), 커터 */
export type PitchType = 'FB' | 'SL' | 'CB' | 'CH' | 'FK' | 'SI' | 'CT';

export interface PitchSkill {
  type: PitchType;
  /** 변화량 1~7 */
  lv: number;
}

/** 모든 능력치는 1~100. velo(구속)만 km/h */
export interface Ratings {
  contact: number; // 미트(컨택)
  power: number; // 파워
  eye: number; // 선구안
  speed: number; // 주력
  arm: number; // 어깨
  fielding: number; // 수비
  velo: number; // 구속 km/h
  control: number; // 제구
  stamina: number; // 스태미나
  pitches: PitchSkill[];
}

export type StatKey = 'contact' | 'power' | 'eye' | 'speed' | 'arm' | 'fielding' | 'velo' | 'control' | 'stamina' | 'breaking';

export interface BatLine {
  g: number;
  pa: number;
  ab: number;
  h: number;
  d2: number;
  d3: number;
  hr: number;
  rbi: number;
  r: number;
  bb: number;
  so: number;
  sb: number;
  cs: number;
  sh: number;
  sf: number;
  e: number;
}

export interface PitLine {
  g: number;
  gs: number;
  outs: number;
  h: number;
  r: number;
  er: number;
  bb: number;
  so: number;
  hr: number;
  w: number;
  l: number;
  np: number;
}

export type Personality = '열혈' | '냉정' | '노력파' | '천재' | '낙천' | '소심';

/** 개인 연습 방침 */
export type Focus = 'auto' | 'contact' | 'power' | 'eye' | 'speed' | 'defense' | 'velo' | 'control' | 'breaking' | 'stamina';

export interface Player {
  id: string;
  sur: string;
  given: string;
  teamId: string;
  /** 입학 연도. 학년 = 현재 시즌 연도 - enrollYear + 1 */
  enrollYear: number;
  pos: Pos;
  sub: Pos[];
  bats: BatHand;
  throws: Hand;
  r: Ratings;
  /** 재능 1~5 (★) */
  talent: number;
  /** 능력치별 잠재 한계 (성장 상한) */
  cap: Record<StatKey, number>;
  /** 소수점 경험치 누적 */
  exp: Partial<Record<StatKey, number>>;
  abilities: string[];
  personality: Personality;
  hometown: string;
  focus: Focus;
  /** 동경하는 프로 선수 id */
  idolId?: string;
  /** 동경도 0~100 */
  idolBond: number;
  /** 동경 이벤트 진행 비트 (1: 비결 전수, 2: 꿈의 만남) */
  idolFlags?: number;
  /** 컨디션 -2(절불조) ~ +2(절호조) */
  cond: number;
  /** 피로 0~100 */
  fatigue: number;
  /** 부상 남은 일수 */
  injury: number;
  /** 투구수 규정에 따른 등판 가능일 (YYYY-MM-DD) */
  restUntil?: string;
  season: { bat: BatLine; pit: PitLine };
  career: { bat: BatLine; pit: PitLine };
  faceSeed: number;
  /** 입단 전 출신 중학교 */
  middleSchool: string;
  draft?: { year: number; teamId: string; round: number };
}

export type OrderKind = 'P' | 'B';

export type LinePos = Pos | 'DH';

export interface LineupSlot {
  playerId: string;
  /** 수비 위치. 한국 고교야구는 지명타자(DH) 제도를 사용한다 */
  pos: LinePos;
}

export interface Team {
  id: string;
  name: string;
  /** 시/도 */
  province: string;
  /** 주말리그 권역 id */
  leagueGroup: string;
  colors: [string, string];
  /** 전통/명성 0~100 (CPU 팀 선수 생성 품질에 영향) */
  prestige: number;
  playerIds: string[];
  isUser: boolean;
  /** 사용자 팀의 수동 타순. 없으면 자동 편성 */
  lineup?: LineupSlot[];
  /** 선발 로테이션 우선순위 (투수 id) */
  rotation?: string[];
  /** 시즌 누적 포인트 (전국체전 시도 대표 선발 등에 사용) */
  seasonPoints: number;
  seasonRecord: { w: number; l: number; d: number };
}

export interface MatchResult {
  homeScore: number;
  awayScore: number;
  innings: number;
  winner: string | null;
  lineScore: { home: number[]; away: number[] };
  hits: { home: number; away: number };
  errors: { home: number; away: number };
  called?: boolean; // 콜드게임
  mvp?: string;
  summary?: string;
}

export interface Fixture {
  id: string;
  compId: string;
  date: string;
  home: string;
  away: string;
  /** 리그: 조 id / 토너먼트: 라운드 번호 */
  group?: string;
  round?: number;
  slot?: number;
  result?: MatchResult;
  /** 우천 연기 횟수 */
  postponed?: number;
}

export type CompKind = 'league' | 'tournament' | 'friendly';

export interface CompDef {
  key: string;
  name: string;
  short: string;
  kind: CompKind;
  /** MM-DD */
  start: string;
  end: string;
  /** 참가 자격 설명 */
  entry: string;
  prestige: number;
  /** 우승 시 명성 */
  repWin: number;
}

export interface LeagueGroup {
  id: string;
  name: string;
  teamIds: string[];
}

export interface Competition {
  id: string;
  key: string;
  name: string;
  kind: CompKind;
  year: number;
  start: string;
  end: string;
  status: 'upcoming' | 'active' | 'done';
  fixtures: Fixture[];
  // 리그 전용
  groups?: LeagueGroup[];
  // 토너먼트 전용: bracket[r][i] = r라운드 i번째 슬롯의 팀 id (null = 부전승/미정)
  bracket?: (string | null)[][];
  roundDates?: string[][];
  entrants?: string[];
  champion?: string;
  runnerUp?: string;
  /** 사용자 팀 최종 성적 문구 */
  userResult?: string;
}

export interface ProTeam {
  id: string;
  name: string;
  city: string;
  colors: [string, string];
}

export type ProStyle = '파워히터' | '교타자' | '준족' | '강견' | '명수비' | '클러치' | '파이어볼러' | '제구파' | '변화구' | '철완';

export interface ProPlayer {
  id: string;
  sur: string;
  given: string;
  teamId: string;
  pos: Pos;
  style: ProStyle;
  number: number;
  birthYear: number;
  /** 최근 시즌 성적 요약 */
  line: string;
  /** 우리 학교 출신 OB 여부 */
  alumniOf?: string;
  retired?: boolean;
}

export interface Prospect {
  id: string;
  player: Player; // teamId = '' 인 상태
  interest: number; // 0~100 입학 의향
  visits: number;
  revealed: number; // 0~3 정보 공개 단계
  rival?: string; // 경쟁 학교 이름
}

export type CardKind = 'batting' | 'pitching' | 'defense' | 'running' | 'stamina' | 'rest' | 'practiceGame' | 'meeting' | 'scout' | 'special';

export interface Card {
  id: string;
  kind: CardKind;
  value: number; // 1~5
  /** 손에 들고 있던 주 수 (4주가 지나면 새 카드로 교체) */
  age?: number;
}

export interface NewsItem {
  date: string;
  text: string;
  kind: 'info' | 'good' | 'bad' | 'idol' | 'result';
}

export interface Popup {
  title: string;
  body: string;
  kind?: 'info' | 'good' | 'bad' | 'idol';
  playerId?: string;
}

export interface YearRecord {
  year: number;
  results: { comp: string; result: string }[];
  captain?: string;
  drafted: string[];
  /** 후원회 목표 달성 수 (예: "2/3") */
  goals?: string;
}

export interface Alumni {
  playerId: string;
  name: string;
  gradYear: number;
  pos: Pos;
  draft?: { teamId: string; round: number };
  proId?: string;
}

export interface Settings {
  speed: 1 | 2 | 3 | 4; // 느림 ~ 즉시
  pauseMode: 'pitch' | 'pa' | 'chance' | 'watch';
  sound: boolean;
}

export interface GameState {
  version: number;
  seed: number;
  rngState: number;
  date: string;
  year: number;
  userTeamId: string;
  managerName: string;
  reputation: number;
  teams: Record<string, Team>;
  players: Record<string, Player>;
  proTeams: ProTeam[];
  pros: ProPlayer[];
  competitions: Competition[];
  hand: Card[];
  /** 이번 주 훈련 완료 여부 (월요일에 초기화) */
  weekTrained: boolean;
  scoutPoints: number;
  prospects: Prospect[];
  news: NewsItem[];
  popups: Popup[];
  history: YearRecord[];
  alumni: Alumni[];
  settings: Settings;
  nextId: number;
  /** 오늘 사용자 팀 경기가 있으면 fixture id */
  pendingFixture?: string;
  /** 이 날짜의 하루 시작 이벤트를 처리했는지 */
  dayEventsDone?: string;
  /** 동계 훈련 등 다음 훈련에 적용할 보너스 배율 */
  trainingBonus?: number;
  /** 야구부 포인트 (경기 결과로 획득, 장터에서 사용) */
  points?: number;
  /** 가방: 아이템 key → 개수 */
  inventory?: Record<string, number>;
  /** 이번 달 장터 */
  shop?: { openUntil: string; stock: { key: string; qty: number; price?: number }[]; sale?: string };
  /** 프로 선수 명단: 실명(real) / 가상(fictional) */
  prosMode?: 'real' | 'fictional';
  /** 시설 레벨 */
  facilities?: Record<string, number>;
  /** 라이벌 학교 */
  rivalId?: string;
  /** 상대 전적 */
  h2h?: Record<string, { w: number; l: number; d: number }>;
  /** 이번 시즌 상대별 패배 수 (라이벌 갱신용) */
  rivalLoss?: Record<string, number>;
  /** 후원회 연간 목표 */
  goals?: Goals;
}
