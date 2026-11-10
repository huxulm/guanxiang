// 构建时预先算好近 20 年的日月食列表，写到 public/data/eclipses.json。
// 首页直接读这个文件，不用先下载 22 MB 的星历；计算用的是和网页同一个 wasm（先运行 npm run wasm）。
//
// 星历路径：环境变量 GUANXIANG_EPHEM_TRIMMED，否则依次找 ../data/ 和 ../app/assets/ 下的 de440s_1900_2100.bsp。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const pkg = path.resolve(here, '../src/wasm/pkg');

const candidates = [
  process.env.GUANXIANG_EPHEM_TRIMMED,
  path.join(root, 'data/de440s_1900_2100.bsp'),
  path.join(root, 'app/assets/de440s_1900_2100.bsp'),
].filter(Boolean);
const ephem = candidates.find((p) => fs.existsSync(p));
if (!ephem) {
  console.error(`找不到裁剪星历，试过：\n  ${candidates.join('\n  ')}`);
  process.exit(1);
}

const { initSync, Engine } = await import(pathToFileURL(path.join(pkg, 'guanxiang_wasm.js')).href);
initSync({ module: fs.readFileSync(path.join(pkg, 'guanxiang_wasm_bg.wasm')) });
const engine = new Engine(fs.readFileSync(ephem));

// 从去年年初到 20 年后年初；同一年内重复构建结果相同
const thisYear = new Date().getUTCFullYear();
const from = thisYear - 1;
const to = thisYear + 20;
const t0 = performance.now();
const lunar = JSON.parse(engine.lunarEclipses(from, to));
const solar = JSON.parse(engine.solarEclipses(from, to));
const ms = Math.round(performance.now() - t0);

const outDir = path.resolve(here, '../public/data');
fs.mkdirSync(outDir, { recursive: true });
const out = path.join(outDir, 'eclipses.json');
fs.writeFileSync(out, JSON.stringify({ from, to, lunar, solar }));
console.log(`${path.relative(root, out)}：${from}–${to - 1} 年，月食 ${lunar.length} 次、日食 ${solar.length} 次，用时 ${ms} ms`);

