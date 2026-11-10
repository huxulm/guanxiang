// 详情页共用：等星历就绪后，按日期和观测地在 Worker 里计算场景；观测地变了自动重算。
import { engineState, getEngine } from './engine/engine.svelte';
import { SCENE_STEP_S } from './config';
import { observerFromSearch, location$ } from './router.svelte';
import { settings } from './settings.svelte';
import type { Observer } from './types';
import type { EngineApi } from './engine/worker';
import type * as Comlink from 'comlink';

/** 链接里带的观测地优先，其次是保存的设置 */
export function pageObserver(): { observer: Observer | null; fromLink: Observer | null } {
  const fromLink = observerFromSearch(location$.search);
  return { observer: fromLink ?? settings.observer, fromLink };
}

export type SceneResult<T> =
  | { status: 'waiting' }
  | { status: 'computing' }
  | { status: 'ok'; scene: T; ms: number }
  | { status: 'notFound' }
  | { status: 'error'; message: string };

/**
 * 计算场景并跟踪状态。`compute` 在 Worker 上执行（传入的观测地是普通对象，可以结构化克隆）。
 * 必须在组件初始化时调用。
 */
export function sceneLoader<T>(
  compute: (e: Comlink.Remote<EngineApi>, obs: Observer | null, step: number) => Promise<T>,
): { readonly current: SceneResult<T> } {
  let result = $state<SceneResult<T>>({ status: 'waiting' });
  let generation = 0;

  $effect(() => {
    const obs = pageObserver().observer;
    // 只取数值字段，避免把响应式代理传进 postMessage
    const plain = obs ? { lat: obs.lat, lon: obs.lon, height: obs.height } : null;
    if (engineState.status !== 'ready') {
      result = { status: 'waiting' };
      return;
    }
    const gen = ++generation;
    result = { status: 'computing' };
    const t0 = performance.now();
    getEngine()
      .then((e) => compute(e, plain, SCENE_STEP_S))
      .then((scene) => {
        if (gen === generation) result = { status: 'ok', scene, ms: Math.round(performance.now() - t0) };
      })
      .catch((err: unknown) => {
        if (gen !== generation) return;
        const message = err instanceof Error ? err.message : String(err);
        result = message.includes('未找到') ? { status: 'notFound' } : { status: 'error', message };
      });
  });

  return {
    get current() {
      return result;
    },
  };
}
