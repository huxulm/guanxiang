<script lang="ts">
  // 月食的天空画面：地影切平面，北在上、东在左（抬头所见），单位为度。
  // zoom = false：以地影中心为原点的总览；zoom = true：以月心为中心放大月面。
  // 月面上的本影、半影按此刻的真实几何关系画（把影子圆裁剪到月面圆内）。
  import type { LunarScene, LunarState } from '../../lib/types';

  let { scene, s, zoom = false }: { scene: LunarScene; s: LunarState; zoom?: boolean } = $props();
  const uid = $props.id();

  const R = $derived(s.radii_deg);
  // 东在左：屏幕 x = −x；北在上：屏幕 y = −y
  const mx = $derived(-s.x_deg);
  const my = $derived(-s.y_deg);

  /** 视野半宽（度）与中心 */
  const half = $derived(zoom ? R.moon * 1.45 : scene.radii_deg.penumbra + scene.radii_deg.moon * 2.4);
  const cx = $derived(zoom ? mx : 0);
  const cy = $derived(zoom ? my : 0);
  const viewBox = $derived(`${cx - half} ${cy - half} ${2 * half} ${2 * half}`);
  /** 线宽、字号按视野缩放，保持屏幕上大小一致 */
  const u = $derived(half / 110);

  const path = $derived(
    scene.path
      .filter((p) => Math.hypot(p.x_deg, p.y_deg) < half * 1.1)
      .map((p) => `${(-p.x_deg).toFixed(4)},${(-p.y_deg).toFixed(4)}`)
      .join(' '),
  );
</script>

<svg {viewBox} class="block aspect-square w-full" role="img">
  <defs>
    <clipPath id="{uid}-moon"><circle cx={mx} cy={my} r={R.moon} /></clipPath>
    <!-- 本影：中心更暗，边缘偏亮（示意） -->
    <radialGradient id="{uid}-umbra" gradientUnits="userSpaceOnUse" cx="0" cy="0" r={R.umbra}>
      <stop offset="0" stop-color="color-mix(in srgb, var(--gx-blood-moon) 45%, var(--gx-sky))" />
      <stop offset="0.8" stop-color="var(--gx-blood-moon)" />
      <stop offset="1" stop-color="color-mix(in srgb, var(--gx-blood-moon) 70%, var(--gx-moon-lit))" />
    </radialGradient>
    <!-- 半影：从本影边缘到半影边缘逐渐变亮 -->
    <radialGradient id="{uid}-pen" gradientUnits="userSpaceOnUse" cx="0" cy="0" r={R.penumbra}>
      <stop offset={R.umbra / R.penumbra} stop-color="var(--gx-sky)" stop-opacity="0.7" />
      <stop offset="1" stop-color="var(--gx-sky)" stop-opacity="0" />
    </radialGradient>
  </defs>

  {#if !zoom}
    <circle r={R.penumbra} fill="color-mix(in srgb, var(--gx-on-surface) 7%, transparent)" stroke="var(--gx-outline)" stroke-width={u * 0.8} />
    <circle r={R.umbra} fill="color-mix(in srgb, var(--gx-blood-moon) 22%, transparent)" stroke="var(--gx-blood-moon)" stroke-width={u * 0.8} />
    <polyline points={path} fill="none" stroke="var(--gx-on-surface-variant)" stroke-width={u * 0.7} stroke-dasharray="{u * 2.5} {u * 2}" />
    {#each scene.contacts as c (c.code)}
      <circle cx={-c.x_deg} cy={-c.y_deg} r={u * 1.3} fill="var(--gx-on-surface-variant)" />
    {/each}
  {:else}
    <rect x={cx - half} y={cy - half} width={2 * half} height={2 * half} fill="var(--gx-sky)" />
  {/if}

  <g clip-path="url(#{uid}-moon)">
    <circle cx={mx} cy={my} r={R.moon} fill="var(--gx-moon-lit)" />
    <circle r={R.penumbra} fill="url(#{uid}-pen)" />
    <circle r={R.umbra} fill="url(#{uid}-umbra)" />
  </g>
  <circle cx={mx} cy={my} r={R.moon} fill="none" stroke="var(--gx-on-surface-variant)" stroke-width={u * (zoom ? 0.6 : 0.9)} />
  {#if zoom}
    <!-- 本影、半影边缘 -->
    <circle r={R.umbra} fill="none" stroke="var(--gx-blood-moon)" stroke-width={u * 0.8} stroke-dasharray="{u * 3} {u * 2}" />
    <circle r={R.penumbra} fill="none" stroke="var(--gx-outline)" stroke-width={u * 0.8} stroke-dasharray="{u * 3} {u * 2}" />
  {/if}
</svg>
