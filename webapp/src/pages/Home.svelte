<script lang="ts">
  // 首页：近 20 年的日月食（构建时预先算好，不用星历），以及按年份实时搜索（要星历）。
  import EclipseItem from '../components/EclipseItem.svelte';
  import EphemerisStatus from '../components/EphemerisStatus.svelte';
  import ObserverBar from '../components/ObserverBar.svelte';
  import { YEAR_MAX, YEAR_MIN } from '../lib/config';
  import { engineState, getEngine } from '../lib/engine/engine.svelte';
  import { fmtDate, fmtNum, fmtTime, lunarKindName, parseUtc, solarKindName } from '../lib/format';
  import { t } from '../lib/i18n';
  import { link } from '../lib/router.svelte';
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

  let activeTab = $state<'featured' | 'search'>('featured');
  let currentMs = $state(Date.now());
  $effect(() => {
    const timer = setInterval(() => (currentMs = Date.now()), 1000);
    return () => clearInterval(timer);
  });

  const nextItem = $derived.by(() => {
    if (!data) return null;
    const all = merge(data.lunar, data.solar);
    return all.find((i) => parseUtc(i.e.greatest.utc).getTime() >= currentMs - 7200_000) ?? null;
  });

  const countdown = $derived.by(() => {
    if (!nextItem) return null;
    const target = parseUtc(nextItem.e.greatest.utc).getTime();
    const diff = target - currentMs;
    if (diff <= 0) return { happening: true, days: 0, hours: 0, mins: 0, secs: 0 };
    const days = Math.floor(diff / 86_400_000);
    const hours = Math.floor((diff % 86_400_000) / 3_600_000);
    const mins = Math.floor((diff % 3_600_000) / 60_000);
    const secs = Math.floor((diff % 60_000) / 1000);
    return { happening: false, days, hours, mins, secs };
  });

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
  <!-- 顶栏双模式切换：近 20 年精选 vs 自定义年份（1900-2100）实时搜索 -->
  <div class="flex items-center gap-2 border-b border-outline pb-2">
    <button
      class={['chip !py-1.5 !px-3.5 text-sm font-medium transition', activeTab === 'featured' && 'chip-on']}
      onclick={() => (activeTab = 'featured')}
    >
      📅 {t('viewModeList')}
    </button>
    <button
      class={['chip !py-1.5 !px-3.5 text-sm font-medium transition', activeTab === 'search' && 'chip-on']}
      onclick={() => (activeTab = 'search')}
    >
      🔍 {t('viewModeSearch')}
    </button>
  </div>

  <ObserverBar />

  {#if activeTab === 'featured'}
    <!-- 下一次天象倒计时 Hero 胶囊 -->
    {#if nextItem && countdown}
      {@const when = parseUtc(nextItem.e.greatest.utc)}
      {@const href = `/${nextItem.type}/${nextItem.e.greatest.utc.slice(0, 10)}`}
      {@const title = nextItem.type === 'lunar' ? lunarKindName(nextItem.e.kind) : solarKindName(nextItem.e.kind)}
      {@const mag = nextItem.type === 'lunar' ? (nextItem.e.kind === 'penumbral' ? nextItem.e.penumbral_magnitude : nextItem.e.umbral_magnitude) : nextItem.e.magnitude}
      <div class="card relative overflow-hidden border-primary/40 bg-gradient-to-br from-surface to-surface-2 p-5 transition hover:border-primary">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div class="space-y-1">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-primary/15 px-2.5 py-0.5 text-xs font-semibold text-primary">
                ⏳ {t('countdownNext')}
              </span>
              <span class="num text-xs text-muted">{fmtDate(when)}</span>
            </div>
            <h2 class="text-xl font-bold tracking-tight text-fg sm:text-2xl">
              {title}
            </h2>
            <p class="num text-xs text-muted">
              {t('phaseG')} {fmtTime(when)} · {t('magnitude')} {fmtNum(mag, 3)}
              {#if nextItem.e.saros}· {t('lunarSaros', { saros: `${nextItem.e.saros.series} · ${nextItem.e.saros.member}/${nextItem.e.saros.count}` })}{/if}
            </p>
          </div>

          <!-- 倒计时数字模块 -->
          <div class="flex flex-wrap items-center gap-3">
            {#if countdown.happening}
              <span class="inline-flex items-center gap-1.5 rounded-xl bg-eclipse/20 px-4 py-2 font-semibold text-eclipse animate-pulse">
                ● {t('happeningNow')}
              </span>
            {:else}
              <div class="flex items-baseline gap-1.5 num text-center">
                <div class="rounded-xl border border-outline-variant bg-surface-3 px-3 py-1.5 min-w-[50px]">
                  <div class="text-xl font-bold leading-tight text-primary sm:text-2xl">{countdown.days}</div>
                  <div class="text-[10px] text-muted">{t('countdownDays')}</div>
                </div>
                <span class="text-muted font-bold">:</span>
                <div class="rounded-xl border border-outline-variant bg-surface-3 px-3 py-1.5 min-w-[46px]">
                  <div class="text-xl font-bold leading-tight text-fg sm:text-2xl">{String(countdown.hours).padStart(2, '0')}</div>
                  <div class="text-[10px] text-muted">{t('countdownHours')}</div>
                </div>
                <span class="text-muted font-bold">:</span>
                <div class="rounded-xl border border-outline-variant bg-surface-3 px-3 py-1.5 min-w-[46px]">
                  <div class="text-xl font-bold leading-tight text-fg sm:text-2xl">{String(countdown.mins).padStart(2, '0')}</div>
                  <div class="text-[10px] text-muted">{t('countdownMins')}</div>
                </div>
              </div>
            {/if}
            <a {href} use:link class="btn-filled text-sm whitespace-nowrap">
              {t('jumpToAnim')} →
            </a>
          </div>
        </div>
      </div>
    {/if}

    <div class="space-y-1 pt-2">
      <h1 class="text-2xl font-semibold">{t('quickEclipses')}</h1>
      <p class="text-sm text-muted">
        {data ? t('listHint', { from: data.from, to: data.to - 1 }) : t('quickEclipsesDesc')}
      </p>
    </div>

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
  {:else}
    <!-- 自定义年份实时搜索界面 -->
    <div class="space-y-4">
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
        <div class="flex flex-wrap items-center gap-2 pt-2">
          <p class="num text-sm text-muted mr-auto">{result.status}</p>
          {#each [['all', 'filterAll'], ['solar', 'filterSolar'], ['lunar', 'filterLunar']] as [value, key] (value)}
            <button class={['chip !py-0.5 !px-2 text-xs', filter === value && 'chip-on']} onclick={() => (filter = value as Filter)}>{t(key)}</button>
          {/each}
        </div>
        {#if resultItems.length}
          <ul class="grid gap-2 md:grid-cols-2">
            {#each resultItems as item (item.type + item.e.greatest.tt)}
              <li><EclipseItem {item} /></li>
            {/each}
          </ul>
        {/if}
      {/if}
    </div>
  {/if}
</section>
