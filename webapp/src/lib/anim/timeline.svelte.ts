// 动画时间轴：时间 t 为相对食甚的 TT 秒数（与场景序列的 t_rel_s 一致）。
// 播放时按 requestAnimationFrame 推进，倍速表示“每秒现实时间走过多少秒天文时间”。

export class Timeline {
  min = $state(0);
  max = $state(0);
  t = $state(0);
  playing = $state(false);
  /** 倍速：天文秒 / 现实秒 */
  speed = $state(300);

  #raf = 0;
  #last = 0;

  constructor(min: number, max: number, t: number, speed: number) {
    this.setRange(min, max, t, speed);
  }

  /** 改变范围（如“本地/全程”切换），t 限制在范围内 */
  setRange(min: number, max: number, t = this.t, speed = this.speed): void {
    this.min = min;
    this.max = max;
    this.speed = speed;
    this.seek(t);
  }

  seek(t: number): void {
    this.t = Math.min(this.max, Math.max(this.min, t));
  }

  play(): void {
    if (this.playing) return;
    if (this.t >= this.max) this.t = this.min; // 放完了从头开始
    this.playing = true;
    this.#last = performance.now();
    const step = (now: number) => {
      if (!this.playing) return;
      const dt = Math.min(0.1, (now - this.#last) / 1000); // 切走标签页回来时不跳太远
      this.#last = now;
      const next = this.t + dt * this.speed;
      if (next >= this.max) {
        this.t = this.max;
        this.playing = false;
        return;
      }
      this.t = next;
      this.#raf = requestAnimationFrame(step);
    };
    this.#raf = requestAnimationFrame(step);
  }

  pause(): void {
    this.playing = false;
    cancelAnimationFrame(this.#raf);
  }

  toggle(): void {
    if (this.playing) this.pause();
    else this.play();
  }

  /** 组件销毁时调用 */
  dispose(): void {
    this.pause();
  }
}

/** 让整个范围大约 30 秒放完的倍速，取整到好读的档位 */
export function defaultSpeed(span: number): number {
  const target = span / 30;
  const steps = [10, 30, 60, 120, 300, 600, 1200, 3000];
  return steps.reduce((best, s) => (Math.abs(Math.log(s / target)) < Math.abs(Math.log(best / target)) ? s : best));
}
