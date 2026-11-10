<script lang="ts">
  // 列表里的一次日月食，点开进详情页（日期取食甚的 UTC 日期）。
  import { fmtCoord, fmtDate, fmtNum, fmtTime, lunarKindName, parseUtc, solarKindName } from '../lib/format';
  import { t } from '../lib/i18n';
  import { link } from '../lib/router.svelte';
  import type { LunarListItem, SolarListItem } from '../lib/types';

  type Item = { type: 'lunar'; e: LunarListItem } | { type: 'solar'; e: SolarListItem };
  let { item }: { item: Item } = $props();

  const when = $derived(parseUtc(item.e.greatest.utc));
  const href = $derived(`/${item.type}/${item.e.greatest.utc.slice(0, 10)}`);
  const title = $derived(item.type === 'lunar' ? lunarKindName(item.e.kind) : solarKindName(item.e.kind));
  const mag = $derived(
    item.type === 'lunar'
      ? item.e.kind === 'penumbral'
        ? item.e.penumbral_magnitude
        : item.e.umbral_magnitude
      : item.e.magnitude,
  );
  /** 全食、环食这类醒目的食用强调色 */
  const strong = $derived(item.e.kind === 'total' || item.e.kind === 'annular' || item.e.kind === 'hybrid');
</script>

<a
  {href}
  use:link
  class="group flex items-center gap-4 rounded-2xl border border-outline-variant bg-surface px-4 py-3 transition hover:border-outline hover:bg-surface-2"
>
  <span
    class={[
      'grid h-10 w-10 shrink-0 place-items-center rounded-full',
      item.type === 'lunar' ? 'bg-blood/25 text-moon' : 'bg-eclipse/20 text-eclipse',
    ]}
    aria-hidden="true"
  >
    {#if item.type === 'lunar'}
      <svg viewBox="0 0 24 24" class="h-5 w-5"><circle cx="12" cy="12" r="8" fill="currentColor" opacity="0.35" /><circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="1.5" /></svg>
    {:else}
      <svg viewBox="0 0 24 24" class="h-5 w-5"><circle cx="12" cy="12" r="8" fill="currentColor" /><circle cx="14.5" cy="11" r="7" fill="var(--gx-surface)" /></svg>
    {/if}
  </span>
  <span class="min-w-0 flex-1">
    <span class="flex flex-wrap items-baseline gap-x-2">
      <span class={['font-medium', strong ? 'text-fg' : 'text-fg/85']}>{title}</span>
      <span class="num text-sm text-muted">{fmtDate(when)} {fmtTime(when, false)}</span>
    </span>
    <span class="num mt-0.5 flex flex-wrap gap-x-3 text-xs text-muted">
      <span>{t('magnitude')} {fmtNum(mag, 3)}</span>
      {#if item.e.saros}<span>{t('lunarSaros', { saros: `${item.e.saros.series} · ${item.e.saros.member}/${item.e.saros.count}` })}</span>{/if}
      {#if item.type === 'solar' && item.e.central && item.e.greatest_point}
        <span>{fmtCoord(item.e.greatest_point.lat_deg, item.e.greatest_point.lon_deg, 1)}</span>
      {/if}
    </span>
  </span>
  <svg viewBox="0 0 24 24" class="h-4 w-4 shrink-0 text-muted transition group-hover:translate-x-0.5" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="m9 6 6 6-6 6" /></svg>
</a>
