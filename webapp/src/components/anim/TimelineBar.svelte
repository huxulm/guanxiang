<script lang="ts">
  // 时间轴控制：播放/暂停、拖动、倍速、跳到各接触时刻。
  import { fmtTime } from '../../lib/format';
  import { t } from '../../lib/i18n';
  import type { Timeline } from '../../lib/anim/timeline.svelte';

  type Mark = { code: string; t: number };
  let {
    tl,
    marks,
    base,
    phase,
    utc,
  }: {
    tl: Timeline;
    marks: Mark[];
    /** t = 0（食甚）对应的时刻 */
    base: Date;
    /** 当前所处的食相文字 */
    phase: string;
    /** 当前帧精确的 UTC（来自 Worker），没有时按 base + t 推算 */
    utc?: string;
  } = $props();

  const SPEEDS = [60, 300, 1200];
  const now = $derived(utc ? new Date(utc) : new Date(base.getTime() + tl.t * 1000));
  const span = $derived(Math.max(1, tl.max - tl.min));
  const pos = (x: number) => `${((x - tl.min) / span) * 100}%`;

  /** 相对食甚：±h:mm:ss */
  function rel(x: number): string {
    const s = Math.round(Math.abs(x));
    const hms = `${Math.floor(s / 3600)}:${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
    return `${x < 0 ? '−' : '+'}${hms}`;
  }

  const visibleMarks = $derived(marks.filter((m) => m.t >= tl.min && m.t <= tl.max));
</script>

<div class="space-y-3">
  <div class="flex flex-wrap items-center gap-3">
    <button
      class="btn-filled h-11 w-11 !p-0"
      onclick={() => tl.toggle()}
      aria-label={tl.playing ? t('pause') : t('play')}
      title={tl.playing ? t('pause') : t('play')}
    >
      {#if tl.playing}
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="currentColor" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>
      {:else}
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="currentColor" aria-hidden="true"><path d="M8 5.5v13a1 1 0 0 0 1.5.9l10.4-6.5a1 1 0 0 0 0-1.8L9.5 4.6A1 1 0 0 0 8 5.5z" /></svg>
      {/if}
    </button>
    <div class="min-w-0">
      <div class="num text-xl font-semibold leading-tight">{fmtTime(now)}</div>
      <div class="num text-xs text-muted">{phase} · {t('phaseG')} {rel(tl.t)}</div>
    </div>
    <div class="ml-auto flex items-center gap-1" role="group" aria-label={t('speed')}>
      {#each SPEEDS as s (s)}
        <button class={['chip !px-2.5 num', tl.speed === s && 'chip-on']} onclick={() => (tl.speed = s)}>×{s}</button>
      {/each}
    </div>
  </div>

  <div class="relative pt-3">
    {#each visibleMarks as m (m.code)}
      <span class="absolute top-0 h-2.5 w-px bg-outline" style:left={pos(m.t)} aria-hidden="true"></span>
    {/each}
    <input
      type="range"
      class="w-full accent-primary"
      min={tl.min}
      max={tl.max}
      step="any"
      value={tl.t}
      oninput={(e) => {
        tl.pause();
        tl.seek(Number(e.currentTarget.value));
      }}
      aria-label={t('lunarSliderLabel')}
      aria-valuetext={fmtTime(now)}
    />
  </div>

  <div class="flex flex-wrap gap-1.5">
    {#each visibleMarks as m (m.code)}
      <button
        class={['chip num !py-0.5 text-xs', Math.abs(tl.t - m.t) < 1 && 'chip-on']}
        onclick={() => {
          tl.pause();
          tl.seek(m.t);
        }}
      >
        {t(`phase${m.code}`)}
        <span class="ml-1 opacity-70">{fmtTime(new Date(base.getTime() + m.t * 1000), false)}</span>
      </button>
    {/each}
  </div>
</div>
