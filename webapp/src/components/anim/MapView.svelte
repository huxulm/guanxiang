<script lang="ts">
  // 等距圆柱世界地图：此刻半影落在地面的阴影区域与边界、影轴地面点、中心线、晨昏线（夜晚加暗）、日下点、观测地。
  // 半影边界：基本面上半径 l1 的圆，逐点沿影轴投到地面（planeToGround），落在地球外的点断开；填充区沿晨昏圈闭合。
  import { footprintPolygon, planeToGround, wrapLon } from '../../lib/anim/bessel';
  import type { Rings } from '../../lib/anim/land';
  import { t } from '../../lib/i18n';
  import type { Observer, SolarScene, SolarState } from '../../lib/types';

  let { scene, s, land, observer }: { scene: SolarScene; s: SolarState; land: Rings | null; observer: Observer | null } = $props();

  // 屏幕坐标：x = 经度，y = −纬度（viewBox −180…180 × −90…90）
  type P = [number, number];

  /** 折线；跨过 ±180° 经线时断开 */
  function polyline(points: (P | null)[]): string {
    let d = '';
    let prev: P | null = null;
    for (const p of points) {
      if (!p) {
        prev = null;
        continue;
      }
      const jump = prev && Math.abs(p[0] - prev[0]) > 180;
      d += `${!prev || jump ? 'M' : 'L'}${p[0].toFixed(2)},${(-p[1]).toFixed(2)}`;
      prev = p;
    }
    return d;
  }

  const landPath = $derived(
    land
      ? land
          .map((r) => {
            let d = '';
            for (let i = 0; i + 1 < r.length; i += 2) d += `${i ? 'L' : 'M'}${r[i].toFixed(1)},${(-r[i + 1]).toFixed(1)}`;
            return d + 'Z';
          })
          .join('')
      : '',
  );

  const centralLine = $derived(polyline(scene.central_line.map((p) => [p.lon_deg, p.lat_deg] as P)));

  /** 基本面上以影轴为圆心、半径 r 的圆投到地面 */
  function footprint(r: number, n: number): string {
    const b = s.bessel;
    const pts: (P | null)[] = [];
    for (let i = 0; i <= n; i++) {
      const a = (i / n) * 2 * Math.PI;
      const g = planeToGround(b.x + r * Math.cos(a), b.y + r * Math.sin(a), b.d_deg, b.mu_deg);
      pts.push(g ? [g.lon, g.lat] : null);
    }
    return polyline(pts);
  }
  const penumbra = $derived(footprint(s.bessel.l1, 240));

  /** 半影落在地面上的闭合阴影区域（跨 ±180° 经线平移展开，覆盖极点时向极点闭合） */
  const penumbraArea = $derived.by(() => {
    const b = s.bessel;
    const gpts = footprintPolygon(b.x, b.y, b.l1, b.d_deg, b.mu_deg);
    const M = gpts.length;
    if (M < 3) return '';
    const ulon = [gpts[0].lon];
    for (let i = 1; i <= M; i++) {
      ulon.push(ulon[i - 1] + wrapLon(gpts[i % M].lon - ulon[i - 1]));
    }
    const winding = Math.round((ulon[M] - ulon[0]) / 360);
    if (winding === 0) {
      const minLon = Math.min(...ulon);
      const maxLon = Math.max(...ulon);
      let d = '';
      for (const shift of [-360, 0, 360]) {
        if (maxLon + shift <= -180 || minLon + shift >= 180) continue;
        for (let i = 0; i < M; i++) {
          d += `${i === 0 ? 'M' : 'L'}${(ulon[i] + shift).toFixed(2)},${(-gpts[i].lat).toFixed(2)}`;
        }
        d += 'Z';
      }
      return d;
    }
    const shifts = winding > 0 ? [-360, 0, 360] : [360, 0, -360];
    const poleY = gpts[0].lat >= 0 ? -90 : 90;
    const startLon = ulon[0] + shifts[0];
    const endLon = ulon[M] + shifts[2];
    let d = '';
    for (let si = 0; si < shifts.length; si++) {
      const shift = shifts[si];
      for (let i = 0; i < M; i++) {
        d += `${si === 0 && i === 0 ? 'M' : 'L'}${(ulon[i] + shift).toFixed(2)},${(-gpts[i].lat).toFixed(2)}`;
      }
    }
    return d + `L${endLon.toFixed(2)},${(-gpts[0].lat).toFixed(2)}L${endLon.toFixed(2)},${poleY}L${startLon.toFixed(2)},${poleY}Z`;
  });

  /** 夜晚区域：晨昏线（太阳中心高度 0°）到背阳的极点 */
  const night = $derived.by(() => {
    const dec = (s.sub_solar.lat_deg * Math.PI) / 180;
    const tanDec = Math.abs(Math.tan(dec)) < 1e-6 ? 1e-6 * Math.sign(dec || 1) : Math.tan(dec);
    let d = '';
    for (let lon = -180; lon <= 180; lon += 2) {
      const h = ((lon - s.sub_solar.lon_deg) * Math.PI) / 180;
      const lat = (Math.atan(-Math.cos(h) / tanDec) * 180) / Math.PI;
      d += `${lon === -180 ? 'M' : 'L'}${lon},${(-lat).toFixed(2)}`;
    }
    // 太阳直射北半球时，夜晚在晨昏线以南（屏幕下方）
    return d + (dec >= 0 ? 'L180,90L-180,90Z' : 'L180,-90L-180,-90Z');
  });
</script>

<svg viewBox="-180 -90 360 180" class="block w-full rounded-xl" role="img" aria-label={t('viewMap')}>
  <rect x="-180" y="-90" width="360" height="180" fill="var(--gx-surface-container)" />
  <path d={landPath} fill="var(--gx-surface-high)" stroke="var(--gx-outline)" stroke-width="0.35" />
  <path d={night} fill="var(--gx-sky)" fill-opacity="0.35" />
  <path d={penumbraArea} fill="color-mix(in srgb, var(--gx-sky) 75%, var(--gx-eclipse))" fill-opacity="0.35" />
  <path d={centralLine} fill="none" stroke="var(--gx-eclipse)" stroke-width="1.1" />
  <path d={penumbra} fill="none" stroke="var(--gx-eclipse)" stroke-width="0.9" stroke-dasharray="3 2" />
  {#if s.shadow_center}
    <circle cx={s.shadow_center.lon_deg} cy={-s.shadow_center.lat_deg} r="2.2" fill="var(--gx-sky-moon)" stroke="var(--gx-eclipse)" stroke-width="0.8" />
  {/if}
  <text x={s.sub_solar.lon_deg} y={-s.sub_solar.lat_deg} font-size="8" text-anchor="middle" dominant-baseline="central" fill="var(--gx-tertiary)">☀</text>
  {#if observer}
    <circle cx={observer.lon} cy={-observer.lat} r="2.4" fill="none" stroke="var(--gx-primary)" stroke-width="1" />
    <circle cx={observer.lon} cy={-observer.lat} r="0.8" fill="var(--gx-primary)" />
  {/if}
</svg>
