<script lang="ts">
  import EphemerisStatus from '../components/EphemerisStatus.svelte';
  import ObserverBar from '../components/ObserverBar.svelte';
  import SafetyNotice from '../components/SafetyNotice.svelte';
  import SolarDiagram from '../components/SolarDiagram.svelte';
  import Stat from '../components/Stat.svelte';
  import {
    fmtCoord,
    fmtDate,
    fmtDuration,
    fmtNum,
    fmtTime,
    localSolarKindName,
    parseUtc,
    solarKindName,
    zoneLabel,
  } from '../lib/format';
  import { t } from '../lib/i18n';
  import { link } from '../lib/router.svelte';
  import { pageObserver, sceneLoader } from '../lib/scene.svelte';
  import { settings } from '../lib/settings.svelte';
  import type { SolarLocal, SolarScene } from '../lib/types';
  import { classify } from '../lib/visibility';

  let { date }: { date: string } = $props();

  const loader = sceneLoader<SolarScene>((e, obs, step) => e.solarScene(date, obs, step));
  const res = $derived(loader.current);
  const fromLink = $derived(pageObserver().fromLink);

  function visibility(l: SolarLocal) {
    const c1 = l.contacts.find((c) => c.code === 'C1');
    const c4 = l.contacts.find((c) => c.code === 'C4');
    if (!c1 || !c4 || c1.sun_alt_deg === null || c4.sun_alt_deg === null) return null;
    const between = l.disk_frames.filter((f) => f.t_rel_s > c1.t_rel_s && f.t_rel_s < c4.t_rel_s).map((f) => f.sun_alt_deg);
    return classify(c1.sun_alt_deg, c4.sun_alt_deg, between);
  }

  const VIS_KEY = {
    full: 'solarVisFull',
    rises: 'solarVisRises',
    sets: 'solarVisSets',
    risesAndSets: 'solarVisRisesAndSets',
    hidden: 'solarVisHidden',
  } as const;
</script>

<div class="space-y-4 pt-4">
  <a href="/" use:link class="btn-text -ml-3">← {t('back')}</a>

  {#if res.status === 'ok'}
    {@const s = res.scene}
    {@const g = parseUtc(s.greatest_utc)}
    <header class="space-y-1">
      <h1 class="text-2xl font-semibold">{solarKindName(s.kind)}</h1>
      <p class="num text-muted">
        {fmtDate(g)} · {t('phaseG')} {fmtTime(g)} ({zoneLabel(g)})
        {#if s.saros}· {t('lunarSaros', { saros: `${s.saros.series} · ${s.saros.member}/${s.saros.count}` })}{/if}
      </p>
    </header>
  {:else}
    <h1 class="text-2xl font-semibold">{t('kindSolarEclipse')} · <span class="num">{date}</span></h1>
  {/if}

  <SafetyNotice />
  <ObserverBar override={fromLink} />
  <EphemerisStatus autoStart />

  {#if res.status === 'computing'}
    <p class="text-sm text-muted" aria-live="polite">{t('computing')}</p>
  {:else if res.status === 'notFound'}
    <p class="card text-sm">
      {t('notFound', { date, kind: settings.lang === 'en' ? t('kindSolarEclipse').toLowerCase() : t('kindSolarEclipse') })}
    </p>
  {:else if res.status === 'error'}
    <p class="rounded-xl bg-error-container px-3 py-2 text-sm text-on-error-container" role="alert">
      {t('computeFailed', { error: res.message })}
    </p>
  {:else if res.status === 'ok'}
    {@const s = res.scene}
    {@const gp = s.greatest_point}

    <section class="card space-y-4">
      <h2 class="font-semibold">{t('globalTitle')}</h2>
      <dl class="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
        <Stat label={t('magnitude')} value={fmtNum(s.magnitude, 4)} />
        <Stat label={t('gamma')} value={fmtNum(s.gamma, 4)} />
        {#if s.central && gp}
          <Stat label={t('pathWidth')} value={`${fmtNum(gp.width_km, 0)} km`} />
          <Stat label={t('sunAlt')} value={`${fmtNum(gp.sun_alt_deg, 1)}°`} />
          <div class="col-span-2 sm:col-span-4">
            <Stat label={t('greatestPoint')} value={fmtCoord(gp.lat_deg, gp.lon_deg)} />
          </div>
        {/if}
      </dl>
    </section>

    <section class="card space-y-3">
      <h2 class="font-semibold">{t('lunarLocalTitle')}</h2>
      {#if !s.observer}
        <p class="text-sm text-muted">{t('solarNeedsLocation')}</p>
      {:else if !s.local}
        <p class="text-sm text-muted">{t('solarVisNone')}</p>
      {:else}
        {@const l = s.local}
        {@const vis = visibility(l)}
        {#if vis}
          <p class={['text-sm', vis === 'hidden' ? 'text-error' : 'text-primary']}>{t(VIS_KEY[vis])}</p>
        {/if}
        <dl class="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
          <Stat label={t('posterKind')} value={localSolarKindName(l.kind)} />
          <Stat label={t('magnitude')} value={fmtNum(l.magnitude, 4)} />
          <Stat label={t('obscuration')} value={`${fmtNum(l.obscuration * 100, 1)}%`} />
          {#if l.central_duration_s !== null}
            <Stat label={t('centralDuration', { kind: localSolarKindName(l.kind) })} value={fmtDuration(l.central_duration_s, true)} />
          {/if}
        </dl>
        <div class="overflow-x-auto">
          <table class="num w-full text-sm">
            <thead class="text-left text-xs text-muted">
              <tr>
                <th class="py-1.5 pr-3 font-normal">{t('lunarColPhase')}</th>
                <th class="py-1.5 pr-3 font-normal">{t('lunarColTime', { zone: zoneLabel(parseUtc(l.maximum_utc)) })}</th>
                <th class="py-1.5 text-right font-normal">{t('sunAlt')}</th>
              </tr>
            </thead>
            <tbody>
              {#each l.contacts as c (c.code)}
                {@const below = c.sun_alt_deg !== null && c.sun_alt_deg <= 0}
                <tr class={['border-t border-outline-variant', c.code === 'MAX' && 'font-medium', below && 'text-muted']}>
                  <td class="py-1.5 pr-3">{t(`phase${c.code}`)} <span class="text-xs text-muted">{c.code === 'MAX' ? '' : c.code}</span></td>
                  <td class="py-1.5 pr-3">{fmtTime(parseUtc(c.utc))}</td>
                  <td class="py-1.5 text-right">
                    {c.sun_alt_deg === null ? '—' : `${fmtNum(c.sun_alt_deg, 1)}°`}
                    {#if below}<span class="ml-1 text-xs">{t('belowHorizon')}</span>{/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>

    <section class="card space-y-3">
      <h2 class="font-semibold">{t('diagramTitle')}</h2>
      <SolarDiagram scene={s} />
      <p class="text-xs text-muted">{t('animationSoon')}</p>
    </section>
  {/if}
</div>
