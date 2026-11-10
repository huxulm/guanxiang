// 陆地轮廓（Natural Earth 1:110m，公有领域，与 App 共用 app/assets/geo/land_110m.json）。
// 按需加载：只有日食动画用得到，单独打包成一个分块。

/** 每个环是 [经度, 纬度, 经度, 纬度, …]（度） */
export type Rings = Float32Array[];

let cache: Promise<Rings> | null = null;

export function loadLand(): Promise<Rings> {
  cache ??= import('../../../../app/assets/geo/land_110m.json').then((m) => {
    const data = m.default as { scale: number; rings: number[][] };
    return data.rings.map((r) => Float32Array.from(r, (v) => v / data.scale));
  });
  return cache;
}
