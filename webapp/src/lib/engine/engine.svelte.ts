// 主线程这边的计算引擎：第一次用到时启动 Worker、下载星历，状态供界面显示进度。
import * as Comlink from 'comlink';
import { EPHEM } from '../config';
import type { EngineApi } from './worker';
import type { EphemProgress } from './ephemeris';

export type EngineStatus = 'idle' | 'loading' | 'ready' | 'error';

export const engineState = $state({
  status: 'idle' as EngineStatus,
  phase: 'download' as EphemProgress['phase'],
  loaded: 0,
  total: EPHEM.bytes as number,
  fromCache: false,
  error: '',
});

let remote: Comlink.Remote<EngineApi> | null = null;
let ready: Promise<Comlink.Remote<EngineApi>> | null = null;

/** 取得已加载星历的引擎；第一次调用时开始加载，失败后再调用会重试。 */
export function getEngine(): Promise<Comlink.Remote<EngineApi>> {
  if (ready) return ready;
  engineState.status = 'loading';
  engineState.error = '';
  engineState.loaded = 0;
  ready = (async () => {
    if (!remote) {
      const worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' });
      remote = Comlink.wrap<EngineApi>(worker);
    }
    const r = await remote.init(
      EPHEM.url,
      EPHEM.sha256,
      EPHEM.bytes,
      Comlink.proxy((p: EphemProgress) => {
        engineState.phase = p.phase;
        engineState.loaded = p.loaded;
        engineState.total = p.total;
      }),
    );
    engineState.fromCache = r.fromCache;
    engineState.status = 'ready';
    return remote;
  })();
  ready.catch((e: unknown) => {
    engineState.status = 'error';
    engineState.error = e instanceof Error ? e.message : String(e);
    ready = null;
  });
  return ready;
}
