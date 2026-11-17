// 纯前端动画渲染与视频录制导出引擎（支持 1080p 9:16 竖屏演示、1:1 日面特写及 2:1 地图投影）
import { calcAzimuth } from '../azimuth';
import { fmtNum } from '../format';
import type { Rings } from './land';
import type { DiskView, Observer, SolarScene, SolarState } from '../types';

export type VideoFormat = 'mp4' | 'webm';

export function getSupportedVideoMime(): { mimeType: string; format: VideoFormat } {
  if (typeof MediaRecorder === 'undefined') {
    return { mimeType: '', format: 'webm' };
  }
  const candidates: { mime: string; format: VideoFormat }[] = [
    { mime: 'video/mp4;codecs=avc1.42E01E,mp4a.40.2', format: 'mp4' },
    { mime: 'video/mp4', format: 'mp4' },
    { mime: 'video/webm;codecs=vp9', format: 'webm' },
    { mime: 'video/webm;codecs=vp8', format: 'webm' },
    { mime: 'video/webm', format: 'webm' },
  ];
  for (const c of candidates) {
    if (MediaRecorder.isTypeSupported(c.mime)) {
      return { mimeType: c.mime, format: c.format };
    }
  }
  return { mimeType: '', format: 'webm' };
}

/** 绘制日面特写（站心天顶朝上，含临边昏暗、月球剪影、全食日冕与地平线） */
export function drawSunDisk(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  radius: number,
  v: DiskView,
  total: boolean,
  lang: 'zh' | 'en' = 'zh',
): void {
  const isZh = lang === 'zh';
  const R = v.sun_r_deg;
  const HALF = 2.6; // 视野半宽（以太阳半径为单位）
  const scale = radius / HALF;

  const mx = (-v.x_deg / R) * scale;
  const my = (-v.y_deg / R) * scale;
  const mr = (v.moon_r_deg / R) * scale;
  const qRad = (v.zenith_angle_deg * Math.PI) / 180;
  const horizonY = (v.sun_alt_deg / R) * scale;
  const isCorona = total && Math.hypot(v.x_deg, v.y_deg) + v.sun_r_deg <= v.moon_r_deg;

  ctx.save();
  ctx.beginPath();
  ctx.rect(cx - radius, cy - radius, radius * 2, radius * 2);
  ctx.clip();

  // 背景天空
  ctx.fillStyle = '#05070c';
  ctx.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);

  // 天顶朝上旋转组
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(qRad);

  // 全食日冕
  if (isCorona) {
    const coronaGrad = ctx.createRadialGradient(0, 0, scale * 0.9, 0, 0, scale * 2.4);
    coronaGrad.addColorStop(0, 'rgba(233, 228, 214, 0.95)');
    coronaGrad.addColorStop(0.35, 'rgba(255, 183, 77, 0.45)');
    coronaGrad.addColorStop(0.7, 'rgba(233, 228, 214, 0.15)');
    coronaGrad.addColorStop(1, 'rgba(233, 228, 214, 0)');
    ctx.fillStyle = coronaGrad;
    ctx.beginPath();
    ctx.arc(0, 0, scale * 2.4, 0, Math.PI * 2);
    ctx.fill();
  }

  // 太阳金轮（临边昏暗）
  const sunGrad = ctx.createRadialGradient(0, 0, 0, 0, 0, scale);
  sunGrad.addColorStop(0, '#ffe4a0');
  sunGrad.addColorStop(0.7, '#ffb74d');
  sunGrad.addColorStop(1, '#b26a00');
  ctx.fillStyle = sunGrad;
  ctx.beginPath();
  ctx.arc(0, 0, scale, 0, Math.PI * 2);
  ctx.fill();

  // 月球暗轮
  ctx.fillStyle = '#020305';
  ctx.beginPath();
  ctx.arc(mx, my, mr, 0, Math.PI * 2);
  ctx.fill();

  // 天球北极方向指示
  ctx.save();
  ctx.translate(0, -radius + 24);
  ctx.rotate(-qRad);
  ctx.fillStyle = '#a6b0c2';
  ctx.font = '12px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(isZh ? '北' : 'N', 0, 0);
  ctx.restore();

  ctx.restore(); // 结束旋转组

  // 地平面（带食日出、日落）
  if (horizonY < radius) {
    const topY = Math.max(cy + horizonY, cy - radius);
    const bottomH = cy + radius - topY;
    if (bottomH > 0) {
      ctx.fillStyle = 'rgba(24, 32, 46, 0.94)';
      ctx.fillRect(cx - radius, topY, radius * 2, bottomH);
      ctx.strokeStyle = '#a6b0c2';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(cx - radius, topY);
      ctx.lineTo(cx + radius, topY);
      ctx.stroke();

      if (horizonY > -radius + 20) {
        ctx.fillStyle = '#a6b0c2';
        ctx.font = '12px system-ui, sans-serif';
        ctx.textAlign = 'right';
        ctx.fillText(isZh ? '地平线' : 'Horizon', cx + radius - 10, topY - 6);
      }
    }
  }

  // 天顶指示
  ctx.fillStyle = '#a6b0c2';
  ctx.font = '12px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillText(isZh ? '↑ 天顶' : '↑ Zenith', cx, cy - radius + 8);

  ctx.restore();
}

/** 绘制等距圆柱世界地图与阴影落区 */
export function drawMapView(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  scene: SolarScene,
  s: SolarState,
  land: Rings | null,
  observer: Observer | null,
): void {
  ctx.save();
  ctx.beginPath();
  ctx.rect(x, y, w, h);
  ctx.clip();

  // 海洋底色
  ctx.fillStyle = '#131924';
  ctx.fillRect(x, y, w, h);

  const toX = (lon: number) => x + ((lon + 180) / 360) * w;
  const toY = (lat: number) => y + ((90 - lat) / 180) * h;

  // 绘制陆地
  if (land) {
    ctx.fillStyle = '#242e40';
    ctx.strokeStyle = '#263246';
    ctx.lineWidth = 0.5;
    for (const ring of land) {
      ctx.beginPath();
      for (let i = 0; i + 1 < ring.length; i += 2) {
        const px = toX(ring[i]);
        const py = toY(ring[i + 1]);
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
    }
  }

  // 中心食带
  if (scene.central_line.length > 0) {
    ctx.strokeStyle = '#ffb74d';
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    let prevLon: number | null = null;
    for (const p of scene.central_line) {
      const px = toX(p.lon_deg);
      const py = toY(p.lat_deg);
      if (prevLon === null || Math.abs(p.lon_deg - prevLon) > 180) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
      prevLon = p.lon_deg;
    }
    ctx.stroke();
  }

  // 阴影地面中心点
  if (s.shadow_center) {
    const sx = toX(s.shadow_center.lon_deg);
    const sy = toY(s.shadow_center.lat_deg);
    ctx.fillStyle = '#05070c';
    ctx.strokeStyle = '#ffb74d';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(sx, sy, 4.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  }

  // 太阳直射点 ☀
  const sunX = toX(s.sub_solar.lon_deg);
  const sunY = toY(s.sub_solar.lat_deg);
  ctx.fillStyle = '#ffb74d';
  ctx.font = '14px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('☀', sunX, sunY);

  // 观测地标记
  if (observer) {
    const ox = toX(observer.lon);
    const oy = toY(observer.lat);
    ctx.strokeStyle = '#569aff';
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.arc(ox, oy, 5, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = '#569aff';
    ctx.beginPath();
    ctx.arc(ox, oy, 2, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

/**
 * 绘制完整的 9:16 竖屏天象演示帧（1080 × 1920 高清规格）
 */
export function renderVerticalFrame(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  opts: {
    scene: SolarScene;
    s: SolarState;
    land: Rings | null;
    observer: Observer | null;
    date: string;
    utcStr: string;
    phaseName: string;
    lang: 'zh' | 'en';
  },
): void {
  const { scene, s, land, observer, date, utcStr, phaseName, lang } = opts;
  const isZh = lang === 'zh';

  // 背景
  ctx.fillStyle = '#080b11';
  ctx.fillRect(0, 0, width, height);

  // 顶栏品牌与事件标题
  ctx.fillStyle = '#569aff';
  ctx.font = 'bold 26px system-ui, sans-serif';
  ctx.textAlign = 'left';
  ctx.fillText('观象 · GUANXIANG', 60, 90);

  ctx.fillStyle = '#a6b0c2';
  ctx.font = '22px system-ui, sans-serif';
  ctx.textAlign = 'right';
  ctx.fillText('app.guanx.huxulm.dev', width - 60, 90);

  // 分割线
  ctx.strokeStyle = '#263246';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(60, 115);
  ctx.lineTo(width - 60, 115);
  ctx.stroke();

  // 主标题
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 44px system-ui, sans-serif';
  ctx.textAlign = 'left';
  ctx.fillText(`${date}  ${isZh ? scene.kind_zh : scene.kind}`, 60, 175);

  // 观测地胶囊
  if (observer) {
    ctx.fillStyle = '#1b2332';
    ctx.beginPath();
    ctx.roundRect(60, 205, width - 120, 52, 26);
    ctx.fill();
    ctx.strokeStyle = '#263246';
    ctx.stroke();

    ctx.fillStyle = '#e2e6ee';
    ctx.font = '22px system-ui, sans-serif';
    ctx.fillText(`📍 ${observer.label ?? `${observer.lat.toFixed(2)}°, ${observer.lon.toFixed(2)}°`}`, 85, 238);

    ctx.fillStyle = '#ffb74d';
    ctx.font = 'bold 22px system-ui, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(phaseName, width - 85, 238);
    ctx.textAlign = 'left';
  }

  // 中心区：日面特写视界 (半径 320 像素)
  const sunCenterY = 640;
  if (s.local) {
    drawSunDisk(ctx, width / 2, sunCenterY, 320, s.local, scene.kind === 'total', lang);
  } else {
    // 无站心数据时绘制概况示意
    ctx.fillStyle = '#131924';
    ctx.beginPath();
    ctx.roundRect(width / 2 - 320, sunCenterY - 320, 640, 640, 28);
    ctx.fill();
    ctx.fillStyle = '#ffb74d';
    ctx.font = '28px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(isZh ? '全球天象视界' : 'Global Eclipse View', width / 2, sunCenterY);
  }

  // 实时数据展示条 (Y: 1020..1160)
  const statsY = 1040;
  ctx.fillStyle = '#131924';
  ctx.beginPath();
  ctx.roundRect(60, statsY, width - 120, 150, 24);
  ctx.fill();
  ctx.strokeStyle = '#263246';
  ctx.stroke();

  // 时刻与食相
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 46px monospace';
  ctx.fillText(utcStr.slice(11, 19) || '12:00:00', 95, statsY + 65);

  ctx.fillStyle = '#a6b0c2';
  ctx.font = '20px system-ui, sans-serif';
  ctx.fillText(isZh ? 'UTC 协调世界时' : 'UTC Time', 95, statsY + 115);

  if (s.local && observer) {
    const az = calcAzimuth(observer.lat, observer.lon, s.sub_solar.lat_deg, s.sub_solar.lon_deg);
    // 右侧三列参数：食分、高度、方位
    const colX1 = 440;
    const colX2 = 660;
    const colX3 = 840;

    // 食分
    ctx.fillStyle = '#a6b0c2';
    ctx.font = '18px system-ui, sans-serif';
    ctx.fillText(isZh ? '食分' : 'Mag', colX1, statsY + 50);
    ctx.fillStyle = '#ffb74d';
    ctx.font = 'bold 30px monospace';
    const mag = Math.max(0, (s.local.sun_r_deg + s.local.moon_r_deg - Math.hypot(s.local.x_deg, s.local.y_deg)) / (2 * s.local.sun_r_deg));
    ctx.fillText(fmtNum(mag, 3), colX1, statsY + 105);

    // 太阳仰角
    ctx.fillStyle = '#a6b0c2';
    ctx.font = '18px system-ui, sans-serif';
    ctx.fillText(isZh ? '太阳高度' : 'Alt', colX2, statsY + 50);
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 30px monospace';
    ctx.fillText(`${fmtNum(s.local.sun_alt_deg, 1)}°`, colX2, statsY + 105);

    // 方位角
    ctx.fillStyle = '#a6b0c2';
    ctx.font = '18px system-ui, sans-serif';
    ctx.fillText(isZh ? '方位角' : 'Az', colX3, statsY + 50);
    ctx.fillStyle = '#569aff';
    ctx.font = 'bold 24px monospace';
    ctx.fillText(`${az.azDeg.toFixed(0)}°`, colX3, statsY + 95);
    ctx.font = '18px system-ui, sans-serif';
    ctx.fillText(isZh ? az.compassZh : az.compassEn, colX3, statsY + 125);
  }

  // 底部：世界地图阴影追踪视界 (Y: 1220..1720, 高度 480)
  const mapY = 1230;
  const mapH = 480;
  drawMapView(ctx, 60, mapY, width - 120, mapH, scene, s, land, observer);

  // 安全声明与底栏说明 (Y: 1740..1860)
  ctx.fillStyle = '#ff6b5e';
  ctx.font = 'bold 20px system-ui, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(
    isZh ? '⚠️ 观测太阳必须使用符合 ISO 12312-2 标准的减光膜，切勿直接目视！' : '⚠️ Always use ISO 12312-2 solar filter to observe the Sun!',
    width / 2,
    1770,
  );

  ctx.fillStyle = '#a6b0c2';
  ctx.font = '19px system-ui, sans-serif';
  ctx.fillText(isZh ? '观象 (Guanxiang) · 跨平台天文事件搜索与科学可视化' : 'Guanxiang · Astronomical Event Search & Visualizer', width / 2, 1835);
}
