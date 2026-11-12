// 地平方位角计算与 16 罗盘方位指示
import { fmtNum } from './format';

export const COMPASS_16_ZH = [
  '北', '北微东', '东北', '东微北',
  '东', '东微南', '东南', '南微东',
  '南', '南微西', '西南', '西微南',
  '西', '西微北', '西北', '北微西',
] as const;

export const COMPASS_16_EN = [
  'N', 'NNE', 'NE', 'ENE',
  'E', 'ESE', 'SE', 'SSE',
  'S', 'SSW', 'SW', 'WSW',
  'W', 'WNW', 'NW', 'NNW',
] as const;

export interface AzimuthResult {
  azDeg: number;
  compassZh: string;
  compassEn: string;
}

/**
 * 由测站经纬度与天体日下点/星下点经纬度计算地平方位角（0° 为正北，90° 为正东，180° 为正南，270° 为正西）
 */
export function calcAzimuth(
  obsLatDeg: number,
  obsLonDeg: number,
  subLatDeg: number,
  subLonDeg: number,
): AzimuthResult {
  const rad = Math.PI / 180;
  const phi = obsLatDeg * rad;
  const delta = subLatDeg * rad;
  const dLon = (obsLonDeg - subLonDeg) * rad;

  const sinDelta = Math.sin(delta);
  const cosDelta = Math.cos(delta);
  const sinPhi = Math.sin(phi);
  const cosPhi = Math.cos(phi);
  const sinH = Math.sin(dLon);
  const cosH = Math.cos(dLon);

  const x = -cosDelta * sinH;
  const y = sinDelta * cosPhi - cosDelta * sinPhi * cosH;

  let az = (Math.atan2(x, y) * 180) / Math.PI;
  if (az < 0) az += 360;

  const idx = Math.round(az / 22.5) % 16;
  return {
    azDeg: az,
    compassZh: COMPASS_16_ZH[idx],
    compassEn: COMPASS_16_EN[idx],
  };
}

export function fmtAzimuth(az: AzimuthResult, lang: 'zh' | 'en'): string {
  const compass = lang === 'zh' ? az.compassZh : az.compassEn;
  return `${fmtNum(az.azDeg, 1)}° (${compass})`;
}
