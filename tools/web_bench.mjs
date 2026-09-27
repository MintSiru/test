// 웹 빌드(Godot WASM) 성능 자동 측정
// 사용법: node tools/web_bench.mjs <웹 빌드 폴더> [--throttle=4]   (예: build/web)
//   --throttle=N : CPU 를 N 배 느리게 (보급형 휴대폰 흉내, Chrome DevTools 의 CPU throttling)
// 폴더를 로컬 서버로 띄우고 헤드리스 Chromium 으로 index.html?bench 를 열어 게임이 출력하는 "BENCH {...}" 를 읽는다.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

import { execSync } from 'node:child_process';

// playwright 는 프로젝트 또는 전역(npm i -g playwright)에서 찾는다
const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright')));
}

const dir = path.resolve(process.argv[2] ?? 'build/web');
const throttle = Number((process.argv.find((a) => a.startsWith('--throttle=')) ?? '--throttle=1').split('=')[1]);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!f.startsWith(dir) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
  // Godot 웹 빌드는 교차 출처 격리 헤더가 있으면 가장 안정적으로 동작한다
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] ?? 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => server.listen(0, r));
const port = server.address().port;
const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
const logs = [];
page.on('console', (m) => logs.push(m.text()));
if (throttle > 1) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
}
const t0 = Date.now();
await page.goto(`http://localhost:${port}/index.html?bench`);
let line = '';
for (let i = 0; i < 600 && !line; i++) {
  await page.waitForTimeout(500);
  line = logs.find((l) => l.startsWith('BENCH ')) ?? '';
}
await browser.close();
server.close();
if (!line) {
  console.error('측정 실패 (콘솔 마지막 20줄):\n' + logs.slice(-20).join('\n'));
  process.exit(1);
}
const res = JSON.parse(line.slice(6));
res.loadAndRunSec = (Date.now() - t0) / 1000;
res.cpuThrottle = throttle;
console.log(JSON.stringify(res, null, 1));
