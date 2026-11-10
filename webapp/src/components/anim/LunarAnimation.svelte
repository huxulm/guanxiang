<script lang="ts">
  import { untrack } from 'svelte';
  // 月食动画：时间轴 + 地影总览 + 月面特写 + 食分、月亮高度曲线。每一帧都由 Worker 精确求值。
  import LunarSky from './LunarSky.svelte';
  import TimeChart from './TimeChart.svelte';
  import TimelineBar from './TimelineBar.svelte';
  import { Timeline, defaultSpeed } from '../../lib/anim/timeline.svelte';
  import { frameState } from '../../lib/anim/frames.svelte';
  import { getEngine } from '../../lib/engine/engine.svelte';
  import { fmtNum, parseUtc } from '../../lib/format';
  import { t } from '../../lib/i18n';
  import type { LunarScene, LunarState, Observer } from '../../lib/types';

  let {
    scene: sceneProp,
    date,
    observer: observerProp,
  }: { scene: LunarScene; date: string; observer: Observer | null } = $props();
  // 详情页按场景对象 {#key} 重建本组件，这里只取初始值
  const { scene, observer } = untrack(() => ({ scene: sceneProp, observer: observerProp }));

  const first = scene.path[0].t_rel_s;
  const last = scene.path[scene.path.length - 1].t_rel_s;
  const tl = new Timeline(first, last, 0, defaultSpeed(last - first));
  $effect(() => () => tl.dispose());

  const obs = observer ? { lat: observer.lat, lon: observer.lon, height: observer.height } : null;
  const frame = frameState<LunarState>(
    () => tl.t,
    (tt) => getEngine().then((e) => e.lunarState(date, tt, obs)),
  );

  const base = parseUtc(scene.greatest_utc);
  const marks = scene.contacts.map((c) => ({ code: c.code, t: c.t_rel_s }));
  const ct = (code: string) => scene.contacts.find((c) => c.code === code)?.t_rel_s;

  /** 此刻所处的食相 */
  const phase = $derived.by(() => {
    const x = tl.t;
    const [p1, u1, u2, u3, u4, p4] = ['P1', 'U1', 'U2', 'U3', 'U4', 'P4'].map(ct);
    if (p1 === undefined || p4 === undefined || x < p1) return t('lunarStateBefore');
    if (x > p4) return t('lunarStateAfter');
    if (u2 !== undefined && u3 !== undefined && x >= u2 && x <= u3) return t('lunarStateTotal');
    if (u1 !== undefined && u4 !== undefined && x >= u1 && x <= u4) return t('lunarStatePartial');
    return t('lunarStatePenumbral');
  });

  const magSeries = [
    { label: t('umbralMag'), color: 'var(--gx-blood-moon)', points: scene.path.map((p) => [p.t_rel_s, p.umbral_mag] as [number, number]) },
    { label: t('penumbralMag'), color: 'var(--gx-on-surface-variant)', dashed: true, points: scene.path.map((p) => [p.t_rel_s, p.penumbral_mag] as [number, number]) },
  ];
  const magMax = Math.max(1, Math.ceil(Math.max(...scene.path.map((p) => p.penumbral_mag)) * 2) / 2);
  const altPoints = scene.path.filter((p) => p.altitude_deg !== null).map((p) => [p.t_rel_s, p.altitude_deg as number] as [number, number]);
</script>

<section class="card space-y-4">
  <h2 class="font-semibold">{t('animTitle')}</h2>
  <TimelineBar {tl} {marks} {base} {phase} utc={frame.current?.utc} />

  {#if frame.current}
    {@const s = frame.current}
    <div class="grid gap-4 sm:grid-cols-2">
      <figure class="space-y-1">
        <figcaption class="label">{t('viewShadow')}</figcaption>
        <LunarSky {scene} {s} />
      </figure>
      <figure class="space-y-1">
        <figcaption class="label">{t('viewMoon')}</figcaption>
        <div class="overflow-hidden rounded-xl">
          <LunarSky {scene} {s} zoom />
        </div>
        <dl class="num grid grid-cols-3 gap-2 pt-1 text-sm">
          <div><dt class="label">{t('umbralMag')}</dt><dd>{fmtNum(Math.max(0, s.umbral_mag), 3)}</dd></div>
          <div><dt class="label">{t('penumbralMag')}</dt><dd>{fmtNum(Math.max(0, s.penumbral_mag), 3)}</dd></div>
          {#if s.altitude_deg !== null}
            <div>
              <dt class="label">{t('moonAlt')}</dt>
              <dd class={s.altitude_deg <= 0 ? 'text-muted' : ''}>{fmtNum(s.altitude_deg, 1)}°</dd>
            </div>
          {/if}
        </dl>
      </figure>
    </div>
  {:else if frame.error}
    <p class="text-sm text-error">{t('computeFailed', { error: frame.error })}</p>
  {:else}
    <div class="aspect-[2/1] w-full animate-pulse rounded-xl bg-surface-2"></div>
  {/if}

  <div class="space-y-1">
    <p class="label">{t('chartMag')}</p>
    <TimeChart
      series={magSeries}
      t={tl.t}
      tMin={tl.min}
      tMax={tl.max}
      yMin={0}
      yMax={magMax}
      yTicks={Array.from({ length: magMax * 2 + 1 }, (_, i) => i / 2)}
      yFormat={(v) => fmtNum(v, 1)}
      {base}
      {marks}
    />
  </div>
  {#if altPoints.length}
    <div class="space-y-1">
      <p class="label">{t('chartMoonAlt')}</p>
      <TimeChart
        series={[{ label: t('chartMoonAlt'), color: 'var(--gx-primary)', points: altPoints }]}
        t={tl.t}
        tMin={tl.min}
        tMax={tl.max}
        yMin={-30}
        yMax={90}
        yTicks={[-30, 0, 30, 60, 90]}
        yFormat={(v) => `${v}°`}
        {base}
        {marks}
        zeroLine
        height={120}
      />
    </div>
  {/if}
  <p class="text-xs leading-relaxed text-muted">{t('lunarAnimCaption')}</p>
</section>
