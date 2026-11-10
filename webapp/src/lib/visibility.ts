// 观测地能不能看到：按食的开始、结束时天体是否在地平线上，以及中间有没有升起或落下（与 App 的分类相同）。

export type Visibility = 'full' | 'rises' | 'sets' | 'risesAndSets' | 'hidden';

/**
 * @param start 开始时的高度（度）
 * @param end   结束时的高度（度）
 * @param between 期间各采样点的高度（度）
 */
export function classify(start: number, end: number, between: number[]): Visibility {
  const up = (a: number) => a > 0;
  const anyUp = between.some(up) || up(start) || up(end);
  const anyDown = between.some((a) => !up(a)) || !up(start) || !up(end);
  if (up(start) && up(end)) return anyDown ? 'risesAndSets' : 'full';
  if (!up(start) && up(end)) return 'rises';
  if (up(start) && !up(end)) return 'sets';
  return anyUp ? 'risesAndSets' : 'hidden';
}
