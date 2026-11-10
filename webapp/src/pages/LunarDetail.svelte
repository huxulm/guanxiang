<script lang="ts">
  import EphemerisStatus from '../components/EphemerisStatus.svelte';
  import LunarAnimation from '../components/anim/LunarAnimation.svelte';
  import ObserverBar from '../components/ObserverBar.svelte';
  import Stat from '../components/Stat.svelte';
  import { fmtDate, fmtDuration, fmtNum, fmtTime, lunarKindName, parseUtc, zoneLabel } from '../lib/format';
  import { t } from '../lib/i18n';
  import { link } from '../lib/router.svelte';
  import { pageObserver, sceneLoader } from '../lib/scene.svelte';
  import { settings } from '../lib/settings.svelte';
  import type { LunarContactCode, LunarScene } from '../lib/types';
  import { classify } from '../lib/visibility';

  let { date }: { date: string } = $props();

  const loader = sceneLoader<LunarScene>((e, obs, step) => e.lunarScene(date, obs, step));
  const res = $derived(loader.current);
  const fromLink = $derived(pageObserver().fromLink);

  function contact(s: LunarScene, code: LunarContactCode) {
    return s.contacts.find((c) => c.code === code);
  }

  function span(s: LunarScene, a: LunarContactCode, b: LunarContactCode): number | null {
    const x = contact(s, a);
    const y = contact(s, b);
    return x && y ? y.t_rel_s - x.t_rel_s : null;
  }

  /** 按本影食（半影月食按半影食）判断能不能看到 */
  function visibility(s: LunarScene) {
    const [a, b] = s.kind === 'penumbral' ? (['P1', 'P4'] as const) : (['U1', 'U4'] as const);
    const ca = contact(s, a);
    const cb = contact(s, b);
    if (!ca || !cb || ca.altitude_deg === null || cb.altitude_deg === null) return null;
    const between = s.path
      .filter((p) => p.t_rel_s > ca.t_rel_s && p.t_rel_s < cb.t_rel_s && p.altitude_deg !== null)
      .map((p) => p.altitude_deg as number);
    return classify(ca.altitude_deg, cb.altitude_deg, between);
  }

  const VIS_KEY = {
    full: 'lunarVisFull',
    rises: 'lunarVisRises',
    sets: 'lunarVisSets',
    risesAndSets: 'lunarVisRisesAndSets',
    hidden: 'lunarVisHidden',
  } as const;
</script>

<div class="space-y-4 pt-4">
  <a href="/" use:link class="btn-text -ml-3">← {t('back')}</a>

  {#if res.status === 'ok'}
    {@const s = res.scene}
    {@const g = parseUtc(s.greatest_utc)}
    <header class="space-y-1">
      <h1 class="text-2xl font-semibold">{lunarKindName(s.kind)}</h1>
      <p class="num text-muted">
        {fmtDate(g)} · {t('phaseG')} {fmtTime(g)} ({zoneLabel(g)})
        {#if s.saros}· {t('lunarSaros', { saros: `${s.saros.series} · ${s.saros.member}/${s.saros.count}` })}{/if}
      </p>
    </header>
  {:else}
    <h1 class="text-2xl font-semibold">{t('kindLunarEclipse')} · <span class="num">{date}</span></h1>
  {/if}

  <ObserverBar override={fromLink} />
  <EphemerisStatus autoStart />

  {#if res.status === 'computing'}
    <p class="text-sm text-muted" aria-live="polite">{t('computing')}</p>
  {:else if res.status === 'notFound'}
    <p class="card text-sm">
      {t('notFound', { date, kind: settings.lang === 'en' ? t('kindLunarEclipse').toLowerCase() : t('kindLunarEclipse') })}
    </p>
  {:else if res.status === 'error'}
    <p class="rounded-xl bg-error-container px-3 py-2 text-sm text-on-error-container" role="alert">
      {t('computeFailed', { error: res.message })}
    </p>
  {:else if res.status === 'ok'}
    {@const s = res.scene}
    {@const vis = s.observer ? visibility(s) : null}
    {@const total = span(s, 'U2', 'U3')}
    {@const umbral = span(s, 'U1', 'U4')}
    {@const penumbral = span(s, 'P1', 'P4')}

    <section class="card space-y-4">
      <h2 class="font-semibold">{t('globalTitle')}</h2>
      <dl class="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
        {#if s.kind !== 'penumbral'}<Stat label={t('umbralMag')} value={fmtNum(s.umbral_magnitude, 4)} />{/if}
        <Stat label={t('penumbralMag')} value={fmtNum(s.penumbral_magnitude, 4)} />
        <Stat label={t('gamma')} value={fmtNum(s.gamma, 4)} />
        {#if total !== null}<Stat label={t('lunarDurationTotal', { duration: '' }).trim()} value={fmtDuration(total)} />{/if}
        {#if umbral !== null}<Stat label={t('lunarDurationUmbral', { duration: '' }).trim()} value={fmtDuration(umbral)} />{/if}
        {#if penumbral !== null}<Stat label={t('lunarDurationPenumbral', { duration: '' }).trim()} value={fmtDuration(penumbral)} />{/if}
      </dl>
    </section>

    <section class="card space-y-3">
      <h2 class="font-semibold">{t('lunarTimesTitle')}</h2>
      {#if vis}
        <p class={['text-sm', vis === 'hidden' ? 'text-error' : 'text-primary']}>{t(VIS_KEY[vis])}</p>
      {:else if !s.observer}
        <p class="text-sm text-muted">{t('lunarNeedsLocation')}</p>
      {/if}
      <div class="overflow-x-auto">
        <table class="num w-full text-sm">
          <thead class="text-left text-xs text-muted">
            <tr>
              <th class="py-1.5 pr-3 font-normal">{t('lunarColPhase')}</th>
              <th class="py-1.5 pr-3 font-normal">{t('lunarColTime', { zone: zoneLabel(parseUtc(s.greatest_utc)) })}</th>
              {#if s.observer}<th class="py-1.5 text-right font-normal">{t('lunarColAlt')}</th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each s.contacts as c (c.code)}
              {@const below = c.altitude_deg !== null && c.altitude_deg <= 0}
              <tr class={['border-t border-outline-variant', c.code === 'G' && 'font-medium', below && 'text-muted']}>
                <td class="py-1.5 pr-3">{t(`phase${c.code}`)} <span class="text-xs text-muted">{c.code}</span></td>
                <td class="py-1.5 pr-3">{fmtTime(parseUtc(c.utc))}</td>
                {#if s.observer}
                  <td class="py-1.5 text-right">
                    {c.altitude_deg === null ? '—' : `${fmtNum(c.altitude_deg, 1)}°`}
                    {#if below}<span class="ml-1 text-xs">{t('belowHorizon')}</span>{/if}
                  </td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>

    {#key s}
      <LunarAnimation scene={s} {date} observer={pageObserver().observer} />
    {/key}
  {/if}
</div>
