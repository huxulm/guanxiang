# 观象 Web 应用（`webapp/`）

浏览器版的日月食搜索与详情。计算全部在浏览器里用 WebAssembly 完成（`crates/guanxiang-wasm`，与 App、CLI 同一个 Rust 核心），星历是 App 打包的同一份裁剪版 DE440s。

技术栈：Vite 8 + Svelte 5 + TypeScript + Tailwind 4；计算在 Web Worker 里（Comlink）。规划和验证记录见 `docs/PLAN.md` 的“Web 应用”。

## 常用命令

```sh
cd webapp
npm ci
npm run wasm     # wasm-pack 编译 crates/guanxiang-wasm → src/wasm/pkg/（需要 rustup target add wasm32-unknown-unknown 和 wasm-pack）
npm run data     # 预算近 20 年的日月食 → public/data/eclipses.json（需要 data/ 或 app/assets/ 下的 de440s_1900_2100.bsp）
npm run dev      # http://localhost:5173 ，/ephem/ 下由开发服务器提供本地星历
npm run build    # svelte-check（警告也算失败）+ 红光主题检查 + vite build
```

改了 Rust 端（`crates/guanxiang-view`、`crates/guanxiang-wasm`）要重新 `npm run wasm`；JSON 字段变了要同步 `src/lib/types.ts`。

## 结构

| 路径 | 内容 |
|---|---|
| `src/lib/engine/` | Worker（加载 wasm、星历，执行计算）、星历下载与缓存（SHA-256 校验，Cache Storage）、主线程的引擎状态 |
| `src/lib/i18n/` | 文案：App 的 ARB（`virtual:arb`，由 `vite.config.ts` 读取 `app/lib/l10n/*.arb`）+ Web 专用文案 `web-strings.ts`（中英文键由类型保证一致） |
| `src/lib/settings.svelte.ts` | 主题、语言、时区、观测地（只存 localStorage） |
| `src/lib/router.svelte.ts` | 路由：`/`、`/lunar/YYYY-MM-DD`、`/solar/YYYY-MM-DD`，详情页可带 `?lat=&lon=&h=` |
| `src/pages/`、`src/components/` | 页面和组件 |
| `src/app.css` | 三套主题的色值（与 `app/lib/src/theme.dart` 一致）；界面里不写死颜色 |
| `scripts/` | wasm 构建、首页数据生成、红光主题检查 |

## 约定

- 颜色只用 `src/app.css` 里的变量（Tailwind 里是 `bg-surface`、`text-muted`、`text-eclipse` 这类名字）；红光主题的每个颜色都要 R 分量最大（`npm run check` 会检查）。
- 日食相关页面必须显示 ISO 12312-2 安全提示（`SafetyNotice`）。
- Comlink 回调不能返回响应式对象：返回值会被传回 Worker，`$state` 代理不能结构化克隆。
- 线上星历地址用环境变量 `VITE_EPHEM_URL` 指定（R2，需要 CORS）；没设时用 `/ephem/`，只有开发和 `vite preview` 能用。

## 部署

线上地址 https://app.guanx.huxulm.dev （Cloudflare Workers 静态资源，单页应用，见 `wrangler.jsonc`）。目前手动发布（需要 `CLOUDFLARE_API_TOKEN`）：

```sh
cd webapp
npm run wasm && npm run data && npm run build
npx wrangler deploy
```

星历放在 R2 存储桶 `huxulm-asia` 的 `guanxiang/ephem/de440s_1900_2100-1b7ff150.bsp`，经 https://s2.huxulm.dev 公开（`Cache-Control: public, max-age=31536000, immutable`）；地址写在 `.env.production`。存储桶的 CORS 只允许 `https://app.guanx.huxulm.dev` 和 `http://localhost:4173`（`vite preview`）以 GET、HEAD 读取。星历换版本时上传新文件名，同时改 `.env.production` 和 `src/lib/config.ts` 的 `sha256`、`bytes`。
