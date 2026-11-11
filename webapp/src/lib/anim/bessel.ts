// 贝塞尔基本面与地面之间的换算（Explanatory Supplement 的标准公式，WGS84 椭球）。
// 与 crates/guanxiang-view/src/state.rs 测试里验证 μ 用的公式相同：反算的影轴地面点与 Rust 中心线相差 < 1e-6°。
// 单位：x、y、ξ、η、ζ 为地球赤道半径；角度为度。

const F = 1 / 298.257223563;
export const E2 = F * (2 - F);
const RAD = Math.PI / 180;

/** 基本面上地球（椭球）轮廓的 y 半轴：x 半轴为 1 */
export function earthRy(dDeg: number): number {
  return Math.sqrt(1 - E2 * Math.cos(dDeg * RAD) ** 2);
}

/**
 * 地面点（大地纬度、东经，海拔忽略）投影到基本面。ζ > 0 表示这一点朝向太阳（从太阳方向看得见）。
 * θ = μ + λ 是影轴方向在该点的时角。
 */
export function groundToPlane(latDeg: number, lonDeg: number, dDeg: number, muDeg: number): { xi: number; eta: number; zeta: number } {
  const phi = latDeg * RAD;
  const c = 1 / Math.sqrt(1 - E2 * Math.sin(phi) ** 2);
  const rc = c * Math.cos(phi); // ρ cos φ′
  const rs = (1 - E2) * c * Math.sin(phi); // ρ sin φ′
  const th = (muDeg + lonDeg) * RAD;
  const d = dDeg * RAD;
  return {
    xi: rc * Math.sin(th),
    eta: rs * Math.cos(d) - rc * Math.cos(th) * Math.sin(d),
    zeta: rs * Math.sin(d) + rc * Math.cos(th) * Math.cos(d),
  };
}

/** 基本面上的点沿影轴投到地面（朝向太阳的一侧）；不在地球上时返回 null。 */
export function planeToGround(x: number, y: number, dDeg: number, muDeg: number): { lat: number; lon: number } | null {
  const d = dDeg * RAD;
  const rho1 = Math.sqrt(1 - E2 * Math.cos(d) ** 2);
  const sd1 = Math.sin(d) / rho1;
  const cd1 = (Math.sqrt(1 - E2) * Math.cos(d)) / rho1;
  const eta1 = y / rho1;
  const q = 1 - x * x - eta1 * eta1;
  if (q < 0) return null;
  const zeta1 = Math.sqrt(q);
  const phi1 = Math.asin(eta1 * cd1 + zeta1 * sd1);
  const theta = Math.atan2(x, -eta1 * sd1 + zeta1 * cd1);
  const lat = Math.atan(Math.tan(phi1) / Math.sqrt(1 - E2)) / RAD;
  return { lat, lon: wrapLon(theta / RAD - muDeg) };
}

export function wrapLon(lon: number): number {
  const x = (((lon + 180) % 360) + 360) % 360 - 180;
  return x === -180 ? 180 : x;
}

/**
 * 基本面上以 (cx, cy) 为圆心、半径 r（< 1）的阴影圆与地球日照盘面交集边界的地面点环。
 * 圆周落在地球外的弧段沿地球边缘（ζ = 0 晨昏圈）闭合；完全不接触地球时返回空数组。
 */
export function footprintPolygon(
  cx: number,
  cy: number,
  r: number,
  dDeg: number,
  muDeg: number,
  n = 240,
  m = 60,
): { lat: number; lon: number }[] {
  const ry = earthRy(dDeg);
  const scale = 1 - 1e-12;
  const ptAt = (a: number) => {
    const x = cx + r * Math.cos(a);
    const y = cy + r * Math.sin(a);
    const eta1 = y / ry;
    return { x, y, eta1, u: x * x + eta1 * eta1 };
  };

  const samples = Array.from({ length: n }, (_, i) => ptAt((i / n) * 2 * Math.PI));
  const inside = samples.map((s) => s.u <= 1);
  const ring: [number, number][] = [];

  if (inside.every(Boolean)) {
    for (const s of samples) ring.push([s.x * scale, s.y * scale]);
  } else if (!inside.some(Boolean)) {
    return [];
  } else {
    let start = 0;
    for (let i = 0; i < n; i++) {
      if (inside[i] && !inside[(i + n - 1) % n]) {
        start = i;
        break;
      }
    }
    let end = start;
    while (inside[(end + 1) % n]) end = (end + 1) % n;

    const bisect = (aOut: number, aIn: number) => {
      let lo = aOut;
      let hi = aIn;
      for (let k = 0; k < 16; k++) {
        const mid = 0.5 * (lo + hi);
        if (ptAt(mid).u <= 1) hi = mid;
        else lo = mid;
      }
      return ptAt(hi);
    };

    const step = (2 * Math.PI) / n;
    const pIn = bisect(start * step - step, start * step);
    const pOut = bisect(end * step + step, end * step);

    ring.push([pIn.x * scale, pIn.y * scale]);
    for (let i = start; ; i = (i + 1) % n) {
      ring.push([samples[i].x * scale, samples[i].y * scale]);
      if (i === end) break;
    }
    ring.push([pOut.x * scale, pOut.y * scale]);

    const betaOut = Math.atan2(pOut.eta1, pOut.x);
    const betaIn = Math.atan2(pIn.eta1, pIn.x);
    const dBeta = Math.atan2(Math.sin(betaIn - betaOut), Math.cos(betaIn - betaOut));
    for (let j = 1; j < m; j++) {
      const beta = betaOut + (j / m) * dBeta;
      ring.push([Math.cos(beta) * scale, ry * Math.sin(beta) * scale]);
    }
  }

  const out: { lat: number; lon: number }[] = [];
  for (const [x, y] of ring) {
    const g = planeToGround(x, y, dDeg, muDeg);
    if (g) out.push(g);
  }
  return out;
}

