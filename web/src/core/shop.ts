import data from '../../../game/data/shop.json';
import { addDays, monthOf } from './calendar';
import { abilityName, cannotLearn, goldOf, isBad, learnAbility } from './abilities';
import { josa } from './names';
import { name } from './player';
import { clamp, type Rng } from './rng';
import type { GameState, PitchType, Player, StatKey } from './types';
import { checkIdolMilestones } from './idol';

// ─────────────────────────────────────────────────────────────
// 야구부 포인트와 장터 (영관나인·백구의 기적의 상점을 참고)
//  - 포인트는 경기 결과로만 얻는다 (승·무·패, 득점, 대회 성적, 리그 1위, 프로 지명)
//  - 장터는 매월 1일부터 7일간 열리고 물건 구성이 매번 바뀐다
//  - 시설 기물은 방학·비시즌 달의 장터에서만 설치할 수 있다
//  - 산 물건은 가방에 보관했다가 원하는 때에 선수에게 쓴다
// 원본 데이터: game/data/shop.json
// ─────────────────────────────────────────────────────────────

export interface FacilityDef { key: string; name: string; desc: string; stats: string[]; growth: number; costs: number[] }
export interface ItemDef {
  key: string; name: string; type: string; desc: string; price: number; weight: number;
  stat?: string; amount?: number; ability?: string; pitcher?: boolean;
}

export const SHOP = data;
export const FACILITIES = data.facilities as FacilityDef[];
export const ITEMS = data.items as ItemDef[];
export type FacLevels = Record<string, number>;

export function itemDef(key: string): ItemDef | undefined {
  return ITEMS.find((i) => i.key === key);
}

// ───────────── 시설 ─────────────

export function facLevel(fac: FacLevels | undefined, key: string): number {
  return fac?.[key] ?? 0;
}

/** 주간 훈련 성장 배율 */
export function facilityGrowth(fac: FacLevels | undefined, k: StatKey): number {
  if (!fac) return 1;
  let m = 1;
  for (const f of FACILITIES) if (f.stats.includes(k)) m += f.growth * facLevel(fac, f.key);
  return m;
}

export function facilityCost(state: GameState, key: string): number | null {
  const f = FACILITIES.find((x) => x.key === key);
  if (!f) return null;
  const lv = facLevel(state.facilities, key);
  return lv >= f.costs.length ? null : f.costs[lv];
}

// ───────────── 포인트 ─────────────

export function earn(state: GameState, pts: number, reason: string) {
  if (pts <= 0) return;
  state.points = (state.points ?? 0) + pts;
  state.news.push({ date: state.date, kind: 'good', text: `${reason} +${pts}P (보유 ${state.points}P)` });
}

/** 우리 경기 한 판의 포인트 */
export function matchPoints(friendly: boolean, won: boolean, drew: boolean, runs: number, called: boolean): number {
  const e = data.earn;
  if (friendly) return won ? e.friendlyWin : e.friendlyPlay;
  return (won ? e.win : drew ? e.draw : e.loss) + runs * e.perRun + (won && called ? e.coldWin : 0);
}

export function placingPoints(result: string): number {
  return (data.earn.placing as Record<string, number>)[result] ?? 0;
}

// ───────────── 장터 ─────────────

export function marketOpen(state: GameState): boolean {
  return !!state.shop && state.date <= state.shop.openUntil;
}

export function facilityMonth(state: GameState): boolean {
  return data.market.facilityMonths.includes(monthOf(state.date));
}

/** 매월 1일: 장터 열기 (물건 구성 무작위) */
export function openMarket(state: GameState, rng: Rng) {
  const stock: { key: string; qty: number }[] = [];
  const pool = [...ITEMS];
  for (let i = 0; i < data.market.stockSize && pool.length; i++) {
    const it = rng.weighted(pool, pool.map((x) => x.weight));
    pool.splice(pool.indexOf(it), 1);
    stock.push({ key: it.key, qty: it.type === 'ability' ? 1 : rng.int(1, 3) });
  }
  state.shop = { openUntil: addDays(state.date, data.market.days - 1), stock };
  state.news.push({
    date: state.date, kind: 'good',
    text: `장터가 열렸다! (${data.market.days}일간${facilityMonth(state) ? ' · 이번 달은 시설 기물 설치 가능' : ''})`,
  });
}

export function buyItem(state: GameState, key: string): string | null {
  if (!marketOpen(state)) return '장터가 열려 있지 않다.';
  const slot = state.shop!.stock.find((s) => s.key === key);
  const def = itemDef(key);
  if (!slot || !def || slot.qty <= 0) return '품절이다.';
  if ((state.points ?? 0) < def.price) return '포인트가 부족하다.';
  state.points = (state.points ?? 0) - def.price;
  slot.qty--;
  state.inventory = state.inventory ?? {};
  state.inventory[key] = (state.inventory[key] ?? 0) + 1;
  return null;
}

export function buyFacility(state: GameState, key: string): string | null {
  if (!marketOpen(state) || !facilityMonth(state)) return '시설 기물은 방학·비시즌(1·2·7·8·12월) 장터에서만 설치할 수 있다.';
  const cost = facilityCost(state, key);
  if (cost === null) return '이미 최고 단계다.';
  if ((state.points ?? 0) < cost) return '포인트가 부족하다.';
  state.points = (state.points ?? 0) - cost;
  state.facilities = { ...(state.facilities ?? {}), [key]: facLevel(state.facilities, key) + 1 };
  const f = FACILITIES.find((x) => x.key === key)!;
  state.news.push({ date: state.date, kind: 'good', text: `${f.name} Lv${state.facilities[key]} 설치! (-${cost}P)` });
  return null;
}

// ───────────── 아이템 사용 ─────────────

/** 금특으로 진화할 수 있는 긍정 능력 → 금특 */
function goldTargets(p: Player): string[] {
  return p.abilities.map(goldOf).filter((g): g is string => !!g && !cannotLearn(p, g));
}

/** 이 선수에게 쓸 수 있는가 (쓸 수 없으면 이유) */
export function cannotUse(def: ItemDef, p: Player): string | null {
  const isP = p.pos === 'P';
  switch (def.type) {
    case 'stat':
      if (def.pitcher && !isP) return '투수 전용';
      if (def.stat === 'velo' && p.r.velo >= 158) return '더 오를 수 없음';
      return null;
    case 'ability':
      return cannotLearn(p, def.ability!);
    case 'gold':
      return goldTargets(p).length ? null : '진화할 능력이 없음';
    case 'fix':
      return p.abilities.some(isBad) ? null : '고칠 버릇이 없음';
    case 'heal':
      return p.injury > 0 ? null : '부상이 없음';
    case 'idol':
      return p.idolId ? null : '동경하는 선수가 없음';
    case 'cond':
      return null;
  }
  return null;
}

/** 대상이 선수 한 명인 아이템인가 */
export function needsPlayer(def: ItemDef): boolean {
  return ['stat', 'ability', 'gold', 'fix', 'heal', 'idol', 'cond'].includes(def.type);
}

/** 아이템 사용. 성공 시 결과 문구, 실패 시 null 과 이유 */
export function useItem(state: GameState, key: string, targetId: string | null, rng: Rng): { ok: boolean; msg: string } {
  const def = itemDef(key);
  const have = state.inventory?.[key] ?? 0;
  if (!def || have <= 0) return { ok: false, msg: '가지고 있지 않다.' };
  let msg = '';
  if (needsPlayer(def)) {
    const p = targetId ? state.players[targetId] : undefined;
    if (!p || p.teamId !== state.userTeamId) return { ok: false, msg: '대상 선수를 고르세요.' };
    const why = cannotUse(def, p);
    if (why) return { ok: false, msg: why };
    const n = name(p);
    switch (def.type) {
      case 'stat': {
        const k = def.stat as StatKey;
        if (k === 'velo') { p.r.velo += def.amount!; p.cap.velo = Math.max(p.cap.velo, p.r.velo); }
        else if (k === 'breaking') {
          const br = p.r.pitches.filter((x) => x.type !== 'FB' && x.lv < 7).sort((a, b) => a.lv - b.lv);
          if (br.length) br[0].lv++;
          else {
            const pool = (['SL', 'CB', 'CH', 'FK', 'SI', 'CT'] as PitchType[]).filter((t) => !p.r.pitches.some((x) => x.type === t));
            if (pool.length) p.r.pitches.push({ type: rng.pick(pool), lv: 1 });
          }
        } else {
          const cur = p.r[k as keyof typeof p.r] as number;
          (p.r[k as keyof typeof p.r] as number) = Math.min(99, cur + def.amount!);
          p.cap[k] = Math.max(p.cap[k], p.r[k as keyof typeof p.r] as number);
        }
        msg = `${josa(n, '은/는')} ${def.name}(으)로 한층 성장했다!`;
        break;
      }
      case 'ability': {
        const removed = learnAbility(p, def.ability!).filter(isBad);
        msg = `${josa(n, '은/는')} ${def.name}을 독파하고 「${abilityName(def.ability!)}」을(를) 익혔다!${removed.length ? ` (「${abilityName(removed[0])}」 극복)` : ''}`;
        break;
      }
      case 'gold': {
        const g = rng.pick(goldTargets(p));
        const old = learnAbility(p, g).find((x) => !isBad(x)) ?? '';
        msg = `${n}의 「${abilityName(old)}」이(가) 금특 「${abilityName(g)}」(으)로 진화했다!`;
        break;
      }
      case 'fix': {
        const b = rng.pick(p.abilities.filter(isBad));
        p.abilities = p.abilities.filter((a) => a !== b);
        msg = `${n}의 나쁜 버릇 「${abilityName(b)}」이(가) 고쳐졌다.`;
        break;
      }
      case 'heal':
        p.injury = Math.max(0, p.injury - def.amount!);
        msg = `${n}의 부상이 빨리 나아지고 있다. (남은 기간 ${p.injury}일)`;
        break;
      case 'idol':
        p.idolBond = clamp(p.idolBond + def.amount!, 0, 100);
        msg = `${josa(n, '은/는')} 사인볼을 품에 안고 잠들었다. (동경도 ${p.idolBond})`;
        {
          const pop = checkIdolMilestones(state, p, rng);
          if (pop) state.popups.push(pop);
        }
        break;
      case 'cond':
        p.cond = 2;
        msg = `${n}, 부적 덕분인지 몸이 가볍다! (절호조)`;
        break;
    }
  } else {
    const roster = Object.values(state.players).filter((p) => p.teamId === state.userTeamId);
    switch (def.type) {
      case 'teamFatigue':
        for (const p of roster) p.fatigue = Math.max(0, p.fatigue - def.amount!);
        msg = '선수단 전원의 피로가 풀렸다.';
        break;
      case 'teamCond':
        for (const p of roster) p.cond = Math.min(2, p.cond + 1);
        msg = '보양식으로 선수단 전원의 기운이 넘친다!';
        break;
      case 'prospect': {
        const pr = targetId ? state.prospects.find((x) => x.id === targetId) : undefined;
        if (!pr) return { ok: false, msg: state.prospects.length ? '유망주를 고르세요.' : '지금은 유망주 명단이 없다. (9월 드래프트 이후)' };
        pr.interest = clamp(pr.interest + def.amount!, 0, 100);
        msg = `${josa(name(pr.player), '에게')} 추천서를 보냈다. (입학 의향 ${pr.interest}%)`;
        break;
      }
      case 'cards':
        state.hand = state.hand.map((c) => ({ ...c, value: Math.max(3, c.value), age: 0 }));
        msg = '훈련 카드가 모두 좋은 카드로 바뀌었다!';
        break;
    }
  }
  state.inventory![key] = have - 1;
  if (state.inventory![key] <= 0) delete state.inventory![key];
  state.news.push({ date: state.date, kind: 'good', text: msg });
  return { ok: true, msg };
}
