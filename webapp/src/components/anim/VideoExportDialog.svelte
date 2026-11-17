<script lang="ts">
  // 纯前端动画视频录制与导出对话框：支持 1080p 9:16 竖屏短视频与 1:1 日面特写高清视频生成。
  import { getEngine } from '../../lib/engine/engine.svelte';
  import { t } from '../../lib/i18n';
  import { settings } from '../../lib/settings.svelte';
  import type { Rings } from '../../lib/anim/land';
  import {
    drawSunDisk,
    getSupportedVideoMime,
    renderVerticalFrame,
  } from '../../lib/anim/video-renderer';
  import type { Observer, SolarScene, SolarState } from '../../lib/types';

  type Props = {
    scene: SolarScene;
    date: string;
    land: Rings | null;
    observer: Observer | null;
  };

  let { scene, date, land, observer }: Props = $props();

  let dialog: HTMLDialogElement;
  let canvasEl = $state<HTMLCanvasElement | null>(null);
  let videoMode = $state<'vertical' | 'square'>('vertical');
  let videoRange = $state<'full' | 'peak'>('full');
  let recording = $state(false);
  let progress = $state({ current: 0, total: 0, percent: 0 });
  let videoUrl = $state<string | null>(null);
  let errorMsg = $state<string | null>(null);
  let cancelRequested = false;

  export function open(): void {
    videoUrl = null;
    errorMsg = null;
    recording = false;
    cancelRequested = false;
    dialog.showModal();
  }

  function close(): void {
    cancelRequested = true;
    recording = false;
    dialog.close();
  }

  async function startExport(): Promise<void> {
    if (!canvasEl) return;
    const { mimeType, format } = getSupportedVideoMime();
    if (typeof MediaRecorder === 'undefined') {
      errorMsg = t('videoUnsupported');
      return;
    }

    recording = true;
    errorMsg = null;
    videoUrl = null;
    cancelRequested = false;

    const width = videoMode === 'vertical' ? 1080 : 1080;
    const height = videoMode === 'vertical' ? 1920 : 1080;
    canvasEl.width = width;
    canvasEl.height = height;

    const ctx = canvasEl.getContext('2d');
    if (!ctx) {
      errorMsg = 'Failed to get 2D canvas context';
      recording = false;
      return;
    }

    // 计算录制的时间范围
    const local = scene.local;
    const lc = (code: string) => local?.contacts.find((c) => c.code === code)?.t_rel_s;
    const c1 = lc('C1');
    const c4 = lc('C4');
    const cMax = lc('MAX') ?? 0;

    let tStart = scene.diagram.track[0].t_rel_s;
    let tEnd = scene.diagram.track[scene.diagram.track.length - 1].t_rel_s;

    if (local && c1 !== undefined && c4 !== undefined) {
      if (videoRange === 'peak') {
        tStart = cMax - 300;
        tEnd = cMax + 300;
      } else {
        tStart = c1 - 120;
        tEnd = c4 + 120;
      }
    }

    const totalFrames = 240; // 30 fps * 8 秒
    const dt = (tEnd - tStart) / totalFrames;

    const stream = canvasEl.captureStream(30);
    const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
    const chunks: Blob[] = [];

    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) chunks.push(e.data);
    };

    recorder.start();

    try {
      const engine = await getEngine();
      const obs = observer ? { lat: observer.lat, lon: observer.lon, height: observer.height } : null;

      for (let i = 0; i < totalFrames; i++) {
        if (cancelRequested) {
          recorder.stop();
          recording = false;
          return;
        }

        const tCurr = tStart + i * dt;
        const s: SolarState = await engine.solarState(date, tCurr, obs);

        if (videoMode === 'vertical') {
          renderVerticalFrame(ctx, width, height, {
            scene,
            s,
            land,
            observer,
            date,
            utcStr: s.utc,
            phaseName: s.local ? (scene.kind === 'total' ? t('solarStateTotal') : t('solarStatePartial')) : t('viewModeAll'),
            lang: settings.lang,
          });
        } else {
          // 1:1 日面特写
          ctx.fillStyle = '#05070c';
          ctx.fillRect(0, 0, width, height);
          if (s.local) {
            drawSunDisk(ctx, width / 2, height / 2, width / 2 - 40, s.local, scene.kind === 'total', settings.lang);
          } else {
            ctx.fillStyle = '#ffb74d';
            ctx.font = '36px system-ui, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText(t('noLocalEclipse'), width / 2, height / 2);
          }
        }

        progress = {
          current: i + 1,
          total: totalFrames,
          percent: Math.round(((i + 1) / totalFrames) * 100),
        };

        // 维持 30fps 录制间隔，留出给 MediaRecorder 抓取帧的时间
        await new Promise((r) => setTimeout(r, 33));
      }

      await new Promise<void>((resolve) => {
        recorder.onstop = () => {
          const blob = new Blob(chunks, { type: mimeType || 'video/webm' });
          const url = URL.createObjectURL(blob);
          videoUrl = url;

          // 自动触发下载
          const a = document.createElement('a');
          a.href = url;
          a.download = `guanxiang-${date.replace(/-/g, '')}-${videoMode}.${format}`;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);

          resolve();
        };
        recorder.stop();
      });
    } catch (err: unknown) {
      errorMsg = err instanceof Error ? err.message : String(err);
    } finally {
      recording = false;
    }
  }
</script>

<dialog
  bind:this={dialog}
  class="m-auto w-[min(94vw,560px)] rounded-2xl border border-outline bg-surface p-0 text-fg backdrop:bg-bg/80"
  onclick={(e) => e.target === dialog && !recording && close()}
>
  <div class="space-y-4 p-5 sm:p-6">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-semibold">{t('exportVideoTitle')}</h2>
      {#if !recording}
        <button class="btn-text !p-1 text-muted hover:text-fg" onclick={close} aria-label={t('close')}>
          ✕
        </button>
      {/if}
    </div>

    <!-- 录制画幅与范围选择 -->
    <div class="space-y-3">
      <div>
        <p class="label mb-1.5 block">视频规格与画幅</p>
        <div class="grid grid-cols-2 gap-2">
          <button
            class={['chip !py-2 text-xs font-medium justify-center', videoMode === 'vertical' && 'chip-on']}
            disabled={recording}
            onclick={() => (videoMode = 'vertical')}
          >
            📱 {t('videoModeVertical')}
          </button>
          <button
            class={['chip !py-2 text-xs font-medium justify-center', videoMode === 'square' && 'chip-on']}
            disabled={recording}
            onclick={() => (videoMode = 'square')}
          >
            ☀️ {t('videoModeSquare')}
          </button>
        </div>
      </div>

      <div>
        <p class="label mb-1.5 block">录制时间跨度</p>
        <div class="grid grid-cols-2 gap-2">
          <button
            class={['chip !py-1.5 text-xs font-medium justify-center', videoRange === 'full' && 'chip-on']}
            disabled={recording}
            onclick={() => (videoRange = 'full')}
          >
            ⏱️ {t('videoRangeFull')}
          </button>
          <button
            class={['chip !py-1.5 text-xs font-medium justify-center', videoRange === 'peak' && 'chip-on']}
            disabled={recording}
            onclick={() => (videoRange = 'peak')}
          >
            ⚡ {t('videoRangePeak')}
          </button>
        </div>
      </div>
    </div>

    <!-- 隐藏的 1080p 离线录制 Canvas -->
    <div class="overflow-hidden rounded-xl border border-outline-variant bg-surface-2 p-2">
      <div class="flex items-center justify-between pb-1 text-xs text-muted">
        <span>实时渲染监视器</span>
        <span>{videoMode === 'vertical' ? '1080 × 1920' : '1080 × 1080'}</span>
      </div>
      <canvas
        bind:this={canvasEl}
        class="mx-auto block max-h-48 w-auto rounded border border-outline bg-black object-contain shadow"
      ></canvas>
    </div>

    <!-- 进度展示 -->
    {#if recording}
      <div class="space-y-1.5">
        <div class="flex justify-between text-xs num">
          <span class="text-primary">{t('videoExporting')}</span>
          <span>{progress.current} / {progress.total} 帧 ({progress.percent}%)</span>
        </div>
        <div class="h-2 w-full overflow-hidden rounded-full bg-surface-3">
          <div
            class="h-full bg-primary transition-all duration-75"
            style:width="{progress.percent}%"
          ></div>
        </div>
      </div>
    {/if}

    {#if videoUrl}
      <div class="space-y-2 rounded-xl bg-primary/10 p-3 text-sm">
        <p class="font-medium text-primary">✨ {t('videoExportDone')}</p>
        <video src={videoUrl} controls autoplay loop muted class="max-h-56 w-full rounded-lg bg-black shadow">
          <track kind="captions" />
        </video>
      </div>
    {/if}

    {#if errorMsg}
      <p class="rounded-xl bg-error-container px-3 py-2 text-sm text-on-error-container" role="alert">
        {errorMsg}
      </p>
    {/if}

    <div class="flex items-center justify-end gap-2 pt-2">
      {#if recording}
        <button class="btn-outline text-error" onclick={() => (cancelRequested = true)}>
          {t('cancel')}
        </button>
      {:else}
        <button class="btn-text" onclick={close}>{t('close')}</button>
        <button class="btn-filled" onclick={startExport}>
          📹 {t('videoStartExport')}
        </button>
      {/if}
    </div>
  </div>
</dialog>