<script lang="ts">
  import { link } from '../lib/router.svelte';
  import { settings, type ThemeChoice } from '../lib/settings.svelte';
  import { t } from '../lib/i18n';

  let dialog: HTMLDialogElement;

  const themes: { value: ThemeChoice; key: string }[] = [
    { value: 'system', key: 'themeSystem' },
    { value: 'deep', key: 'themeDeepSpace' },
    { value: 'red', key: 'themeAstroRed' },
    { value: 'light', key: 'themeLight' },
  ];
</script>

<header class="sticky top-0 z-20 border-b border-outline-variant bg-bg/90 backdrop-blur">
  <div class="mx-auto flex h-14 max-w-[960px] lg:max-w-[1360px] items-center gap-3 px-4 transition-[max-width]">
    <a href="/" use:link class="flex items-baseline gap-2 text-fg no-underline">
      <span class="text-lg font-semibold tracking-wide">{settings.lang === 'zh' ? '观象' : 'Guanxiang'}</span>
      <span class="text-xs text-muted">{t('brandSub')}</span>
    </a>
    <div class="ml-auto flex items-center gap-1">
      <button
        class="btn-text"
        onclick={() => (settings.lang = settings.lang === 'zh' ? 'en' : 'zh')}
        aria-label={settings.lang === 'zh' ? 'Switch to English' : '切换到中文'}
      >
        {settings.lang === 'zh' ? 'EN' : '中文'}
      </button>
      <button class="btn-text" onclick={() => dialog.showModal()} aria-label={t('settingsTitle')}>
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
          <circle cx="12" cy="12" r="3" />
          <path
            d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
          />
        </svg>
      </button>
    </div>
  </div>
</header>

<dialog
  bind:this={dialog}
  class="m-auto w-[min(92vw,420px)] rounded-2xl border border-outline bg-surface p-0 text-fg backdrop:bg-bg/80"
  onclick={(e) => e.target === dialog && dialog.close()}
>
  <div class="space-y-5 p-5">
    <h2 class="text-base font-semibold">{t('settingsTitle')}</h2>
    <fieldset class="space-y-2">
      <legend class="label mb-2">{t('themeMode')}</legend>
      <div class="flex flex-wrap gap-2">
        {#each themes as th (th.value)}
          <button class={['chip', settings.theme === th.value && 'chip-on']} onclick={() => (settings.theme = th.value)}>
            {t(th.key)}
          </button>
        {/each}
      </div>
    </fieldset>
    <fieldset class="space-y-2">
      <legend class="label mb-2">{t('language')}</legend>
      <div class="flex gap-2">
        <button class={['chip', settings.lang === 'zh' && 'chip-on']} onclick={() => (settings.lang = 'zh')}>中文</button>
        <button class={['chip', settings.lang === 'en' && 'chip-on']} onclick={() => (settings.lang = 'en')}>English</button>
      </div>
    </fieldset>
    <fieldset class="space-y-2">
      <legend class="label mb-2">{t('timeZone')}</legend>
      <div class="flex gap-2">
        <button class={['chip', settings.tz === 'local' && 'chip-on']} onclick={() => (settings.tz = 'local')}>{t('tzLocal')}</button>
        <button class={['chip', settings.tz === 'utc' && 'chip-on']} onclick={() => (settings.tz = 'utc')}>{t('tzUtc')}</button>
      </div>
    </fieldset>
    <div class="flex justify-end">
      <button class="btn-tonal" onclick={() => dialog.close()}>{t('apply')}</button>
    </div>
  </div>
</dialog>
