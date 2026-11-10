// 用 wasm-pack 把 crates/guanxiang-wasm 编成浏览器用的 ES 模块，输出到 src/wasm/pkg/（不进 Git）。
// 需要 Rust 的 wasm32-unknown-unknown 目标和 wasm-pack。
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const crate = path.resolve(here, '../../crates/guanxiang-wasm');
const out = path.resolve(here, '../src/wasm/pkg');

const r = spawnSync(
  'wasm-pack',
  ['build', crate, '--release', '--target', 'web', '--no-pack', '--out-dir', out, '--out-name', 'guanxiang_wasm'],
  { stdio: 'inherit', shell: process.platform === 'win32' },
);
process.exit(r.status ?? 1);
