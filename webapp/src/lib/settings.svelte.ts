// 用户设置：主题、语言、时区、观测地。只存在本机浏览器（localStorage），存取失败时用默认值。
import type { Observer } from './types';

export type ThemeChoice = 'system' | 'deep' | 'red' | 'light';
export type ResolvedTheme = Exclude<ThemeChoice, 'system'>;
export type Lang = 'zh' | 'en';
export type TimeZoneChoice = 'local' | 'utc';

// 键名与 index.html 里防闪烁的脚本一致
const KEYS = { theme: 'gx.theme', lang: 'gx.lang', tz: 'gx.tz', observer: 'gx.observer' } as const;

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string | null): void {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // 隐私模式或禁用了存储：只在本次会话里生效
  }
}

function initialLang(): Lang {
  const v = read(KEYS.lang);
  if (v === 'zh' || v === 'en') return v;
  return navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en';
}

function initialObserver(): Observer | null {
  try {
    const o = JSON.parse(read(KEYS.observer) ?? 'null');
    if (o && Number.isFinite(o.lat) && Number.isFinite(o.lon)) {
      return { lat: o.lat, lon: o.lon, height: Number.isFinite(o.height) ? o.height : 0, label: o.label };
    }
  } catch {
    // 忽略损坏的数据
  }
  return null;
}

const theme = read(KEYS.theme);
const tz = read(KEYS.tz);

export const settings = $state({
  theme: (theme === 'deep' || theme === 'red' || theme === 'light' ? theme : 'system') as ThemeChoice,
  lang: initialLang(),
  tz: (tz === 'utc' ? 'utc' : 'local') as TimeZoneChoice,
  observer: initialObserver(),
});

/** 系统是否偏好浅色（主题选“跟随系统”时用） */
const media = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: light)') : null;
const system = $state({ light: media?.matches ?? false });
media?.addEventListener('change', (e) => (system.light = e.matches));

export function resolvedTheme(): ResolvedTheme {
  if (settings.theme !== 'system') return settings.theme;
  return system.light ? 'light' : 'deep';
}

/** 在根组件里调用一次：设置变化时写回存储，并更新 <html> 的主题和语言 */
export function persistSettings(): void {
  $effect(() => write(KEYS.theme, settings.theme === 'system' ? null : settings.theme));
  $effect(() => write(KEYS.lang, settings.lang));
  $effect(() => write(KEYS.tz, settings.tz));
  $effect(() => write(KEYS.observer, settings.observer ? JSON.stringify(settings.observer) : null));
  $effect(() => {
    document.documentElement.dataset.theme = resolvedTheme();
  });
  $effect(() => {
    document.documentElement.lang = settings.lang === 'zh' ? 'zh-CN' : 'en';
  });
}
