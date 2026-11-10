<script lang="ts">
  // 观测太阳的安全提示（ISO 12312-2）。日食相关页面必须显示。
  import { t } from '../lib/i18n';
</script>

<aside class="flex gap-3 rounded-2xl border border-tertiary/50 bg-surface-2 p-4 text-sm" role="note">
  <svg viewBox="0 0 24 24" class="mt-0.5 h-5 w-5 shrink-0 text-tertiary" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
    <path d="M12 3 2 21h20L12 3z" />
    <path d="M12 10v5M12 18h.01" />
  </svg>
  <div class="space-y-1">
    <p class="font-medium text-fg">{t('posterSolarSafety')}</p>
    <p class="text-muted">{t('solarTipFilter')}</p>
  </div>
</aside>
