// 核对前端的基本面↔地面换算（src/lib/anim/bessel.ts）与 Rust 的计算一致：
// 用同一个 wasm 逐帧求值，影轴地面点由 JS 从 (x, y, d, μ) 反算，与 Rust 的 shadow_center 比较；
// 再把 shadow_center 正向投影回基本面，与 (x, y) 比较。
// 运行：node scripts/check-geometry.ts（Node 24 直接运行 TypeScript；先 npm run wasm，需要裁剪星历）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { footprintPolygon, groundToPlane, planeToGround, wrapLon } from '../src/lib/anim/bessel.ts';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const ephem = [
  process.env.GUANXIANG_EPHEM_TRIMMED,
  path.join(root, 'data/de440s_1900_2100.bsp'),
  path.join(root, 'app/assets/de440s_1900_2100.bsp'),
].find((p) => p && fs.existsSync(p));
if (!ephem) {
  console.error('找不到裁剪星历 de440s_1900_2100.bsp');
  process.exit(1);
}

const pkg = path.resolve(here, '../src/wasm/pkg');
const { initSync, Engine } = await import(pathToFileURL(path.join(pkg, 'guanxiang_wasm.js')).href);
initSync({ module: fs.readFileSync(path.join(pkg, 'guanxiang_wasm_bg.wasm')) });
const engine = new Engine(fs.readFileSync(ephem));

// 不同纬度、影轴赤纬正负、全食和环食
const dates = ['2027-08-02', '2026-08-12', '2024-04-08', '2030-06-01', '2021-12-04', '2023-10-14'];
let worstLatLon = 0;
let worstPlane = 0;
let frames = 0;
for (const date of dates) {
  const h = engine.solarEclipse(date);
  for (let t = -4 * 3600; t <= 4 * 3600; t += 120) {
    const s = JSON.parse(h.stateAt(engine, t));
    if (!s.shadow_center) continue;
    const b = s.bessel;
    const g = planeToGround(b.x, b.y, b.d_deg, b.mu_deg);
    if (!g) throw new Error(`${date} t=${t}：Rust 有影轴地面点，JS 反算却在地球外`);
    worstLatLon = Math.max(
      worstLatLon,
      Math.abs(g.lat - s.shadow_center.lat_deg),
      Math.abs(wrapLon(g.lon - s.shadow_center.lon_deg)) * Math.cos((g.lat * Math.PI) / 180),
    );
    const p = groundToPlane(s.shadow_center.lat_deg, s.shadow_center.lon_deg, b.d_deg, b.mu_deg);
    if (p.zeta <= 0) throw new Error(`${date} t=${t}：影轴地面点投影到了背面`);
    worstPlane = Math.max(worstPlane, Math.hypot(p.xi - b.x, p.eta - b.y));

    const ring = footprintPolygon(b.x, b.y, b.l1, b.d_deg, b.mu_deg);
    if (ring.length < 3) throw new Error(`${date} t=${t}：有影轴地面点但半影多边形为空`);
    const ulon = [ring[0].lon];
    for (let i = 1; i <= ring.length; i++) {
      ulon.push(ulon[i - 1] + wrapLon(ring[i % ring.length].lon - ulon[i - 1]));
    }
    const winding = Math.round((ulon[ring.length] - ulon[0]) / 360);
    const np = groundToPlane(90, 0, b.d_deg, b.mu_deg);
    const sp = groundToPlane(-90, 0, b.d_deg, b.mu_deg);
    const poleIn =
      (np.zeta > 0 && Math.hypot(np.xi - b.x, np.eta - b.y) < b.l1) ||
      (sp.zeta > 0 && Math.hypot(sp.xi - b.x, sp.eta - b.y) < b.l1);
    if ((winding !== 0) !== poleIn) {
      throw new Error(`${date} t=${t}：半影环绕极点数 ${winding} 与极点包含 ${poleIn} 不一致`);
    }
    frames++;
  }
}

const ok = worstLatLon < 1e-6 && worstPlane < 1e-8 && frames > 100;
console.log(
  `${frames} 帧：反算地面点最大差 ${worstLatLon.toExponential(2)}°，正向投影最大差 ${worstPlane.toExponential(2)} 地球半径${ok ? '' : '（超出容差）'}`,
);
process.exit(ok ? 0 : 1);
