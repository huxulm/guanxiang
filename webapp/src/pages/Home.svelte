<script lang="ts">
  // 首页：近 20 年的日月食（构建时预先算好，不用星历），以及按年份实时搜索（要星历）。
  import EclipseItem from '../components/EclipseItem.svelte';
  import EphemerisStatus from '../components/EphemerisStatus.svelte';
  import ObserverBar from '../components/ObserverBar.svelte';
  import { YEAR_MAX, YEAR_MIN } from '../lib/config';
  import { engineState, getEngine } from '../lib/engine/engine.svelte';
  import { parseUtc } from '../lib/format';
  import { t } from '../lib/i18n';
  import type { EclipseData, LunarListItem, SolarListItem } from '../lib/types';
  import * as Comlink from 'comlink';

  type Item = { type: 'lunar'; e: LunarListItem } | { type: 'solar'; e: SolarListItem };
  type Filter = 'all' | 'solar' | 'lunar';

  const PAGE = 12;

  let data = $state<EclipseData | null>(null);
  let loadError = $state('');
  let filter = $state<Filter>('all');
  let showPast = $state(false);
  let shown = $state(PAGE);

  $effect(() => {
    fetch('/data/eclipses.json')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((d: EclipseData) => (data = d))
      .catch((e: unknown) => (loadError = e instanceof Error ? e.message : String(e)));
  });

  function merge(lunar: LunarListItem[], solar: SolarListItem[]): Item[] {
    const items: Item[] = [
      ...lunar.map((e) => ({ type: 'lunar' as const, e })),
      ...solar.map((e) => ({ type: 'solar' as const, e })),
    ];
    return items.sort((a, b) => a.e.greatest.tt - b.e.greatest.tt);
  }

  const applyFilter = (items: Item[]) => (filter === 'all' ? items : items.filter((i) => i.type === filter));

  /** 一天前之后的算“未来的” */
  const cutoff = Date.now() - 86_400_000;
  const items = $derived.by(() => {
    if (!data) return [];
    const all = applyFilter(merge(data.lunar, data.solar));
    return showPast ? all : all.filter((i) => parseUtc(i.e.greatest.utc).getTime() >= cutoff);
  });

  // ---- 按年份搜索 ----
  const thisYear = new Date().getFullYear();
  let fromYear = $state(thisYear);
  let toYear = $state(thisYear + 10);
  let searching = $state(false);
  let progress = $state({ done: 0, total: 0 });
  let result = $state<{ items: Item[]; status: string } | null>(null);
  let rangeError = $state('');

  async function search(): Promise<void> {
    const a = Math.trunc(Number(fromYear));
    const b = Math.trunc(Number(toYear));
    if (!(a >= YEAR_MIN && b <= YEAR_MAX && a <= b)) {
      rangeError = t('yearRangeInvalid', { min: YEAR_MIN, max: YEAR_MAX });
      return;
    }
    rangeError = '';
    searching = true;
    progress = { done: 0, total: b - a + 1 };
    const t0 = performance.now();
    try {
      const engine = await getEngine();
      const r = await engine.search(a, b, Comlink.proxy((done: number, total: number) => {
          // 回调不能有返回值：Comlink 会把返回值传回 Worker，而响应式代理对象不能结构化克隆
          progress = { done, total };
        }));
      const found = merge(r.lunar, r.solar);
      const ms = Math.round(performance.now() - t0);
      result = {
        items: found,
        status: t(r.cancelled ? 'searchCancelled' : 'searchFinished', { count: found.length, ms }),
      };
    } catch (e) {
      result = { items: [], status: t('searchFailed', { error: e instanceof Error ? e.message : String(e) }) };
    } finally {
      searching = false;
    }
  }

  async function cancel(): Promise<void> {
    (await getEngine()).cancel();
  }

  const resultItems = $derived(result ? applyFilter(result.items) : []);
</script>

<section class="space-y-4 pt-6">
  <div class="space-y-1">
    <h1 class="text-2xl font-semibold">{t('quickEclipses')}</h1>
    <p class="text-sm text-muted">
      {data ? t('listHint', { from: data.from, to: data.to - 1 }) : t('quickEclipsesDesc')}
    </p>
  </div>

  <ObserverBar />

  <div class="flex flex-wrap items-center gap-2">
    {#each [['all', 'filterAll'], ['solar', 'filterSolar'], ['lunar', 'filterLunar']] as [value, key] (value)}
      <button class={['chip', filter === value && 'chip-on']} onclick={() => ((filter = value as Filter), (shown = PAGE))}>{t(key)}</button>
    {/each}
    <label class="ml-auto flex items-center gap-2 text-sm text-muted">
      <input type="checkbox" class="accent-primary" bind:checked={showPast} onchange={() => (shown = PAGE)} />
      {t('showPast')}
    </label>
  </div>

  {#if loadError}
    <p class="rounded-xl bg-error-container px-3 py-2 text-sm text-on-error-container" role="alert">
      {t('listLoadFailed', { error: loadError })}
    </p>
  {:else if !data}
    <p class="text-sm text-muted">{t('loading')}</p>
  {:else if items.length === 0}
    <p class="text-sm text-muted">{t('listEmpty')}</p>
  {:else}
    <ul class="grid gap-2 md:grid-cols-2">
      {#each items.slice(0, shown) as item (item.type + item.e.greatest.tt)}
        <li><EclipseItem {item} /></li>
      {/each}
    </ul>
    {#if items.length > shown}
      <div class="flex justify-center">
        <button class="btn-outline" onclick={() => (shown += PAGE)}>{t('showMore')}</button>
      </div>
    {/if}
  {/if}
</section>

<section class="mt-10 space-y-4">
  <div class="space-y-1">
    <h2 class="text-lg font-semibold">{t('customSearch')}</h2>
    <p class="text-sm text-muted">{t('customSearchHint', { min: YEAR_MIN, max: YEAR_MAX })}</p>
  </div>
  <div class="card flex flex-wrap items-end gap-3">
    <label class="w-32 space-y-1">
      <span class="label">{t('fromYear')}</span>
      <input class="field" type="number" min={YEAR_MIN} max={YEAR_MAX} bind:value={fromYear} />
    </label>
    <label class="w-32 space-y-1">
      <span class="label">{t('toYear')}</span>
      <input class="field" type="number" min={YEAR_MIN} max={YEAR_MAX} bind:value={toYear} />
    </label>
    {#if searching}
      <button class="btn-outline" onclick={cancel}>{t('cancel')}</button>
      {#if engineState.status === 'ready'}
        <span class="num text-sm text-muted" aria-live="polite">{t('searchProgress', progress)}</span>
      {/if}
    {:else}
      <button class="btn-filled" onclick={search}>{t('search')}</button>
    {/if}
    <div class="flex w-full flex-wrap items-center gap-1.5 pt-1 text-xs">
      <span class="text-muted">{t('quickYears')}：</span>
      {#each [2026, 2027, 2028, 2030, 2034, 2035] as y}
        <button
          class={['chip num !py-0.5 !px-2 text-xs', fromYear === y && toYear === y && 'chip-on']}
          onclick={() => {
            fromYear = y;
            toYear = y;
            search();
          }}
        >
          {y}
        </button>
      {/each}
    </div>
    {#if rangeError}<p class="w-full text-sm text-error">{rangeError}</p>{/if}
  </div>

  {#if engineState.status !== 'ready' && (searching || engineState.status === 'error')}
    <EphemerisStatus />
  {/if}

  {#if result}
    <p class="num text-sm text-muted">{result.status}</p>
    {#if resultItems.length}
      <ul class="grid gap-2 md:grid-cols-2">
        {#each resultItems as item (item.type + item.e.greatest.tt)}
          <li><EclipseItem {item} /></li>
        {/each}
      </ul>
    {/if}
  {/if}
</section>
