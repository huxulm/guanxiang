<script lang="ts">
  import { SITE_URL, SOURCE_URL } from '../lib/config';
  import { t } from '../lib/i18n';
</script>

<footer class="border-t border-outline-variant">
  <div class="mx-auto flex max-w-[960px] flex-col gap-2 px-4 py-6 text-xs text-muted sm:flex-row sm:items-center sm:justify-between">
    <p>{t('footerCalc')}</p>
    <p class="flex shrink-0 gap-4">
      <a class="text-primary hover:underline" href={SITE_URL}>{t('footerApp')}</a>
      <a class="text-primary hover:underline" href={SOURCE_URL}>{t('footerSource')}</a>
    </p>
  </div>
</footer>
