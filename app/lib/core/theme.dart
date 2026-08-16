import 'package:flutter/material.dart';

/// الثيم. عربي RTL بخط Almarai، وألوان دافية تليق بتطبيق بيتفتح كذا مرة
/// في اليوم — مش لوحة تحكم باردة.
class AppTheme {
  const AppTheme._();

  /// أخضر غامق هادي — لون «تم وانحفظ». درجات الفاتح والغامق بتتولد منه.
  static const Color _seed = Color(0xFF166D53);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Almarai',
      scaffoldBackgroundColor: dark
          ? scheme.surface
          : scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? scheme.surface : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Almarai',
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      textTheme: const TextTheme(
        // الأرقام والحروف العربية أوطى بصريًا من اللاتيني — ارتفاع سطر
        // أكبر شوية بيمنع التلاصق في الرسايل الطويلة.
        bodyMedium: TextStyle(height: 1.55, fontSize: 15),
        bodyLarge: TextStyle(height: 1.55, fontSize: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? scheme.surfaceContainerHigh : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Almarai',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: 'Almarai',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
