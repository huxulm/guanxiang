import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_style.dart';
import 'locale.dart';
import 'lunar_eclipse_detail.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'solar_eclipse_detail.dart';
import 'theme.dart';
import 'time_format.dart';

/// 分享图的逻辑尺寸，按 3 倍导出：月食固定 4:5（1080 × 1350）。日食多一张全宽的食带地图，
/// 宽度相同、高度按内容撑开（约 1080 × 1650～1800）：观测地、结论文字、英文文案折行时不会溢出。
const posterSize = Size(360, 450);

/// 分享图的高度；null 表示按内容撑开（日食）。
double? posterHeightFor(Object detail) =>
    detail is SolarEclipseDetail ? null : posterSize.height;
const _posterPixelRatio = 3.0;

/// 官网地址（分享文字里写它，分享图右下角是它的二维码）
const posterSite = 'guanx.huxulm.dev';
const posterSiteUrl = 'https://$posterSite';

/// 能分享文件的平台：Android 和 Windows（Windows 10 1809 起）。Linux 只能保存。
bool get canShareFiles => Platform.isAndroid || Platform.isWindows;

/// 桌面上可以另存为图片。
bool get canSaveFiles =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// 经纬度取整到 1°：“40°N 116°E”。
String roundedPlace(double lat, double lon) {
  final ns = lat >= 0 ? 'N' : 'S';
  final ew = lon >= 0 ? 'E' : 'W';
  return '${lat.abs().round()}°$ns ${lon.abs().round()}°$ew';
}

/// 日月食分享页：预览分享图，可选是否显示观测地，然后分享或保存。
class EclipseSharePage extends StatefulWidget {
  const EclipseSharePage({
    super.key,
    required this.engine,
    required this.event,
    this.settings,
  });

  final Engine engine;
  final EventItem event;
  final Settings? settings;

  @override
  State<EclipseSharePage> createState() => _EclipseSharePageState();
}

class _EclipseSharePageState extends State<EclipseSharePage> {
  final _boundary = GlobalKey();
  Future<Object>? _future;
  bool _showPlace = false;
  bool _busy = false;
  Place? _place;

  bool get _lunar => widget.event.kind == EventKind.lunarEclipse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return;
    _place = widget.settings?.knownPlace;
    final site = _place == null
        ? null
        : Site(
            latitudeDeg: _place!.lat,
            longitudeDeg: _place!.lon,
            heightM: _place!.height,
          );
    final lang = rustLang(context);
    _future = _lunar
        ? lunarEclipseDetail(
            engine: widget.engine,
            ttJd: widget.event.ttJd,
            site: site,
            lang: lang,
          )
        : solarEclipseDetail(
            engine: widget.engine,
            ttJd: widget.event.ttJd,
            site: site,
            lang: lang,
          );
  }

  Future<List<int>> _png() async {
    final ro =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: _posterPixelRatio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  String get _fileName {
    final t = parseUtc(widget.event.utc)?.toLocal();
    final day = t == null
        ? 'eclipse'
        : '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
    return 'guanxiang-$day-${_lunar ? 'lunar' : 'solar'}.png';
  }

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.shareFailed(describeError(e, l)))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() async {
    final bytes = await _png();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: '${widget.event.title} · $posterSite',
      ),
    );
  });

  Future<void> _save() => _run(() async {
    final l = AppLocalizations.of(context);
    final bytes = await _png();
    final loc = await getSaveLocation(
      suggestedName: _fileName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (loc == null) return;
    await File(loc.path).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${l.shareSaved}：${loc.path}')));
    }
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.shareImage)),
      body: FutureBuilder<Object>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  describeError(snap.error!, l),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            );
          }
          final d = snap.data;
          if (d == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final poster = RepaintBoundary(
            key: _boundary,
            child: SizedBox(
              width: posterSize.width,
              height: posterHeightFor(d),
              child: EclipsePoster(
                event: widget.event,
                detail: d,
                place: _showPlace ? _place : null,
              ),
            ),
          );
          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: FittedBox(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: poster,
                        ),
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      if (_place != null)
                        SwitchListTile(
                          title: Text(l.shareShowLocation),
                          subtitle: Text(l.shareShowLocationHint),
                          value: _showPlace,
                          onChanged: (v) => setState(() => _showPlace = v),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Row(
                          children: [
                            if (canSaveFiles)
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.save_alt),
                                  label: Text(l.shareSave),
                                  onPressed: _busy ? null : _save,
                                ),
                              ),
                            if (canSaveFiles && canShareFiles)
                              const SizedBox(width: 12),
                            if (canShareFiles)
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.share),
                                  label: Text(l.shareButton),
                                  onPressed: _busy ? null : _share,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 分享图本身（逻辑尺寸 [posterSize]）。始终用深空主题，和应用当前的主题无关。
class EclipsePoster extends StatelessWidget {
  const EclipsePoster({
    super.key,
    required this.event,
    required this.detail,
    this.place,
  });

  final EventItem event;

  /// [LunarEclipseDetail] 或 [SolarEclipseDetail]
  final Object detail;

  /// 显示在图上的观测地（null 时不显示）
  final Place? place;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Theme(
      data: AstroTheme.deepSpaceTheme,
      child: Builder(
        builder: (context) => _PosterBody(
          event: event,
          detail: detail,
          place: place,
          localeTag: locale.toLanguageTag(),
        ),
      ),
    );
  }
}

/// 分享图上的一项数字。
typedef _Stat = (String label, String value);

class _PosterBody extends StatelessWidget {
  const _PosterBody({
    required this.event,
    required this.detail,
    required this.place,
    required this.localeTag,
  });

  final EventItem event;
  final Object detail;
  final Place? place;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final accents = AstroAccents.of(context);
    final t = parseUtc(event.utc)?.toLocal();
    final left = t == null ? null : countdown(l, t.toUtc());
    final date = t == null
        ? event.utc
        : '${DateFormat.yMMMEd(localeTag).format(t)}  '
              '${localClock(t, t, seconds: false)} ${zoneLabel(t)}';

    final (hero, stats, verdict, saros, solar) = switch (detail) {
      final LunarEclipseDetail d => _lunar(context, l, d),
      final SolarEclipseDetail d => _solar(context, l, d),
      _ => (const SizedBox.shrink(), <_Stat>[], null, '', false),
    };
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final p = place;
    final solarDetail = detail is SolarEclipseDetail
        ? detail as SolarEclipseDetail
        : null;

    final pill = left == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              left,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    Widget brand({bool withPill = true}) => Row(
      children: [
        KindBadge(kind: event.kind, size: 26),
        const SizedBox(width: 8),
        Text('观象 · Guanxiang', style: muted),
        const Spacer(),
        if (withPill) ?pill,
      ],
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          date,
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
        ),
      ],
    );
    final locationLine = p == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [
                      l.posterSeenFrom(roundedPlace(p.lat, p.lon)),
                      ?verdict,
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
    final statsRow = Row(
      children: [
        for (final (i, s) in stats.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _StatTile(stat: s, accent: accents.eclipse),
          ),
        ],
      ],
    );
    // 页脚：左边是安全提示和沙罗序列，右边是官网二维码
    final footer = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (solar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    l.posterSolarSafety,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.error,
                    ),
                  ),
                ),
              if (saros.isNotEmpty)
                Text(
                  l.lunarSaros(saros),
                  style: muted,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(l.posterScan, style: muted, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const _SiteQr(size: 76),
      ],
    );

    final Widget content;
    if (solarDetail == null) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            brand(),
            const SizedBox(height: 14),
            titleBlock,
            Expanded(
              child: Center(
                child: SizedBox.square(dimension: 170, child: hero),
              ),
            ),
            ?locationLine,
            statsRow,
            const SizedBox(height: 12),
            footer,
          ],
        ),
      );
    } else {
      // 日食：太阳面缩小放在标题右侧，下面是左右贴边的食带地图；高度按内容撑开
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brand(withPill: false),
                      const SizedBox(height: 14),
                      titleBlock,
                      if (pill != null) ...[const SizedBox(height: 8), pill],
                    ],
                  ),
                ),
                SizedBox.square(dimension: 112, child: hero),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SolarPathMap(detail: solarDetail, place: p),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?locationLine,
                const SizedBox(height: 4),
                statsRow,
                const SizedBox(height: 14),
                footer,
              ],
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(cs.primary.withValues(alpha: 0.10), cs.surface),
            Color.alphaBlend(Colors.black.withValues(alpha: 0.45), cs.surface),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _StarsPainter(
          seed: (event.ttJd * 1000).round(),
          color: cs.onSurface,
        ),
        child: content,
      ),
    );
  }

  /// 月食：食甚时的月面、时长、食分、食甚时刻。
  (Widget, List<_Stat>, String?, String, bool) _lunar(
    BuildContext context,
    AppLocalizations l,
    LunarEclipseDetail d,
  ) {
    final accents = AstroAccents.of(context);
    final max = d.diagram.marks.isEmpty ? null : d.diagram.marks.last;
    final hero = Stack(
      fit: StackFit.expand,
      children: [
        // 月面周围的光晕
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                accents.bloodMoon.withValues(alpha: 0.45),
                accents.bloodMoon.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(28),
          child: MoonFace(
            diagram: d.diagram,
            position: max == null ? Offset.zero : Offset(max.x, max.y),
          ),
        ),
      ],
    );
    final (durLabel, dur) = d.totalMinutes != null
        ? (l.posterTotality, d.totalMinutes!)
        : d.partialMinutes != null
        ? (l.posterUmbral, d.partialMinutes!)
        : (l.posterPenumbral, d.penumbralMinutes);
    final stats = <_Stat>[
      (durLabel, formatDuration(l, dur)),
      ?_summaryStat(),
      if (_maxTime(d.phases.map((p) => (p.code, p.utc))) case final s?)
        (l.posterGreatest, s),
    ];
    final verdict = d.local == null
        ? null
        : visibilityText(l, d.local!.verdict);
    return (hero, stats, verdict, d.saros, false);
  }

  /// 日食：本地有食时画本地食甚时的太阳面，否则按全球类型画示意图。
  (Widget, List<_Stat>, String?, String, bool) _solar(
    BuildContext context,
    AppLocalizations l,
    SolarEclipseDetail d,
  ) {
    final v = d.local;
    final kind = v?.kind;
    SolarDiskPoint point;
    final List<_Stat> stats;
    if (v != null && kind != null && v.track.length >= 2) {
      final max = v.phases.where((p) => p.code == 'Max').firstOrNull;
      final sampler = SolarTrackSampler(v);
      point = sampler.at(
        (max == null ? null : parseUtc(max.utc)) ?? sampler.start,
      );
      // 分享图上统一天顶朝上的角度意义不大，摆正（北在上）更好看
      point = _withZenith(point, 0);
      final central = v.centralSeconds;
      stats = [
        if (central == null)
          (l.posterKind, solarKindText(l, kind))
        else
          (
            kind == LocalEclipseKind.annular
                ? l.posterAnnular
                : l.posterTotality,
            formatSeconds(l, central),
          ),
        (l.posterMagnitude, v.magnitude.toStringAsFixed(3)),
        (
          l.posterObscuration,
          '${(v.obscuration * 100).toStringAsFixed(v.obscuration > 0.999 ? 0 : 1)}%',
        ),
      ];
    } else {
      point = _globalSun(d);
      stats = [
        ?_summaryStat(),
        if (_maxTime([('Max', event.utc)]) case final s?) (l.posterGreatest, s),
      ];
    }
    final hero = SunFace(
      point: point,
      moon: Colors.black.withValues(alpha: 0.92),
    );
    final verdict = v == null ? null : solarVisibilityText(l, v.verdict);
    return (hero, stats, verdict, d.saros, true);
  }

  /// 摘要“本影食分 1.362”拆成一项数字。
  _Stat? _summaryStat() {
    final s = event.summary.trim();
    final i = s.lastIndexOf(' ');
    if (i <= 0) return null;
    return (s.substring(0, i), s.substring(i + 1));
  }

  /// 食甚的本地时刻（时:分）。
  String? _maxTime(Iterable<(String, String)> phases) {
    for (final (code, utc) in phases) {
      if (code != 'Max') continue;
      final t = parseUtc(utc)?.toLocal();
      if (t != null) return localClock(t, t, seconds: false);
    }
    return null;
  }

  SolarDiskPoint _withZenith(SolarDiskPoint p, double z) => SolarDiskPoint(
    seconds: p.seconds,
    xArcmin: p.xArcmin,
    yArcmin: p.yArcmin,
    sunRadiusArcmin: p.sunRadiusArcmin,
    moonRadiusArcmin: p.moonRadiusArcmin,
    obscuration: p.obscuration,
    sunAltitudeDeg: p.sunAltitudeDeg,
    zenithAngleDeg: z,
  );

  /// 没有本地情况时按全球类型画：全食、环食画在正中，偏食月面偏到一侧。
  SolarDiskPoint _globalSun(SolarEclipseDetail d) {
    final u = d.diagram.umbraRadius;
    final central = d.greatestPoint != null;
    final (dx, moonR, ob) = !central
        ? (9.0, 16.2, 0.6)
        : u < 0
        ? (0.0, 16.6, 1.0)
        : (0.0, 15.2, 0.9);
    return SolarDiskPoint(
      seconds: 0,
      xArcmin: dx,
      yArcmin: central ? 0 : -6,
      sunRadiusArcmin: 15.8,
      moonRadiusArcmin: moonR,
      obscuration: ob,
      sunAltitudeDeg: 45,
      zenithAngleDeg: 0,
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, required this.accent});

  final _Stat stat;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.$1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              stat.$2,
              style: theme.textTheme.titleMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 星空背景：按种子固定的随机星点，同一事件每次生成的图都一样。
class _StarsPainter extends CustomPainter {
  _StarsPainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    for (var i = 0; i < 90; i++) {
      final o = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      final r = 0.3 + rnd.nextDouble() * rnd.nextDouble() * 1.2;
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.15 + rnd.nextDouble() * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) =>
      old.seed != seed || old.color != color;
}

/// 官网二维码：浅色底、深色码点（颜色取自主题，对比度足够扫码）。
class _SiteQr extends StatelessWidget {
  const _SiteQr({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.onSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: QrImageView(
        data: posterSiteUrl,
        padding: EdgeInsets.zero,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: cs.surface),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: cs.surface,
        ),
        semanticsLabel: posterSiteUrl,
      ),
    );
  }
}
