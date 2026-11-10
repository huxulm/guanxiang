// 最简单的前端路由（History API）。线上由 wrangler.jsonc 的 single-page-application 把所有地址回到 index.html。
//   /                    首页
//   /lunar/YYYY-MM-DD    月食详情（日期为食甚的 UTC 日期）
//   /solar/YYYY-MM-DD    日食详情
// 详情页可以带 ?lat=…&lon=…[&h=…]，指定观测地（分享链接用）。

export type Route =
  | { page: 'home' }
  | { page: 'lunar'; date: string }
  | { page: 'solar'; date: string }
  | { page: 'notFound' };

export const location$ = $state({ path: location.pathname, search: location.search });

function sync(): void {
  location$.path = location.pathname;
  location$.search = location.search;
}

window.addEventListener('popstate', sync);

export function navigate(href: string): void {
  history.pushState(null, '', href);
  sync();
  window.scrollTo(0, 0);
}

/** 用在 <a href="/…" use:link>：站内链接不刷新页面；带修饰键或新窗口打开时交给浏览器 */
export function link(node: HTMLAnchorElement) {
  const onClick = (e: MouseEvent) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (node.target && node.target !== '_self') return;
    const href = node.getAttribute('href');
    if (!href?.startsWith('/')) return;
    e.preventDefault();
    navigate(href);
  };
  node.addEventListener('click', onClick);
  return { destroy: () => node.removeEventListener('click', onClick) };
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;

export function matchRoute(path: string): Route {
  if (path === '/' || path === '') return { page: 'home' };
  const m = /^\/(lunar|solar)\/([^/]+)\/?$/.exec(path);
  if (m && DATE.test(m[2])) return { page: m[1] as 'lunar' | 'solar', date: m[2] };
  return { page: 'notFound' };
}

/** 链接里的观测地（?lat=&lon=&h=），没有或不合法时返回 null */
export function observerFromSearch(search: string): { lat: number; lon: number; height: number } | null {
  const p = new URLSearchParams(search);
  const lat = Number(p.get('lat'));
  const lon = Number(p.get('lon'));
  if (!p.has('lat') || !p.has('lon') || !(Math.abs(lat) <= 90) || !(Math.abs(lon) <= 180)) return null;
  const h = Number(p.get('h') ?? 0);
  return { lat, lon, height: Number.isFinite(h) ? h : 0 };
}
