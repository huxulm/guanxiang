<script lang="ts">
  // 月食示意图：地影切平面，北在上、东在左（抬头所见）。单位为度，画布以地影中心为原点。
  import { t } from '../lib/i18n';
  import type { LunarScene } from '../lib/types';

  let { scene }: { scene: LunarScene } = $props();

  const r = $derived(scene.radii_deg);
  /** 画面半径（度）：半影外再留出一个月球直径多一点 */
  const extent = $derived(r.penumbra + r.moon * 2.4);
  const k = $derived(100 / extent);
  // 东在左：屏幕 x = −x；北在上：屏幕 y = −y
  const sx = (x: number) => -x * k;
  const sy = (y: number) => -y * k;

  const path = $derived(
    scene.path
      .filter((p) => Math.hypot(p.x_deg, p.y_deg) < extent * 1.1)
      .map((p) => `${sx(p.x_deg).toFixed(2)},${sy(p.y_deg).toFixed(2)}`)
      .join(' '),
  );

  /** 接触点标签放在月球外侧（离地影中心的方向） */
  function labelPos(x: number, y: number): [number, number] {
    const d = Math.hypot(x, y) || 1;
    const off = r.moon * 1.9;
    return [sx(x + (x / d) * off), sy(y + (y / d) * off)];
  }
</script>

<figure class="space-y-3">
  <svg viewBox="-110 -110 220 220" class="mx-auto block w-full max-w-[440px]" role="img" aria-label={t('diagramTitle')}>
    <circle r={r.penumbra * k} fill="color-mix(in srgb, var(--gx-on-surface) 9%, transparent)" stroke="var(--gx-outline)" stroke-width="0.6" />
    <circle r={r.umbra * k} fill="color-mix(in srgb, var(--gx-blood-moon) 42%, transparent)" stroke="var(--gx-blood-moon)" stroke-width="0.6" />
    <line x1="-104" x2="104" y1="0" y2="0" stroke="var(--gx-outline)" stroke-width="0.3" />
    <line y1="-104" y2="104" x1="0" x2="0" stroke="var(--gx-outline)" stroke-width="0.3" />
    <polyline points={path} fill="none" stroke="var(--gx-on-surface-variant)" stroke-width="0.6" stroke-dasharray="2 1.6" />

    {#each scene.contacts as c (c.code)}
      {@const [lx, ly] = labelPos(c.x_deg, c.y_deg)}
      <circle
        cx={sx(c.x_deg)}
        cy={sy(c.y_deg)}
        r={r.moon * k}
        fill={c.code === 'G' ? 'color-mix(in srgb, var(--gx-moon-lit) 22%, transparent)' : 'none'}
        stroke="var(--gx-on-surface-variant)"
        stroke-width={c.code === 'G' ? 0.8 : 0.45}
      />
      <text x={lx} y={ly} font-size="6.5" text-anchor="middle" dominant-baseline="middle" fill="var(--gx-on-surface-variant)">{c.code}</text>
    {/each}

    <text x="0" y="-104" font-size="6" text-anchor="middle" dominant-baseline="hanging" fill="var(--gx-on-surface-variant)">{t('dirN')}</text>
    <text x="-104" y="0" font-size="6" dominant-baseline="middle" fill="var(--gx-on-surface-variant)">{t('dirE')}</text>
  </svg>
  <figcaption class="text-xs leading-relaxed text-muted">{t('lunarDiagramCaption')}</figcaption>
</figure>
