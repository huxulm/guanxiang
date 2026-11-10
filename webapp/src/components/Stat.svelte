<script lang="ts">
  // 详情页里的一项数值：小标签 + 数值。
  let { label, value }: { label: string; value: string } = $props();
</script>

<div class="min-w-0">
  <dt class="label">{label}</dt>
  <dd class="num mt-0.5 text-base text-fg">{value}</dd>
</div>
