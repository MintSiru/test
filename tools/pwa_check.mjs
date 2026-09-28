// 홈 화면 앱(PWA) 점검: 서비스 워커 등록 → 두 번째 실행은 캐시에서 → 오프라인 실행 → 새 버전 배포 시 타이틀 「새 버전」 버튼 → 업데이트
// 사용: node tools/pwa_check.mjs game/build/web [스크린샷 폴더]
import http from 'http';
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { execSync } from 'child_process';

const require = createRequire(path.join(execSync('npm root -g').toString().trim(), '/'));
const { chromium } = require('playwright');
const dir = process.argv[2] || 'game/build/web';
const out = process.argv[3] || '/tmp';
let version = 1;
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  let name = decodeURIComponent(req.url.split('?')[0]).replace(/^\//, '') || 'index.html';
  const f = path.join(dir, name);
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  let data = fs.readFileSync(f);
  // 새 버전 배포 흉내: 서비스 워커의 캐시 버전만 바뀐다 (실제 내보내기도 매번 바뀜)
  if (name === 'index.service.worker.js' && version > 1) data = Buffer.from(data.toString().replace(/const CACHE_VERSION = '([^']*)'/, `const CACHE_VERSION = '$1-v${version}'`));
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
  res.end(data);
}).listen(8766);
const URL = 'http://localhost:8766/index.html';
const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
const ctx = await browser.newContext({ viewport: { width: 844, height: 390 } });
const page = await ctx.newPage();
const results = [];
const ok = (name, cond, extra = '') => { results.push(cond); console.log(`${cond ? 'OK  ' : 'FAIL'} ${name} ${extra}`); };
const started = () => page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 90000 });

await page.goto(URL);
await started();
ok('매니페스트 링크', (await page.locator('link[rel=manifest]').count()) === 1);
await page.waitForFunction(() => navigator.serviceWorker.controller !== null || navigator.serviceWorker.getRegistration().then((r) => !!r && !!r.active), null, { timeout: 30000 });
const reg = await page.evaluate(async () => { const r = await navigator.serviceWorker.getRegistration(); return r ? r.active?.scriptURL : null; });
ok('서비스 워커 등록', !!reg, reg || '');

// 두 번째 실행: 엔진·데이터를 캐시에서
const fromSW = {};
page.on('response', (r) => { const n = r.url().split('/').pop(); if (n === 'index.wasm' || n === 'index.pck') fromSW[n] = r.fromServiceWorker(); });
await page.reload();
await started();
ok('두 번째 실행은 캐시에서', fromSW['index.wasm'] === true && fromSW['index.pck'] === true, JSON.stringify(fromSW));

// 오프라인 실행
await ctx.setOffline(true);
await page.reload();
await started();
await page.waitForTimeout(1500);
await page.screenshot({ path: path.join(out, 'pwa_offline.png') });
ok('오프라인에서도 실행', true);
await ctx.setOffline(false);

// 새 버전 배포 → 타이틀에 「새 버전」 버튼 → 업데이트
version = 2;
await page.reload();
await started();
await page.waitForFunction(() => window.__cnUpdate === true, null, { timeout: 30000 }).catch(() => {});
ok('새 버전 감지', await page.evaluate(() => window.__cnUpdate === true));
await page.waitForTimeout(3000);
await page.screenshot({ path: path.join(out, 'pwa_update.png') });
const before = await page.evaluate(() => caches.keys());
await page.evaluate(() => window.__cnApplyUpdate());
await page.waitForTimeout(1500);
await started();
await page.waitForTimeout(1000);
const after = await page.evaluate(() => caches.keys());
ok('업데이트 후 새 캐시만 남음', after.length === 1 && after[0].endsWith('-v2'), `${JSON.stringify(before)} → ${JSON.stringify(after)}`);
ok('업데이트 후 버튼 사라짐', await page.evaluate(() => window.__cnUpdate === false));

await browser.close();
server.close();
console.log(results.every(Boolean) ? 'PWA OK' : 'PWA FAIL');
process.exit(results.every(Boolean) ? 0 : 1);
