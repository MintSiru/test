import './style.css';
import { abilityDef, sortAbilities } from './core/abilities';
import { prettyDate } from './core/calendar';
import { roundName, standings } from './core/competition';
import { LEAGUE_GROUPS } from './core/data';
import { COND_KO, POS_KO, PITCH_KO, avg, era, grade, letter, name, overall, statValue } from './core/player';
import { visitProspect } from './core/scouting';
import { FACILITIES, ITEMS, buyFacility, buyItem, cannotUse, facLevel, facilityCost, facilityMonth, itemDef, marketOpen, needsPlayer, slotPrice, useItem } from './core/shop';
import { FAN_MADE_NOTICE } from './core/data';
import { captainOf, mood } from './core/mood';
import {
  advance, autoPlayUserMatch, createMatch, finishUserMatch, findFixture, idolLabel, rngOf, startNewGame, upcomingSchedule, useCard, userFixtures,
} from './core/season';
import { BATTER_FOCUS, CARD_INFO, FOCUS_KO, PITCHER_FOCUS } from './core/training';
import type { Focus, GameState, Player, StatKey } from './core/types';
import { teamPlayers, userTeam } from './core/world';
import { aiOrders, aiPitchingChange, relievers } from './sim/ai';
import type { Match } from './sim/engine';

/** 기반 시스템(웹)에는 없고 Godot 게임에만 있는 기능 — 규칙·밸런스 원형은 웹, 연출·이벤트는 Godot */
const GODOT_ONLY = [
  '도트 야구장 관전 · 작전 성공 가능성 안내 · 특수능력 발동 실황 · 명장면',
  '비시즌: 동계 합숙(에피소드·마지막 밤), 진로 상담, 학교 행사, 졸업생 진로·대졸 드래프트',
  '기록실: 개인 타이틀, 학교 기록, 명예의 전당, 업적 24개, 특수능력 수집률',
  '주장 선출 팝업, 감독 성장(특기), 선수 이야기(불방망이·슬럼프·재활)·선수 면담 (팀 분위기 규칙은 웹에도 있음)',
  '포지션 연습·투타 겸업, CPU 학교 흥망(신흥 강호·명문의 위기)',
  '장터 가방 일괄 사용, 저장 슬롯 3개와 경기 중 저장, 배경음악·응원가, 홈 화면 앱(PWA)',
];
import type { OffOrder, PitchOrder, ShiftOrder } from './sim/types';

// ─────────────────────────────────────────────────────────────
// 웹 기반 시스템 확인용 UI (텍스트/표 위주).
// 실제 게임 화면(도트 그래픽)은 Godot 프로젝트(game/)에서 만든다.
// ─────────────────────────────────────────────────────────────

const SAVE_KEY = 'cheongchun-nine-web-save';
const app = document.getElementById('app')!;
let S: GameState | null = null;
let tab = 'home';
let M: Match | null = null;
let mLog: string[] = [];
let offOrder: OffOrder = 'normal';
let pitchOrder: PitchOrder = 'normal';
let shiftOrder: ShiftOrder = 'normal';

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

function save() {
  if (!S) return;
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(S)); } catch { /* 용량 초과 등 */ }
}
function load(): GameState | null {
  try { const s = localStorage.getItem(SAVE_KEY); return s ? JSON.parse(s) : null; } catch { return null; }
}

function h(html: string): string { return html; }

// ───────────────────────── 타이틀 ─────────────────────────

function renderTitle() {
  const opts = LEAGUE_GROUPS.map((g) => `<option value="${g.id}">${g.name}</option>`).join('');
  app.innerHTML = h(`
    <h1>⚾ 청춘나인 — 한국 고교야구부 육성 시뮬레이션</h1>
    <p class="dim">웹 기반 시스템 확인용 화면입니다. 본 게임은 Godot 프로젝트(game/)에서 개발합니다.</p>
    <p class="dim">${FAN_MADE_NOTICE}</p>
    <details class="panel"><summary>이 화면에 없는 기능 (Godot 게임 전용)</summary>
      <ul class="dim">${GODOT_ONLY.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
    </details>
    <div class="panel">
      <div class="row">학교 이름 <input id="school" value="한빛고" maxlength="8"></div>
      <div class="row">감독 이름 <input id="mgr" value="김감독" maxlength="8"></div>
      <div class="row">주말리그 권역 <select id="grp">${opts}</select></div>
      <div class="row">프로 선수 <select id="pros"><option value="real">실명 (비공식 팬메이드)</option><option value="fictional">가상</option></select></div>
      <div class="row"><button id="new">새 게임</button> <button id="cont" ${load() ? '' : 'disabled'}>이어하기</button></div>
    </div>`);
  app.querySelector<HTMLButtonElement>('#new')!.onclick = () => {
    S = startNewGame({
      schoolName: (app.querySelector('#school') as HTMLInputElement).value,
      managerName: (app.querySelector('#mgr') as HTMLInputElement).value,
      groupId: (app.querySelector('#grp') as HTMLSelectElement).value,
      prosMode: (app.querySelector('#pros') as HTMLSelectElement).value as 'real' | 'fictional',
    });
    save();
    render();
  };
  app.querySelector<HTMLButtonElement>('#cont')!.onclick = () => { S = load(); render(); };
}

// ───────────────────────── 메인 ─────────────────────────

function render() {
  if (!S) return renderTitle();
  const s = S;
  const t = userTeam(s);
  const tabs: [string, string][] = [['home', '홈'], ['roster', '선수단'], ['schedule', '일정'], ['standings', '순위'], ['scout', '스카우트'], ['shop', '장터'], ['records', '기록']];
  if (s.pendingFixture || M) tabs.unshift(['match', '▶ 경기']);
  app.innerHTML = h(`
    <div class="bar">
      <b style="color:var(--accent)">${esc(t.name)}</b>
      <span>${prettyDate(s.date, true)}</span>
      <span>명성 ${s.reputation}</span>
      <span>분위기 ${mood(s)}${captainOf(s) ? ` · 주장 ${esc(name(captainOf(s)!))}` : ''}</span>
      <span>시즌 ${t.seasonRecord.w}승 ${t.seasonRecord.l}패 ${t.seasonRecord.d}무</span>
      <span>스카우트 행동력 ${s.scoutPoints}</span>
      <span>${s.points ?? 0}P${marketOpen(s) ? ' <span class="good">장터 영업 중</span>' : ''}</span>
      <button id="saveBtn">저장</button> <button id="exportBtn">내보내기</button> <button id="titleBtn">타이틀</button>
    </div>
    <div class="tabs">${tabs.map(([k, l]) => `<button data-tab="${k}" class="${tab === k ? 'on' : ''}">${l}</button>`).join('')}</div>
    <div id="body"></div>
    ${s.popups.length ? `<div class="modal"><div class="panel"><h2>${esc(s.popups[0].title)}</h2><div>${esc(s.popups[0].body)}</div><div class="row"><button id="popOk">확인</button></div></div></div>` : ''}
  `);
  app.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => (b.onclick = () => { tab = b.dataset.tab!; render(); }));
  app.querySelector<HTMLButtonElement>('#saveBtn')!.onclick = () => { save(); alert('저장했습니다.'); };
  app.querySelector<HTMLButtonElement>('#exportBtn')!.onclick = () => {
    const blob = new Blob([JSON.stringify(s)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `cheongchun-nine-${s.date}.json`;
    a.click();
  };
  app.querySelector<HTMLButtonElement>('#titleBtn')!.onclick = () => { S = null; M = null; render(); };
  const pop = app.querySelector<HTMLButtonElement>('#popOk');
  if (pop) pop.onclick = () => { s.popups.shift(); save(); render(); };
  const body = app.querySelector<HTMLDivElement>('#body')!;
  if (tab === 'match' && !s.pendingFixture && !M) tab = 'home';
  ({ home: renderHome, roster: renderRoster, schedule: renderSchedule, standings: renderStandings, scout: renderScout, shop: renderShop, records: renderRecords, match: renderMatch } as Record<string, (b: HTMLElement, s: GameState) => void>)[tab](body, s);
}

function renderHome(body: HTMLElement, s: GameState) {
  const next = userFixtures(s).find((x) => !x.f.result);
  const nextTxt = next ? `${prettyDate(next.f.date)} ${next.comp.name}${next.f.round !== undefined && next.comp.kind === 'tournament' ? ' ' + roundName(next.comp, next.f.round) : ''} vs ${esc(s.teams[next.f.home === s.userTeamId ? next.f.away : next.f.home].name)}` : '예정된 경기 없음';
  body.innerHTML = h(`
    <div class="panel">다음 경기: <b>${nextTxt}</b></div>
    ${!s.weekTrained ? `<div class="panel"><h2>이번 주 훈련 카드를 고르세요</h2><div class="cards">${s.hand.map((c) => `<div class="card" data-card="${c.id}"><b>${CARD_INFO[c.kind].name}</b><br>Lv ${'●'.repeat(c.value)}<br><span class="dim">${CARD_INFO[c.kind].desc}</span></div>`).join('')}</div></div>` : ''}
    ${s.pendingFixture ? `<div class="panel"><h2>오늘은 경기일!</h2><div class="row"><button id="goMatch">직접 지휘</button><button id="autoMatch">위임 (자동 진행)</button></div></div>` : ''}
    ${s.weekTrained && !s.pendingFixture ? `<div class="row"><button id="adv">▶ 진행</button><span class="dim">다음 할 일(훈련/경기/이벤트)까지 날짜를 넘깁니다.</span></div>` : ''}
    <h2>소식</h2>
    <div class="panel news">${[...s.news].reverse().slice(0, 80).map((n) => `<div class="${n.kind === 'result' ? '' : n.kind}"><span class="dim">${n.date.slice(5)}</span> ${esc(n.text)}</div>`).join('')}</div>
    <h2>연간 일정</h2>
    <div class="panel">${upcomingSchedule(s).map((e) => `<div class="${e.date < s.date ? 'dim' : ''}">${e.date.slice(5)} ${esc(e.label)}</div>`).join('')}</div>
  `);
  body.querySelectorAll<HTMLElement>('[data-card]').forEach((el) => (el.onclick = () => { useCard(s, el.dataset.card!); advance(s); save(); render(); }));
  const adv = body.querySelector<HTMLButtonElement>('#adv');
  if (adv) adv.onclick = () => { advance(s); save(); render(); };
  const am = body.querySelector<HTMLButtonElement>('#autoMatch');
  if (am) am.onclick = () => { autoPlayUserMatch(s); advance(s); save(); render(); };
  const gm = body.querySelector<HTMLButtonElement>('#goMatch');
  if (gm) gm.onclick = () => { tab = 'match'; render(); };
}

function statCell(p: Player, k: StatKey) {
  const v = statValue(p.r, k);
  return `<td class="g-${letter(v)}">${letter(v)}${k === 'velo' ? ` ${p.r.velo}` : ` ${Math.round(v)}`}</td>`;
}

/** 특수능력 칩: 금특(노랑) · 긍정(파랑) · 부정(빨강), 마우스를 올리면 설명 */
function abilityChips(ids: string[]): string {
  return sortAbilities(ids).map((id) => {
    const a = abilityDef(id);
    return `<span class="ab ab-${a?.tier ?? 'good'}" title="${esc(a?.desc ?? '')}">${a?.tier === 'gold' ? '★' : ''}${esc(a?.name ?? id)}</span>`;
  }).join(' ');
}

function renderRoster(body: HTMLElement, s: GameState) {
  const ps = teamPlayers(s, s.userTeamId).sort((a, b) => (a.pos === 'P' ? 0 : 1) - (b.pos === 'P' ? 0 : 1) || grade(b, s.year) - grade(a, s.year));
  const row = (p: Player) => {
    const isP = p.pos === 'P';
    const stats: StatKey[] = isP ? ['velo', 'control', 'stamina', 'breaking'] : ['contact', 'power', 'eye', 'speed', 'arm', 'fielding'];
    const focusOpts = (isP ? PITCHER_FOCUS : BATTER_FOCUS).map((f) => `<option value="${f}" ${p.focus === f ? 'selected' : ''}>${FOCUS_KO[f]}</option>`).join('');
    const idol = idolLabel(s, p);
    return `<tr>
      <td>${esc(name(p))}</td><td>${grade(p, s.year)}</td><td>${POS_KO[p.pos]}</td><td>${'★'.repeat(p.talent)}</td><td>${overall(p)}</td>
      ${stats.map((k) => statCell(p, k)).join('')}${isP ? '<td></td><td></td>' : ''}
      <td>${COND_KO[p.cond + 2]}</td><td>${Math.round(p.fatigue)}</td><td class="bad">${p.injury > 0 ? p.injury + '일' : ''}</td>
      <td>${isP ? `${era(p.season.pit)} ${p.season.pit.w}승` : `${avg(p.season.bat)} ${p.season.bat.hr}홈런`}</td>
      <td><select data-focus="${p.id}">${focusOpts}</select></td>
      <td>${abilityChips(p.abilities)}</td>
      <td class="idol">${idol ? `${esc(idol)} (${p.idolBond})` : ''}</td>
    </tr>`;
  };
  body.innerHTML = h(`<div class="panel scroll"><table>
    <tr><th>이름</th><th>학년</th><th>포지션</th><th>재능</th><th>종합</th><th colspan="6">능력 (투수: 구속/제구/스태미나/변화구 · 야수: 컨택/파워/선구/주력/어깨/수비)</th><th>컨디션</th><th>피로</th><th>부상</th><th>시즌</th><th>개인연습</th><th>특수능력</th><th>동경</th></tr>
    ${ps.map(row).join('')}
  </table></div>
  <div class="panel dim">투수 구종: ${ps.filter((p) => p.pos === 'P').map((p) => `${esc(name(p))}(${p.r.pitches.filter((x) => x.type !== 'FB').map((x) => PITCH_KO[x.type] + x.lv).join(' ') || '직구만'})`).join(' · ')}</div>`);
  body.querySelectorAll<HTMLSelectElement>('[data-focus]').forEach((sel) => (sel.onchange = () => { s.players[sel.dataset.focus!].focus = sel.value as Focus; save(); }));
}

function renderSchedule(body: HTMLElement, s: GameState) {
  const games = userFixtures(s);
  body.innerHTML = h(`
    <div class="panel"><h2>대회 현황 (${s.year})</h2>${s.competitions.map((c) => `<div>${esc(c.name)} <span class="dim">${c.start.slice(5)}~${c.end.slice(5)}</span> ${c.status === 'done' ? '종료' : c.status === 'active' ? '<span class="good">진행 중</span>' : '예정'} ${c.champion ? `· 우승 ${esc(s.teams[c.champion].name)}` : ''} ${c.userResult ? `· <b>우리: ${esc(c.userResult)}</b>` : ''}</div>`).join('')}</div>
    <div class="panel"><h2>우리 경기</h2><table>${games.map(({ comp, f }) => {
      const u = s.userTeamId;
      const opp = s.teams[f.home === u ? f.away : f.home].name;
      const r = f.result;
      const sc = r ? `${f.home === u ? r.homeScore : r.awayScore} : ${f.home === u ? r.awayScore : r.homeScore}` : '';
      const out = r ? (r.winner === u ? '<span class="good">승</span>' : r.winner ? '<span class="bad">패</span>' : '무') : '';
      return `<tr><td>${prettyDate(f.date)}</td><td>${esc(comp.name)}${comp.kind === 'tournament' ? ' ' + roundName(comp, f.round!) : ''}</td><td>vs ${esc(opp)}</td><td>${sc}</td><td>${out}</td></tr>`;
    }).join('')}</table></div>`);
}

function renderStandings(body: HTMLElement, s: GameState) {
  const g = userTeam(s).leagueGroup;
  body.innerHTML = s.competitions.filter((c) => c.kind === 'league').map((c) => {
    const rows = standings(c, g);
    return `<div class="panel"><h2>${esc(c.name)} — ${esc(LEAGUE_GROUPS.find((x) => x.id === g)!.name)}</h2><table><tr><th>순위</th><th>팀</th><th>승</th><th>패</th><th>무</th><th>득</th><th>실</th></tr>${rows.map((r, i) => `<tr class="${r.teamId === s.userTeamId ? 'good' : ''}"><td>${i + 1}</td><td>${esc(s.teams[r.teamId].name)}</td><td>${r.w}</td><td>${r.l}</td><td>${r.d}</td><td>${r.rs}</td><td>${r.ra}</td></tr>`).join('')}</table></div>`;
  }).join('');
}

function renderScout(body: HTMLElement, s: GameState) {
  if (!s.prospects.length) { body.innerHTML = '<div class="panel dim">유망주 명단은 9월 드래프트 이후 공개됩니다.</div>'; return; }
  body.innerHTML = h(`<div class="panel">행동력 ${s.scoutPoints} — 방문할수록 입학 의향이 오르고 정보가 공개됩니다. 입학은 3월.</div>
    <div class="panel scroll"><table><tr><th>이름</th><th>포지션</th><th>재능</th><th>종합</th><th>의향</th><th>경쟁교</th><th>동경</th><th></th></tr>
    ${s.prospects.map((pr) => {
      const p = pr.player;
      const idol = idolLabel(s, p);
      return `<tr><td>${esc(name(p))}</td><td>${POS_KO[p.pos]}</td><td>${pr.revealed >= 1 ? '★'.repeat(p.talent) : '?'}</td><td>${pr.revealed >= 2 ? overall(p) : '?'}</td><td>${pr.interest}%</td><td>${esc(pr.rival ?? '')}</td><td class="idol">${pr.revealed >= 3 && idol ? esc(idol) : pr.revealed >= 3 ? '-' : '?'}</td><td><button data-visit="${pr.id}" ${s.scoutPoints ? '' : 'disabled'}>방문</button></td></tr>`;
    }).join('')}</table></div>`);
  body.querySelectorAll<HTMLButtonElement>('[data-visit]').forEach((b) => (b.onclick = () => {
    const rng = rngOf(s);
    const msg = visitProspect(s, b.dataset.visit!, rng);
    s.rngState = rng.state;
    s.news.push({ date: s.date, kind: 'info', text: msg });
    save();
    render();
  }));
}

function renderShop(body: HTMLElement, s: GameState) {
  const open = marketOpen(s);
  const players = teamPlayers(s, s.userTeamId);
  const inv = Object.entries(s.inventory ?? {});
  body.innerHTML = `<div class="panel">포인트 <b>${s.points ?? 0}P</b> — 경기 결과로 얻는다. 장터는 매월 1~7일, 시설 기물은 1·2·7·8·12월 장터에서만. ${open ? '<span class="good">장터 영업 중</span>' : '<span class="dim">장터 닫힘</span>'}</div>
    <div class="panel"><h2>이번 장터</h2><table>${(s.shop?.stock ?? []).map((st) => { const d = itemDef(st.key)!; return `<tr><td>${esc(d.name)}</td><td class="dim">${esc(d.desc)}</td><td>${slotPrice(st)}P</td><td>남은 ${st.qty}</td><td><button data-buy="${st.key}" ${!open || st.qty <= 0 || (s.points ?? 0) < slotPrice(st) ? 'disabled' : ''}>구매</button></td></tr>`; }).join('') || '<tr><td class="dim">없음</td></tr>'}</table></div>
    <div class="panel"><h2>시설 기물</h2><table>${FACILITIES.map((f) => { const c = facilityCost(s, f.key); return `<tr><td>${esc(f.name)}</td><td>Lv${facLevel(s.facilities, f.key)}</td><td class="dim">${esc(f.desc)}</td><td><button data-fac="${f.key}" ${c === null || !open || !facilityMonth(s) || (s.points ?? 0) < c ? 'disabled' : ''}>${c === null ? '최고' : `설치 ${c}P`}</button></td></tr>`; }).join('')}</table></div>
    <div class="panel"><h2>가방</h2><table>${inv.map(([k, n]) => { const d = itemDef(k)!; const opts = needsPlayer(d) ? players.map((p) => `<option value="${p.id}" ${cannotUse(d, p) ? 'disabled' : ''}>${esc(name(p))}${cannotUse(d, p) ? ' (' + cannotUse(d, p) + ')' : ''}</option>`).join('') : d.type === 'prospect' ? s.prospects.map((x) => `<option value="${x.id}">${esc(name(x.player))} ${x.interest}%</option>`).join('') : ''; return `<tr><td>${esc(d.name)} ×${n}</td><td class="dim">${esc(d.desc)}</td><td>${opts ? `<select id="t-${k}">${opts}</select>` : ''}</td><td><button data-use="${k}">사용</button></td></tr>`; }).join('') || '<tr><td class="dim">비어 있음</td></tr>'}</table></div>
    <div class="panel dim">아이템 ${ITEMS.length}종 · 시설 ${FACILITIES.length}종</div>`;
  const rng = rngOf(s);
  const done = (msg: string | null) => { if (msg) alert(msg); s.rngState = rng.state; save(); render(); };
  body.querySelectorAll<HTMLButtonElement>('[data-buy]').forEach((b) => (b.onclick = () => done(buyItem(s, b.dataset.buy!))));
  body.querySelectorAll<HTMLButtonElement>('[data-fac]').forEach((b) => (b.onclick = () => done(buyFacility(s, b.dataset.fac!))));
  body.querySelectorAll<HTMLButtonElement>('[data-use]').forEach((b) => (b.onclick = () => {
    const k = b.dataset.use!;
    const sel = body.querySelector<HTMLSelectElement>(`#t-${k}`);
    const r = useItem(s, k, sel?.value ?? null, rng);
    done(r.ok ? null : r.msg);
  }));
}

function renderRecords(body: HTMLElement, s: GameState) {
  body.innerHTML = h(`<div class="panel"><h2>연도별 성적</h2>${s.history.map((y) => `<div><b>${y.year}</b> ${y.results.map((r) => `${esc(r.comp)}: ${esc(r.result)}`).join(' · ')}</div>`).join('') || '<span class="dim">아직 기록이 없습니다.</span>'}</div>
  <div class="panel"><h2>졸업생</h2>${s.alumni.map((a) => `<div>${a.gradYear} ${esc(a.name)} (${POS_KO[a.pos]}) ${a.draft ? `— ${esc(s.proTeams.find((t) => t.id === a.draft!.teamId)!.name)} ${a.draft.round}라운드` : ''}</div>`).join('') || '<span class="dim">-</span>'}</div>
  <div class="panel"><h2>프로야구 (가상 리그)</h2><table>${s.pros.filter((p) => !p.retired).map((p) => `<tr><td>${esc(s.proTeams.find((t) => t.id === p.teamId)!.name)}</td><td>${esc(p.sur + p.given)}${p.alumniOf === s.userTeamId ? ' <span class="good">(OB)</span>' : ''}</td><td>${POS_KO[p.pos]}</td><td>${p.style}</td><td class="dim">${esc(p.line)}</td></tr>`).join('')}</table></div>`);
}

// ───────────────────────── 경기 (텍스트 관전 + 작전) ─────────────────────────

function ensureMatch(s: GameState): Match | null {
  if (M) return M;
  if (!s.pendingFixture) return null;
  const found = findFixture(s, s.pendingFixture);
  if (!found) return null;
  M = createMatch(s, found.f, rngOf(s));
  mLog = [`${found.comp.name} — ${M.away.input.name} vs ${M.home.input.name}`];
  return M;
}

function userIsBatting(m: Match): boolean {
  return m.off.input.isUser;
}

function stepOnce(s: GameState, m: Match, delegate = false) {
  const userSide = m.home.input.isUser ? m.home : m.away;
  // CPU 쪽 투수 교체
  if (!m.def.input.isUser || delegate) aiPitchingChange(m, m.def);
  else if ((m.def.pitchCount[m.def.pitcherId] ?? 0) >= m.rules.pitchLimit && m.balls === 0 && m.strikes === 0) aiPitchingChange(m, m.def);
  const ai = aiOrders(m);
  const orders = delegate ? ai : userIsBatting(m)
    ? { off: offOrder, pitch: ai.pitch, shift: ai.shift }
    : { off: ai.off, pitch: pitchOrder, shift: shiftOrder };
  const inning = `${m.inning}회${m.top ? '초' : '말'}`;
  const ev = m.step(orders);
  mLog.push(`${inning} ${m.away.score}:${m.home.score} | ${ev.text}`);
  if (ev.paResult) { offOrder = 'normal'; pitchOrder = pitchOrder === 'ibb' ? 'normal' : pitchOrder; }
  if (ev.endHalf && !m.over) mLog.push(`── ${m.top ? m.inning + '회초' : m.inning + '회말'} ──`);
  if (m.over) finish(s, m, userSide.input.teamId);
}

function finish(s: GameState, m: Match, uid: string) {
  mLog.push(`경기 종료! ${m.away.input.name} ${m.away.score} : ${m.home.score} ${m.home.input.name} ${m.winner === uid ? '— 승리!' : m.winner ? '— 패배' : '— 무승부'}`);
  finishUserMatch(s, m);
  save();
}

function renderMatch(body: HTMLElement, s: GameState) {
  const m = ensureMatch(s);
  if (!m) { body.innerHTML = '<div class="panel">경기가 없습니다.</div>'; return; }
  const bat = m.batter();
  const pit = m.pitcher();
  const userSide = m.home.input.isUser ? m.home : m.away;
  const inn = Math.max(9, m.home.line.length, m.away.line.length);
  const line = (sd: typeof m.home) => `<tr><td>${esc(sd.input.name)}</td>${Array.from({ length: inn }, (_, i) => `<td>${sd.line[i] ?? ''}</td>`).join('')}<td><b>${sd.score}</b></td><td>${sd.hits}</td><td>${sd.errors}</td></tr>`;
  const b = m.bases;
  const base = (i: number) => (b[i] ? '◆' : '◇');
  const batting = userIsBatting(m);
  const sit = m.over ? '' : `${m.inning}회${m.top ? '초' : '말'} ${m.outs}아웃  B${m.balls} S${m.strikes}`;
  const bench = userSide.input.players.filter((p) => !userSide.used.includes(p.id));
  const pen = relievers(userSide);
  const offOpts: [OffOrder, string][] = [['normal', '자유 타격'], ['wait', '기다려'], ['aggressive', '적극 공략'], ['bunt', '희생 번트'], ['safetyBunt', '기습 번트'], ['squeeze', '스퀴즈'], ['steal', '도루'], ['hitRun', '히트앤런']];
  const pitOpts: [PitchOrder, string][] = [['normal', '자유'], ['zone', '정면 승부'], ['edge', '유인구 위주'], ['ibb', '고의사구']];
  const shiftOpts: [ShiftOrder, string][] = [['normal', '기본 수비'], ['infieldIn', '전진 수비'], ['buntShift', '번트 시프트'], ['deep', '장타 경계']];
  const sel = (id: string, opts: [string, string][], cur: string) => `<select id="${id}">${opts.map(([v, l]) => `<option value="${v}" ${v === cur ? 'selected' : ''}>${l}</option>`).join('')}</select>`;
  const pc = m.def.pitchCount[pit.id] ?? 0;
  body.innerHTML = h(`
    <div class="panel scroll"><table><tr><th></th>${Array.from({ length: inn }, (_, i) => `<th>${i + 1}</th>`).join('')}<th>R</th><th>H</th><th>E</th></tr>${line(m.away)}${line(m.home)}</table></div>
    <div class="panel row">
      <div class="diamond">   ${base(1)}\n ${base(2)}   ${base(0)}\n    ⌂</div>
      <div><b>${sit}</b><br>타자 <b>${esc(bat.name)}</b> (${esc(m.off.input.name)}) 컨택 ${Math.round(bat.con)} 파워 ${Math.round(bat.pow)} 주력 ${Math.round(bat.spd)}<br>
      투수 <b>${esc(pit.name)}</b> (${esc(m.def.input.name)}) ${Math.round(pit.velo)}km 제구 ${Math.round(pit.ctl)} 투구수 ${pc}</div>
    </div>
    ${m.over ? `<div class="panel"><button id="done">결과 확인</button></div>` : `
    <div class="panel">
      <div class="row">${batting ? `공격 작전 ${sel('offSel', offOpts, offOrder)}` : `투구 ${sel('pitSel', pitOpts, pitchOrder)} 수비 ${sel('shiftSel', shiftOpts, shiftOrder)}`}</div>
      <div class="row"><button id="p1">공 1개</button><button id="pa">타석 끝까지</button><button id="half">이닝 끝까지</button><button id="all">경기 끝까지 (위임)</button></div>
      <div class="row">${batting
        ? `대타 <select id="phSel"><option value="">-</option>${bench.filter((p) => p.pos !== 'P').map((p) => `<option value="${p.id}">${esc(p.name)} (컨${Math.round(p.con)} 파${Math.round(p.pow)})</option>`).join('')}</select>
           대주자(1루) <select id="prSel"><option value="">-</option>${bench.filter((p) => p.pos !== 'P').map((p) => `<option value="${p.id}">${esc(p.name)} (주력 ${Math.round(p.spd)})</option>`).join('')}</select>`
        : `투수 교체 <select id="pcSel"><option value="">-</option>${pen.map((p) => `<option value="${p.id}">${esc(p.name)} ${Math.round(p.velo)}km 제구${Math.round(p.ctl)}</option>`).join('')}</select>`}</div>
    </div>`}
    <div class="panel log">${[...mLog].reverse().map((l) => `<div>${esc(l)}</div>`).join('')}</div>`);
  const bind = (id: string, fn: (v: string) => void) => { const el = body.querySelector<HTMLSelectElement>('#' + id); if (el) el.onchange = () => fn(el.value); };
  bind('offSel', (v) => (offOrder = v as OffOrder));
  bind('pitSel', (v) => (pitchOrder = v as PitchOrder));
  bind('shiftSel', (v) => (shiftOrder = v as ShiftOrder));
  bind('phSel', (v) => { if (v) { m.pinchHit(m.off, v); mLog.push(`[대타] ${m.batter().name}`); render(); } });
  bind('prSel', (v) => { if (v && m.bases[0]) { m.pinchRun(m.off, 0, v); mLog.push('[대주자 기용]'); render(); } });
  bind('pcSel', (v) => { if (v) { m.changePitcher(m.def, v); mLog.push(`[투수 교체] ${m.pitcher().name}`); render(); } });
  const run = (until: () => boolean, delegate = false) => {
    let guard = 0;
    do { stepOnce(s, m, delegate); } while (!m.over && !until() && guard++ < 3000);
    render();
  };
  const click = (id: string, fn: () => void) => { const el = body.querySelector<HTMLButtonElement>('#' + id); if (el) el.onclick = fn; };
  click('p1', () => run(() => true));
  click('pa', () => run(() => m.balls === 0 && m.strikes === 0));
  const half = m.top;
  click('half', () => run(() => m.top !== half));
  click('all', () => run(() => false, true));
  click('done', () => { M = null; advance(s); save(); tab = 'home'; render(); });
}

S = null;
render();
