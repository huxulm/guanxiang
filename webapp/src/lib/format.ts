// 时间、时长、坐标的格式化。时区按设置显示本地时区或 UTC。
import { t } from './i18n';
import { settings } from './settings.svelte';
import type { LocalSolarKind, LunarKind, SolarKind } from './types';

/** 解析 wasm 返回的 UTC 时间：ISO（`…T…Z`）或场景里的 `YYYY-MM-DD HH:MM:SS` */
export function parseUtc(s: string): Date {
  return new Date(s.includes('T') ? s : `${s.replace(' ', 'T')}Z`);
}

function locale(): string {
  return settings.lang === 'zh' ? 'zh-CN' : 'en-GB';
}

function timeZone(): string | undefined {
  return settings.tz === 'utc' ? 'UTC' : undefined;
}

export function fmtDate(d: Date): string {
  return new Intl.DateTimeFormat(locale(), {
    timeZone: timeZone(),
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  }).format(d);
}

export function fmtTime(d: Date, seconds = true): string {
  return new Intl.DateTimeFormat(locale(), {
    timeZone: timeZone(),
    hour: '2-digit',
    minute: '2-digit',
    second: seconds ? '2-digit' : undefined,
    hourCycle: 'h23',
  }).format(d);
}

export function fmtDateTime(d: Date): string {
  return `${fmtDate(d)} ${fmtTime(d)}`;
}

/** 当前时区的名称，如 “UTC+8” 或 “UTC” */
export function zoneLabel(at: Date = new Date()): string {
  if (settings.tz === 'utc') return 'UTC';
  const part = new Intl.DateTimeFormat('en-US', { timeZoneName: 'shortOffset' })
    .formatToParts(at)
    .find((p) => p.type === 'timeZoneName')?.value;
  return part ? part.replace('GMT', 'UTC').replace(/^UTC$/, 'UTC±0') : 'UTC';
}

/** 时长：≥1 小时显示“x 小时 y 分”，否则“m 分 s 秒”或“m 分钟” */
export function fmtDuration(seconds: number, withSeconds = false): string {
  const s = Math.max(0, Math.round(seconds));
  if (s >= 3600) {
    return t('durationHm', { hours: Math.floor(s / 3600), minutes: Math.round((s % 3600) / 60) });
  }
  if (withSeconds) return t('durationMs', { minutes: Math.floor(s / 60), seconds: s % 60 });
  return t('durationM', { minutes: Math.round(s / 60) });
}

export function fmtNum(x: number, digits: number): string {
  return x.toLocaleString(locale(), { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export function fmtCoord(lat: number, lon: number, digits = 2): string {
  const la = `${fmtNum(Math.abs(lat), digits)}°`;
  const lo = `${fmtNum(Math.abs(lon), digits)}°`;
  const ns = lat >= 0 ? t('coordN') : t('coordS');
  const ew = lon >= 0 ? t('coordE') : t('coordW');
  return settings.lang === 'zh' ? `${ns} ${la}，${ew} ${lo}` : `${la} ${ns}, ${lo} ${ew}`;
}

const LUNAR_KIND: Record<LunarKind, string> = { penumbral: 'lunarPenumbral', partial: 'lunarPartial', total: 'lunarTotal' };
const SOLAR_KIND: Record<SolarKind, string> = {
  partial: 'solarPartial',
  annular: 'solarAnnular',
  total: 'solarTotal',
  hybrid: 'solarHybrid',
};
const LOCAL_KIND: Record<LocalSolarKind, string> = { partial: 'localPartial', annular: 'localAnnular', total: 'localTotal' };

export const lunarKindName = (k: LunarKind) => t(LUNAR_KIND[k]);
export const solarKindName = (k: SolarKind) => t(SOLAR_KIND[k]);
export const localSolarKindName = (k: LocalSolarKind) => t(LOCAL_KIND[k]);
