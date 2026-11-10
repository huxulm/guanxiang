// 星历下载与缓存（在 Worker 里运行）。
// 首次从网络下载并核对 SHA-256，存进 Cache Storage；以后直接从缓存读取。

export interface EphemProgress {
  phase: 'cache' | 'download' | 'verify';
  loaded: number;
  total: number;
}

const CACHE_NAME = 'guanxiang-ephemeris';

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes as Uint8Array<ArrayBuffer>);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** 缓存键带上 SHA-256：星历换版本后自动重新下载 */
function cacheKey(sha256: string): string {
  return new URL(`/__ephemeris/${sha256}.bsp`, self.location.origin).href;
}

async function openCache(): Promise<Cache | null> {
  try {
    return await caches.open(CACHE_NAME);
  } catch {
    return null; // 隐私模式等情况下 Cache Storage 不可用，每次都下载
  }
}

export async function loadEphemeris(
  url: string,
  sha256: string,
  expectedBytes: number,
  onProgress: (p: EphemProgress) => void,
): Promise<{ bytes: Uint8Array; fromCache: boolean }> {
  const cache = await openCache();
  const key = cacheKey(sha256);
  const hit = await cache?.match(key).catch(() => undefined);
  if (hit) {
    onProgress({ phase: 'cache', loaded: 0, total: expectedBytes });
    const bytes = new Uint8Array(await hit.arrayBuffer());
    if (bytes.length === expectedBytes) return { bytes, fromCache: true };
    await cache?.delete(key).catch(() => false); // 缓存损坏，重新下载
  }

  const res = await fetch(url);
  if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);
  // 有些服务器会压缩传输，Content-Length 是压缩后的大小，这里以已知的文件大小为准
  const total = expectedBytes;
  let buf = new Uint8Array(total);
  let loaded = 0;
  let lastReport = 0;
  const reader = res.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (loaded + value.length > buf.length) {
      const bigger = new Uint8Array(Math.max(buf.length * 2, loaded + value.length));
      bigger.set(buf.subarray(0, loaded));
      buf = bigger;
    }
    buf.set(value, loaded);
    loaded += value.length;
    const now = performance.now();
    if (now - lastReport > 100) {
      lastReport = now;
      onProgress({ phase: 'download', loaded, total });
    }
  }
  const bytes = loaded === buf.length ? buf : buf.slice(0, loaded);

  onProgress({ phase: 'verify', loaded, total });
  const actual = await sha256Hex(bytes);
  if (actual !== sha256) {
    throw new Error(`星历校验失败（SHA-256 ${actual.slice(0, 12)}…，应为 ${sha256.slice(0, 12)}…）`);
  }
  await cache
    ?.put(key, new Response(bytes as Uint8Array<ArrayBuffer>, { headers: { 'Content-Type': 'application/octet-stream' } }))
    .catch(() => undefined); // 存储空间不足时不缓存
  return { bytes, fromCache: false };
}
