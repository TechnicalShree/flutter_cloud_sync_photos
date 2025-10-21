import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light([ColorScheme? dynamicScheme]) {
    final colorScheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        );
    return _buildTheme(colorScheme);
  }

  static ThemeData dark([ColorScheme? dynamicScheme]) {
    final colorScheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        );
    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final brightness = colorScheme.brightness;
    final baseTextTheme = brightness == Brightness.dark
        ? Typography.material2021.white
        : Typography.material2021.black;

    final textTheme = baseTextTheme
        .apply(
          displayColor: colorScheme.onSurface,
          bodyColor: colorScheme.onSurface,
        )
        .copyWith(
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
          ),
          titleSmall: baseTextTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.35),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.35),
          bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.3),
        );

    final iconTheme = IconThemeData(color: colorScheme.onSurfaceVariant);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: textTheme,
      iconTheme: iconTheme,
      primaryIconTheme: iconTheme,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        elevation: 12,
        iconTheme: MaterialStateProperty.resolveWith((states) {
          final color = states.contains(MaterialState.selected)
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant;
          return IconThemeData(color: color);
        }),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final color = states.contains(MaterialState.selected)
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant;
          return textTheme.labelMedium?.copyWith(color: color);
        }),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: iconTheme,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        actionTextColor: colorScheme.primary,
      ),
      cardTheme: CardTheme(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          iconColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return colorScheme.onSurfaceVariant.withOpacity(0.38);
            }
            return colorScheme.onSurface;
          }),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 0.7,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(),
      visualDensity: VisualDensity.standard,
    );
  }

  static const Color _seedColor = Color(0xFF6750A4);
}
