// 检查红光主题：src/app.css 里 data-theme='red' 的每个颜色都必须以红色分量为主（R 大于 G 和 B），
// 保护夜间观测时的暗适应。与 App 的同类测试对应。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const css = fs.readFileSync(path.resolve(here, '../src/app.css'), 'utf8');

const m = /:root\[data-theme='red'\]\s*\{([^}]*)\}/.exec(css);
if (!m) {
  console.error("app.css 里找不到 :root[data-theme='red']");
  process.exit(1);
}

const bad = [];
let count = 0;
for (const [, name, hex] of m[1].matchAll(/(--[\w-]+):\s*#([0-9a-fA-F]{6})\b/g)) {
  count++;
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
  if (!(r > g && r > b)) bad.push(`${name}: #${hex}`);
}
if (count === 0) {
  console.error('红光主题里没有找到颜色');
  process.exit(1);
}
if (bad.length) {
  console.error(`红光主题有 ${bad.length} 个颜色不以红色为主：\n  ${bad.join('\n  ')}`);
  process.exit(1);
}
console.log(`红光主题 ${count} 个颜色都以红色为主`);
