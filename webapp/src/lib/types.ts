// guanxiang-wasm 返回的 JSON（格式定义在 crates/guanxiang-view，字段为 snake_case）。
// 改 Rust 端字段时同步这里。

export interface TimeRef {
  /** ISO 8601 UTC，精确到毫秒 */
  utc: string;
  /** J2000.0 起算的 TT 秒数 */
  tt: number;
}

export interface Saros {
  series: number;
  member: number;
  count: number;
}

export type LunarKind = 'penumbral' | 'partial' | 'total';
export type SolarKind = 'partial' | 'annular' | 'total' | 'hybrid';
export type LocalSolarKind = 'partial' | 'annular' | 'total';

/** list::lunar_eclipses_json 的一项 */
export interface LunarListItem {
  kind: LunarKind;
  greatest: TimeRef;
  gamma: number;
  penumbral_magnitude: number;
  umbral_magnitude: number;
  /** P1、U1、U2、U3、U4、P4 */
  contacts: (TimeRef | null)[];
  saros: Saros | null;
}

export interface GroundPointJson {
  lat_deg: number;
  lon_deg: number;
  sun_alt_deg: number;
  width_km: number;
}

/** list::solar_eclipses_json 的一项 */
export interface SolarListItem {
  kind: SolarKind;
  central: boolean;
  greatest: TimeRef;
  gamma: number;
  magnitude: number;
  greatest_point: GroundPointJson | null;
  saros: Saros | null;
}

/** public/data/eclipses.json（scripts/gen-eclipses.mjs 生成） */
export interface EclipseData {
  from: number;
  to: number;
  lunar: LunarListItem[];
  solar: SolarListItem[];
}

export interface ObserverJson {
  lat_deg: number;
  lon_deg: number;
  height_m: number;
}

// ---- 场景（scene.rs，格式与 guanxiang scene 相同；utc 为 “YYYY-MM-DD HH:MM:SS”） ----

export type LunarContactCode = 'P1' | 'U1' | 'U2' | 'G' | 'U3' | 'U4' | 'P4';

export interface LunarContact {
  code: LunarContactCode;
  label_zh: string;
  utc: string;
  t_rel_s: number;
  x_deg: number;
  y_deg: number;
  altitude_deg: number | null;
}

export interface LunarPathPoint {
  t_rel_s: number;
  utc: string;
  x_deg: number;
  y_deg: number;
  sep_deg: number;
  umbral_mag: number;
  penumbral_mag: number;
  altitude_deg: number | null;
}

export interface LunarScene {
  scene: 'lunar_eclipse';
  kind: LunarKind;
  kind_zh: string;
  greatest_utc: string;
  greatest_tt_jd: number;
  gamma: number;
  penumbral_magnitude: number;
  umbral_magnitude: number;
  saros: Saros | null;
  observer: ObserverJson | null;
  radii_deg: { penumbra: number; umbra: number; moon: number };
  contacts: LunarContact[];
  path: LunarPathPoint[];
}

export interface DiskView {
  x_deg: number;
  y_deg: number;
  sun_r_deg: number;
  moon_r_deg: number;
  obscuration: number;
  sun_alt_deg: number;
  zenith_angle_deg: number;
}

export type SolarContactCode = 'C1' | 'C2' | 'MAX' | 'C3' | 'C4';

export interface SolarLocalContact {
  code: SolarContactCode;
  label_zh: string;
  utc: string;
  t_rel_s: number;
  x_deg: number | null;
  y_deg: number | null;
  sun_r_deg: number | null;
  moon_r_deg: number | null;
  obscuration: number | null;
  sun_alt_deg: number | null;
  zenith_angle_deg: number | null;
}

export interface SolarLocal {
  kind: LocalSolarKind;
  kind_zh: string;
  maximum_utc: string;
  magnitude: number;
  obscuration: number;
  central_duration_s: number | null;
  contacts: SolarLocalContact[];
  disk_frames: (DiskView & { t_rel_s: number; utc: string })[];
}

export interface SolarScene {
  scene: 'solar_eclipse';
  kind: SolarKind;
  kind_zh: string;
  central: boolean;
  greatest_utc: string;
  greatest_tt_jd: number;
  gamma: number;
  magnitude: number;
  saros: Saros | null;
  greatest_point: GroundPointJson | null;
  observer: ObserverJson | null;
  diagram: {
    l1: number;
    l2: number;
    d_deg: number;
    sub_solar_lat_deg: number;
    sub_solar_lon_deg: number;
    greatest: { x: number; y: number };
    track: { t_rel_s: number; utc: string; x: number; y: number }[];
  };
  central_line: ({ t_rel_s: number; utc: string } & GroundPointJson)[];
  local: SolarLocal | null;
}

// ---- 逐帧状态（state.rs） ----

export interface LunarState {
  t_rel_s: number;
  utc: string;
  x_deg: number;
  y_deg: number;
  sep_deg: number;
  radii_deg: { penumbra: number; umbra: number; moon: number };
  umbral_mag: number;
  penumbral_mag: number;
  altitude_deg: number | null;
}

export interface SolarState {
  t_rel_s: number;
  utc: string;
  bessel: {
    x: number;
    y: number;
    z: number;
    d_deg: number;
    mu_deg: number;
    l1: number;
    l2: number;
    tan_f1: number;
    tan_f2: number;
  };
  sub_solar: { lat_deg: number; lon_deg: number };
  shadow_center: GroundPointJson | null;
  local: DiskView | null;
}

/** 前端的观测地（度、米） */
export interface Observer {
  lat: number;
  lon: number;
  height: number;
  /** 城市名或“当前位置”，只用于显示 */
  label?: string;
}
