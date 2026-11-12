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

  type PhaseSegment = { left: string; width: string; color: string; opacity: number };

  const phaseSegments = $derived.by((): PhaseSegment[] => {
    const segs: PhaseSegment[] = [];
    const findT = (code: string) => marks.find((m) => m.code === code)?.t;
    const clampT = (t: number) => Math.max(tl.min, Math.min(tl.max, t));
    const makeSeg = (tA: number, tB: number, color: string, opacity: number): PhaseSegment | null => {
      const a = clampT(Math.min(tA, tB));
      const b = clampT(Math.max(tA, tB));
      if (b <= a || span <= 0) return null;
      return {
        left: `${((a - tl.min) / span) * 100}%`,
        width: `${((b - a) / span) * 100}%`,
        color,
        opacity,
      };
    };

    // Solar
    const c1 = findT('C1');
    const c2 = findT('C2');
    const c3 = findT('C3');
    const c4 = findT('C4');
    if (c1 !== undefined && c4 !== undefined) {
      const sPart = makeSeg(c1, c4, 'var(--gx-eclipse)', 0.3);
      if (sPart) segs.push(sPart);
      if (c2 !== undefined && c3 !== undefined) {
        const sTot = makeSeg(c2, c3, 'var(--gx-eclipse)', 0.9);
        if (sTot) segs.push(sTot);
      }
    }

    // Lunar
    const p1 = findT('P1');
    const u1 = findT('U1');
    const u2 = findT('U2');
    const u3 = findT('U3');
    const u4 = findT('U4');
    const p4 = findT('P4');
    if (p1 !== undefined && p4 !== undefined) {
      const sPenum = makeSeg(p1, p4, 'var(--gx-on-surface-variant)', 0.25);
      if (sPenum) segs.push(sPenum);
    }
    if (u1 !== undefined && u4 !== undefined) {
      const sUmb = makeSeg(u1, u4, 'var(--gx-blood-moon)', 0.5);
      if (sUmb) segs.push(sUmb);
      if (u2 !== undefined && u3 !== undefined) {
        const sTot = makeSeg(u2, u3, 'var(--gx-blood-moon)', 0.95);
        if (sTot) segs.push(sTot);
      }
    }

    return segs;
  });

  function onKeyDown(e: KeyboardEvent) {
    const tag = (e.target as HTMLElement)?.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;

    if (e.code === 'Space') {
      e.preventDefault();
      tl.toggle();
    } else if (e.code === 'ArrowLeft') {
      e.preventDefault();
      tl.pause();
      const step = e.shiftKey ? 60 : 10;
      tl.seek(Math.max(tl.min, tl.t - step));
    } else if (e.code === 'ArrowRight') {
      e.preventDefault();
      tl.pause();
      const step = e.shiftKey ? 60 : 10;
      tl.seek(Math.min(tl.max, tl.t + step));
    } else if (e.key === '[' || e.key === 'BracketLeft') {
      e.preventDefault();
      const prevMarks = visibleMarks.filter((m) => m.t < tl.t - 0.5);
      if (prevMarks.length) {
        tl.pause();
        tl.seek(prevMarks[prevMarks.length - 1].t);
      }
    } else if (e.key === ']' || e.key === 'BracketRight') {
      e.preventDefault();
      const nextMarks = visibleMarks.filter((m) => m.t > tl.t + 0.5);
      if (nextMarks.length) {
        tl.pause();
        tl.seek(nextMarks[0].t);
      }
    }
  }
</script>

<svelte:window onkeydown={onKeyDown} />

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

  <div class="space-y-1 pt-2">
    <!-- 彩色阶段条与接触刻度 -->
    <div class="relative h-2 w-full">
      {#if phaseSegments.length > 0}
        <div class="absolute inset-x-0 top-0.5 h-1.5 overflow-hidden rounded-full bg-surface-3">
          {#each phaseSegments as seg}
            <div
              class="absolute top-0 bottom-0"
              style:left={seg.left}
              style:width={seg.width}
              style:background-color={seg.color}
              style:opacity={seg.opacity}
            ></div>
          {/each}
        </div>
      {/if}
      {#each visibleMarks as m (m.code)}
        <span
          class="absolute -top-1 h-3.5 w-px -translate-x-1/2 bg-outline"
          style:left={pos(m.t)}
          aria-hidden="true"
        ></span>
      {/each}
    </div>
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

  <div class="flex flex-wrap items-center gap-1.5">
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
    <span class="ml-auto hidden text-[11px] text-muted sm:inline-block cursor-help" title={t('keyHint')}>
      ⌨ {t('keyHintShort')}
    </span>
  </div>
</div>
