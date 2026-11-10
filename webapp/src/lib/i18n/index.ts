// 文案：先查 Web 专用文案，再查 App 的 ARB。模板里调用 t() 会随语言切换自动刷新（读取了 settings.lang）。
import { zh as arbZh, en as arbEn } from 'virtual:arb';
import { settings } from '../settings.svelte';
import { web } from './web-strings';

const arb: Record<'zh' | 'en', Record<string, string>> = { zh: arbZh, en: arbEn };

export function t(key: string, params?: Record<string, string | number>): string {
  const lang = settings.lang;
  const s = web[lang][key] ?? arb[lang][key];
  if (s === undefined) {
    if (import.meta.env.DEV) console.warn(`缺少文案：${key}`);
    return key;
  }
  if (!params) return s;
  return s.replace(/\{(\w+)\}/g, (m, k: string) => (k in params ? String(params[k]) : m));
}
