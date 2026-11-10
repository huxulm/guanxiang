<script lang="ts">
  // 随时间变化的曲线（食分、高度等），竖线标出当前时刻和各接触时刻。
  // 按容器实际宽度画（像素坐标），文字不会被拉伸。
  import { fmtTime } from '../../lib/format';

  type Series = { points: [number, number][]; color: string; label: string; dashed?: boolean };
  let {
    series,
    t,
    tMin,
    tMax,
    yMin,
    yMax,
    yTicks,
    yFormat,
    base,
    marks = [],
    zeroLine = false,
    height = 140,
  }: {
    series: Series[];
    t: number;
    tMin: number;
    tMax: number;
    yMin: number;
    yMax: number;
    yTicks: number[];
    yFormat: (v: number) => string;
    base: Date;
    marks?: { code: string; t: number }[];
    /** 画 y = 0 的参考线（如地平线） */
    zeroLine?: boolean;
    height?: number;
  } = $props();

  let width = $state(600);
  const pad = { l: 40, r: 8, t: 8, b: 20 };
  const x = (v: number) => pad.l + ((v - tMin) / (tMax - tMin || 1)) * (width - pad.l - pad.r);
  const y = (v: number) => pad.t + (1 - (v - yMin) / (yMax - yMin || 1)) * (height - pad.t - pad.b);

  function path(points: [number, number][]): string {
    let d = '';
    let pen = false;
    for (const [tv, v] of points) {
      if (tv < tMin || tv > tMax || !Number.isFinite(v)) {
        pen = false;
        continue;
      }
      const yy = y(Math.min(yMax, Math.max(yMin, v)));
      d += `${pen ? 'L' : 'M'}${x(tv).toFixed(1)},${yy.toFixed(1)}`;
      pen = true;
    }
    return d;
  }

  /** 横轴刻度：大约每 100 像素一个，取整到 5/10/15/30/60/120 分钟 */
  const xTicks = $derived.by(() => {
    const span = tMax - tMin;
    const want = Math.max(2, Math.floor((width - pad.l - pad.r) / 100));
    const steps = [300, 600, 900, 1800, 3600, 7200];
    const step = steps.find((s) => span / s <= want) ?? 7200;
    const t0 = base.getTime() / 1000;
    const out: number[] = [];
    for (let a = Math.ceil((t0 + tMin) / step) * step; a <= t0 + tMax; a += step) out.push(a - t0);
    return out;
  });
</script>

<div bind:clientWidth={width} class="w-full">
  <svg {width} {height} class="block" role="img" aria-label={series.map((s) => s.label).join('、')}>
    {#each yTicks as v (v)}
      <line x1={pad.l} x2={width - pad.r} y1={y(v)} y2={y(v)} stroke="var(--gx-outline-variant)" stroke-width="1" />
      <text x={pad.l - 6} y={y(v)} font-size="10" text-anchor="end" dominant-baseline="middle" fill="var(--gx-on-surface-variant)" class="num">{yFormat(v)}</text>
    {/each}
    {#if zeroLine}
      <line x1={pad.l} x2={width - pad.r} y1={y(0)} y2={y(0)} stroke="var(--gx-on-surface-variant)" stroke-width="1" stroke-dasharray="3 3" />
    {/if}
    {#each xTicks as v (v)}
      <text x={x(v)} y={height - 4} font-size="10" text-anchor="middle" fill="var(--gx-on-surface-variant)" class="num">{fmtTime(new Date(base.getTime() + v * 1000), false)}</text>
    {/each}
    {#each marks.filter((m) => m.t >= tMin && m.t <= tMax) as m (m.code)}
      <line x1={x(m.t)} x2={x(m.t)} y1={pad.t} y2={height - pad.b} stroke="var(--gx-outline)" stroke-width="1" />
    {/each}
    {#each series as s (s.label)}
      <path d={path(s.points)} fill="none" stroke={s.color} stroke-width="1.8" stroke-dasharray={s.dashed ? '4 3' : undefined} />
    {/each}
    <line x1={x(t)} x2={x(t)} y1={pad.t} y2={height - pad.b} stroke="var(--gx-primary)" stroke-width="1.5" />
  </svg>
  <div class="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
    {#each series as s (s.label)}
      <span class="flex items-center gap-1.5">
        <svg width="18" height="6" aria-hidden="true"><line x1="0" x2="18" y1="3" y2="3" stroke={s.color} stroke-width="2" stroke-dasharray={s.dashed ? '4 3' : undefined} /></svg>
        {s.label}
      </span>
    {/each}
  </div>
</div>
