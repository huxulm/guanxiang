// 中英文切换：默认跟随浏览器语言，用户选过就记住（只存在本浏览器）。
// 中文文本直接写在 index.html 里，这里只放英文；切回中文时恢复原文。

type Lang = 'zh' | 'en';

/** 当前版本。发新版时只改这里。 */
const VERSION = '0.1.5';
/** 安装包放在 Cloudflare R2（桶 huxulm-asia），由 CI 的 release-mirror 任务从 GitLab 包仓库同步。 */
const DOWNLOAD_BASE = 'https://s2.huxulm.dev/guanxiang';

const en: Record<string, string> = {
  brand: 'Guanxiang',
  navFeatures: 'Features',
  navAccuracy: 'Accuracy',
  navScreens: 'Screenshots',
  navDownload: 'Download',
  badge: `v${VERSION} · Android · Windows`,
  heroTitle: 'Know what the sky will do before you look up',
  heroText:
    'Guanxiang searches transits, conjunctions, oppositions, eclipses and lunar occultations from 1900 to 2100 on your phone, and predicts when and where the ISS or Tiangong will cross the Sun or the Moon. Everything is computed on the device.',
  ctaDownload: 'Get it for Android',
  ctaMore: 'See features',
  featuresTitle: 'What it finds',
  f1Title: 'Transits of Mercury and Venus',
  f1Text: 'When a planet crosses the solar disk and how close it gets, optionally only those visible from your location.',
  f2Title: 'Conjunctions, oppositions, close approaches',
  f2Text: 'Pick any two bodies and find when they come closest or stand opposite each other.',
  f3Title: 'Solar and lunar eclipses',
  f3Text: 'Eclipse types match NASA’s Five Millennium Canon, with local circumstances for where you are.',
  f4Title: 'Lunar occultations',
  f4Text: 'When the Moon covers a planet or any of 550 bright stars.',
  f5Title: 'Satellite transits',
  f5Text: 'When the ISS or Tiangong crosses the Sun or the Moon, with the centre line of the visibility path on a map.',
  f6Title: 'Offline, and your location stays put',
  f6Text: 'Ships with the JPL DE440 ephemeris; only satellite elements and map tiles need a network. GPS location is kept on the device.',
  accuracyTitle: 'Checked against independent sources',
  accuracyText: 'Every kind of result has been compared one by one with independent astronomy software or catalogues.',
  thItem: 'Quantity',
  thRef: 'Reference',
  thDiff: 'Difference',
  r1: 'Apparent positions',
  r2: 'Conjunction and opposition times',
  r2d: '≤ 0.002 s',
  r3: 'Eclipse maxima',
  r3r: 'NASA Five Millennium Canon',
  r3d: '≤ 2.3 s, all types agree',
  r4: 'Lunar occultations',
  r4d: '≤ 0.003 s',
  r5: 'Satellite approaches',
  r5d: '≤ 0.007 s',
  screensTitle: 'Screenshots',
  capSearch: 'Pick an event type and years',
  capResults: 'Results on their own page',
  capSatellite: 'Space station passing the Sun',
  capSettings: 'GPS or a manual location',
  altSearch: 'Search screen',
  altResults: 'Search results',
  altSatellite: 'Satellite transit results',
  altSettings: 'Settings screen',
  downloadTitle: 'Download',
  dlAndroid: 'Android',
  dlAndroidText: 'Android 7.0 or later. Most phones need arm64-v8a.',
  dlCert: 'Signing certificate SHA-256: ',
  dlWindows: 'Windows',
  dlWindowsText:
    'Windows 10 / 11 (x64). The installer does not need administrator rights; there is also a portable zip, just unzip and run guanxiang.exe. The program is not signed, so SmartScreen may warn on first run; choose “More info → Run anyway”.',
  dlWinSetup: 'Installer',
  dlWinZip: 'Portable zip',
  dlNotes: 'SHA-256 checksums',
  safetyTitle: 'Protect your eyes when observing the Sun.',
  safetyText:
    'Use a certified solar filter (ISO 12312-2). Never look at the Sun with the naked eye, ordinary sunglasses, or an unfiltered telescope or camera.',
  credits:
    'Ephemeris: JPL DE440. Precession, nutation and related algorithms: IAU SOFA. Satellite elements: CelesTrak. Maps: © OpenStreetMap contributors. Full licences and acknowledgements are in the app under Settings → About & licences.',
  disclaimer: 'Results are for reference only.',
  privacyLink: 'Privacy policy',
};

const zhText = new Map<Element, string>();
const zhAlt = new Map<Element, string>();
const zhTitle = document.title;

function storedLang(): Lang | null {
  try {
    const v = localStorage.getItem('lang');
    return v === 'zh' || v === 'en' ? v : null;
  } catch {
    return null;
  }
}

function apply(lang: Lang): void {
  document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
  document.title = lang === 'zh' ? zhTitle : 'Guanxiang · Astronomical event search';
  document.querySelectorAll<HTMLElement>('[data-i18n]').forEach((el) => {
    if (!zhText.has(el)) zhText.set(el, el.textContent ?? '');
    const t = lang === 'en' ? en[el.dataset.i18n!] : undefined;
    el.textContent = t ?? zhText.get(el)!;
  });
  document.querySelectorAll<HTMLImageElement>('[data-i18n-alt]').forEach((el) => {
    if (!zhAlt.has(el)) zhAlt.set(el, zhAltText[el.dataset.i18nAlt!] ?? '');
    el.alt = lang === 'en' ? (en[el.dataset.i18nAlt!] ?? '') : zhAlt.get(el)!;
  });
  const btn = document.getElementById('lang')!;
  btn.textContent = lang === 'zh' ? 'EN' : '中文';
  btn.setAttribute('aria-label', lang === 'zh' ? 'Switch to English' : '切换到中文');
}

const zhAltText: Record<string, string> = {
  altSearch: '搜索页',
  altResults: '搜索结果',
  altSatellite: '卫星凌日结果',
  altSettings: '设置页',
};

function setLinks(): void {
  const pkg = `${DOWNLOAD_BASE}/${VERSION}`;
  (document.getElementById('dl-arm64') as HTMLAnchorElement).href = `${pkg}/guanxiang-${VERSION}-arm64-v8a.apk`;
  (document.getElementById('dl-x86') as HTMLAnchorElement).href = `${pkg}/guanxiang-${VERSION}-x86_64.apk`;
  (document.getElementById('dl-win') as HTMLAnchorElement).href = `${pkg}/guanxiang-${VERSION}-windows-x64-setup.exe`;
  (document.getElementById('dl-win-zip') as HTMLAnchorElement).href = `${pkg}/guanxiang-${VERSION}-windows-x64.zip`;
  (document.getElementById('dl-release') as HTMLAnchorElement).href = `${pkg}/SHA256SUMS`;
}

let lang: Lang = storedLang() ?? (navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en');
setLinks();
apply(lang);

document.getElementById('lang')!.addEventListener('click', () => {
  lang = lang === 'zh' ? 'en' : 'zh';
  try {
    localStorage.setItem('lang', lang);
  } catch {
    // 无痕模式等情况下存不了，只影响下次打开
  }
  apply(lang);
});
