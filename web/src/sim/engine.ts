import { PITCH_KO, POS_KO, emptyBat, emptyPit } from '../core/player';
import { clamp, type Rng } from '../core/rng';
import type { LinePos, PitchType, Pos } from '../core/types';
import type {
  BattedType, BoxEntry, MatchRules, Orders, PitchEvent, PlayResult, Runner, SideInput, SideState, SimPlayer,
} from './types';
import { DEFAULT_RULES } from './types';

// ─────────────────────────────────────────────────────────────
// 투구 단위 야구 시뮬레이션 엔진.
// 한 번의 step() 호출 = 공 하나. 결과는 PitchEvent 로 돌려주며 UI 는 이것으로 애니메이션을 만든다.
// 확률 상수는 고교 야구(나무배트) 기록 수준에 맞춰 tests/balance.test.ts 로 튜닝했다.
// ─────────────────────────────────────────────────────────────

function makeSide(input: SideInput): SideState {
  const byId: Record<string, SimPlayer> = {};
  for (const p of input.players) byId[p.id] = p;
  const box: Record<string, BoxEntry> = {};
  const posOf: Record<string, LinePos> = {};
  for (const s of input.lineup) posOf[s.playerId] = s.pos;
  posOf[input.pitcherId] = 'P';
  const used = [...input.lineup.map((s) => s.playerId), input.pitcherId];
  for (const id of used) box[id] = { bat: emptyBat(), pit: emptyPit() };
  for (const s of input.lineup) box[s.playerId].bat.g = 1;
  box[input.pitcherId].pit.g = 1;
  box[input.pitcherId].pit.gs = 1;
  return {
    input,
    byId,
    order: input.lineup.map((s) => s.playerId),
    posOf,
    batterIdx: 0,
    pitcherId: input.pitcherId,
    used,
    pitchers: [input.pitcherId],
    pitchCount: { [input.pitcherId]: 0 },
    score: 0,
    hits: 0,
    errors: 0,
    line: [],
    box,
    visits: 0,
    visitPa: 0,
    leadAny: input.players.some((p) => p.fx.flat.lead > 0),
  };
}

/** 특수능력 수치 합 (조건을 만족하는 효과만) */
type Mods = Record<string, number>;
const NO_MODS: Mods = {};

const DIR_SINGLE = (a: number) => (a < -14 ? '좌전' : a > 14 ? '우전' : '중전');
const DIR_XBH = (a: number) => (a < -33 ? '좌익선상' : a < -10 ? '좌중간' : a > 33 ? '우익선상' : a > 10 ? '우중간' : '중견수 키를 넘기는');
const DIR_HR = (a: number) => (a < -14 ? '좌월' : a > 14 ? '우월' : '중월');
const POS_NAME = (p: Pos) => POS_KO[p];

export class Match {
  rng: Rng;
  rules: MatchRules;
  home: SideState;
  away: SideState;
  inning = 1;
  top = true;
  outs = 0;
  balls = 0;
  strikes = 0;
  bases: (Runner | null)[] = [null, null, null];
  over = false;
  winner: string | null = null;
  called = false;
  /** 투수 기록 판정용 */
  private pW: string | null = null;
  private pL: string | null = null;
  private leader: 'home' | 'away' | null = null;
  /** 한 경기 텍스트 로그 */
  log: string[] = [];
  pitchNo = 0;

  constructor(home: SideInput, away: SideInput, rng: Rng, rules: MatchRules = DEFAULT_RULES) {
    this.rng = rng;
    this.rules = rules;
    this.home = makeSide(home);
    this.away = makeSide(away);
  }

  get off(): SideState {
    return this.top ? this.away : this.home;
  }
  get def(): SideState {
    return this.top ? this.home : this.away;
  }
  batter(): SimPlayer {
    const o = this.off;
    return o.byId[o.order[o.batterIdx]];
  }
  pitcher(): SimPlayer {
    return this.def.byId[this.def.pitcherId];
  }
  fielder(pos: Pos, side: SideState = this.def): SimPlayer {
    if (pos === 'P') return side.byId[side.pitcherId];
    const id = Object.keys(side.posOf).find((k) => side.posOf[k] === pos && k !== side.pitcherId && side.order.includes(k));
    return side.byId[id ?? side.pitcherId];
  }
  /** 수비 위치 적성을 반영한 수비력 */
  defValue(pos: Pos): number {
    const f = this.fielder(pos);
    const apt = f.pos === pos ? 1 : f.sub.includes(pos) ? 0.88 : pos === '1B' ? 0.82 : 0.7;
    let v = f.fld * apt;
    if (['LF', 'CF', 'RF'].includes(pos)) v = v * 0.7 + f.spd * 0.3 * apt;
    return v + f.fx.flat.fld;
  }
  pitchCountOf(id: string): number {
    return this.def.pitchCount[id] ?? this.home.pitchCount[id] ?? this.away.pitchCount[id] ?? 0;
  }
  sideOf(teamId: string): SideState {
    return this.home.input.teamId === teamId ? this.home : this.away;
  }
  scoreDiffFor(side: SideState): number {
    const other = side === this.home ? this.away : this.home;
    return side.score - other.score;
  }
  risp(): boolean {
    return !!(this.bases[1] || this.bases[2]);
  }
  lateClose(): boolean {
    return this.inning >= 7 && Math.abs(this.home.score - this.away.score) <= 2;
  }

  /** 특수능력 발동 조건. oppHand: 상대 투수의 투구 손(타자일 때)/상대 타자의 타석(투수일 때), diff: 우리 팀 점수 차 */
  private cond(c: string, oppHand: string, diff: number): boolean {
    switch (c) {
      case 'always': return true;
      case 'risp': return this.risp();
      case 'lateClose': return this.lateClose();
      case 'late': return this.inning >= 7;
      case 'early': return this.inning <= 2;
      case 'twoStrikes': return this.strikes === 2;
      case 'firstPitch': return this.balls === 0 && this.strikes === 0;
      case 'runnersOn': return !!(this.bases[0] || this.bases[1] || this.bases[2]);
      case 'basesLoaded': return !!(this.bases[0] && this.bases[1] && this.bases[2]);
      case 'leadoff': return this.outs === 0 && !this.bases[0] && !this.bases[1] && !this.bases[2];
      case 'twoOuts': return this.outs === 2;
      case 'vsL': return oppHand === 'L';
      case 'ahead': return diff > 0;
      case 'behindLate': return diff < 0 && this.inning >= 7;
    }
    return false;
  }

  private sumFx(list: { c: string; m: Mods }[], oppHand: string, diff: number): Mods {
    if (!list.length) return NO_MODS;
    let out: Mods | null = null;
    for (const e of list) {
      if (!this.cond(e.c, oppHand, diff)) continue;
      out ??= {};
      for (const k in e.m) out[k] = (out[k] ?? 0) + e.m[k];
    }
    return out ?? NO_MODS;
  }

  /** 현재 타자의 특수능력 효과 */
  batMods(b: SimPlayer = this.batter()): Mods {
    return this.sumFx(b.fx.bat, this.pitcher().throws, this.scoreDiffFor(this.off));
  }

  /** 투수의 특수능력 효과 (현재 타자 상대) */
  pitMods(p: SimPlayer, side: SideState = this.def): Mods {
    return this.sumFx(p.fx.pit, this.batter().bats, this.scoreDiffFor(side));
  }

  /** 투수의 현재(피로·특수능력 반영) 능력 */
  pitcherEff(p: SimPlayer, side: SideState, pm: Mods = this.pitMods(p, side)): { velo: number; ctl: number; stuff: number; tired: number } {
    const np = side.pitchCount[p.id] ?? 0;
    const pool = 40 + p.sta * 0.85 * (1 + (pm.sta ?? 0));
    const over = Math.max(0, np - pool);
    let velo = p.velo - over * 0.12 + (pm.velo ?? 0);
    let ctl = p.ctl - over * 0.45 + (pm.ctl ?? 0);
    let stuff = p.stuff - over * 0.3 + (pm.stuff ?? 0);
    if (side.leadAny) {
      const lead = this.fielder('C', side).fx.flat.lead;
      ctl += lead;
      stuff += lead;
    }
    if (side.visitPa > 0) ctl += 8;
    return { velo, ctl, stuff, tired: over };
  }

  /** 투수 교체 */
  changePitcher(side: SideState, id: string) {
    if (side.pitcherId === id) return;
    if (!side.byId[id] || side.used.includes(id)) return;
    side.pitcherId = id;
    side.used.push(id);
    side.pitchers.push(id);
    side.pitchCount[id] = 0;
    side.posOf[id] = 'P';
    side.box[id] = side.box[id] ?? { bat: emptyBat(), pit: emptyPit() };
    side.box[id].pit.g = 1;
    this.log.push(`[투수 교체] ${side.input.name}: ${side.byId[id].name}`);
  }

  /** 마운드 방문: 한 경기 3번까지, 다음 두 타자 동안 제구 +8 */
  moundVisit(side: SideState): boolean {
    if (side.visits >= Match.MAX_VISITS) return false;
    side.visits++;
    side.visitPa = 2;
    this.log.push(`[마운드 방문] ${side.input.name} (${side.visits}/${Match.MAX_VISITS})`);
    return true;
  }

  static readonly MAX_VISITS = 3;

  /** 대타: 현재 타자를 교체하고 수비 위치를 물려받는다 */
  pinchHit(side: SideState, id: string) {
    if (side !== this.off || !side.byId[id] || side.used.includes(id)) return;
    const old = side.order[side.batterIdx];
    side.order[side.batterIdx] = id;
    side.posOf[id] = side.posOf[old];
    delete side.posOf[old];
    side.used.push(id);
    side.box[id] = side.box[id] ?? { bat: emptyBat(), pit: emptyPit() };
    side.box[id].bat.g = 1;
    this.log.push(`[대타] ${side.byId[old].name} → ${side.byId[id].name}`);
  }

  /** 대주자 */
  pinchRun(side: SideState, base: number, id: string) {
    const r = this.bases[base];
    if (!r || side !== this.off || !side.byId[id] || side.used.includes(id)) return;
    const idx = side.order.indexOf(r.id);
    if (idx < 0) return;
    side.order[idx] = id;
    side.posOf[id] = side.posOf[r.id];
    delete side.posOf[r.id];
    side.used.push(id);
    side.box[id] = side.box[id] ?? { bat: emptyBat(), pit: emptyPit() };
    side.box[id].bat.g = 1;
    this.log.push(`[대주자] ${side.byId[r.id].name} → ${side.byId[id].name}`);
    this.bases[base] = { ...r, id };
  }

  /** 수비 교체 (벤치 선수를 지정 위치에 투입) */
  defSub(side: SideState, outId: string, inId: string) {
    const idx = side.order.indexOf(outId);
    if (idx < 0 || !side.byId[inId] || side.used.includes(inId)) return;
    side.order[idx] = inId;
    side.posOf[inId] = side.posOf[outId];
    delete side.posOf[outId];
    side.used.push(inId);
    side.box[inId] = side.box[inId] ?? { bat: emptyBat(), pit: emptyPit() };
    side.box[inId].bat.g = 1;
    this.log.push(`[수비 교체] ${side.byId[outId].name} → ${side.byId[inId].name}`);
  }

  // ───────────────────────── 핵심: 공 하나 ─────────────────────────

  step(orders: Orders = {}): PitchEvent {
    if (this.over) throw new Error('game over');
    const rng = this.rng;
    const off = this.off;
    const def = this.def;
    const b = this.batter();
    const p = this.pitcher();
    const ev: PitchEvent = {
      inning: this.inning, top: this.top, pitcherId: p.id, batterId: b.id, pitchType: 'FB', kmh: 0,
      loc: { x: 0, y: 0 }, call: 'ball', moves: [], runs: 0, text: '', endHalf: false, gameOver: false,
    };
    const offOrder = orders.off ?? 'normal';
    const shift = orders.shift ?? 'normal';

    // 고의사구
    if (orders.pitch === 'ibb') {
      ev.call = 'ibb';
      ev.loc = { x: 2.2, y: 0 };
      this.walk(ev, '고의사구');
      ev.text = `${b.name}, 고의사구로 출루`;
      return this.finish(ev);
    }

    this.pitchNo++;
    def.pitchCount[p.id] = (def.pitchCount[p.id] ?? 0) + 1;
    def.box[p.id].pit.np++;

    const pm = this.pitMods(p, def);
    const bm = this.batMods(b);
    const eff = this.pitcherEff(p, def, pm);
    // 구종 선택
    const breaking = p.pitches.filter((x) => x.type !== 'FB');
    let pt: PitchType = 'FB';
    let lv = 0;
    const fbRate = clamp(0.64 - breaking.length * 0.06 + (this.balls >= 3 ? 0.15 : 0), 0.35, 0.95);
    if (breaking.length && !rng.chance(fbRate)) {
      const c = rng.weighted(breaking, breaking.map((x) => x.lv + 1));
      pt = c.type;
      lv = c.lv;
    }
    const isBreaking = pt !== 'FB';
    const speedMul: Record<PitchType, number> = { FB: 1, SL: 0.9, CB: 0.82, CH: 0.86, FK: 0.88, SI: 0.97, CT: 0.95 };
    ev.pitchType = pt;
    ev.kmh = Math.round(eff.velo * speedMul[pt] + rng.gauss() * 1.5);

    // 구위: 타자가 공략하기 어려운 정도
    let pp = isBreaking ? lv * 5.5 + (eff.velo - 115) * 0.55 + 5 : (eff.velo - 115) * 1.2;
    pp += isBreaking ? (pm.ppBR ?? 0) : (pm.ppFB ?? 0);
    pp += (eff.stuff - 40) * 0.08;

    // 제구: 존 안에 던질 의도
    let wantZone = 0.56;
    if (this.balls === 3) wantZone += 0.25;
    else if (this.balls === 2) wantZone += 0.08;
    if (this.strikes === 2 && this.balls < 2) wantZone -= 0.2;
    if (orders.pitch === 'zone') wantZone += 0.22;
    if (orders.pitch === 'edge') wantZone -= 0.22;
    const bunting = offOrder === 'bunt' || offOrder === 'squeeze' || offOrder === 'safetyBunt';
    if (bunting) wantZone -= 0.06;
    wantZone += pm.zone ?? 0;
    let ctl = eff.ctl;
    if (pm.wild && rng.chance(pm.wild)) ctl -= 30;
    const intendZone = rng.chance(clamp(wantZone, 0.1, 0.95));
    let inZone: boolean;
    let mistake = false;
    if (intendZone) {
      inZone = rng.chance(clamp(0.7 + ctl * 0.0026 - (isBreaking ? 0.05 : 0), 0.55, 0.97));
      if (inZone) mistake = rng.chance(clamp(0.13 - ctl * 0.0011 + (pm.mistake ?? 0), 0.01, 0.2));
    } else {
      inZone = !rng.chance(clamp(0.8 + ctl * 0.0015, 0.75, 0.97));
      if (inZone) mistake = rng.chance(0.4);
    }
    ev.loc = inZone
      ? { x: rng.range(-0.9, 0.9), y: rng.range(-0.9, 0.9) }
      : (() => {
          const side = rng.int(0, 3);
          const d = rng.range(1.1, 1.8);
          const t = rng.range(-1.2, 1.2);
          return side === 0 ? { x: d, y: t } : side === 1 ? { x: -d, y: t } : side === 2 ? { x: t, y: d } : { x: t, y: -d };
        })();
    if (mistake) ev.loc = { x: rng.range(-0.4, 0.4), y: rng.range(-0.3, 0.3) };

    // 사구
    if (!inZone && rng.chance(0.012 + (ctl < 40 ? 0.008 : 0))) {
      ev.call = 'hbp';
      this.walk(ev, '몸에 맞는 공', true);
      ev.text = `${b.name}, 몸에 맞는 공으로 출루`;
      return this.finish(ev);
    }

    // 도루/히트앤런/스퀴즈 주자 출발
    let stealer: { base: number; r: Runner } | null = null;
    if (offOrder === 'steal' || offOrder === 'hitRun') {
      if (this.bases[1] && !this.bases[2]) stealer = { base: 1, r: this.bases[1] };
      else if (this.bases[0] && !this.bases[1]) stealer = { base: 0, r: this.bases[0] };
    }
    const squeezeRunner = offOrder === 'squeeze' && this.bases[2] ? this.bases[2] : null;

    // ── 번트 ──
    if (bunting) {
      return this.resolveBunt(ev, b, bm, pp, inZone, offOrder, shift, squeezeRunner);
    }

    // ── 타격 판단 ──
    let swingP: number;
    if (inZone) {
      swingP = 0.63 + (this.strikes === 0 ? -0.08 : 0) + (this.strikes === 2 ? 0.22 : 0);
      if (this.balls === 3 && this.strikes === 0) swingP = 0.15;
    } else {
      swingP = 0.34 - (b.eye + (bm.eye ?? 0)) * 0.0028 + (this.strikes === 2 ? 0.12 : 0) + (isBreaking ? 0.06 : 0);
      if (this.balls === 3 && this.strikes < 2) swingP *= 0.4;
    }
    if (offOrder === 'wait') swingP = this.strikes === 0 ? 0.03 : swingP;
    if (offOrder === 'aggressive') swingP += 0.15;
    if (offOrder === 'hitRun') swingP = inZone ? 0.95 : 0.7;
    if (mistake) swingP += 0.12;
    swingP += bm.swing ?? 0;
    const swing = rng.chance(clamp(swingP, 0.01, 0.98));

    if (!swing) {
      if (inZone) {
        this.strikes++;
        ev.call = 'called';
      } else {
        this.balls++;
        ev.call = 'ball';
      }
    } else {
      const con = b.con + (bm.con ?? 0);
      const pow = b.pow + (bm.pow ?? 0);
      const platoon = b.bats === 'S' ? 0.01 : b.bats === p.throws ? -0.015 : 0.015;
      let contactP = 0.87 + (con - 50) * 0.0045 - (pp - 28) * 0.0062 + platoon - (inZone ? 0 : 0.22) + (mistake ? 0.08 : 0);
      contactP += (bm.contact ?? 0) - (pm.whiff ?? 0);
      if (offOrder === 'hitRun') contactP += 0.05;
      const contact = rng.chance(clamp(contactP, 0.3, 0.97));
      if (!contact) {
        this.strikes++;
        ev.call = 'swinging';
      } else {
        const foulP = (inZone ? 0.4 : 0.55) + (bm.foul ?? 0);
        if (rng.chance(foulP)) {
          ev.call = 'foul';
          if (this.strikes < 2) this.strikes++;
        } else {
          ev.call = 'inplay';
          this.resolveInPlay(ev, b, pow, pp, inZone, mistake, shift, stealer, bm, pm);
          return this.finish(ev);
        }
      }
    }

    // 폭투/포일
    if (this.bases.some(Boolean) && ev.call !== 'foul') {
      const catcher = this.fielder('C');
      const wpP = (0.007 + Math.max(0, 55 - ctl) * 0.00025 + Math.max(0, 50 - catcher.fld) * 0.0002 + (isBreaking ? 0.004 : 0)) * (1 - catcher.fx.flat.block);
      if (rng.chance(wpP)) {
        ev.wildPitch = true;
        this.advanceAll(ev, 1, false);
        ev.text = `폭투! 주자 진루`;
        stealer = null;
      }
    }

    // 삼진/볼넷
    if (this.strikes >= 3) {
      const bl = off.box[b.id].bat;
      bl.pa++; bl.ab++; bl.so++;
      def.box[p.id].pit.so++;
      this.addOut(ev, b.id, 0);
      ev.paResult = ev.call === 'called' ? '루킹 삼진' : '헛스윙 삼진';
      if (stealer && !this.halfOver()) this.resolveSteal(ev, stealer);
      ev.text = this.pitchText(ev) + ` — ${ev.paResult}!`;
      return this.finish(ev, true);
    }
    if (this.balls >= 4) {
      this.walk(ev, '볼넷');
      ev.text = this.pitchText(ev) + ' — 볼넷';
      return this.finish(ev);
    }
    if (stealer && ev.call !== 'foul') this.resolveSteal(ev, stealer);
    if (!ev.text) ev.text = this.pitchText(ev);
    return this.finish(ev, false);
  }

  private pitchText(ev: PitchEvent): string {
    const c: Record<PitchEvent['call'], string> = {
      ball: '볼', called: '스트라이크', swinging: '헛스윙', foul: '파울', inplay: '타격', hbp: '사구', ibb: '고의사구',
      buntFoul: '번트 파울', buntMiss: '번트 헛스윙',
    };
    return `${ev.kmh}km ${PITCH_KO[ev.pitchType]} ${c[ev.call]}`;
  }

  // ───────────────────────── 번트 ─────────────────────────

  private resolveBunt(
    ev: PitchEvent, b: SimPlayer, bm: Mods, pp: number, inZone: boolean,
    order: 'bunt' | 'squeeze' | 'safetyBunt', shift: string, squeezeRunner: Runner | null,
  ): PitchEvent {
    const rng = this.rng;
    const off = this.off;
    const def = this.def;
    // 볼이면 대부분 배트를 거둔다 (스퀴즈는 무조건 댄다)
    if (!inZone && order !== 'squeeze' && rng.chance(0.75)) {
      this.balls++;
      ev.call = 'ball';
      if (this.balls >= 4) {
        this.walk(ev, '볼넷');
        ev.text = this.pitchText(ev) + ' — 볼넷';
        return this.finish(ev);
      }
      ev.text = this.pitchText(ev) + ' (번트 자세에서 배트를 거둠)';
      return this.finish(ev, false);
    }
    let good = 0.6 + (b.con - 50) * 0.004 - (pp - 28) * 0.004 + (bm.bunt ?? 0) - (inZone ? 0 : 0.15);
    if (shift === 'buntShift') good -= 0.12;
    const roll = rng.next();
    if (roll < 0.1 + (1 - good) * 0.1) {
      // 헛스윙
      ev.call = 'buntMiss';
      this.strikes++;
      if (squeezeRunner) {
        // 스퀴즈 실패 — 3루 주자 협살
        this.bases[2] = null;
        ev.moves.push({ runnerId: squeezeRunner.id, from: 3, to: -1 });
        this.outs++;
        ev.text = '스퀴즈 실패! 3루 주자 협살';
      }
      if (this.strikes >= 3) {
        const bl = off.box[b.id].bat;
        bl.pa++; bl.ab++; bl.so++;
        def.box[this.pitcher().id].pit.so++;
        this.addOut(ev, b.id, 0);
        ev.paResult = '번트 헛스윙 삼진';
        ev.text = (ev.text ? ev.text + ' / ' : '') + '번트 헛스윙 삼진';
        return this.finish(ev, true);
      }
      ev.text = ev.text || '번트 헛스윙';
      return this.finish(ev, false);
    }
    if (roll < 0.1 + (1 - good) * 0.55 && order !== 'squeeze') {
      // 파울
      ev.call = 'buntFoul';
      if (this.strikes === 2) {
        this.strikes = 3;
        const bl = off.box[b.id].bat;
        bl.pa++; bl.ab++; bl.so++;
        def.box[this.pitcher().id].pit.so++;
        this.addOut(ev, b.id, 0);
        ev.paResult = '스리번트 실패 (삼진)';
        ev.text = '번트 파울 — 스리번트 실패, 삼진';
        return this.finish(ev, true);
      }
      this.strikes++;
      ev.text = '번트 파울';
      return this.finish(ev, false);
    }
    ev.call = 'inplay';
    const angle = rng.range(-25, 25);
    const fielder: Pos = angle < -10 ? '3B' : angle > 10 ? '1B' : rng.chance(0.5) ? 'P' : 'C';
    const bl = off.box[b.id].bat;
    const success = rng.next() < good;
    if (order === 'safetyBunt' && success) {
      const hitP = 0.2 + (b.spd - 50) * 0.009 + (bm.buntHit ?? 0) - (shift === 'buntShift' ? 0.1 : 0);
      if (rng.chance(hitP)) {
        ev.batted = { type: 'BUNT', angle, dist: 12, result: '1B', fielder, caught: false };
        bl.pa++; bl.ab++; bl.h++;
        off.hits++;
        this.def.box[this.pitcher().id].pit.h++;
        this.advanceForced(ev, b.id, false, true);
        ev.paResult = '기습번트 안타';
        ev.text = '기습번트! 내야 안타';
        return this.finish(ev, true);
      }
    }
    if (success) {
      ev.batted = { type: 'BUNT', angle, dist: 12, result: 'SAC', fielder, caught: false };
      bl.pa++; bl.sh++;
      // 주자 1개씩 진루, 타자 아웃
      const hadRunners = this.bases.some(Boolean);
      this.advanceAll(ev, 1, true, b.id);
      this.addOut(ev, b.id, 0);
      if (!hadRunners) { bl.sh--; bl.ab++; }
      ev.paResult = squeezeRunner ? '스퀴즈 성공' : hadRunners ? '희생번트 성공' : '번트 아웃';
      ev.text = ev.paResult + (squeezeRunner ? '! 3루 주자 홈인' : '');
      return this.finish(ev, true);
    }
    // 실패: 뜬공 or 선행주자 아웃
    bl.pa++; bl.ab++;
    if (rng.chance(0.35)) {
      ev.batted = { type: 'PU', angle, dist: 15, result: 'OUT', fielder, caught: true };
      this.addOut(ev, b.id, 0);
      ev.paResult = '번트 뜬공';
      ev.text = '번트가 떴다 — 뜬공 아웃';
      if (squeezeRunner && !this.halfOver()) {
        // 스퀴즈 주자 더블아웃
        this.bases[2] = null;
        ev.moves.push({ runnerId: squeezeRunner.id, from: 3, to: -1 });
        this.outs++;
        ev.text += ', 3루 주자까지 더블아웃';
      }
      return this.finish(ev, true);
    }
    // 선행 주자 포스아웃 (야수선택)
    ev.batted = { type: 'BUNT', angle, dist: 12, result: 'FC', fielder, caught: false };
    const lead = [2, 1, 0].find((i) => this.bases[i] && (i === 0 || this.forcedAt(i)));
    if (lead !== undefined) {
      const r = this.bases[lead]!;
      this.bases[lead] = null;
      ev.moves.push({ runnerId: r.id, from: lead + 1, to: -1 });
      this.outs++;
      if (!this.halfOver()) this.advanceForced(ev, b.id, false, false);
      ev.paResult = '번트 실패 (선행주자 아웃)';
      ev.text = '번트 실패! 선행 주자 아웃';
    } else {
      this.addOut(ev, b.id, 0);
      ev.paResult = '번트 아웃';
      ev.text = '번트 아웃';
    }
    return this.finish(ev, true);
  }

  /** i 루 주자가 포스 상태인가 (뒤 루가 모두 차 있음) */
  private forcedAt(i: number): boolean {
    for (let k = 0; k < i; k++) if (!this.bases[k]) return false;
    return true;
  }

  // ───────────────────────── 인플레이 ─────────────────────────

  private resolveInPlay(
    ev: PitchEvent, b: SimPlayer, pow: number, pp: number, inZone: boolean, mistake: boolean, shift: string,
    stealer: { base: number; r: Runner } | null, bm: Mods, pm: Mods,
  ) {
    const rng = this.rng;
    const off = this.off;
    const def = this.def;
    const p = this.pitcher();
    const bl = off.box[b.id].bat;
    const pl = def.box[p.id].pit;

    let evel = 113 + pow * 0.42 + rng.gauss() * 13 - (pp - 28) * 0.35 + (mistake ? 10 : 0) - (inZone ? 0 : 10);
    evel += bm.evel ?? 0;
    // 타구 종류
    let gbW = 0.44 - (pow - 50) * 0.002 + (pm.gbRate ?? 0);
    let fbW = 0.27 + (pow - 50) * 0.002 - (pm.gbRate ?? 0) * 0.6;
    if (ev.pitchType === 'SI' || ev.pitchType === 'FK') { gbW += 0.08; fbW -= 0.05; }
    const type: BattedType = rng.weighted<BattedType>(['GB', 'LD', 'FB', 'PU'], [gbW, 0.21 + (bm.ld ?? 0), fbW, Math.max(0.01, 0.08 + (bm.pu ?? 0))]);
    const pull = b.bats === 'L' ? 1 : b.bats === 'R' ? -1 : p.throws === 'R' ? 1 : -1;
    const angle = clamp(rng.gauss() * 21 + pull * 7, -44, 44);

    let result: PlayResult = 'OUT';
    let fielder: Pos;
    let dist = 0;
    let caught = false;
    const risp3 = this.bases[2];

    if (type === 'GB') {
      fielder = angle < -24 ? '3B' : angle < -7 ? 'SS' : angle < 7 ? (rng.chance(0.15) ? 'P' : angle < 0 ? 'SS' : '2B') : angle < 24 ? '2B' : '1B';
      const dv = this.defValue(fielder);
      let hitP = 0.25 + (evel - 130) * 0.0045 + (b.spd - 50) * 0.0025 - (dv - 50) * 0.0025 + (bm.gbHit ?? 0);
      if (Math.abs(angle) < 7) hitP += 0.06;
      if (shift === 'infieldIn') hitP += 0.08;
      dist = rng.range(28, 40);
      if (rng.chance(clamp(hitP, 0.05, 0.6))) {
        result = Math.abs(angle) > 36 && evel > 140 && rng.chance(0.4) ? '2B' : '1B';
        dist = result === '2B' ? 80 : 55;
      } else if (rng.chance(clamp(0.05 + (55 - dv) * 0.001 + this.fielder(fielder).fx.flat.err, 0.01, 0.14))) {
        result = 'E';
      } else if (this.bases[0] && this.outs < 2 && !(stealer && stealer.base === 0) && rng.chance(clamp(0.42 - (b.spd - 50) * 0.004 + (dv - 50) * 0.003 + (bm.dp ?? 0), 0.05, 0.75))) {
        result = 'DP';
      } else if (this.bases[0] && this.outs < 2 && !(stealer && stealer.base === 0) && rng.chance(0.3)) {
        result = 'FC';
      }
    } else if (type === 'PU') {
      fielder = Math.abs(angle) < 10 && rng.chance(0.3) ? 'C' : angle < -20 ? '3B' : angle < 0 ? 'SS' : angle < 20 ? '2B' : '1B';
      dist = rng.range(10, 35);
      caught = true;
      if (rng.chance(0.02 + this.fielder(fielder).fx.flat.err * 0.5)) { result = 'E'; caught = false; }
    } else {
      // 라인드라이브 / 플라이
      fielder = angle < -15 ? 'LF' : angle > 15 ? 'RF' : 'CF';
      dist = (evel - 55) * 0.95 + rng.gauss() * 6 + (type === 'LD' ? -12 : 0) + (bm.dist ?? 0) + (pm.hrAllow ?? 0);
      if (shift === 'deep') dist -= 0;
      const dv = this.defValue(fielder);
      const fence = 98 + (1 - Math.abs(angle) / 45) * 20;
      if (type === 'LD' && dist < 45) {
        fielder = angle < -24 ? '3B' : angle < 0 ? 'SS' : angle < 24 ? '2B' : '1B';
      }
      if (type === 'FB' && dist > fence) {
        result = 'HR';
      } else if (type === 'LD') {
        let hitP = 0.7 + (evel - 130) * 0.004 - (dv - 50) * 0.002;
        if (shift === 'deep') hitP -= 0.04;
        if (shift === 'infieldIn') hitP += 0.05;
        if (rng.chance(clamp(hitP, 0.35, 0.85))) {
          const gap = Math.abs(angle) > 8 && Math.abs(angle) < 38;
          if (evel > 142 && (gap || rng.chance(0.2)) && rng.chance(0.4)) {
            result = b.spd > 65 && rng.chance(0.14) ? '3B' : '2B';
            dist = Math.max(dist, 85);
          } else result = '1B';
        } else caught = true;
      } else {
        // FB
        let catchP = 0.83 - Math.max(0, dist - 80) * 0.014 + (dv - 50) * 0.003;
        if (dist > 38 && dist < 58) catchP -= 0.28; // 텍사스 안타 구역
        if (shift === 'deep') catchP += dist > 80 ? 0.06 : -0.08;
        if (shift === 'infieldIn') catchP -= 0.04;
        if (rng.chance(clamp(catchP, 0.2, 0.97))) {
          caught = true;
          if (rng.chance(clamp(0.02 + (50 - dv) * 0.0006 + this.fielder(fielder).fx.flat.err, 0.003, 0.08))) { result = 'E'; caught = false; }
        } else if (dist > 88) {
          result = b.spd > 60 && rng.chance(0.25) ? '3B' : '2B';
        } else {
          result = dist > 72 && rng.chance(0.35) ? '2B' : '1B';
        }
      }
      if (caught && result === 'OUT' && this.outs < 2 && risp3 && type === 'FB') {
        const of = this.fielder(fielder);
        const ofArm = of.arm + of.fx.flat.arm;
        const sfP = 0.5 + (dist - 60) * 0.018 + (off.byId[risp3.id].spd - 50) * 0.006 - (ofArm - 50) * 0.005;
        if (dist > 55 && rng.chance(clamp(sfP, 0.05, 0.97))) result = 'SF';
      }
    }

    ev.batted = { type, angle, dist, result, fielder, caught };
    const dirSingle = DIR_SINGLE(angle);

    // 결과 처리
    bl.pa++;
    switch (result) {
      case 'HR': {
        bl.ab++; bl.h++; bl.hr++;
        off.hits++; pl.h++; pl.hr++;
        this.advanceAll(ev, 4, false, b.id);
        this.moveBatter(ev, b.id, 4, true);
        ev.paResult = `${DIR_HR(angle)} ${ev.runs >= 4 ? '만루 홈런' : '홈런'}`;
        ev.text = `${ev.paResult}!! ${b.name}의 한 방!`;
        break;
      }
      case '3B': {
        bl.ab++; bl.h++; bl.d3++;
        off.hits++; pl.h++;
        this.advanceAll(ev, 3, false, b.id);
        this.moveBatter(ev, b.id, 3, true);
        ev.paResult = `${DIR_XBH(angle)} 3루타`;
        ev.text = `${ev.paResult}!`;
        break;
      }
      case '2B': {
        bl.ab++; bl.h++; bl.d2++;
        off.hits++; pl.h++;
        this.advanceHit(ev, 2, b.id, fielder, stealer != null);
        this.moveBatter(ev, b.id, 2, true);
        ev.paResult = `${DIR_XBH(angle)} 2루타`;
        ev.text = `${ev.paResult}!`;
        break;
      }
      case '1B': {
        bl.ab++; bl.h++;
        off.hits++; pl.h++;
        const infield = type === 'GB' && dist < 45;
        this.advanceHit(ev, infield ? 0 : 1, b.id, fielder, stealer != null);
        this.moveBatter(ev, b.id, 1, true);
        ev.paResult = infield ? '내야 안타' : type === 'GB' ? `${dirSingle} 땅볼 안타` : `${dirSingle} 안타`;
        ev.text = ev.paResult + '!';
        break;
      }
      case 'E': {
        bl.ab++;
        def.errors++;
        const f = this.fielder(fielder);
        def.box[f.id] && def.box[f.id].bat.e++;
        this.advanceForced(ev, b.id, false, false);
        ev.paResult = `${POS_NAME(fielder)} 실책`;
        ev.text = `${POS_NAME(fielder)} 실책! 타자 출루`;
        break;
      }
      case 'DP': {
        bl.ab++;
        const r1 = this.bases[0]!;
        this.bases[0] = null;
        ev.moves.push({ runnerId: r1.id, from: 1, to: -1 });
        this.outs++;
        this.addOut(ev, b.id, 0);
        if (!this.halfOver()) this.advanceOthersOnGround(ev, shift, 1);
        ev.paResult = `${POS_NAME(fielder)} 앞 병살타`;
        ev.text = ev.paResult;
        break;
      }
      case 'FC': {
        bl.ab++;
        const r1 = this.bases[0]!;
        this.bases[0] = null;
        ev.moves.push({ runnerId: r1.id, from: 1, to: -1 });
        this.outs++;
        if (!this.halfOver()) {
          this.advanceOthersOnGround(ev, shift, 1);
          this.moveBatter(ev, b.id, 1, false);
        }
        ev.paResult = `${POS_NAME(fielder)} 땅볼 (선행주자 아웃)`;
        ev.text = ev.paResult;
        break;
      }
      case 'SF': {
        bl.sf++;
        this.addOut(ev, b.id, 0);
        const r3 = this.bases[2]!;
        this.bases[2] = null;
        ev.moves.push({ runnerId: r3.id, from: 3, to: 4 });
        this.scoreRunner(ev, r3, b.id, true);
        ev.paResult = `${POS_NAME(fielder)} 희생플라이`;
        ev.text = `${ev.paResult}! 3루 주자 홈인`;
        break;
      }
      default: {
        bl.ab++;
        this.addOut(ev, b.id, 0);
        if (!this.halfOver()) {
          if (type === 'GB') this.advanceOthersOnGround(ev, shift, 0, b.id);
          else if (type === 'FB' && dist > 85 && this.bases[1] && !this.bases[2] && rng.chance(0.5)) {
            const r2 = this.bases[1];
            this.bases[1] = null;
            this.bases[2] = r2;
            ev.moves.push({ runnerId: r2.id, from: 2, to: 3 });
          }
        }
        const kind = type === 'GB' ? '땅볼' : type === 'LD' ? '직선타' : type === 'PU' ? (fielder === 'C' ? '파울플라이' : '뜬공') : '플라이';
        ev.paResult = `${POS_NAME(fielder)} ${kind}`;
        ev.text = ev.paResult;
      }
    }
  }

  // ───────────────────────── 주자 처리 ─────────────────────────

  private scoreRunner(ev: PitchEvent, r: Runner, batterId: string | null, rbi: boolean) {
    const off = this.off;
    const def = this.def;
    off.score++;
    ev.runs++;
    const li = this.inning - 1;
    while (off.line.length <= li) off.line.push(0);
    off.line[li]++;
    off.box[r.id] && off.box[r.id].bat.r++;
    if (rbi && batterId && off.box[batterId]) off.box[batterId].bat.rbi++;
    const resp = def.box[r.resp] ? r.resp : def.pitcherId;
    def.box[resp].pit.r++;
    if (r.earned) def.box[resp].pit.er++;
    this.checkLead();
  }

  private checkLead() {
    const lead = this.home.score > this.away.score ? 'home' : this.away.score > this.home.score ? 'away' : null;
    if (lead && lead !== this.leader) {
      const ls = lead === 'home' ? this.home : this.away;
      const os = lead === 'home' ? this.away : this.home;
      this.pW = ls.pitcherId;
      this.pL = os.pitcherId;
    }
    this.leader = lead;
  }

  /** 타자를 n루로 (4=홈) */
  private moveBatter(ev: PitchEvent, id: string, to: number, earned: boolean) {
    const r: Runner = { id, resp: this.def.pitcherId, earned };
    ev.moves.push({ runnerId: id, from: 0, to });
    if (to >= 4) this.scoreRunner(ev, r, id, true);
    else this.bases[to - 1] = r;
  }

  /** 모든 주자 n 베이스 진루 */
  private advanceAll(ev: PitchEvent, n: number, rbi: boolean, batterId: string | null = null) {
    for (let i = 2; i >= 0; i--) {
      const r = this.bases[i];
      if (!r) continue;
      const to = Math.min(4, i + 1 + n);
      this.bases[i] = null;
      ev.moves.push({ runnerId: r.id, from: i + 1, to });
      if (to >= 4) this.scoreRunner(ev, r, batterId, rbi || n >= 2);
      else this.bases[to - 1] = r;
    }
  }

  /** 볼넷/사구/실책 등 포스 진루. 타자 1루 */
  private advanceForced(ev: PitchEvent, batterId: string, rbi: boolean, earned: boolean) {
    const carry = (i: number): void => {
      if (i > 2) return;
      const r = this.bases[i];
      if (!r) return;
      carry(i + 1);
      this.bases[i] = null;
      ev.moves.push({ runnerId: r.id, from: i + 1, to: i + 2 });
      if (i + 2 >= 4) this.scoreRunner(ev, r, batterId, rbi);
      else this.bases[i + 1] = r;
    };
    carry(0);
    this.moveBatter(ev, batterId, 1, earned);
  }

  /** 안타 시 주자 진루 (주력/어깨 반영). base=0 내야안타, 1 단타, 2 2루타 */
  private advanceHit(ev: PitchEvent, kind: number, batterId: string, fielder: Pos, running: boolean) {
    const rng = this.rng;
    const off = this.off;
    const f = this.fielder(fielder);
    const arm = f.arm + f.fx.flat.arm;
    // 주력 + 주루 능력 (확률 가산을 주력 환산: 0.009 당 1)
    const spd = (r: Runner) => off.byId[r.id].spd + off.byId[r.id].fx.flat.run / 0.009;
    const r3 = this.bases[2];
    const r2 = this.bases[1];
    const r1 = this.bases[0];
    this.bases = [null, null, null];
    if (kind === 0) {
      // 내야 안타: 포스 진루만
      if (r3 && r2 && r1) { ev.moves.push({ runnerId: r3.id, from: 3, to: 4 }); this.scoreRunner(ev, r3, batterId, true); }
      else if (r3) this.bases[2] = r3;
      if (r2 && r1) { ev.moves.push({ runnerId: r2.id, from: 2, to: 3 }); this.bases[2] = r2; }
      else if (r2) this.bases[1] = r2;
      if (r1) { ev.moves.push({ runnerId: r1.id, from: 1, to: 2 }); this.bases[1] = r1; }
      return;
    }
    if (r3) { ev.moves.push({ runnerId: r3.id, from: 3, to: 4 }); this.scoreRunner(ev, r3, batterId, true); }
    if (kind === 2) {
      if (r2) { ev.moves.push({ runnerId: r2.id, from: 2, to: 4 }); this.scoreRunner(ev, r2, batterId, true); }
      if (r1) {
        const p = 0.4 + (spd(r1) - 50) * 0.009 - (arm - 50) * 0.004 + (running ? 0.35 : 0) + (this.outs === 2 ? 0.15 : 0);
        if (rng.chance(clamp(p, 0.05, 0.97))) { ev.moves.push({ runnerId: r1.id, from: 1, to: 4 }); this.scoreRunner(ev, r1, batterId, true); }
        else { ev.moves.push({ runnerId: r1.id, from: 1, to: 3 }); this.bases[2] = r1; }
      }
      return;
    }
    // 단타
    if (r2) {
      const p = 0.55 + (spd(r2) - 50) * 0.009 - (arm - 50) * 0.005 + (this.outs === 2 ? 0.2 : 0) + (running ? 0.2 : 0);
      if (rng.chance(clamp(p, 0.1, 0.97))) { ev.moves.push({ runnerId: r2.id, from: 2, to: 4 }); this.scoreRunner(ev, r2, batterId, true); }
      else { ev.moves.push({ runnerId: r2.id, from: 2, to: 3 }); this.bases[2] = r2; }
    }
    if (r1) {
      const p = 0.22 + (spd(r1) - 50) * 0.007 - (arm - 50) * 0.003 + (fielder === 'RF' ? 0.1 : 0) + (running ? 0.4 : 0);
      if (!this.bases[2] && rng.chance(clamp(p, 0.03, 0.9))) { ev.moves.push({ runnerId: r1.id, from: 1, to: 3 }); this.bases[2] = r1; }
      else { ev.moves.push({ runnerId: r1.id, from: 1, to: 2 }); this.bases[1] = r1; }
    }
  }

  /** 땅볼 아웃 시 다른 주자 진루. skipFirst=1 이면 1루 주자는 이미 처리됨 */
  private advanceOthersOnGround(ev: PitchEvent, shift: string, _skipFirst: number, batterId: string | null = null) {
    const rng = this.rng;
    const r3 = this.bases[2];
    const r2 = this.bases[1];
    const r1 = this.bases[0];
    if (r3) {
      const forced = !!(r2 && r1);
      const goP = forced ? 1 : shift === 'infieldIn' ? 0.12 : 0.55;
      if (rng.chance(goP)) {
        this.bases[2] = null;
        ev.moves.push({ runnerId: r3.id, from: 3, to: 4 });
        this.scoreRunner(ev, r3, batterId, true);
      }
    }
    if (r2 && !this.bases[2]) {
      this.bases[1] = null;
      this.bases[2] = r2;
      ev.moves.push({ runnerId: r2.id, from: 2, to: 3 });
    }
    if (r1 && !this.bases[1] && this.bases[0] === r1) {
      this.bases[0] = null;
      this.bases[1] = r1;
      ev.moves.push({ runnerId: r1.id, from: 1, to: 2 });
    }
  }

  private walk(ev: PitchEvent, label: string, hbp = false) {
    const off = this.off;
    const def = this.def;
    const b = this.batter();
    const bl = off.box[b.id].bat;
    bl.pa++;
    bl.bb++;
    if (!hbp) def.box[def.pitcherId].pit.bb++;
    this.advanceForced(ev, b.id, true, true);
    ev.paResult = label;
  }

  private resolveSteal(ev: PitchEvent, s: { base: number; r: Runner }) {
    if (this.bases[s.base] !== s.r) return; // 이미 이동함
    if (this.bases[s.base + 1]) return;
    const off = this.off;
    const runner = off.byId[s.r.id];
    const catcher = this.fielder('C');
    const arm = catcher.arm + catcher.fx.flat.arm * 0.8;
    let p = 0.62 + (runner.spd - 50) * 0.009 - (arm - 50) * 0.005 + runner.fx.flat.steal + (this.pitcher().fx.pit.length ? (this.pitMods(this.pitcher()).hold ?? 0) : 0);
    if (s.base === 1) p -= 0.08;
    if (this.pitcher().throws === 'L' && s.base === 0) p -= 0.05;
    const success = this.rng.chance(clamp(p, 0.1, 0.96));
    ev.steal = { runnerId: s.r.id, from: s.base + 1, success };
    this.bases[s.base] = null;
    if (success) {
      this.bases[s.base + 1] = s.r;
      off.box[s.r.id].bat.sb++;
      ev.moves.push({ runnerId: s.r.id, from: s.base + 1, to: s.base + 2 });
      ev.text = (ev.text ? ev.text + ' / ' : this.pitchText(ev) + ' / ') + `${runner.name} ${s.base + 2}루 도루 성공!`;
    } else {
      off.box[s.r.id].bat.cs++;
      ev.moves.push({ runnerId: s.r.id, from: s.base + 1, to: -1 });
      this.outs++;
      ev.text = (ev.text ? ev.text + ' / ' : this.pitchText(ev) + ' / ') + `${runner.name} 도루 실패`;
    }
  }

  private addOut(ev: PitchEvent, runnerId: string, from: number) {
    this.outs++;
    ev.moves.push({ runnerId, from, to: -1 });
    this.def.box[this.def.pitcherId].pit.outs += 0; // 아웃 카운트는 finish 에서 일괄 계산
  }

  private halfOver(): boolean {
    return this.outs >= 3;
  }

  // ───────────────────────── 타석/이닝 마무리 ─────────────────────────

  private outsBefore = 0;

  private finish(ev: PitchEvent, paEnded = true): PitchEvent {
    const def = this.def;
    // 투수 아웃카운트 기록
    const newOuts = Math.min(3, this.outs) - this.outsBefore;
    if (newOuts > 0) def.box[def.pitcherId].pit.outs += newOuts;
    this.outsBefore = Math.min(3, this.outs);

    if (ev.paResult) paEnded = true;
    if (paEnded) {
      this.balls = 0;
      this.strikes = 0;
      if (def.visitPa > 0) def.visitPa--;
      const off = this.off;
      off.batterIdx = (off.batterIdx + 1) % 9;
      if (ev.paResult) this.log.push(`${this.inning}회${this.top ? '초' : '말'} ${off.byId[ev.batterId].name}: ${ev.paResult}${ev.runs ? ` (+${ev.runs}점)` : ''}`);
    }

    // 끝내기
    if (!this.top && this.inning >= this.rules.innings && this.home.score > this.away.score) {
      this.endGame(ev);
      return ev;
    }
    // 콜드게임 (말 공격 중 점수 차)
    if (!this.top && this.home.score - this.away.score >= this.mercyGap(this.inning)) {
      this.called = true;
      this.endGame(ev);
      return ev;
    }

    if (this.outs >= 3) {
      ev.endHalf = true;
      this.endHalf(ev);
    }
    return ev;
  }

  private mercyGap(inning: number): number {
    let gap = Infinity;
    for (const [inn, g] of this.rules.mercy) if (inning >= inn) gap = g;
    return gap;
  }

  private endHalf(ev: PitchEvent) {
    const off = this.off;
    while (off.line.length < this.inning) off.line.push(0);
    this.outs = 0;
    this.outsBefore = 0;
    this.balls = 0;
    this.strikes = 0;
    this.bases = [null, null, null];
    const diff = this.home.score - this.away.score;
    if (this.top) {
      // 초 종료: 9회 이상 홈팀 리드면 종료, 콜드 체크
      if (this.inning >= this.rules.innings && diff > 0) return this.endGame(ev);
      if (diff >= this.mercyGap(this.inning)) { this.called = true; return this.endGame(ev); }
      this.top = false;
    } else {
      if (this.inning >= this.rules.innings && diff !== 0) return this.endGame(ev);
      if (Math.abs(diff) >= this.mercyGap(this.inning)) { this.called = true; return this.endGame(ev); }
      if (this.inning >= this.rules.maxInnings) return this.endGame(ev);
      this.top = true;
      this.inning++;
    }
    this.setupTiebreak();
  }

  /** 승부치기: 무사 1,2루에서 시작 (직전 두 타순의 타자가 주자) */
  private setupTiebreak() {
    if (this.inning < this.rules.tiebreakFrom) return;
    const off = this.off;
    const n = off.order.length;
    const r2 = off.order[(off.batterIdx - 1 + n) % n];
    const r1 = off.order[(off.batterIdx - 2 + n) % n];
    this.bases = [
      { id: r1, resp: this.def.pitcherId, earned: false },
      { id: r2, resp: this.def.pitcherId, earned: false },
      null,
    ];
  }

  private endGame(ev: PitchEvent) {
    this.over = true;
    ev.gameOver = true;
    for (const s of [this.home, this.away]) while (s.line.length < (s === this.home && this.top ? this.inning - 1 : this.inning)) s.line.push(0);
    const diff = this.home.score - this.away.score;
    if (diff === 0) {
      if (this.rules.allowDraw) this.winner = null;
      else {
        // 최대 이닝까지 동점: 안타 수 → 추첨
        const w = this.home.hits !== this.away.hits ? (this.home.hits > this.away.hits ? this.home : this.away) : this.rng.chance(0.5) ? this.home : this.away;
        this.winner = w.input.teamId;
      }
    } else {
      this.winner = diff > 0 ? this.home.input.teamId : this.away.input.teamId;
    }
    if (this.winner) {
      const ws = this.sideOf(this.winner);
      const ls = ws === this.home ? this.away : this.home;
      const wp = this.pW && ws.box[this.pW] ? this.pW : ws.pitchers[0];
      const lp = this.pL && ls.box[this.pL] ? this.pL : ls.pitchers[0];
      ws.box[wp].pit.w = 1;
      ls.box[lp].pit.l = 1;
    }
  }

  // ───────────────────────── 유틸 ─────────────────────────

  /** 현재 상황 요약 (UI 용) */
  situation() {
    return {
      inning: this.inning,
      top: this.top,
      outs: this.outs,
      balls: this.balls,
      strikes: this.strikes,
      bases: this.bases.map((r) => r?.id ?? null),
      home: this.home.score,
      away: this.away.score,
    };
  }
}
