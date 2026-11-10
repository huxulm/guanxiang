import fs from 'node:fs';
import path from 'node:path';
import type { Connect, Plugin } from 'vite';
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';

const root = path.resolve(__dirname, '..');

/**
 * 本地开发和预览时，在 /ephem/ 下提供裁剪星历（线上从 R2 下载，见 src/lib/config.ts）。
 * 文件依次找 data/ 和 app/assets/，带 Content-Length，前端能显示下载进度。
 */
function localEphemeris(): Plugin {
  const name = 'de440s_1900_2100.bsp';
  const file = [path.join(root, 'data', name), path.join(root, 'app/assets', name)].find((p) => fs.existsSync(p));
  const handler: Connect.NextHandleFunction = (req, res, next) => {
    if (req.url?.split('?')[0] !== `/ephem/${name}`) return next();
    if (!file) {
      res.statusCode = 404;
      res.end(`找不到 ${name}，见 data/README.md`);
      return;
    }
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Length', fs.statSync(file).size);
    fs.createReadStream(file).pipe(res);
  };
  return {
    name: 'guanxiang-local-ephemeris',
    configureServer: (server) => void server.middlewares.use(handler),
    configurePreviewServer: (server) => void server.middlewares.use(handler),
  };
}

/** 虚拟模块 virtual:arb：App 的中英文案（app/lib/l10n/*.arb，去掉 @ 开头的元数据）。 */
function arb(): Plugin {
  const id = 'virtual:arb';
  const files = { zh: 'app_zh.arb', en: 'app_en.arb' };
  const read = (f: string) =>
    Object.fromEntries(
      Object.entries(JSON.parse(fs.readFileSync(path.join(root, 'app/lib/l10n', f), 'utf8'))).filter(
        ([k]) => !k.startsWith('@'),
      ),
    );
  return {
    name: 'guanxiang-arb',
    resolveId: (s) => (s === id ? '\0' + id : undefined),
    load(s) {
      if (s !== '\0' + id) return;
      for (const f of Object.values(files)) this.addWatchFile(path.join(root, 'app/lib/l10n', f));
      return `export const zh = ${JSON.stringify(read(files.zh))};\nexport const en = ${JSON.stringify(read(files.en))};`;
    },
  };
}

export default defineConfig({
  plugins: [svelte(), tailwindcss(), localEphemeris(), arb()],
  worker: { format: 'es' },
  server: { fs: { allow: [root] } },
  build: { target: 'es2022' },
});
