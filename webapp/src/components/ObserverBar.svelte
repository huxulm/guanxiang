<script lang="ts">
  // 显示当前观测地，点“更改”打开选择框。`override` 是链接里带的观测地，优先于保存的设置。
  import ObserverDialog from './ObserverDialog.svelte';
  import { fmtCoord } from '../lib/format';
  import { t } from '../lib/i18n';
  import { settings } from '../lib/settings.svelte';
  import type { Observer } from '../lib/types';

  let { override = null }: { override?: Observer | null } = $props();
  let dlg: ObserverDialog;

  export function open(): void {
    dlg.open();
  }

  const obs = $derived(override ?? settings.observer);
</script>

<div class="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-2xl border border-outline-variant bg-surface-2 px-4 py-2.5 text-sm">
  <svg viewBox="0 0 24 24" class="h-4 w-4 shrink-0 text-primary" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
    <path d="M12 21s-7-6.2-7-11a7 7 0 1 1 14 0c0 4.8-7 11-7 11z" />
    <circle cx="12" cy="10" r="2.5" />
  </svg>
  {#if obs}
    <span class="font-medium">{obs.label ?? t('observerLocation')}</span>
    <span class="num text-muted">{fmtCoord(obs.lat, obs.lon)}</span>
    {#if override}<span class="text-xs text-muted">（{t('fromLink')}）</span>{/if}
  {:else}
    <span class="text-muted">{t('observerNone')}</span>
  {/if}
  <button class="btn-text ml-auto -my-1" onclick={() => dlg.open()}>
    {obs ? t('observerChange') : t('observerSet')}
  </button>
</div>

<ObserverDialog bind:this={dlg} />
