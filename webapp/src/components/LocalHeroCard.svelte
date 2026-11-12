<script lang="ts">
  // 本地观测结论胶囊卡片：直观解答“我在的地方能看到什么、几点看、往哪看”。
  import { downloadIcs, generateLunarIcs, generateSolarIcs } from '../lib/calendar';
  import { fmtDuration, fmtNum, fmtTime, parseUtc, zoneLabel } from '../lib/format';
  import { t } from '../lib/i18n';
  import { settings } from '../lib/settings.svelte';
  import type { LunarScene, Observer, SolarLocal } from '../lib/types';

  type Props = {
    type: 'solar' | 'lunar';
    observer: Observer | null;
    date?: string;
    solarLocal?: SolarLocal | null;
    lunarScene?: LunarScene | null;
    visText?: string | null;
    onSetObserver: () => void;
  };

  let { type, observer, date = '', solarLocal, lunarScene, visText, onSetObserver }: Props = $props();

  function scrollToAnim(): void {
    const el = document.getElementById('anim-section');
    el?.scrollIntoView({ behavior: 'smooth' });
  }

  function exportCalendar(): void {
    if (type === 'solar' && solarLocal) {
      const ics = generateSolarIcs(date, solarLocal, observer, settings.lang);
      downloadIcs(`eclipse_${date}`, ics);
    } else if (type === 'lunar' && lunarScene) {
      const ics = generateLunarIcs(date, lunarScene, observer, settings.lang);
      downloadIcs(`eclipse_${date}`, ics);
    }
  }
</script>

<div class="card space-y-3 border-outline-variant bg-surface-2 transition">
  {#if !observer}
    <div class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex items-center gap-2.5">
        <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-primary-container text-primary">
          <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M12 21s-7-6.2-7-11a7 7 0 1 1 14 0c0 4.8-7 11-7 11z" />
            <circle cx="12" cy="10" r="2.5" />
          </svg>
        </span>
        <p class="text-sm font-medium text-fg">{t('verdictPromptSetLoc')}</p>
      </div>
      <button class="btn-filled shrink-0" onclick={onSetObserver}>
        {t('observerSet')}
      </button>
    </div>
  {:else if type === 'solar'}
    {#if !solarLocal}
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <span class="inline-flex items-center rounded-full border border-outline bg-surface-high px-2.5 py-0.5 text-xs text-muted">
            ⚪ {t('verdictSolarNone')}
          </span>
        </div>
        <button class="btn-text -my-1 text-xs" onclick={scrollToAnim}>
          {t('jumpToAnim')} ↓
        </button>
      </div>
      <p class="text-sm text-muted">{t('solarVisNone')}</p>
    {:else}
      {@const l = solarLocal}
      {@const maxUtc = parseUtc(l.maximum_utc)}
      {@const isTotal = l.kind === 'total'}
      {@const isAnnular = l.kind === 'annular'}
      {@const maxContact = l.contacts.find((c) => c.code === 'MAX')}
      {@const alt = maxContact?.sun_alt_deg ?? null}

      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex flex-wrap items-center gap-2">
          <span
            class={[
              'inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-medium',
              isTotal || isAnnular
                ? 'border border-eclipse/40 bg-eclipse/20 text-eclipse'
                : 'border border-primary/40 bg-primary/20 text-primary',
            ]}
          >
            {#if isTotal}🌕 {t('verdictSolarTotal')}
            {:else if isAnnular}⭕ {t('verdictSolarAnnular')}
            {:else}🌘 {t('verdictSolarPartial')}
            {/if}
          </span>
          {#if visText}
            <span class="text-xs font-medium text-primary">{visText}</span>
          {/if}
        </div>
        <div class="flex items-center gap-1.5">
          <button class="btn-text -my-1 text-xs text-primary" onclick={exportCalendar} title={t('addToCalendar')}>
            📅 {t('addToCalendar')}
          </button>
          <button class="btn-text -my-1 text-xs text-primary" onclick={scrollToAnim}>
            {t('jumpToAnim')} ↓
          </button>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3 pt-1 sm:grid-cols-4">
        <div>
          <span class="label">{t('phaseMAX')}</span>
          <p class="num text-base font-semibold text-fg">
            {fmtTime(maxUtc)} <span class="text-xs font-normal text-muted">({zoneLabel(maxUtc)})</span>
          </p>
        </div>
        {#if l.central_duration_s !== null}
          <div>
            <span class="label">{t('centralDuration', { kind: isTotal ? t('localTotal') : t('localAnnular') })}</span>
            <p class="num text-base font-semibold text-fg">{fmtDuration(l.central_duration_s, true)}</p>
          </div>
        {/if}
        <div>
          <span class="label">{t('magnitude')} / {t('obscuration')}</span>
          <p class="num text-base font-semibold text-fg">
            {fmtNum(l.magnitude, 3)} <span class="text-xs font-normal text-muted">({fmtNum(l.obscuration * 100, 1)}%)</span>
          </p>
        </div>
        {#if alt !== null}
          <div>
            <span class="label">{t('sunAlt')}</span>
            <p class={['num text-base font-semibold', alt <= 0 ? 'text-muted' : 'text-fg']}>
              {fmtNum(alt, 1)}°
              {#if alt <= 0}<span class="text-xs font-normal text-muted">({t('belowHorizon')})</span>{/if}
            </p>
          </div>
        {/if}
      </div>
    {/if}
  {:else if type === 'lunar' && lunarScene}
    {@const s = lunarScene}
    {@const gUtc = parseUtc(s.greatest_utc)}
    {@const isTotal = s.kind === 'total'}
    {@const isPartial = s.kind === 'partial'}
    {@const gContact = s.contacts.find((c) => c.code === 'G')}
    {@const alt = gContact?.altitude_deg ?? null}
    {@const isHidden = alt !== null && alt <= -5}

    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex flex-wrap items-center gap-2">
        <span
          class={[
            'inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-medium',
            isHidden
              ? 'border border-outline bg-surface-high text-muted'
              : isTotal
                ? 'border border-blood/40 bg-blood/20 text-moon'
                : 'border border-primary/40 bg-primary/20 text-primary',
          ]}
        >
          {#if isHidden}⚪ {t('verdictLunarNone')}
          {:else if isTotal}🌕 {t('verdictLunarTotal')}
          {:else if isPartial}🌘 {t('verdictLunarPartial')}
          {:else}🌑 {t('verdictLunarPenumbral')}
          {/if}
        </span>
        {#if visText && !isHidden}
          <span class="text-xs font-medium text-primary">{visText}</span>
        {/if}
      </div>
      <div class="flex items-center gap-1.5">
        {#if !isHidden}
          <button class="btn-text -my-1 text-xs text-primary" onclick={exportCalendar} title={t('addToCalendar')}>
            📅 {t('addToCalendar')}
          </button>
        {/if}
        <button class="btn-text -my-1 text-xs text-primary" onclick={scrollToAnim}>
          {t('jumpToAnim')} ↓
        </button>
      </div>
    </div>

    <div class="grid grid-cols-2 gap-3 pt-1 sm:grid-cols-4">
      <div>
        <span class="label">{t('phaseG')}</span>
        <p class="num text-base font-semibold text-fg">
          {fmtTime(gUtc)} <span class="text-xs font-normal text-muted">({zoneLabel(gUtc)})</span>
        </p>
      </div>
      <div>
        <span class="label">{isTotal || isPartial ? t('umbralMag') : t('penumbralMag')}</span>
        <p class="num text-base font-semibold text-fg">
          {fmtNum(isTotal || isPartial ? s.umbral_magnitude : s.penumbral_magnitude, 3)}
        </p>
      </div>
      {#if alt !== null}
        <div>
          <span class="label">{t('lunarColAlt')}</span>
          <p class={['num text-base font-semibold', alt <= 0 ? 'text-muted' : 'text-fg']}>
            {fmtNum(alt, 1)}°
            {#if alt <= 0}<span class="text-xs font-normal text-muted">({t('belowHorizon')})</span>{/if}
          </p>
        </div>
      {/if}
    </div>
  {/if}
</div>
