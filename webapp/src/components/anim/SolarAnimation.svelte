<script lang="ts">
  // 日食动画：时间轴 + 从太阳看地球（基本面）+ 观测地看到的太阳 + 世界地图 + 食面积、太阳高度曲线。
  // 每一帧都由 Worker 精确求值（贝塞尔根数、影轴地面点、站心日面）。
  import { untrack } from 'svelte';
  import MapView from './MapView.svelte';
  import PlaneView from './PlaneView.svelte';
  import SunDiskView from './SunDiskView.svelte';
  import TimeChart from './TimeChart.svelte';
  import TimelineBar from './TimelineBar.svelte';
  import { Timeline, defaultSpeed } from '../../lib/anim/timeline.svelte';
  import { frameState } from '../../lib/anim/frames.svelte';
  import { loadLand, type Rings } from '../../lib/anim/land';
  import { getEngine } from '../../lib/engine/engine.svelte';
  import { fmtNum, parseUtc, solarKindName } from '../../lib/format';
  import { t } from '../../lib/i18n';
  import type { Observer, SolarScene, SolarState } from '../../lib/types';

  let {
    scene: sceneProp,
    date,
    observer: observerProp,
  }: { scene: SolarScene; date: string; observer: Observer | null } = $props();
  // 详情页按场景对象 {#key} 重建本组件，这里只取初始值
  const { scene, observer } = untrack(() => ({ scene: sceneProp, observer: observerProp }));
  const local = scene.local;
  const obs = observer ? { lat: observer.lat, lon: observer.lon, height: observer.height } : null;

  // 两种范围：全球（半影接触地球的整段时间）和本地（初亏前到复圆后各 10 分钟）
  const track = scene.diagram.track;
  const globalRange: [number, number] = [track[0].t_rel_s, track[track.length - 1].t_rel_s];
  const lc = (code: string) => local?.contacts.find((c) => c.code === code)?.t_rel_s;
  const localRange: [number, number] | null =
    local && lc('C1') !== undefined && lc('C4') !== undefined ? [lc('C1')! - 600, lc('C4')! + 600] : null;

  let range = $state<'local' | 'global'>(localRange ? 'local' : 'global');
  const initial = localRange ?? globalRange;
  const tl = new Timeline(initial[0], initial[1], lc('MAX') ?? 0, defaultSpeed(initial[1] - initial[0]));
  $effect(() => () => tl.dispose());

  function setRange(r: 'local' | 'global'): void {
    range = r;
    const [a, b] = r === 'local' && localRange ? localRange : globalRange;
    tl.setRange(a, b, tl.t, defaultSpeed(b - a));
  }

  const frame = frameState<SolarState>(
    () => tl.t,
    (tt) => getEngine().then((e) => e.solarState(date, tt, obs)),
  );

  let land = $state<Rings | null>(null);
  let mapFocused = $state(false);
  $effect(() => {
    loadLand().then((r) => (land = r));
  });

  const base = parseUtc(scene.greatest_utc);
  const marks = local
    ? local.contacts.map((c) => ({ code: c.code, t: c.t_rel_s }))
    : [{ code: 'G', t: 0 }];

  const centralKind = local && (local.kind === 'total' || local.kind === 'annular') ? local.kind : null;
  const phase = $derived.by(() => {
    if (!local) return solarKindName(scene.kind);
    const x = tl.t;
    const [c1, c2, c3, c4] = ['C1', 'C2', 'C3', 'C4'].map(lc);
    if (c1 === undefined || c4 === undefined || x < c1) return t('solarStateBefore');
    if (x > c4) return t('solarStateAfter');
    if (centralKind && c2 !== undefined && c3 !== undefined && x >= c2 && x <= c3) {
      return t(centralKind === 'total' ? 'solarStateTotal' : 'solarStateAnnular');
    }
    return t('solarStatePartial');
  });

  const obscPoints = local ? local.disk_frames.map((f) => [f.t_rel_s, f.obscuration * 100] as [number, number]) : [];
  const altPoints = local ? local.disk_frames.map((f) => [f.t_rel_s, f.sun_alt_deg] as [number, number]) : [];

  /** 此刻的食分：日月圆心距换算（与 local_solar 的偏食定义相同） */
  function magnitude(v: { x_deg: number; y_deg: number; sun_r_deg: number; moon_r_deg: number }): number {
    return Math.max(0, (v.sun_r_deg + v.moon_r_deg - Math.hypot(v.x_deg, v.y_deg)) / (2 * v.sun_r_deg));
  }
</script>

<section class="card space-y-4">
  <div class="flex flex-wrap items-center gap-2">
    <h2 class="mr-auto font-semibold">{t('animTitle')}</h2>
    {#if localRange}
      <button class={['chip', range === 'local' && 'chip-on']} onclick={() => setRange('local')}>{t('rangeLocal')}</button>
      <button class={['chip', range === 'global' && 'chip-on']} onclick={() => setRange('global')}>{t('rangeGlobal')}</button>
    {/if}
  </div>
  <TimelineBar {tl} {marks} {base} {phase} utc={frame.current?.utc} />

  {#if observer && !local}
    <p class="text-sm text-muted">{t('noLocalEclipse')}</p>
  {/if}

  {#if frame.current}
    {@const s = frame.current}
    <div class={['grid gap-4', s.local && local && 'sm:grid-cols-2']}>
      <figure class="space-y-1">
        <figcaption class="label">{t('viewPlane')}</figcaption>
        <PlaneView {scene} {s} {land} {observer} />
      </figure>
      {#if s.local && local}
        <figure class="space-y-1">
          <figcaption class="label">{t('viewSun')}</figcaption>
          <SunDiskView v={s.local} total={local.kind === 'total'} />
          <dl class="num grid grid-cols-3 gap-2 pt-1 text-sm">
            <div><dt class="label">{t('magnitude')}</dt><dd>{fmtNum(magnitude(s.local), 3)}</dd></div>
            <div><dt class="label">{t('obscuration')}</dt><dd>{fmtNum(s.local.obscuration * 100, 1)}%</dd></div>
            <div>
              <dt class="label">{t('sunAlt')}</dt>
              <dd class={s.local.sun_alt_deg <= 0 ? 'text-muted' : ''}>{fmtNum(s.local.sun_alt_deg, 1)}°</dd>
            </div>
          </dl>
        </figure>
      {/if}
    </div>
    <figure class="space-y-1">
      <figcaption class="flex items-center justify-between">
        <span class="label">{t('viewMap')}</span>
        <div class="flex gap-1" role="group" aria-label={t('viewMap')}>
          <button
            class={['chip !py-0.5 !px-2 text-xs', !mapFocused && 'chip-on']}
            onclick={() => (mapFocused = false)}
          >
            {t('mapGlobal')}
          </button>
          <button
            class={['chip !py-0.5 !px-2 text-xs', mapFocused && 'chip-on']}
            onclick={() => (mapFocused = true)}
          >
            {t('mapFocus')}
          </button>
        </div>
      </figcaption>
      <MapView {scene} {s} {land} {observer} focused={mapFocused} />
    </figure>
  {:else if frame.error}
    <p class="text-sm text-error">{t('computeFailed', { error: frame.error })}</p>
  {:else}
    <div class="aspect-[2/1] w-full animate-pulse rounded-xl bg-surface-2"></div>
  {/if}

  {#if local}
    <div class="space-y-1">
      <p class="label">{t('chartObsc')}</p>
      <TimeChart
        series={[{ label: t('chartObsc'), color: 'var(--gx-eclipse)', points: obscPoints }]}
        t={tl.t}
        tMin={tl.min}
        tMax={tl.max}
        yMin={0}
        yMax={100}
        yTicks={[0, 25, 50, 75, 100]}
        yFormat={(v) => `${v}%`}
        {base}
        {marks}
      />
    </div>
    <div class="space-y-1">
      <p class="label">{t('chartSunAlt')}</p>
      <TimeChart
        series={[{ label: t('chartSunAlt'), color: 'var(--gx-primary)', points: altPoints }]}
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
  <p class="text-xs leading-relaxed text-muted">{t('planeCaption')}</p>
  <p class="text-xs leading-relaxed text-muted">{t('mapCaption')}</p>
  {#if local}<p class="text-xs leading-relaxed text-muted">{t('solarSimCaption')}</p>{/if}
</section>
