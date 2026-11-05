import 'package:flutter/widgets.dart';

import 'rust/api/guanxiang.dart';

/// 当前界面语言对应的 Rust 输出语言：中文界面用中文，其他一律英文。
Lang rustLang(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh' ? Lang.zh : Lang.en;
