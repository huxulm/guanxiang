<script lang="ts">
  // 选择观测地：常用城市、浏览器定位或手动输入经纬度。结果写进 settings.observer（只存本机）。
  import { CITIES } from '../lib/cities';
  import { t } from '../lib/i18n';
  import { settings } from '../lib/settings.svelte';

  let dialog: HTMLDialogElement;
  let lat = $state('');
  let lon = $state('');
  let height = $state('');
  let label = $state<string | undefined>(undefined);
  let error = $state('');
  let locating = $state(false);

  export function open(): void {
    const o = settings.observer;
    lat = o ? String(o.lat) : '';
    lon = o ? String(o.lon) : '';
    height = o ? String(o.height) : '';
    label = o?.label;
    error = '';
    dialog.showModal();
  }

  function pickCity(c: (typeof CITIES)[number]): void {
    lat = String(c.lat);
    lon = String(c.lon);
    height = String(c.height);
    label = settings.lang === 'zh' ? c.zh : c.en;
    error = '';
  }

  function locate(): void {
    if (!('geolocation' in navigator)) {
      error = t('geoUnsupported');
      return;
    }
    locating = true;
    error = '';
    navigator.geolocation.getCurrentPosition(
      (p) => {
        locating = false;
        lat = p.coords.latitude.toFixed(4);
        lon = p.coords.longitude.toFixed(4);
        height = p.coords.altitude != null ? String(Math.round(p.coords.altitude)) : '0';
        label = t('myLocation');
      },
      (e) => {
        locating = false;
        error =
          e.code === e.PERMISSION_DENIED
            ? t('locDenied')
            : e.code === e.TIMEOUT
              ? t('locTimeout')
              : t('locUnavailable', { detail: e.message });
      },
      { enableHighAccuracy: false, timeout: 15000, maximumAge: 600000 },
    );
  }

  function apply(): void {
    const la = Number(lat);
    const lo = Number(lon);
    const h = height.trim() === '' ? 0 : Number(height);
    if (lat.trim() === '' || lon.trim() === '' || !(Math.abs(la) <= 90) || !(Math.abs(lo) <= 180) || !Number.isFinite(h)) {
      error = t('invalidCoords');
      return;
    }
    settings.observer = { lat: la, lon: lo, height: h, label };
    dialog.close();
  }

  function clear(): void {
    settings.observer = null;
    dialog.close();
  }

  /** 手动改了数字后，城市名不再对应 */
  const edited = () => (label = undefined);
</script>

<dialog
  bind:this={dialog}
  class="m-auto w-[min(94vw,520px)] rounded-2xl border border-outline bg-surface p-0 text-fg backdrop:bg-bg/80"
  onclick={(e) => e.target === dialog && dialog.close()}
>
  <div class="space-y-4 p-5">
    <h2 class="text-base font-semibold">{t('observerTitle')}</h2>

    <div>
      <p class="label mb-2">{t('cities')}</p>
      <div class="flex flex-wrap gap-2">
        {#each CITIES as c (c.en)}
          <button class={['chip', label === (settings.lang === 'zh' ? c.zh : c.en) && 'chip-on']} onclick={() => pickCity(c)}>
            {settings.lang === 'zh' ? c.zh : c.en}
          </button>
        {/each}
      </div>
    </div>

    <!-- 标签可能折行（如英文 “Longitude ° (E+)”），输入框按底边对齐 -->
    <div class="grid grid-cols-3 items-end gap-3">
      <label class="flex flex-col gap-1">
        <span class="label">{t('latitude')}</span>
        <input class="field" inputmode="decimal" bind:value={lat} oninput={edited} />
      </label>
      <label class="flex flex-col gap-1">
        <span class="label">{t('longitude')}</span>
        <input class="field" inputmode="decimal" bind:value={lon} oninput={edited} />
      </label>
      <label class="flex flex-col gap-1">
        <span class="label">{t('height')}</span>
        <input class="field" inputmode="decimal" bind:value={height} />
      </label>
    </div>

    <button class="btn-outline" onclick={locate} disabled={locating}>
      {locating ? t('locating') : t('useMyLocation')}
    </button>

    {#if error}
      <p class="rounded-xl bg-error-container px-3 py-2 text-sm text-on-error-container" role="alert">{error}</p>
    {/if}
    <p class="text-xs text-muted">{t('observerPrivacy')}</p>

    <div class="flex flex-wrap items-center justify-end gap-2">
      {#if settings.observer}
        <button class="btn-text mr-auto" onclick={clear}>{t('observerClear')}</button>
      {/if}
      <button class="btn-text" onclick={() => dialog.close()}>{t('cancel')}</button>
      <button class="btn-filled" onclick={apply}>{t('apply')}</button>
    </div>
  </div>
</dialog>
