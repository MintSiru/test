import type { Pos, ProStyle } from './types';
import schools from '../../../game/data/schools.json';
import pros from '../../../game/data/pros.json';
import prosFictional from '../../../game/data/pros_fictional.json';

// 공용 데이터는 Godot 프로젝트의 game/data/*.json 이 원본이다. (웹·Godot 양쪽에서 같은 파일을 읽는다)
//  - 학교 이름은 실제 야구부와 겹치지 않도록 지명·산 이름 등으로 새로 지은 가상 학교다.
//  - 프로 구단/선수는 실존 선수의 성명권 문제를 피하기 위해 전부 가상이다.

export interface GroupDef {
  id: string;
  name: string;
  schools: { name: string; province: string }[];
}

export const LEAGUE_GROUPS: GroupDef[] = schools.groups;
export const PROVINCES: string[] = schools.provinces;
export const TEAM_COLORS = schools.teamColors as [string, string][];

export const PRO_TEAM_DEFS = pros.teams as { id: string; name: string; city: string; colors: [string, string] }[];
export type ProDef = { sur: string; given: string; team: string; pos: Pos; style: ProStyle; age: number };
/** 실존 선수 이름 (구단은 가상) — 비공식 팬메이드 */
export const PRO_PLAYER_DEFS = pros.players as ProDef[];
/** 가상 선수 명단 */
export const PRO_PLAYER_DEFS_FICTIONAL = prosFictional.players as ProDef[];

export const FAN_MADE_NOTICE = '본 게임은 비상업적 비공식 팬메이드 게임이며, 실존 선수·구단·KBO와 관련이 없습니다. 게임 속 성적과 사건은 모두 가상입니다.';
