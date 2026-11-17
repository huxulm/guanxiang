<script lang="ts">
  // 9:16 竖屏全屏/沉浸式演示视图：适合手机端全屏沉浸观测与录屏/投屏。
  import MapView from './MapView.svelte';
  import SunDiskView from './SunDiskView.svelte';
  import TimelineBar from './TimelineBar.svelte';
  import { calcAzimuth, fmtAzimuth } from '../../lib/azimuth';
  import { fmtNum, parseUtc, solarKindName } from '../../lib/format';
  import { t } from '../../lib/i18n';
  import { settings } from '../../lib/settings.svelte';
  import type { Rings } from '../../lib/anim/land';
  import type { Timeline } from '../../lib/anim/timeline.svelte';
  import type { Observer, SolarScene, SolarState } from '../../lib/types';

  type Props = {
    scene: SolarScene;
    date: string;
    s: SolarState;
    tl: Timeline;
    land: Rings | null;
    observer: Observer | null;
    phase: string;
    onExportVideo: () => void;
  };

  let { scene, date, s, tl, land, observer, phase, onExportVideo }: Props = $props();

  let dialog: HTMLDialogElement;

  export function open(): void {
    dialog.showModal();
  }

  export function close(): void {
    dialog.close();
  }

  const base = $derived(parseUtc(scene.greatest_utc));
  const marks = $derived(
    scene.local
      ? scene.local.contacts.map((c) => ({ code: c.code, t: c.t_rel_s }))
      : [{ code: 'G', t: 0 }],
  );

  const az = $derived(observer ? calcAzimuth(observer.lat, observer.lon, s.sub_solar.lat_deg, s.sub_solar.lon_deg) : null);

  function magnitude(v: { x_deg: number; y_deg: number; sun_r_deg: number; moon_r_deg: number }): number {
    return Math.max(0, (v.sun_r_deg + v.moon_r_deg - Math.hypot(v.x_deg, v.y_deg)) / (2 * v.sun_r_deg));
  }
</script>

<dialog
  bind:this={dialog}
  class="m-auto w-[min(94vw,440px)] max-h-[92vh] overflow-y-auto rounded-3xl border border-outline bg-surface-2 p-0 text-fg shadow-2xl backdrop:bg-bg/85"
  onclick={(e) => e.target === dialog && close()}
>
  <div class="flex flex-col gap-3 p-4 sm:p-5">
    <!-- 顶栏 -->
    <div class="flex items-center justify-between border-b border-outline pb-2.5">
      <div class="space-y-0.5">
        <div class="flex items-center gap-2">
          <span class="text-xs font-bold tracking-wider text-primary">观象 · GUANXIANG</span>
          <span class="rounded-full bg-primary/20 px-2 py-0.2 text-[10px] text-primary">9:16</span>
        </div>
        <h2 class="text-base font-bold text-fg leading-tight">
          {date} · {solarKindName(scene.kind)}
        </h2>
      </div>
      <div class="flex items-center gap-1.5">
        <button
          class="chip !py-1 !px-2 text-xs text-primary"
          onclick={() => {
            close();
            onExportVideo();
          }}
          title={t('exportVideo')}
        >
          📹 {t('exportVideo')}
        </button>
        <button class="btn-text !p-1 text-muted hover:text-fg" onclick={close} aria-label={t('close')}>
          ✕
        </button>
      </div>
    </div>

    <!-- 观测地标签 -->
    {#if observer}
      <div class="flex items-center justify-between rounded-xl bg-surface px-3 py-1.5 text-xs">
        <span class="text-muted">📍 {observer.label ?? `${observer.lat.toFixed(2)}°, ${observer.lon.toFixed(2)}°`}</span>
        <span class="font-semibold text-eclipse">{phase}</span>
      </div>
    {/if}

    <!-- 中心主视界：日面特写 -->
    <div class="relative overflow-hidden rounded-2xl border border-outline bg-black aspect-square shadow-inner">
      {#if s.local}
        <SunDiskView v={s.local} total={scene.kind === 'total'} />
      {:else}
        <div class="grid h-full place-items-center p-4 text-center text-sm text-muted">
          {t('noLocalEclipse')}
        </div>
      {/if}
    </div>

    <!-- 实时数据看板 -->
    {#if s.local}
      <dl class="num grid grid-cols-4 gap-2 rounded-xl border border-outline-variant bg-surface p-2.5 text-center text-xs">
        <div>
          <dt class="label text-[10px]">{t('magnitude')}</dt>
          <dd class="font-bold text-eclipse">{fmtNum(magnitude(s.local), 3)}</dd>
        </div>
        <div>
          <dt class="label text-[10px]">{t('obscuration')}</dt>
          <dd class="font-bold">{fmtNum(s.local.obscuration * 100, 1)}%</dd>
        </div>
        <div>
          <dt class="label text-[10px]">{t('sunAlt')}</dt>
          <dd class={['font-bold', s.local.sun_alt_deg <= 0 && 'text-muted']}>{fmtNum(s.local.sun_alt_deg, 1)}°</dd>
        </div>
        <div>
          <dt class="label text-[10px]">{t('sunAzimuth')}</dt>
          <dd class="font-bold text-primary">{az ? fmtAzimuth(az, settings.lang) : '—'}</dd>
        </div>
      </dl>
    {/if}

    <!-- 地球投影微型缩略图 -->
    <div class="relative overflow-hidden rounded-xl border border-outline-variant bg-surface-3">
      <div class="px-2 pt-1.5 text-[11px] text-muted">{t('viewMap')}</div>
      <MapView {scene} {s} {land} {observer} />
    </div>

    <!-- 底部时间轴控制 -->
    <div class="rounded-xl border border-outline bg-surface p-3">
      <TimelineBar {tl} {marks} {base} {phase} utc={s.utc} />
    </div>

    <!-- 安全警示 -->
    <p class="text-center text-[10px] font-medium text-error">
      {t('posterSolarSafety')}
    </p>
  </div>
</dialog>
