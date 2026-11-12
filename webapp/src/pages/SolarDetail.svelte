<script lang="ts">
  import EphemerisStatus from '../components/EphemerisStatus.svelte';
  import LocalHeroCard from '../components/LocalHeroCard.svelte';
  import ObserverBar from '../components/ObserverBar.svelte';
  import SafetyNotice from '../components/SafetyNotice.svelte';
  import SolarAnimation from '../components/anim/SolarAnimation.svelte';
  import Stat from '../components/Stat.svelte';
  import {
    fmtCoord,
    fmtDate,
    fmtNum,
    fmtTime,
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
  let observerBar: ObserverBar;

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
  <ObserverBar bind:this={observerBar} override={fromLink} />
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
    {@const obs = pageObserver().observer}
    {@const vis = s.local ? visibility(s.local) : null}

    <LocalHeroCard
      type="solar"
      observer={obs}
      {date}
      solarLocal={s.local}
      visText={vis ? t(VIS_KEY[vis]) : null}
      onSetObserver={() => observerBar?.open()}
    />

    <div class="lg:grid lg:grid-cols-12 lg:items-start lg:gap-6">
      <div id="anim-section" class="space-y-4 lg:col-span-7 xl:col-span-8 lg:sticky lg:top-18">
        {#key s}
          <SolarAnimation scene={s} {date} observer={obs} />
        {/key}
      </div>

      <div class="mt-4 space-y-4 lg:mt-0 lg:col-span-5 xl:col-span-4">
        {#if s.local}
          {@const l = s.local}
          <section class="card space-y-3">
            <h2 class="font-semibold">{t('lunarLocalTitle')}</h2>
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
          </section>
        {/if}

        <section class="card space-y-3">
          <h2 class="font-semibold">{t('globalTitle')}</h2>
          <dl class="grid grid-cols-2 gap-x-4 gap-y-3">
            <Stat label={t('magnitude')} value={fmtNum(s.magnitude, 4)} />
            <Stat label={t('gamma')} value={fmtNum(s.gamma, 4)} />
            {#if s.central && gp}
              <Stat label={t('pathWidth')} value={`${fmtNum(gp.width_km, 0)} km`} />
              <Stat label={t('sunAlt')} value={`${fmtNum(gp.sun_alt_deg, 1)}°`} />
              <div class="col-span-2">
                <Stat label={t('greatestPoint')} value={fmtCoord(gp.lat_deg, gp.lon_deg)} />
              </div>
            {/if}
          </dl>
        </section>
      </div>
    </div>
  {/if}
</div>
