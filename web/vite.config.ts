import { defineConfig } from 'vite';

// base: './' 로 두면 GitHub Pages 등 어떤 하위 경로에 올려도 동작한다.
// 공용 데이터(../game/data/*.json)와 폰트(../game/assets/fonts)를 읽기 위해 상위 폴더 접근을 허용한다.
export default defineConfig({
  base: './',
  build: { target: 'es2020', assetsInlineLimit: 0 },
  server: { fs: { allow: ['..'] } },
  test: { environment: 'node' },
} as any);
