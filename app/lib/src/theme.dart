import 'package:flutter/material.dart';

/// 观象的三套外观，共用一个构建函数，各自只给一组色值（[_Palette]）：
/// 1. [AstroTheme.deepSpaceTheme]：深空暗夜，近黑底色加星空蓝；
/// 2. [AstroTheme.astroRedTheme]：夜间红光，户外观星用。只用暗红色、不用大块实心亮色，
///    避免破坏暗适应；
/// 3. [AstroTheme.lightTheme]：明亮浅色。
///
/// 界面代码不要写死颜色：通用颜色用 `colorScheme`，事件类型的强调色用 [AstroAccents]。
class AstroTheme {
  AstroTheme._();

  static ThemeData get deepSpaceTheme => _build(_deepSpace);
  static ThemeData get astroRedTheme => _build(_astroRed);
  static ThemeData get lightTheme => _build(_light);

  static const _deepSpace = _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0E14),
    surface: Color(0xFF131924),
    surfaceContainer: Color(0xFF1B2332),
    surfaceContainerHigh: Color(0xFF242E40),
    navBar: Color(0xFF0F141E),
    outline: Color(0xFF263246),
    outlineVariant: Color(0xFF1C2534),
    onSurface: Color(0xFFE2E6EE),
    onSurfaceVariant: Color(0xFFA6B0C2),
    navUnselected: Color(0xFF8E9CAD),
    primary: Color(0xFF569AFF),
    onPrimary: Color(0xFF00214D),
    primaryContainer: Color(0xFF1A3358),
    onPrimaryContainer: Color(0xFFD3E4FF),
    // 次要色与主色同为蓝色系：分段按钮、tonal 按钮、进度条底色都用它
    secondary: Color(0xFF9DB8E0),
    secondaryContainer: Color(0xFF1F3556),
    onSecondaryContainer: Color(0xFFD3E4FF),
    // 琥珀色只做点缀（标题图标）
    tertiary: Color(0xFFFFB74D),
    error: Color(0xFFFF6B5E),
    errorContainer: Color(0xFF4D120E),
    onErrorContainer: Color(0xFFFFDAD6),
    accents: AstroAccents(
      eclipse: Color(0xFFFFB74D),
      conjunction: Color(0xFF6EA8FF),
      transit: Color(0xFFFF8A65),
      satellite: Color(0xFF4DB6AC),
    ),
  );

  /// 红光：所有颜色都只有红色分量占主导，亮度压低；实心按钮用暗红底。
  static const _astroRed = _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF0A0101),
    surface: Color(0xFF140303),
    surfaceContainer: Color(0xFF1D0505),
    surfaceContainerHigh: Color(0xFF280707),
    navBar: Color(0xFF0F0202),
    outline: Color(0xFF3D0C0C),
    outlineVariant: Color(0xFF2A0707),
    onSurface: Color(0xFFD95050),
    onSurfaceVariant: Color(0xFFA33E3E),
    navUnselected: Color(0xFF8A3030),
    primary: Color(0xFFD03030),
    onPrimary: Color(0xFF1A0000),
    primaryContainer: Color(0xFF4A0C0C),
    onPrimaryContainer: Color(0xFFE05050),
    secondary: Color(0xFFB03838),
    secondaryContainer: Color(0xFF3A0909),
    onSecondaryContainer: Color(0xFFD84C4C),
    tertiary: Color(0xFFC04040),
    error: Color(0xFFE84040),
    errorContainer: Color(0xFF330808),
    onErrorContainer: Color(0xFFDD5555),
    accents: AstroAccents(
      eclipse: Color(0xFFD03030),
      conjunction: Color(0xFFD03030),
      transit: Color(0xFFD03030),
      satellite: Color(0xFFD03030),
      nightVision: true,
    ),
    dimFilledButtons: true,
  );

  static const _light = _Palette(
    brightness: Brightness.light,
    background: Color(0xFFF7F9FC),
    surface: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEFF3F8),
    surfaceContainerHigh: Color(0xFFE6ECF4),
    navBar: Color(0xFFFFFFFF),
    outline: Color(0xFFD5DDE8),
    outlineVariant: Color(0xFFE2E8F0),
    onSurface: Color(0xFF161C26),
    onSurfaceVariant: Color(0xFF4F5B6D),
    navUnselected: Color(0xFF5E6A7C),
    primary: Color(0xFF2558A8),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE7FA),
    onPrimaryContainer: Color(0xFF0F2A55),
    secondary: Color(0xFF51617A),
    secondaryContainer: Color(0xFFDCE7FA),
    onSecondaryContainer: Color(0xFF0F2A55),
    tertiary: Color(0xFFB26A00),
    error: Color(0xFFBA1A1A),
    errorContainer: Color(0xFFFFE4E0),
    onErrorContainer: Color(0xFF5C0F0A),
    accents: AstroAccents(
      eclipse: Color(0xFFB26A00),
      conjunction: Color(0xFF2558A8),
      transit: Color(0xFFD84315),
      satellite: Color(0xFF00796B),
    ),
  );

  static ThemeData _build(_Palette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primaryContainer,
      onPrimaryContainer: p.onPrimaryContainer,
      secondary: p.secondary,
      onSecondary: p.onPrimary,
      secondaryContainer: p.secondaryContainer,
      onSecondaryContainer: p.onSecondaryContainer,
      tertiary: p.tertiary,
      onTertiary: p.onPrimary,
      tertiaryContainer: p.secondaryContainer,
      onTertiaryContainer: p.onSecondaryContainer,
      error: p.error,
      onError: p.onPrimary,
      errorContainer: p.errorContainer,
      onErrorContainer: p.onErrorContainer,
      surface: p.surface,
      onSurface: p.onSurface,
      onSurfaceVariant: p.onSurfaceVariant,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceContainer,
      surfaceContainerHigh: p.surfaceContainerHigh,
      surfaceContainerHighest: p.surfaceContainerHigh,
      outline: p.outline,
      outlineVariant: p.outlineVariant,
      inverseSurface: p.onSurface,
      onInverseSurface: p.surface,
      inversePrimary: p.primaryContainer,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
    );
    WidgetStateProperty<T> selected<T>(T on, T off) =>
        WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? on : off,
        );
    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: _tabular(base.textTheme),
      extensions: [p.accents],
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.outline, width: 0.8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.outlineVariant,
        thickness: 0.8,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.navBar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: selected(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.primary,
          ),
          TextStyle(fontSize: 12, color: p.navUnselected),
        ),
        iconTheme: selected(
          IconThemeData(color: p.primary, size: 24),
          IconThemeData(color: p.navUnselected, size: 24),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.navBar,
        indicatorColor: p.secondaryContainer,
        selectedIconTheme: IconThemeData(color: p.primary),
        unselectedIconTheme: IconThemeData(color: p.navUnselected),
        selectedLabelTextStyle: TextStyle(
          color: p.primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: p.navUnselected,
          fontSize: 12,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceContainer,
        selectedColor: p.secondaryContainer,
        side: BorderSide(color: p.outline, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(fontSize: 13, color: p.onSurface),
        iconTheme: IconThemeData(color: p.primary, size: 18),
      ),
      filledButtonTheme: p.dimFilledButtons
          ? FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: p.primaryContainer,
                foregroundColor: p.onPrimaryContainer,
              ),
            )
          : null,
      // M3 默认未选中时圆点用 outline 色，而这里的 outline 是很暗的卡片边框色，会看不见
      switchTheme: SwitchThemeData(
        trackColor: selected(
          p.dimFilledButtons ? p.primaryContainer : p.primary,
          p.surfaceContainerHigh,
        ),
        thumbColor: selected(
          p.dimFilledButtons ? p.primary : p.onPrimary,
          p.navUnselected,
        ),
        trackOutlineColor: selected(Colors.transparent, p.navUnselected),
      ),
    );
  }

  /// 数字等宽，时间和数值在列表里能上下对齐。
  static TextTheme _tabular(TextTheme t) {
    const f = [FontFeature.tabularFigures()];
    TextStyle? tab(TextStyle? s) => s?.copyWith(fontFeatures: f);
    return t.copyWith(
      displayLarge: tab(t.displayLarge),
      displayMedium: tab(t.displayMedium),
      displaySmall: tab(t.displaySmall),
      headlineLarge: tab(t.headlineLarge),
      headlineMedium: tab(t.headlineMedium),
      headlineSmall: tab(t.headlineSmall),
      titleLarge: tab(t.titleLarge),
      titleMedium: tab(t.titleMedium),
      titleSmall: tab(t.titleSmall),
      bodyLarge: tab(t.bodyLarge),
      bodyMedium: tab(t.bodyMedium),
      bodySmall: tab(t.bodySmall),
      labelLarge: tab(t.labelLarge),
      labelMedium: tab(t.labelMedium),
      labelSmall: tab(t.labelSmall),
    );
  }
}

/// 一套外观的全部色值。
class _Palette {
  const _Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.navBar,
    required this.outline,
    required this.outlineVariant,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.navUnselected,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.accents,
    this.dimFilledButtons = false,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color navBar;
  final Color outline;
  final Color outlineVariant;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color navUnselected;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;
  final AstroAccents accents;

  /// 实心按钮、开关用暗色底（红光模式）
  final bool dimFilledButtons;
}

/// 各类天象的强调色（图标底色等）。红光模式下全部是暗红。
@immutable
class AstroAccents extends ThemeExtension<AstroAccents> {
  const AstroAccents({
    required this.eclipse,
    required this.conjunction,
    required this.transit,
    required this.satellite,
    this.nightVision = false,
  });

  final Color eclipse;
  final Color conjunction;
  final Color transit;
  final Color satellite;

  /// 红光（夜视）模式：地图等图片内容也要压暗成红色
  final bool nightVision;

  static AstroAccents of(BuildContext context) =>
      Theme.of(context).extension<AstroAccents>() ?? _fallback;

  static const _fallback = AstroAccents(
    eclipse: Color(0xFFFFB74D),
    conjunction: Color(0xFF6EA8FF),
    transit: Color(0xFFFF8A65),
    satellite: Color(0xFF4DB6AC),
  );

  @override
  AstroAccents copyWith({
    Color? eclipse,
    Color? conjunction,
    Color? transit,
    Color? satellite,
  }) => AstroAccents(
    eclipse: eclipse ?? this.eclipse,
    conjunction: conjunction ?? this.conjunction,
    transit: transit ?? this.transit,
    satellite: satellite ?? this.satellite,
    nightVision: nightVision,
  );

  @override
  AstroAccents lerp(AstroAccents? other, double t) {
    if (other == null) return this;
    return AstroAccents(
      eclipse: Color.lerp(eclipse, other.eclipse, t)!,
      conjunction: Color.lerp(conjunction, other.conjunction, t)!,
      transit: Color.lerp(transit, other.transit, t)!,
      satellite: Color.lerp(satellite, other.satellite, t)!,
      nightVision: t < 0.5 ? nightVision : other.nightVision,
    );
  }
}
