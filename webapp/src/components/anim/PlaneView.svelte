<script lang="ts">
  // 从太阳方向看地球：贝塞尔基本面上的正射投影（x 向东、y 向北，单位地球赤道半径）。
  // 在这个视角下，半影、本影正好是以 (x, y) 为圆心、半径 l1、|l2| 的圆；地球是 y 半轴为 ρ1 的椭圆。
  // 陆地、赤道、中心线和观测地按此刻的 d、μ 投影，只画朝向太阳的一面（ζ > 0）。
  import { earthRy, groundToPlane } from '../../lib/anim/bessel';
  import type { Rings } from '../../lib/anim/land';
  import { t } from '../../lib/i18n';
  import type { Observer, SolarScene, SolarState } from '../../lib/types';

  let { scene, s, land, observer }: { scene: SolarScene; s: SolarState; land: Rings | null; observer: Observer | null } = $props();
  const uid = $props.id();

  const b = $derived(s.bessel);
  const ry = $derived(earthRy(b.d_deg));
  /** 视野半宽：地球之外留出半影的位置 */
  const HALF = 1.5;
  const k = 100 / HALF;
  const X = (x: number) => x * k;
  const Y = (y: number) => -y * k;

  /** 一串经纬度投影成路径；背面（ζ ≤ 0）的点断开 */
  function project(points: Iterable<[number, number]>): string {
    let d = '';
    let pen = false;
    for (const [lon, lat] of points) {
      const p = groundToPlane(lat, lon, b.d_deg, b.mu_deg);
      if (p.zeta <= 0) {
        pen = false;
        continue;
      }
      d += `${pen ? 'L' : 'M'}${X(p.xi).toFixed(2)},${Y(p.eta).toFixed(2)}`;
      pen = true;
    }
    return d;
  }

  function* ringPoints(r: Float32Array): Generator<[number, number]> {
    for (let i = 0; i + 1 < r.length; i += 2) yield [r[i], r[i + 1]];
  }

  const landPath = $derived(land ? land.map((r) => project(ringPoints(r))).join('') : '');
  const equator = $derived(project(Array.from({ length: 181 }, (_, i) => [i * 2 - 180, 0] as [number, number])));
  const centralLine = $derived(project(scene.central_line.map((p) => [p.lon_deg, p.lat_deg] as [number, number])));
  const obs = $derived(observer ? groundToPlane(observer.lat, observer.lon, b.d_deg, b.mu_deg) : null);
  const pole = $derived(groundToPlane(90, 0, b.d_deg, b.mu_deg));
</script>

<svg viewBox="-100 -100 200 200" class="block aspect-square w-full" role="img" aria-label={t('viewPlane')}>
  <defs>
    <clipPath id="{uid}-earth"><ellipse rx={k} ry={ry * k} /></clipPath>
  </defs>
  <ellipse rx={k} ry={ry * k} fill="var(--gx-surface-high)" stroke="var(--gx-outline)" stroke-width="0.8" />
  <path d={landPath} fill="none" stroke="var(--gx-on-surface-variant)" stroke-opacity="0.75" stroke-width="0.55" stroke-linejoin="round" />
  <path d={equator} fill="none" stroke="var(--gx-on-surface-variant)" stroke-opacity="0.4" stroke-width="0.5" stroke-dasharray="2 1.5" />
  {#if pole.zeta > 0}
    <text x={X(pole.xi)} y={Y(pole.eta) - 2.5} font-size="6" text-anchor="middle" fill="var(--gx-on-surface-variant)">{t('dirN')}</text>
  {/if}
  <path d={centralLine} fill="none" stroke="var(--gx-eclipse)" stroke-width="1" stroke-opacity="0.85" />

  <!-- 半影：落在地面上的部分加深，整圈用虚线 -->
  <circle cx={X(b.x)} cy={Y(b.y)} r={b.l1 * k} fill="color-mix(in srgb, var(--gx-sky) 30%, transparent)" clip-path="url(#{uid}-earth)" />
  <circle cx={X(b.x)} cy={Y(b.y)} r={b.l1 * k} fill="none" stroke="var(--gx-eclipse)" stroke-width="0.8" stroke-dasharray="3 2" />
  <circle cx={X(b.x)} cy={Y(b.y)} r={Math.max(Math.abs(b.l2) * k, 1.3)} fill="var(--gx-sky-moon)" stroke="var(--gx-eclipse)" stroke-width="0.6" />

  {#if obs && obs.zeta > 0}
    <circle cx={X(obs.xi)} cy={Y(obs.eta)} r="2.2" fill="none" stroke="var(--gx-primary)" stroke-width="1.2" />
    <circle cx={X(obs.xi)} cy={Y(obs.eta)} r="0.7" fill="var(--gx-primary)" />
  {/if}
</svg>
