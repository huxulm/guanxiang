<script lang="ts">
  // 日食示意图：贝塞尔基本面（从太阳方向看地球），x 向东、y 向北，单位为地球赤道半径。
  import { t } from '../lib/i18n';
  import type { SolarScene } from '../lib/types';

  let { scene }: { scene: SolarScene } = $props();

  const dg = $derived(scene.diagram);
  const d = $derived((dg.d_deg * Math.PI) / 180);
  /** 画面半径：地球、半影圈都要放得下 */
  const extent = $derived(Math.max(1.25, Math.hypot(dg.greatest.x, dg.greatest.y) + dg.l1 + 0.1));
  const k = $derived(100 / extent);
  const sx = (x: number) => x * k;
  const sy = (y: number) => -y * k;

  const track = $derived(
    dg.track
      .filter((p) => Math.hypot(p.x, p.y) < extent * 1.05)
      .map((p) => `${sx(p.x).toFixed(2)},${sy(p.y).toFixed(2)}`)
      .join(' '),
  );
  /** 轨迹末端的方向箭头 */
  const arrow = $derived.by(() => {
    const pts = dg.track.filter((p) => Math.hypot(p.x, p.y) < extent * 1.05);
    if (pts.length < 2) return '';
    const a = pts[pts.length - 2];
    const b = pts[pts.length - 1];
    const ang = Math.atan2(sy(b.y) - sy(a.y), sx(b.x) - sx(a.x));
    const L = 5;
    const [x, y] = [sx(b.x), sy(b.y)];
    const p1 = [x - L * Math.cos(ang - 0.45), y - L * Math.sin(ang - 0.45)];
    const p2 = [x - L * Math.cos(ang + 0.45), y - L * Math.sin(ang + 0.45)];
    return `M${p1.join(',')} L${x},${y} L${p2.join(',')}`;
  });
</script>

<figure class="space-y-3">
  <svg viewBox="-110 -110 220 220" class="mx-auto block w-full max-w-[440px]" role="img" aria-label={t('diagramTitle')}>
    <!-- 地球圆面、赤道（投影成椭圆）、地轴方向 -->
    <circle r={k} fill="var(--gx-surface-high)" stroke="var(--gx-outline)" stroke-width="0.8" />
    <ellipse rx={k} ry={Math.abs(Math.sin(d)) * k} fill="none" stroke="var(--gx-on-surface-variant)" stroke-opacity="0.45" stroke-width="0.5" stroke-dasharray="2 1.5" />
    <line x1="0" x2="0" y1={sy(Math.cos(d))} y2={sy(-Math.cos(d))} stroke="var(--gx-on-surface-variant)" stroke-opacity="0.45" stroke-width="0.5" />
    <text x="0" y={sy(Math.cos(d)) - 3} font-size="6" text-anchor="middle" fill="var(--gx-on-surface-variant)">{t('dirN')}</text>

    <!-- 食甚时的半影范围和本影 -->
    <circle
      cx={sx(dg.greatest.x)}
      cy={sy(dg.greatest.y)}
      r={dg.l1 * k}
      fill="color-mix(in srgb, var(--gx-eclipse) 10%, transparent)"
      stroke="var(--gx-eclipse)"
      stroke-width="0.7"
      stroke-dasharray="3 2"
    />
    <polyline points={track} fill="none" stroke="var(--gx-eclipse)" stroke-width="1" />
    <path d={arrow} fill="none" stroke="var(--gx-eclipse)" stroke-width="1" />
    <circle cx={sx(dg.greatest.x)} cy={sy(dg.greatest.y)} r={Math.max(Math.abs(dg.l2) * k, 1.4)} fill="var(--gx-on-surface)" />
  </svg>
  <figcaption class="text-xs leading-relaxed text-muted">{t('solarDiagramCaption')}</figcaption>
</figure>
