import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../l10n/app_localizations.dart';
import 'settings.dart';

/// 高德 Android Key。按包名 dev.huxulm.guanxiang 和签名证书 SHA1 绑定，别的应用拿去用不了。
const amapAndroidKey = '3527fb755dbe252bf8b1d342e0c443a7';

/// 本应用隐私政策（包含高德 SDK 的说明）与高德开放平台隐私权政策。
const appPrivacyUrl = 'https://guanx.huxulm.dev/privacy';
const amapPrivacyUrl = 'https://lbs.amap.com/pages/privacy/';

/// 高德地图只在 arm64 的 Android 上可用：高德原生库没有 x86_64 版本，模拟器和桌面用 OpenStreetMap。
bool get amapSupported =>
    Platform.isAndroid && Abi.current() == Abi.androidArm64;

/// 当前是否用高德地图：支持且用户已同意隐私说明。
bool useAmap(Settings s) => amapSupported && s.amapConsent == true;

bool _initialized = false;

/// 用户同意后初始化高德 SDK（Key 和合规声明）。在创建 AMapWidget 之前调用。
void ensureAmapInitialized(BuildContext context) {
  if (_initialized) return;
  AMapInitializer.init(
    context,
    apiKey: const AMapApiKey(androidKey: amapAndroidKey),
  );
  AMapInitializer.updatePrivacyAgree(
    const AMapPrivacyStatement(
      hasContains: true,
      hasShow: true,
      hasAgree: true,
    ),
  );
  _initialized = true;
}

/// 询问是否使用高德地图并保存选择。返回用户是否同意（关掉对话框算不同意）。
Future<bool> askAmapConsent(BuildContext context, Settings settings) async {
  final l = AppLocalizations.of(context);
  final agree = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(l.amapConsentTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.amapConsentBody),
            const SizedBox(height: 8),
            _LinkText(l.appPrivacyPolicy, appPrivacyUrl),
            _LinkText(l.amapPrivacyPolicy, amapPrivacyUrl),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.amapDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.amapAgree),
        ),
      ],
    ),
  );
  await settings.setAmapConsent(agree ?? false);
  return agree ?? false;
}

class _LinkText extends StatelessWidget {
  const _LinkText(this.text, this.url);

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}
