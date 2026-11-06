import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Rust 依赖的许可证全文，由 `tools/licenses/gen_rust_notices.py` 生成。
const rustNoticesAsset = 'assets/licenses/rust.txt';

/// 算法和数据来源致谢，显示在“关于”的许可页里。
const acknowledgements = '''
观象使用了以下算法和数据，谨此致谢。

星历：NASA 喷气推进实验室（JPL）DE440 行星和月球历表（Park et al. 2021, AJ 161, 105），由 JPL/NAIF 发布。应用内置的是 de440s 裁剪到 1900–2100 年的版本，范围内数据未作改动。

基本天文学算法：时间尺度、岁差章动、坐标变换等采用国际天文学联合会 SOFA（Standards of Fundamental Astronomy）的算法，通过 sofars（SOFA 的 Rust 实现，MIT 许可）调用。观象不是 SOFA 官方软件，未经 IAU SOFA 理事会认可；SOFA 的原始软件见 http://www.iausofa.org 。

ΔT：1800 年至今采用美国海军天文台（USNO）和国际地球自转服务（IERS）公布的数值，之后为外推，远期结果的时刻不确定度随之增大。

亮星星表：Hipparcos 星表（ESA 1997, ESA SP-1200），经 NASA HEASARC 获取。

人造卫星：轨道根数来自 CelesTrak（T. S. Kelso）提供的 GP 数据，运行时下载；轨道预报采用 SGP4（Vallado et al. 2006），通过 sgp4 crate（MIT 许可）调用。

地图：底图 © OpenStreetMap 贡献者，数据以 ODbL 许可发布。

验证：日月食结果与 NASA 五千年日月食典（Espenak & Meeus）比对，视位置与 Skyfield 比对；这些对照数据不随应用分发。
''';

/// 致谢的英文版。
const acknowledgementsEn = '''
Guanxiang relies on the following algorithms and data.

Ephemeris: JPL DE440 planetary and lunar ephemeris (Park et al. 2021, AJ 161, 105), published by NASA JPL/NAIF. The app ships de440s cut to the years 1900–2100; the data inside that range are unchanged.

Fundamental astronomy: time scales, precession-nutation and coordinate transformations follow the IAU Standards of Fundamental Astronomy (SOFA), used through sofars (a Rust implementation of SOFA, MIT licence). Guanxiang is not SOFA software and is not endorsed by the IAU SOFA Board; the original SOFA software is at http://www.iausofa.org .

ΔT: values published by the US Naval Observatory (USNO) and the IERS from 1800 to the present, extrapolated afterwards, so far-future times become less certain.

Bright stars: the Hipparcos Catalogue (ESA 1997, ESA SP-1200), obtained from NASA HEASARC.

Artificial satellites: orbital elements are CelesTrak GP data (T. S. Kelso), downloaded at run time; orbits are propagated with SGP4 (Vallado et al. 2006) through the sgp4 crate (MIT licence).

Maps: base map © OpenStreetMap contributors, data available under the ODbL.

Validation: eclipses were checked against the NASA Five Millennium Canon (Espenak & Meeus) and apparent positions against Skyfield; these reference data are not distributed with the app.
''';

/// `rust.txt` 中的一条：若干 crate 共用的一份许可证文本。
class NoticeBlock {
  const NoticeBlock(this.packages, this.text);

  final List<String> packages;
  final String text;
}

/// 解析 `rust.txt`：每条以 `@@ 包1, 包2` 开头，直到下一个 `@@` 为止是许可证全文。
List<NoticeBlock> parseNotices(String text) {
  final out = <NoticeBlock>[];
  List<String>? packages;
  final buf = StringBuffer();
  void flush() {
    final p = packages;
    if (p != null) {
      out.add(NoticeBlock(p, buf.toString().trim()));
    }
    buf.clear();
  }

  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('@@ ')) {
      flush();
      packages = line.substring(3).split(', ').map((s) => s.trim()).toList();
    } else {
      buf.writeln(line);
    }
  }
  flush();
  return out;
}

/// 在 runApp 之前调用一次。许可证文本在打开许可页时才读取。
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['观象：算法与数据来源'], acknowledgements);
    yield const LicenseEntryWithLineBreaks([
      'Guanxiang: algorithms and data',
    ], acknowledgementsEn);
    final text = await rootBundle.loadString(rustNoticesAsset);
    for (final b in parseNotices(text)) {
      yield LicenseEntryWithLineBreaks(b.packages, b.text);
    }
  });
}

/// 打开“关于 / 许可”页。
void showAbout(BuildContext context) {
  final l = AppLocalizations.of(context);
  showLicensePage(
    context: context,
    applicationName: l.appTitle,
    applicationVersion: '0.1.1',
    applicationLegalese: l.legalese,
  );
}
