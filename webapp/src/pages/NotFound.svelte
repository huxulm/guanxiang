<script lang="ts">
  import { t } from '../lib/i18n';
  import { link } from '../lib/router.svelte';
</script>

<section class="space-y-3 py-16 text-center">
  <h1 class="text-2xl font-semibold">{t('pageNotFound')}</h1>
  <a href="/" use:link class="btn-tonal">{t('goHome')}</a>
</section>
