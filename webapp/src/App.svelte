<script lang="ts">
  import Header from './components/Header.svelte';
  import Footer from './components/Footer.svelte';
  import Home from './pages/Home.svelte';
  import LunarDetail from './pages/LunarDetail.svelte';
  import SolarDetail from './pages/SolarDetail.svelte';
  import NotFound from './pages/NotFound.svelte';
  import { location$, matchRoute } from './lib/router.svelte';
  import { persistSettings, settings } from './lib/settings.svelte';
  import { t } from './lib/i18n';

  persistSettings();

  const route = $derived(matchRoute(location$.path));

  $effect(() => {
    const base = settings.lang === 'zh' ? '观象' : 'Guanxiang';
    const sub = t('brandSub');
    document.title = route.page === 'home' ? `${base} · ${sub}` : `${base} · ${route.page === 'notFound' ? t('pageNotFound') : sub}`;
  });
</script>

<Header />
<main class="mx-auto w-full max-w-[960px] lg:max-w-[1360px] px-4 pb-10 transition-[max-width]">
  {#if route.page === 'home'}
    <Home />
  {:else if route.page === 'lunar'}
    {#key route.date}
      <LunarDetail date={route.date} />
    {/key}
  {:else if route.page === 'solar'}
    {#key route.date}
      <SolarDetail date={route.date} />
    {/key}
  {:else}
    <NotFound />
  {/if}
</main>
<Footer />
