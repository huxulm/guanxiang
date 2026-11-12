// 生成并下载标准 iCalendar（.ics）日程文件，兼容 Apple Calendar、Google Calendar、Outlook 等。
import { fmtCoord, fmtDuration, fmtNum, fmtTime, localSolarKindName, lunarKindName, parseUtc } from './format';
import type { LunarScene, Observer, SolarLocal } from './types';

function formatIcsDate(d: Date): string {
  return d
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}/, '');
}

function escapeIcsText(s: string): string {
  return s
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n');
}

export function downloadIcs(filename: string, content: string): void {
  const blob = new Blob([content], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename.endsWith('.ics') ? filename : `${filename}.ics`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

export function generateSolarIcs(date: string, local: SolarLocal, observer: Observer | null, lang: 'zh' | 'en'): string {
  const isZh = lang === 'zh';
  const c1 = local.contacts.find((c) => c.code === 'C1');
  const c4 = local.contacts.find((c) => c.code === 'C4');
  const max = local.contacts.find((c) => c.code === 'MAX');
  const start = c1 ? parseUtc(c1.utc) : max ? parseUtc(max.utc) : parseUtc(date);
  const end = c4 ? parseUtc(c4.utc) : new Date(start.getTime() + 2 * 3600_000);
  const now = new Date();

  const kindName = localSolarKindName(local.kind);
  const locName = observer ? observer.label ?? fmtCoord(observer.lat, observer.lon) : isZh ? '观测地' : 'Location';
  const title = isZh ? `${kindName}观测 · ${locName}` : `${kindName} observation · ${locName}`;

  const lines: string[] = [];
  lines.push(isZh ? `观象（Guanxiang）天文预报` : `Guanxiang Astronomical Forecast`);
  lines.push(isZh ? `天象类型：${kindName}` : `Type: ${kindName}`);
  lines.push(isZh ? `观测地点：${locName}` : `Location: ${locName}`);
  lines.push(isZh ? `最大食分：${fmtNum(local.magnitude, 3)}（食面积 ${fmtNum(local.obscuration * 100, 1)}%）` : `Max magnitude: ${fmtNum(local.magnitude, 3)} (Obscuration ${fmtNum(local.obscuration * 100, 1)}%)`);
  if (local.central_duration_s !== null) {
    lines.push(isZh ? `全食/环食持续：${fmtDuration(local.central_duration_s, true)}` : `Duration of totality/annularity: ${fmtDuration(local.central_duration_s, true)}`);
  }
  lines.push('');
  lines.push(isZh ? `各阶段精确时刻：` : `Contact times:`);
  for (const c of local.contacts) {
    const tStr = fmtTime(parseUtc(c.utc));
    const altStr = c.sun_alt_deg !== null ? ` (仰角 ${fmtNum(c.sun_alt_deg, 1)}°)` : '';
    lines.push(`  · ${c.label_zh || c.code}: ${tStr}${altStr}`);
  }
  lines.push('');
  lines.push(
    isZh
      ? `【安全警告】观测太阳必须使用符合 ISO 12312-2 标准的日食减光镜/滤光膜。切勿使用普通太阳镜、墨镜、曝光胶片或透过未安装滤膜的望远镜直接目视！`
      : `[SAFETY NOTICE] Always use ISO 12312-2 certified eclipse glasses or solar filters when viewing the Sun. Never look directly through sunglasses or unfiltered optics.`,
  );

  const desc = escapeIcsText(lines.join('\n'));
  const summary = escapeIcsText(title);
  const location = escapeIcsText(locName);

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Guanxiang//Solar Eclipse Calendar//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:solar-${date}-${formatIcsDate(start)}@guanxiang.huxulm.dev`,
    `DTSTAMP:${formatIcsDate(now)}`,
    `DTSTART:${formatIcsDate(start)}`,
    `DTEND:${formatIcsDate(end)}`,
    `SUMMARY:${summary}`,
    `LOCATION:${location}`,
    `DESCRIPTION:${desc}`,
    'BEGIN:VALARM',
    'TRIGGER:-PT15M',
    'ACTION:DISPLAY',
    isZh ? 'DESCRIPTION:日食即将开始观测' : 'DESCRIPTION:Solar eclipse approaching',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}

export function generateLunarIcs(date: string, scene: LunarScene, observer: Observer | null, lang: 'zh' | 'en'): string {
  const isZh = lang === 'zh';
  const p1 = scene.contacts.find((c) => c.code === 'P1');
  const u1 = scene.contacts.find((c) => c.code === 'U1');
  const u4 = scene.contacts.find((c) => c.code === 'U4');
  const p4 = scene.contacts.find((c) => c.code === 'P4');

  const start = u1 ? parseUtc(u1.utc) : p1 ? parseUtc(p1.utc) : parseUtc(date);
  const end = u4 ? parseUtc(u4.utc) : p4 ? parseUtc(p4.utc) : new Date(start.getTime() + 3 * 3600_000);
  const now = new Date();

  const kindName = lunarKindName(scene.kind);
  const locName = observer ? observer.label ?? fmtCoord(observer.lat, observer.lon) : isZh ? '全球概况' : 'Global';
  const title = isZh ? `${kindName}观测 · ${locName}` : `${kindName} observation · ${locName}`;

  const lines: string[] = [];
  lines.push(isZh ? `观象（Guanxiang）天文预报` : `Guanxiang Astronomical Forecast`);
  lines.push(isZh ? `天象类型：${kindName}` : `Type: ${kindName}`);
  lines.push(isZh ? `本影食分：${fmtNum(scene.umbral_magnitude, 3)}` : `Umbral magnitude: ${fmtNum(scene.umbral_magnitude, 3)}`);
  lines.push(isZh ? `半影食分：${fmtNum(scene.penumbral_magnitude, 3)}` : `Penumbral magnitude: ${fmtNum(scene.penumbral_magnitude, 3)}`);
  lines.push('');
  lines.push(isZh ? `各阶段精确时刻：` : `Contact times:`);
  for (const c of scene.contacts) {
    const tStr = fmtTime(parseUtc(c.utc));
    const altStr = c.altitude_deg !== null ? ` (高度 ${fmtNum(c.altitude_deg, 1)}°)` : '';
    lines.push(`  · ${c.label_zh || c.code}: ${tStr}${altStr}`);
  }

  const desc = escapeIcsText(lines.join('\n'));
  const summary = escapeIcsText(title);
  const location = escapeIcsText(locName);

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Guanxiang//Lunar Eclipse Calendar//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:lunar-${date}-${formatIcsDate(start)}@guanxiang.huxulm.dev`,
    `DTSTAMP:${formatIcsDate(now)}`,
    `DTSTART:${formatIcsDate(start)}`,
    `DTEND:${formatIcsDate(end)}`,
    `SUMMARY:${summary}`,
    `LOCATION:${location}`,
    `DESCRIPTION:${desc}`,
    'BEGIN:VALARM',
    'TRIGGER:-PT15M',
    'ACTION:DISPLAY',
    isZh ? 'DESCRIPTION:月食即将开始观测' : 'DESCRIPTION:Lunar eclipse approaching',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}
