<script lang="ts">
  // 观测地看到的太阳：天顶朝上（接近抬头所见）。单位为太阳视半径。
  // 月心偏移 (x 向东, y 向北) 先按天空方位画（北上东左），再整体旋转天顶位置角 q，使天顶朝上；
  // 地平线不随旋转，画在太阳中心下方 h（太阳视高度）处，太阳低时能看到带食日出、日落。
  import { t } from '../../lib/i18n';
  import type { DiskView } from '../../lib/types';

  let { v, total }: { v: DiskView; total: boolean } = $props();
  const uid = $props.id();

  const R = $derived(v.sun_r_deg);
  /** 视野半宽（太阳半径） */
  const HALF = 2.6;
  const mx = $derived(-v.x_deg / R);
  const my = $derived(-v.y_deg / R);
  const mr = $derived(v.moon_r_deg / R);
  const q = $derived(v.zenith_angle_deg);
  /** 地平线在画面上的位置（太阳中心以下多少个太阳半径） */
  const horizon = $derived(v.sun_alt_deg / R);
  /**
   * 日全食：只有月面在几何上完全盖住日面（圆心距 + 日半径 ≤ 月半径）时才画日冕。
   * 不用“食面积接近 100%”判断：食既前几秒还剩一线日面，此时画日冕会让人误以为可以摘下滤光片。
   */
  const corona = $derived(total && Math.hypot(v.x_deg, v.y_deg) + v.sun_r_deg <= v.moon_r_deg);
</script>

<svg viewBox="{-HALF} {-HALF} {2 * HALF} {2 * HALF}" class="block aspect-square w-full rounded-xl" role="img" aria-label={t('viewSun')}>
  <defs>
    <!-- 临边昏暗：中心亮、边缘暗 -->
    <radialGradient id="{uid}-sun">
      <stop offset="0" stop-color="color-mix(in srgb, var(--gx-eclipse) 55%, var(--gx-moon-lit))" />
      <stop offset="0.75" stop-color="var(--gx-eclipse)" />
      <stop offset="1" stop-color="color-mix(in srgb, var(--gx-eclipse) 70%, var(--gx-sky))" />
    </radialGradient>
    <radialGradient id="{uid}-corona" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="2.4">
      <stop offset="0.4" stop-color="var(--gx-moon-lit)" stop-opacity="0.9" />
      <stop offset="0.6" stop-color="var(--gx-moon-lit)" stop-opacity="0.25" />
      <stop offset="1" stop-color="var(--gx-moon-lit)" stop-opacity="0" />
    </radialGradient>
  </defs>
  <rect x={-HALF} y={-HALF} width={2 * HALF} height={2 * HALF} fill="var(--gx-sky)" />

  <g transform="rotate({q})">
    {#if corona}
      <circle r="2.4" fill="url(#{uid}-corona)" />
    {/if}
    <circle r="1" fill="url(#{uid}-sun)" />
    <circle cx={mx} cy={my} r={mr} fill="var(--gx-sky-moon)" />
    <!-- 天球北方向 -->
    <g transform="translate(0 {-HALF + 0.65})">
      <text font-size="0.22" text-anchor="middle" dominant-baseline="central" fill="var(--gx-on-surface-variant)" transform="rotate({-q})">{t('dirN')}</text>
    </g>
  </g>

  {#if horizon < HALF}
    <!-- 地面：从地平线填到画面底部（太阳在地平线下时整个画面都是地面） -->
    <rect x={-HALF} y={Math.max(horizon, -HALF)} width={2 * HALF} height={HALF - Math.max(horizon, -HALF)} fill="var(--gx-surface-high)" fill-opacity="0.92" />
    <line x1={-HALF} x2={HALF} y1={horizon} y2={horizon} stroke="var(--gx-on-surface-variant)" stroke-width="0.02" />
    {#if horizon > -HALF + 0.3}
      <text x={HALF - 0.1} y={horizon - 0.08} font-size="0.2" text-anchor="end" fill="var(--gx-on-surface-variant)">{t('horizon')}</text>
    {/if}
  {/if}
  <text x="0" y={-HALF + 0.12} font-size="0.2" text-anchor="middle" dominant-baseline="hanging" fill="var(--gx-on-surface-variant)">↑ {t('zenith')}</text>
</svg>
