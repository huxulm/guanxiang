// 计算 Worker：加载 wasm 和星历，所有天文计算都在这里做，不卡界面。
// 主线程通过 Comlink 调用（见 engine.svelte.ts）。
import * as Comlink from 'comlink';
import init, { Engine, LunarEclipseHandle, SolarEclipseHandle } from '../../wasm/pkg/guanxiang_wasm.js';
import wasmUrl from '../../wasm/pkg/guanxiang_wasm_bg.wasm?url';
import { loadEphemeris, type EphemProgress } from './ephemeris';
import type {
  LunarListItem,
  LunarScene,
  LunarState,
  Observer,
  SolarListItem,
  SolarScene,
  SolarState,
} from '../types';

let engine: Engine | null = null;
const lunarHandles = new Map<string, LunarEclipseHandle>();
const solarHandles = new Map<string, SolarEclipseHandle>();
/** 每次搜索或取消都加一；搜索循环发现它变了就停 */
let searchToken = 0;

function need(): Engine {
  if (!engine) throw new Error('星历还没有加载');
  return engine;
}

function lunarHandle(date: string): LunarEclipseHandle {
  let h = lunarHandles.get(date);
  if (!h) {
    h = need().lunarEclipse(date);
    lunarHandles.set(date, h);
  }
  return h;
}

function solarHandle(date: string): SolarEclipseHandle {
  let h = solarHandles.get(date);
  if (!h) {
    h = need().solarEclipse(date);
    solarHandles.set(date, h);
  }
  return h;
}

/** wasm 接口里观测地是三个可省略的参数 */
function obsArgs(o: Observer | null): [number | undefined, number | undefined, number | undefined] {
  return o ? [o.lat, o.lon, o.height] : [undefined, undefined, undefined];
}

const yieldToEvents = () => new Promise<void>((r) => setTimeout(r, 0));

const api = {
  /** 加载 wasm 和星历。重复调用无副作用。 */
  async init(
    url: string,
    sha256: string,
    bytes: number,
    onProgress: (p: EphemProgress) => void,
  ): Promise<{ fromCache: boolean; ms: number }> {
    if (engine) return { fromCache: true, ms: 0 };
    const t0 = performance.now();
    await init({ module_or_path: wasmUrl });
    const eph = await loadEphemeris(url, sha256, bytes, onProgress);
    engine = new Engine(eph.bytes);
    return { fromCache: eph.fromCache, ms: Math.round(performance.now() - t0) };
  },

  /**
   * 搜索 [from, to] 年（含两端）的日月食，按年分块，每块之后回报进度。
   * 被 cancel() 打断时返回已经找到的部分，cancelled 为 true。
   */
  async search(
    from: number,
    to: number,
    onYear: (done: number, total: number) => void,
  ): Promise<{ lunar: LunarListItem[]; solar: SolarListItem[]; cancelled: boolean }> {
    const e = need();
    const token = ++searchToken;
    const lunar: LunarListItem[] = [];
    const solar: SolarListItem[] = [];
    const total = to - from + 1;
    for (let y = from; y <= to; y++) {
      await yieldToEvents(); // 让 cancel 消息有机会进来
      if (token !== searchToken) return { lunar, solar, cancelled: true };
      lunar.push(...(JSON.parse(e.lunarEclipses(y, y + 1)) as LunarListItem[]));
      solar.push(...(JSON.parse(e.solarEclipses(y, y + 1)) as SolarListItem[]));
      onYear(y - from + 1, total);
    }
    return { lunar, solar, cancelled: false };
  },

  cancel(): void {
    searchToken++;
  },

  lunarScene(date: string, obs: Observer | null, stepS: number): LunarScene {
    return JSON.parse(lunarHandle(date).scene(need(), ...obsArgs(obs), stepS));
  },

  solarScene(date: string, obs: Observer | null, stepS: number): SolarScene {
    return JSON.parse(solarHandle(date).scene(need(), ...obsArgs(obs), stepS));
  },

  lunarState(date: string, tRelS: number, obs: Observer | null): LunarState {
    return JSON.parse(lunarHandle(date).stateAt(need(), tRelS, ...obsArgs(obs)));
  },

  solarState(date: string, tRelS: number, obs: Observer | null): SolarState {
    return JSON.parse(solarHandle(date).stateAt(need(), tRelS, ...obsArgs(obs)));
  },
};

export type EngineApi = typeof api;

Comlink.expose(api);
