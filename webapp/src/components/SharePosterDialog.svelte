<script lang="ts">
  // 分享海报对话框：纯前端高清晰度渲染天文事件海报，支持另存为 3x PNG 图片、复制图片和复制链接。
  import { fmtCoord, fmtDate, fmtDuration, fmtNum, fmtTime, lunarKindName, parseUtc, solarKindName } from '../lib/format';
  import { t } from '../lib/i18n';
  import { settings } from '../lib/settings.svelte';
  import type { LunarScene, Observer, SolarLocal, SolarScene } from '../lib/types';

  type Props = {
    type: 'solar' | 'lunar';
    date: string;
    solarScene?: SolarScene | null;
    solarLocal?: SolarLocal | null;
    lunarScene?: LunarScene | null;
    observer?: Observer | null;
    visText?: string | null;
  };

  let { type, date, solarScene, solarLocal, lunarScene, observer, visText }: Props = $props();

  let dialog: HTMLDialogElement;
  let svgEl = $state<SVGSVGElement | null>(null);
  let showPlace = $state(true);
  let exporting = $state(false);
  let copied = $state(false);
  let linkCopied = $state(false);

  export function open(): void {
    showPlace = !!observer;
    copied = false;
    linkCopied = false;
    dialog.showModal();
  }

  const isSolar = $derived(type === 'solar');
  const isZh = $derived(settings.lang === 'zh');

  const title = $derived.by(() => {
    if (isSolar && solarScene) return solarKindName(solarScene.kind);
    if (!isSolar && lunarScene) return lunarKindName(lunarScene.kind);
    return isSolar ? t('kindSolarEclipse') : t('kindLunarEclipse');
  });

  const sarosStr = $derived.by(() => {
    const s = isSolar ? solarScene?.saros : lunarScene?.saros;
    return s ? `${s.series} · ${s.member}/${s.count}` : '';
  });

  const maxUtc = $derived.by(() => {
    if (isSolar && solarScene) return parseUtc(solarScene.greatest_utc);
    if (!isSolar && lunarScene) return parseUtc(lunarScene.greatest_utc);
    return parseUtc(date);
  });

  const maxMagnitude = $derived.by(() => {
    if (isSolar) {
      if (showPlace && solarLocal) return solarLocal.magnitude;
      return solarScene?.magnitude ?? 0;
    }
    return lunarScene ? (lunarScene.kind === 'penumbral' ? lunarScene.penumbral_magnitude : lunarScene.umbral_magnitude) : 0;
  });

  const obscurationVal = $derived(isSolar && showPlace && solarLocal ? solarLocal.obscuration * 100 : null);

  const contactsList = $derived.by(() => {
    if (isSolar && showPlace && solarLocal) {
      return solarLocal.contacts.map((c) => ({
        label: isZh ? c.label_zh || c.code : c.code,
        time: fmtTime(parseUtc(c.utc)),
        alt: c.sun_alt_deg !== null ? `${fmtNum(c.sun_alt_deg, 1)}°` : null,
      }));
    }
    if (!isSolar && lunarScene) {
      return lunarScene.contacts.map((c) => ({
        label: isZh ? c.label_zh || c.code : c.code,
        time: fmtTime(parseUtc(c.utc)),
        alt: c.altitude_deg !== null ? `${fmtNum(c.altitude_deg, 1)}°` : null,
      }));
    }
    return [];
  });

  async function getBlob(): Promise<Blob | null> {
    if (!svgEl) return null;
    const svgXml = new XMLSerializer().serializeToString(svgEl);
    const blob = new Blob([svgXml], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    return new Promise<Blob | null>((resolve) => {
      const img = new Image();
      img.onload = () => {
        const scale = 3;
        const canvas = document.createElement('canvas');
        canvas.width = 380 * scale;
        canvas.height = 540 * scale;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
          URL.revokeObjectURL(url);
          resolve(null);
          return;
        }
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        URL.revokeObjectURL(url);
        canvas.toBlob((b) => resolve(b), 'image/png');
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        resolve(null);
      };
      img.src = url;
    });
  }

  async function download(): Promise<void> {
    exporting = true;
    try {
      const blob = await getBlob();
      if (!blob) return;
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `guanxiang-${date.replace(/-/g, '')}-${type}.png`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 2000);
    } finally {
      exporting = false;
    }
  }

  async function copyImage(): Promise<void> {
    try {
      const blob = await getBlob();
      if (!blob || !navigator.clipboard || typeof ClipboardItem === 'undefined') return;
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
      copied = true;
      setTimeout(() => (copied = false), 2500);
    } catch {
      // 忽略无法写入剪贴板的错误
    }
  }

  async function copyLink(): Promise<void> {
    try {
      await navigator.clipboard.writeText(window.location.href);
      linkCopied = true;
      setTimeout(() => (linkCopied = false), 2500);
    } catch {
      // 忽略
    }
  }
</script>

<dialog
  bind:this={dialog}
  class="m-auto w-[min(94vw,680px)] rounded-2xl border border-outline bg-surface p-0 text-fg backdrop:bg-bg/80"
  onclick={(e) => e.target === dialog && dialog.close()}
>
  <div class="space-y-4 p-5 sm:p-6">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-semibold">{t('shareImage')}</h2>
      <button class="btn-text !p-1 text-muted hover:text-fg" onclick={() => dialog.close()} aria-label={t('cancel')}>
        ✕
      </button>
    </div>

    <div class="grid gap-6 md:grid-cols-[auto_1fr] md:items-center">
      <!-- 预览 SVG 海报 (标准 380x540) -->
      <div class="flex justify-center">
        <svg
          bind:this={svgEl}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 380 540"
          width="380"
          height="540"
          class="h-auto w-full max-w-[280px] rounded-2xl shadow-xl ring-1 ring-outline sm:max-w-[320px]"
        >
          <!-- 背景与天文氛围暗调渐变 -->
          <defs>
            <radialGradient id="gx-poster-glow" cx="50%" cy="38%" r="45%">
              <stop offset="0%" stop-color={isSolar ? '#241b10' : '#260c0c'} stop-opacity="0.8" />
              <stop offset="100%" stop-color="#0b0e14" stop-opacity="1" />
            </radialGradient>
          </defs>
          <rect width="380" height="540" rx="20" fill="url(#gx-poster-glow)" />
          <rect width="380" height="540" rx="20" fill="none" stroke="#263246" stroke-width="1.5" />

          <!-- 顶栏品牌 -->
          <text x="24" y="38" fill="#e2e6ee" font-size="12" font-weight="700" letter-spacing="1.5" font-family="system-ui, sans-serif">
            观象 · GUANXIANG
          </text>
          <text x="356" y="38" text-anchor="end" fill={isSolar ? '#ffb74d' : '#e05050'} font-size="12" font-family="system-ui, sans-serif">
            {isSolar ? '☀ ☾ ⊕' : '☾ ⊕ ☀'}
          </text>
          <line x1="24" y1="48" x2="356" y2="48" stroke="#1c2534" stroke-width="1" />

          <!-- 天象标题与日期 -->
          <text x="24" y="78" fill="#a6b0c2" font-size="12" font-family="monospace">
            {fmtDate(maxUtc)}
          </text>
          <text x="24" y="106" fill="#ffffff" font-size="20" font-weight="700" font-family="system-ui, sans-serif">
            {title}
          </text>
          {#if sarosStr}
            <rect x="24" y="118" width="124" height="20" rx="10" fill={isSolar ? 'rgba(255,183,77,0.15)' : 'rgba(196,83,47,0.18)'} />
            <text x="86" y="132" text-anchor="middle" fill={isSolar ? '#ffb74d' : '#e05050'} font-size="10.5" font-weight="600" font-family="system-ui, sans-serif">
              沙罗 {sarosStr}
            </text>
          {/if}

          <!-- 中心图形 Hero Illustration -->
          {#if isSolar}
            <!-- 日面模拟：金阳 + 黑月 -->
            <g transform="translate(190, 215)">
              <!-- 日冕微光外环 -->
              <circle cx="0" cy="0" r="48" fill="none" stroke="#ffb74d" stroke-width="5" opacity="0.25" />
              <!-- 太阳金轮 -->
              <circle cx="0" cy="0" r="44" fill="#ffb74d" />
              <!-- 月球暗轮剪影 -->
              {#if solarScene?.kind === 'total' && (!showPlace || solarLocal?.kind === 'total')}
                <circle cx="0" cy="0" r="44.5" fill="#0b0e14" stroke="#ffb74d" stroke-width="1.8" />
              {:else if solarScene?.kind === 'annular' && (!showPlace || solarLocal?.kind === 'annular')}
                <circle cx="0" cy="0" r="38" fill="#0b0e14" />
              {:else}
                <!-- 偏食月影根据食分偏移 -->
                {@const offset = (1 - Math.min(1, Math.max(0.1, maxMagnitude))) * 88}
                <circle cx={offset} cy="0" r="44" fill="#0b0e14" stroke="#ffb74d" stroke-width="0.75" />
              {/if}
            </g>
          {:else}
            <!-- 月面与地影模拟 -->
            <g transform="translate(190, 215)">
              <!-- 半影外圈 -->
              <circle cx="0" cy="0" r="62" fill="none" stroke="#a6b0c2" stroke-width="1" stroke-dasharray="3 3" opacity="0.35" />
              <!-- 本影深红内圈 -->
              <circle cx="0" cy="0" r="42" fill="#200606" stroke="#c4532f" stroke-width="1.5" opacity="0.85" />
              <!-- 月亮红铜色 -->
              <circle cx="0" cy="0" r="24" fill="#c4532f" stroke="#e05050" stroke-width="1" />
            </g>
          {/if}

          <!-- 数据信息中控卡片 (y: 285..455) -->
          <rect x="24" y="285" width="332" height="162" rx="14" fill="#131924" stroke="#263246" stroke-width="1" />

          <!-- 观测地或全球概况 -->
          <text x="38" y="312" fill="#e2e6ee" font-size="13" font-weight="600" font-family="system-ui, sans-serif">
            {#if showPlace && observer}
              📍 {observer.label ?? fmtCoord(observer.lat, observer.lon)}
            {:else}
              🌐 全球最大食甚概况
            {/if}
          </text>
          <text x="342" y="312" text-anchor="end" fill={isSolar ? '#ffb74d' : '#e05050'} font-size="12" font-weight="500" font-family="system-ui, sans-serif">
            {showPlace && visText ? visText : `食分 ${fmtNum(maxMagnitude, 3)}`}
          </text>
          <line x1="38" y1="324" x2="342" y2="324" stroke="#1c2534" stroke-width="0.8" />

          <!-- 统计行：食分、面积、持续时间 -->
          <text x="38" y="345" fill="#a6b0c2" font-size="11" font-family="system-ui, sans-serif">最大食分</text>
          <text x="38" y="364" fill="#ffffff" font-size="15" font-weight="600" font-family="monospace">
            {fmtNum(maxMagnitude, 3)}
          </text>

          {#if obscurationVal !== null}
            <text x="140" y="345" fill="#a6b0c2" font-size="11" font-family="system-ui, sans-serif">遮挡面积</text>
            <text x="140" y="364" fill="#ffffff" font-size="15" font-weight="600" font-family="monospace">
              {fmtNum(obscurationVal, 1)}%
            </text>
          {/if}

          {#if isSolar && showPlace && solarLocal?.central_duration_s}
            <text x="240" y="345" fill="#a6b0c2" font-size="11" font-family="system-ui, sans-serif">全食/环食持续</text>
            <text x="240" y="364" fill="#ffffff" font-size="15" font-weight="600" font-family="monospace">
              {fmtDuration(solarLocal.central_duration_s, true)}
            </text>
          {:else if contactsList.length > 0}
            <text x="240" y="345" fill="#a6b0c2" font-size="11" font-family="system-ui, sans-serif">食甚时刻</text>
            <text x="240" y="364" fill="#ffffff" font-size="15" font-weight="600" font-family="monospace">
              {fmtTime(maxUtc)}
            </text>
          {/if}

          <!-- 接触时刻点列表 (初亏、食甚、复圆等) -->
          {#if contactsList.length > 0}
            <line x1="38" y1="382" x2="342" y2="382" stroke="#1c2534" stroke-width="0.8" />
            <g transform="translate(38, 400)">
              {#each contactsList.slice(0, 4) as c, i}
                {@const cx = (i % 2) * 150}
                {@const cy = Math.floor(i / 2) * 20}
                <text x={cx} y={cy} fill="#a6b0c2" font-size="10.5" font-family="system-ui, sans-serif">
                  {c.label}：<tspan fill="#e2e6ee" font-family="monospace">{c.time}</tspan>
                  {#if c.alt}<tspan fill="#569aff" font-size="9.5"> ({c.alt})</tspan>{/if}
                </text>
              {/each}
            </g>
          {/if}

          <!-- 太阳安全警告（严格要求保留） -->
          {#if isSolar}
            <text x="24" y="468" fill="#ff6b5e" font-size="9" font-weight="600" font-family="system-ui, sans-serif">
              {t('posterSolarSafety')}
            </text>
          {/if}

          <!-- 页脚品牌与网址 -->
          <line x1="24" y1="480" x2="356" y2="480" stroke="#1c2534" stroke-width="1" />
          <text x="24" y="504" fill="#a6b0c2" font-size="10" font-family="system-ui, sans-serif">
            观象 (Guanxiang) · 跨平台天文事件搜索
          </text>
          <text x="24" y="522" fill="#569aff" font-size="10" font-weight="500" font-family="monospace">
            https://app.guanx.huxulm.dev
          </text>
          <text x="356" y="513" text-anchor="end" fill="#4f5b6d" font-size="9" font-family="system-ui, sans-serif">
            {t('posterScan')}
          </text>
        </svg>
      </div>

      <!-- 右侧控制项与操作按钮 -->
      <div class="space-y-4">
        {#if observer}
          <label class="flex items-center gap-2 text-sm text-fg cursor-pointer">
            <input type="checkbox" class="accent-primary" bind:checked={showPlace} />
            <span>{t('posterShowPlace')}（{observer.label ?? fmtCoord(observer.lat, observer.lon)}）</span>
          </label>
        {/if}

        <p class="text-xs leading-relaxed text-muted">
          采用 3× 超高清（1140×1620 像素）纯前端渲染，包含日食/月食几何形态、食分、精确接触时间与安全观测须知，适合保存分享至社交平台。
        </p>

        <div class="flex flex-col gap-2 pt-2">
          <button class="btn-filled w-full" onclick={download} disabled={exporting}>
            {exporting ? t('loading') : `💾 ${t('downloadPng')}`}
          </button>
          <div class="grid grid-cols-2 gap-2">
            <button class="btn-outline w-full" onclick={copyImage}>
              {copied ? `✓ ${t('imageCopied')}` : `📋 ${t('copyImage')}`}
            </button>
            <button class="btn-outline w-full" onclick={copyLink}>
              {linkCopied ? `✓ ${t('linkCopied')}` : `🔗 ${t('copyLink')}`}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</dialog>