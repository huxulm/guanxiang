<script lang="ts">
  // 星历加载状态：没开始时给出说明和按钮（autoStart 时直接开始），加载中显示进度，失败可重试。
  import { engineState, getEngine } from '../lib/engine/engine.svelte';
  import { t } from '../lib/i18n';

  let { autoStart = false }: { autoStart?: boolean } = $props();

  $effect(() => {
    if (autoStart && engineState.status === 'idle') void getEngine().catch(() => {});
  });

  const mb = (n: number) => (n / 1048576).toFixed(1);
  const pct = $derived(Math.min(100, (engineState.loaded / engineState.total) * 100));
</script>

{#if engineState.status === 'idle'}
  <div class="card flex flex-col gap-3 sm:flex-row sm:items-center">
    <p class="text-sm text-muted">{t('ephemNeeded')}</p>
    <button class="btn-filled shrink-0" onclick={() => void getEngine().catch(() => {})}>{t('ephemDownload')}</button>
  </div>
{:else if engineState.status === 'loading'}
  <div class="card space-y-2" aria-live="polite">
    <p class="num text-sm">
      {#if engineState.phase === 'cache'}
        {t('ephemFromCache')}
      {:else if engineState.phase === 'verify'}
        {t('ephemVerifying')}
      {:else}
        {t('ephemDownloading', { loaded: mb(engineState.loaded), total: mb(engineState.total) })}
      {/if}
    </p>
    <div class="h-1.5 overflow-hidden rounded-full bg-surface-3">
      <div
        class="h-full rounded-full bg-primary transition-[width]"
        style:width={engineState.phase === 'download' ? `${pct}%` : '100%'}
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax="100"
        aria-valuenow={Math.round(pct)}
      ></div>
    </div>
    <p class="text-xs text-muted">{t('ephemNeeded')}</p>
  </div>
{:else if engineState.status === 'error'}
  <div class="flex flex-col gap-3 rounded-2xl bg-error-container p-4 text-on-error-container sm:flex-row sm:items-center" role="alert">
    <p class="text-sm">{t('ephemerisLoadFailed', { error: engineState.error })}</p>
    <button class="btn-outline shrink-0" onclick={() => void getEngine().catch(() => {})}>{t('retry')}</button>
  </div>
{/if}
