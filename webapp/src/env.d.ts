/// <reference types="svelte" />
/// <reference types="vite/client" />

declare module 'virtual:arb' {
  /** app/lib/l10n/app_zh.arb（去掉 @ 元数据） */
  export const zh: Record<string, string>;
  /** app/lib/l10n/app_en.arb */
  export const en: Record<string, string>;
}

interface ImportMetaEnv {
  /** 线上星历地址（R2）；不设时用本地开发服务器的 /ephem/ */
  readonly VITE_EPHEM_URL?: string;
}
