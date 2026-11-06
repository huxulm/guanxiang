import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/app_localizations.dart';
import 'licenses.dart';
import 'settings.dart';

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 设置页：观测位置（GPS 自动 / 手动）、关于与许可。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final Settings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String? _manualError;

  @override
  void initState() {
    super.initState();
    _fillManual();
  }

  /// 把设置里的手动位置填进输入框（经纬度保留 6 位小数，约 0.1 米）。
  void _fillManual() {
    final m = widget.settings.manual;
    _latCtrl.text = formatNumber(m.lat, 6);
    _lonCtrl.text = formatNumber(m.lon, 6);
    _heightCtrl.text = formatNumber(m.height, 1);
    _manualError = null;
  }

  Future<void> _setMode(LocationMode m) async {
    // 切到手动时用最新的手动位置（可能刚被 GPS 定位更新过）
    if (m == LocationMode.manual) setState(_fillManual);
    await widget.settings.setMode(m);
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  /// 手动位置：输入有效时立即保存
  void _manualChanged(AppLocalizations l) {
    final p = Place(
      double.tryParse(_latCtrl.text.trim()) ?? double.nan,
      double.tryParse(_lonCtrl.text.trim()) ?? double.nan,
      double.tryParse(_heightCtrl.text.trim()) ?? double.nan,
    );
    if (p.isValid) {
      widget.settings.setManual(p);
      setState(() => _manualError = null);
    } else {
      setState(() => _manualError = l.invalidObserver);
    }
  }

  Future<void> _locate() async {
    try {
      await widget.settings.locate();
    } on LocationException {
      // 错误显示在页面上（settings.gpsError）
    }
  }

  Widget _numberField(
    AppLocalizations l,
    TextEditingController c,
    String label, {
    double width = 120,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) => _manualChanged(l),
      ),
    );
  }

  Widget _gpsSection(AppLocalizations l, ThemeData theme) {
    final s = widget.settings;
    final fix = s.gpsFix;
    final err = s.gpsError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fix == null
              ? l.gpsNoFix
              : '${fix.describe()}\n${l.gpsFixAt(_hm(s.gpsTime!))}',
        ),
        if (err != null) ...[
          const SizedBox(height: 4),
          Text(
            err.describe(l),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: s.locating ? null : _locate,
              icon: s.locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(s.locating ? l.locating : l.locateNow),
            ),
            if (err?.error == LocationError.deniedForever)
              OutlinedButton(
                onPressed: Geolocator.openAppSettings,
                child: Text(l.openSystemSettings),
              ),
            if (err?.error == LocationError.serviceOff)
              OutlinedButton(
                onPressed: Geolocator.openLocationSettings,
                child: Text(l.openSystemSettings),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) {
            final s = widget.settings;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l.locationSection, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<LocationMode>(
                  segments: [
                    ButtonSegment(
                      value: LocationMode.gps,
                      icon: const Icon(Icons.gps_fixed),
                      label: Text(l.locationGps),
                    ),
                    ButtonSegment(
                      value: LocationMode.manual,
                      icon: const Icon(Icons.edit_location_alt),
                      label: Text(l.locationManual),
                    ),
                  ],
                  selected: {s.mode},
                  onSelectionChanged: (v) => _setMode(v.single),
                ),
                const SizedBox(height: 12),
                if (s.mode == LocationMode.gps)
                  _gpsSection(l, theme)
                else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _numberField(l, _latCtrl, l.latitude, width: 110),
                      _numberField(l, _lonCtrl, l.longitude),
                      _numberField(l, _heightCtrl, l.height, width: 90),
                    ],
                  ),
                  if (_manualError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _manualError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                Text(l.locationPrivacy, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: Text(l.aboutTooltip),
                  subtitle: Text('${l.appTitle} $appVersion'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAbout(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 数字转文字：最多保留 [digits] 位小数，去掉末尾的 0。
String formatNumber(double v, int digits) {
  var t = v.toStringAsFixed(digits);
  if (t.contains('.')) {
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return t == '-0' ? '0' : t;
}

/// 搜索页上的一行位置摘要，点击进入设置页。
class LocationSummary extends StatelessWidget {
  const LocationSummary({
    super.key,
    required this.settings,
    this.enabled = true,
  });

  final Settings settings;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final String text;
        if (settings.mode == LocationMode.manual) {
          text = '${l.locationManual} · ${settings.manual.describe()}';
        } else if (settings.locating) {
          text = '${l.locationGps} · ${l.locating}';
        } else {
          final fix = settings.gpsFix;
          text = fix == null
              ? '${l.locationGps} · ${l.gpsLocateOnSearch}'
              : '${l.locationGps} · ${fix.describe()} '
                    '(${_hm(settings.gpsTime!)})';
        }
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            settings.mode == LocationMode.gps
                ? Icons.gps_fixed
                : Icons.edit_location_alt,
          ),
          title: Text(l.observerLocation),
          subtitle: Text(text),
          trailing: const Icon(Icons.settings_outlined),
          enabled: enabled,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SettingsPage(settings: settings)),
          ),
        );
      },
    );
  }
}
