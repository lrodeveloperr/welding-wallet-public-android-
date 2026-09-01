import 'package:flutter/material.dart';

abstract final class WalletColors {
  static const background = Color(0xFFF5F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF132238);
  static const muted = Color(0xFF617087);
  static const border = Color(0xFFDCE4EE);
  static const blue = Color(0xFF1769E0);
  static const blueSoft = Color(0xFFEAF2FF);
  static const green = Color(0xFF00896B);
  static const greenSoft = Color(0xFFE6F6F2);
  static const amber = Color(0xFFB96B00);
  static const amberSoft = Color(0xFFFFF3DD);
  static const violet = Color(0xFF6D51C5);
  static const violetSoft = Color(0xFFF1EDFF);
  static const danger = Color(0xFFC3353B);
}

ThemeData buildWalletTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: WalletColors.blue,
    brightness: Brightness.light,
    primary: WalletColors.blue,
    secondary: WalletColors.green,
    surface: WalletColors.surface,
    error: WalletColors.danger,
  );
  const radius = BorderRadius.all(Radius.circular(16));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WalletColors.background,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        color: WalletColors.ink,
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        color: WalletColors.ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: WalletColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: WalletColors.ink, fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(
        color: WalletColors.muted,
        fontSize: 14,
        height: 1.4,
      ),
      labelLarge: TextStyle(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WalletColors.background,
      foregroundColor: WalletColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: WalletColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: WalletColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: WalletColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: WalletColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: WalletColors.border),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: WalletColors.background,
      modalBackgroundColor: WalletColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: WalletColors.surface,
      indicatorColor: WalletColors.blueSoft,
      elevation: 4,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
