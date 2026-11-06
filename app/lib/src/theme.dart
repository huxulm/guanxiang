import 'package:flutter/material.dart';

/// 观象（Guanxiang）设计系统与主题配置。
///
/// 包含三种外观：
/// 1. [deepSpaceTheme]：深空暗夜模式（OLED 纯黑与冷色调星空蓝，适合暗光环境沉浸式探索）；
/// 2. [astroRedTheme]：天文夜间红光模式（专为户外实地观星暗适应设计，单色红光避免视紫红质被漂白）；
/// 3. [lightTheme]：明亮浅色模式（现代极简星空蓝调）。
class AstroTheme {
  AstroTheme._();

  // ---------------------------------------------------------------------------
  // 1. 深空暗夜主题 (Deep Space Dark)
  // ---------------------------------------------------------------------------
  static ThemeData get deepSpaceTheme {
    const scaffoldBg = Color(0xFF0B0E14);
    const surface = Color(0xFF131924);
    const surfaceContainer = Color(0xFF1B2332);
    const surfaceContainerHigh = Color(0xFF242E40);
    const primary = Color(0xFF569AFF);
    const secondary = Color(0xFFFFAA00);
    const outline = Color(0xFF263246);

    final colorScheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF1A3358),
      onPrimaryContainer: const Color(0xFFD3E4FF),
      secondary: secondary,
      onSecondary: Colors.black,
      secondaryContainer: const Color(0xFF4E3500),
      onSecondaryContainer: const Color(0xFFFFDF9E),
      surface: surface,
      onSurface: const Color(0xFFE2E6EE),
      onSurfaceVariant: const Color(0xFFA6B0C2),
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      outline: outline,
      outlineVariant: const Color(0xFF1C2534),
      error: const Color(0xFFFF5449),
      errorContainer: const Color(0xFF4D120E),
      onErrorContainer: const Color(0xFFFFDAD6),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFFE2E6EE),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline, width: 0.8),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1B2433),
        thickness: 0.8,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0F141E),
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF1F3556),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFF8E9CAD),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(color: Color(0xFF8E9CAD), size: 24);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF0F141E),
        indicatorColor: const Color(0xFF1F3556),
        selectedIconTheme: const IconThemeData(color: primary),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF8E9CAD)),
        selectedLabelTextStyle: const TextStyle(
          color: primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: Color(0xFF8E9CAD),
          fontSize: 12,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: const Color(0xFF1F3556),
        side: const BorderSide(color: outline, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFE2E6EE)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. 天文夜间红光主题 (Astro Red Night Vision)
  // ---------------------------------------------------------------------------
  static ThemeData get astroRedTheme {
    const scaffoldBg = Color(0xFF0A0202);
    const surface = Color(0xFF160404);
    const surfaceContainer = Color(0xFF220808);
    const surfaceContainerHigh = Color(0xFF330C0C);
    const primary = Color(0xFFFF3B30);
    const outline = Color(0xFF481010);

    final colorScheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.black,
      primaryContainer: const Color(0xFF500F0F),
      onPrimaryContainer: const Color(0xFFFFB4AB),
      secondary: const Color(0xFFFF6961),
      onSecondary: Colors.black,
      surface: surface,
      onSurface: const Color(0xFFFF9494),
      onSurfaceVariant: const Color(0xFFD67373),
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      outline: outline,
      outlineVariant: const Color(0xFF2F0A0A),
      error: const Color(0xFFFF2222),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFFFF9494),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline, width: 0.8),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2F0A0A),
        thickness: 0.8,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF100303),
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF4D1010),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            );
          }
          return const TextStyle(fontSize: 12, color: Color(0xFFB05555));
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(color: Color(0xFFB05555), size: 24);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF100303),
        indicatorColor: const Color(0xFF4D1010),
        selectedIconTheme: const IconThemeData(color: primary),
        unselectedIconTheme: const IconThemeData(color: Color(0xFFB05555)),
        selectedLabelTextStyle: const TextStyle(
          color: primary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: Color(0xFFB05555),
          fontSize: 12,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: const Color(0xFF4D1010),
        side: const BorderSide(color: outline, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFFFF9494)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. 明亮浅色主题 (Clean Light)
  // ---------------------------------------------------------------------------
  static ThemeData get lightTheme {
    const primary = Color(0xFF1F3A68);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F9FC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 0.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFE2ECFA),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
