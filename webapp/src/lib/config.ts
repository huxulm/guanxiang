/** 星历：App 打包的同一份裁剪版 de440s（1899-12 至 2101-02），可由 CI 复现。 */
export const EPHEM = {
  /** 线上用 VITE_EPHEM_URL（R2）；本地开发、预览由 vite.config.ts 的中间件提供 */
  url: import.meta.env.VITE_EPHEM_URL || '/ephem/de440s_1900_2100.bsp',
  sha256: '1b7ff150cbc00d364f584ad65dad651129fde4ab2e7aa23f9551dc9b9674afaa',
  bytes: 21_965_920,
} as const;

/** 可搜索的年份范围（含两端），受星历覆盖范围限制 */
export const YEAR_MIN = 1900;
export const YEAR_MAX = 2100;

/** 场景序列的采样步长（秒） */
export const SCENE_STEP_S = 60;

export const SITE_URL = 'https://guanx.huxulm.dev';
export const SOURCE_URL = 'https://github.com/huxulm/guanxiang';
