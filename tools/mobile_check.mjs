// 모바일 화면비율 점검: 여러 휴대폰·태블릿 크기(세로/가로)로 웹 빌드를 열어 스크린샷과 게임 영역 크기를 기록한다
// 사용법: node tools/mobile_check.mjs <웹 빌드 폴더> <스크린샷 폴더>
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(execSync('npm root -g').toString().trim(), 'playwright')); }
const { chromium, devices } = pw;

const dir = path.resolve(process.argv[2] ?? 'build/web');
const outDir = path.resolve(process.argv[3] ?? 'mobile_shots');
fs.mkdirSync(outDir, { recursive: true });
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!f.startsWith(dir) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] ?? 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;

// 대표 기종 (CSS 픽셀 · 픽셀 비율). 가로는 주소창 등을 뺀 대략적인 높이
const CASES = [
  ['iPhone13-세로', devices['iPhone 13']],
  ['iPhone13-가로', devices['iPhone 13 landscape']],
  ['iPhoneSE-가로', devices['iPhone SE landscape']],
  ['Pixel7-세로', devices['Pixel 7']],
  ['Pixel7-가로', devices['Pixel 7 landscape']],
  ['GalaxyS9-가로', devices['Galaxy S9+ landscape']],
  ['iPadMini-가로', devices['iPad Mini landscape']],
  ['데스크톱-1366', { viewport: { width: 1366, height: 768 }, deviceScaleFactor: 1 }],
];
const query = process.argv[4] ?? '';
const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
const rows = [];
for (const [name, dev] of CASES) {
  const ctx = await browser.newContext({ ...dev });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  await page.goto(`http://localhost:${port}/index.html${query}`);
  // 게임이 뜰 때까지 (타이틀 화면이 그려질 시간)
  for (let i = 0; i < 60; i++) {
    await page.waitForTimeout(500);
    if (logs.some((l) => l.startsWith('LAYOUT '))) break;
  }
  await page.waitForTimeout(1500);
  const layout = logs.filter((l) => l.startsWith('LAYOUT ')).pop() ?? '';
  const vp = page.viewportSize();
  await page.screenshot({ path: path.join(outDir, `${name}.png`) });
  rows.push(`${name.padEnd(16)} 화면 ${vp.width}x${vp.height} @${dev.deviceScaleFactor ?? 1}  ${layout}`);
  await ctx.close();
}
// 터치 확인: 소수 배율에서도 터치 위치가 맞는지 (iPhone 가로에서 「새 게임」 버튼을 누르면 새 게임 화면으로)
{
  const dev = devices['iPhone 13 landscape'];
  const ctx = await browser.newContext({ ...dev });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  await page.goto(`http://localhost:${port}/index.html`);
  for (let i = 0; i < 60 && !logs.some((l) => l.startsWith('LAYOUT ')); i++) await page.waitForTimeout(500);
  await page.waitForTimeout(1500);
  const vp = page.viewportSize();
  const s = Math.min(vp.width / 640, vp.height / 360);
  const ox = (vp.width - 640 * s) / 2;
  const oy = (vp.height - 360 * s) / 2;
  // 타이틀 「새 게임」 버튼: 게임 좌표 (320, 178) 근처 (저장이 없을 때 첫 버튼)
  await page.touchscreen.tap(ox + 320 * s, oy + 178 * s);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(outDir, 'touch-새게임.png') });
  const moved = logs.some((l) => l.includes('SCREEN new_game'));
  rows.push(`터치 확인 (iPhone 가로, 새 게임 버튼): ${moved ? 'OK' : '실패'}`);
  // 학교 이름 입력칸(게임 좌표 약 326,105)을 누르면 브라우저 입력창이 떠야 한다
  let asked = '';
  page.on('dialog', async (d) => { asked = d.message(); await d.accept('푸른고'); });
  await page.touchscreen.tap(ox + 326 * s, oy + 105 * s);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(outDir, 'touch-이름입력.png') });
  rows.push(`이름 입력 (iPhone 가로): ${asked ? `입력창 뜸 「${asked}」` : '입력창 안 뜸'}`);
  await ctx.close();
}
// 게임 속 화면 (주소 뒤 개발용 인자): 홈·경기 화면을 휴대폰 가로에서 찍고, 길게 누르기 설명을 시험
for (const [name, q] of [['홈', '?newgame&notut&days=3&screen=hub'], ['경기', '?newgame&notut&days=5&pitches=26&screen=match']]) {
  const dev = devices['iPhone 13 landscape'];
  const ctx = await browser.newContext({ ...dev });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  await page.goto(`http://localhost:${port}/index.html${q}`);
  for (let i = 0; i < 90 && !logs.some((l) => l.startsWith(`SCREEN ${name === '홈' ? 'hub' : 'match'}`)); i++) await page.waitForTimeout(500);
  await page.waitForTimeout(2000);
  await page.screenshot({ path: path.join(outDir, `화면-${name}.png`) });
  if (name === '경기') {
    // 「희생 번트」 작전 버튼(게임 좌표 약 571,153)을 0.8초 누르고 있으면 설명(성공 가능성)이 떠야 한다
    const vp = page.viewportSize();
    const s = Math.min(vp.width / 640, vp.height / 360);
    const x = (vp.width - 640 * s) / 2 + 571 * s;
    const y = (vp.height - 360 * s) / 2 + 153 * s;
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
    await page.waitForTimeout(800);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForTimeout(800);
    await page.screenshot({ path: path.join(outDir, '길게누르기.png') });
  }
  rows.push(`게임 화면 (${name}, iPhone 가로): ${logs.filter((l) => l.startsWith('SCREEN')).pop() ?? '열리지 않음'}`);
  await ctx.close();
}
await browser.close();
server.close();
console.log(rows.join('\n'));
