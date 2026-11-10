// 逐帧求值：时间轴的 t 变了就向 Worker 请求该时刻的状态。
// 同一时间只有一个请求在途；期间 t 又变了，只记住最新的，等上一个返回后再发（不会排起长队）。
// 只跟踪 t：观测地等其他参数变了时，由使用方重建组件（详情页按场景对象 {#key}）。

export function frameState<T>(
  getT: () => number,
  fetch: (t: number) => Promise<T>,
): { readonly current: T | null; readonly error: string } {
  let current = $state<T | null>(null);
  let error = $state('');
  let inFlight = false;
  let pending: number | null = null;

  function request(t: number): void {
    inFlight = true;
    fetch(t)
      .then((s) => {
        current = s;
        error = '';
      })
      .catch((e: unknown) => {
        error = e instanceof Error ? e.message : String(e);
      })
      .finally(() => {
        inFlight = false;
        if (pending !== null) {
          const next = pending;
          pending = null;
          request(next);
        }
      });
  }

  $effect(() => {
    const t = getT();
    if (inFlight) pending = t;
    else request(t);
  });

  return {
    get current() {
      return current;
    },
    get error() {
      return error;
    },
  };
}
