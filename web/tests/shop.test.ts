import { describe, expect, it } from 'vitest';
import { advance, autoPlayUserMatch, rngOf, startNewGame, useCard } from '../src/core/season';
import { buyFacility, buyItem, cannotUse, itemDef, marketOpen, openMarket, slotPrice, useItem } from '../src/core/shop';
import { Rng } from '../src/core/rng';
import { teamPlayers } from '../src/core/world';
import type { GameState } from '../src/core/types';

function playUntil(state: GameState, until: string) {
  while (state.date < until) {
    const r = advance(state);
    if (r === 'training') useCard(state, state.hand[0].id);
    else if (r === 'match') autoPlayUserMatch(state);
    else state.popups.splice(0);
  }
}

describe('포인트 · 장터', () => {
  it('경기 결과로 포인트를 얻고, 매월 1일 장터가 열린다', () => {
    const s = startNewGame({ schoolName: '한빛고', managerName: 't', groupId: 'seoulA', seed: 21 });
    expect(s.points).toBe(100);
    expect(s.pros.some((p) => p.sur + p.given === '김도영')).toBe(true); // 실명 명단
    playUntil(s, '2026-04-02');
    expect(s.points!).toBeGreaterThan(100);
    expect(marketOpen(s)).toBe(true);
    expect(s.shop!.stock.length).toBe(7);
    playUntil(s, '2026-04-09');
    expect(marketOpen(s)).toBe(false);
    expect(buyItem(s, s.shop!.stock[0].key)).toBe('장터가 열려 있지 않다.');
  }, 60000);

  it('아이템을 사서 선수에게 쓴다', () => {
    const s = startNewGame({ schoolName: '한빛고', managerName: 't', groupId: 'seoulA', seed: 22 });
    playUntil(s, '2026-04-02');
    s.points = 2000;
    s.shop!.stock = [{ key: 'protein', qty: 2 }, { key: 'bk_power', qty: 1 }, { key: 'video', qty: 1 }];
    expect(buyItem(s, 'protein')).toBeNull();
    expect(buyItem(s, 'protein')).toBeNull();
    expect(buyItem(s, 'bk_power')).toBeNull();
    expect(buyItem(s, 'video')).toBeNull();
    expect(buyItem(s, 'bk_power')).toBe('품절이다.');
    const rng = rngOf(s);
    const batter = teamPlayers(s, 'user').find((p) => p.pos !== 'P' && !p.abilities.includes('powerHitter'))!;
    const pitcher = teamPlayers(s, 'user').find((p) => p.pos === 'P')!;
    const pow = batter.r.power;
    expect(useItem(s, 'protein', batter.id, rng).ok).toBe(true);
    expect(batter.r.power).toBe(Math.min(99, pow + 3));
    expect(useItem(s, 'bk_power', batter.id, rng).ok).toBe(true);
    expect(batter.abilities).toContain('powerHitter');
    // 투수 전용 아이템은 타자에게 쓸 수 없다
    expect(cannotUse(itemDef('video')!, batter)).toBe('투수 전용');
    const ctl = pitcher.r.control;
    expect(useItem(s, 'video', pitcher.id, rng).ok).toBe(true);
    expect(pitcher.r.control).toBe(Math.min(99, ctl + 3));
    expect(s.inventory!.protein).toBe(1);
  }, 60000);

  it('시설 기물은 방학·비시즌 달 장터에서만 설치', () => {
    const s = startNewGame({ schoolName: '한빛고', managerName: 't', groupId: 'seoulA', seed: 23 });
    playUntil(s, '2026-04-02');
    s.points = 5000;
    expect(buyFacility(s, 'weight')).toContain('방학');
    playUntil(s, '2026-07-02');
    expect(buyFacility(s, 'weight')).toBeNull();
    expect(s.facilities!.weight).toBe(1);
  }, 60000);

  it('가상 선수 명단 선택', () => {
    const s = startNewGame({ schoolName: '한빛고', managerName: 't', groupId: 'seoulA', seed: 24, prosMode: 'fictional' });
    expect(s.pros.some((p) => p.sur + p.given === '강도윤')).toBe(true);
  });

  it('시기 한정 상품 · 연말 대바겐 · 복주머니', () => {
    const s = startNewGame({ schoolName: '한빛고', managerName: 't', groupId: 'seoulA', seed: 23 });
    const keys = () => s.shop!.stock.map((x) => x.key);
    s.date = '2026-04-01';
    openMarket(s, new Rng(1));
    expect(keys().some((k) => ['icevest', 'samgyetang', 'luckybag'].includes(k))).toBe(false);
    expect(s.shop!.stock.length).toBe(7);
    s.date = '2026-06-01';
    openMarket(s, new Rng(1));
    expect(keys()).toContain('icevest');
    expect(keys()).toContain('samgyetang');
    expect(s.shop!.stock.length).toBe(9);
    s.date = '2026-12-01';
    openMarket(s, new Rng(1));
    expect(keys()).toContain('luckybag');
    expect(s.shop!.stock.length).toBe(10);
    const bag = s.shop!.stock.find((x) => x.key === 'luckybag')!;
    expect(slotPrice(bag)).toBe(55); // 80P 의 30% 할인 (5P 단위)
    s.points = 55;
    expect(buyItem(s, 'luckybag')).toBeNull();
    expect(s.points).toBe(0);
    const r = useItem(s, 'luckybag', null, new Rng(2));
    expect(r.ok).toBe(true);
    const n = Object.values(s.inventory!).reduce((a, b) => a + b, 0);
    expect(n).toBe(2);
    expect(s.inventory!.luckybag).toBeUndefined();
  });
});
