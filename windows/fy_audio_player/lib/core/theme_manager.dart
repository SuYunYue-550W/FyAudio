import 'package:flutter/material.dart';

enum AppThemeMode {
  transparent,
  darkGlass,
  aurora,
  pureWhite,
  cyberBlue,
}

class ThemeColorManager {
  static AppThemeMode currentTheme = AppThemeMode.transparent;

  static List<Color> getBgGradient() {
    switch (currentTheme) {
      case AppThemeMode.transparent:
        return [const Color(0xfff6f9ff), const Color(0xffeef2ff)];
      case AppThemeMode.darkGlass:
        return [const Color(0xff0a0a12), const Color(0xff121220)];
      case AppThemeMode.aurora:
        return [const Color(0xff6366f1), const Color(0xffa855f7), const Color(0xffec4899)];
      case AppThemeMode.pureWhite:
        return [const Color(0xffffffff), const Color(0xfff8f9fa)];
      case AppThemeMode.cyberBlue:
        return [const Color(0xff0f172a), const Color(0xff1e293b), const Color(0xff06b6d4)];
    }
  }

  static Color getTextColor() {
    if (currentTheme == AppThemeMode.darkGlass || currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.95);
    }
    return const Color(0xff1d2129);
  }

  static Color getSubTextColor() {
    if (currentTheme == AppThemeMode.darkGlass || currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.6);
    }
    return const Color(0xff86909c);
  }

  static Color getPrimaryColor() {
    switch (currentTheme) {
      case AppThemeMode.transparent:
        return const Color(0xff4f46e5);
      case AppThemeMode.darkGlass:
        return const Color(0xff60a5fa);
      case AppThemeMode.aurora:
        return const Color(0xffa855f7);
      case AppThemeMode.pureWhite:
        return const Color(0xff3b82f6);
      case AppThemeMode.cyberBlue:
        return const Color(0xff22d3ee);
    }
  }

  static Color getSurfaceColor() {
    if (currentTheme == AppThemeMode.darkGlass || currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.05);
    }
    return Colors.white.withOpacity(0.6);
  }

  static Color getBorderColor() {
    if (currentTheme == AppThemeMode.darkGlass || currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.1);
    }
    return Colors.black.withOpacity(0.05);
  }

  static Brightness getBrightness() {
    if (currentTheme == AppThemeMode.darkGlass || currentTheme == AppThemeMode.cyberBlue) {
      return Brightness.dark;
    }
    return Brightness.light;
  }

  static void switchTheme(AppThemeMode mode) {
    currentTheme = mode;
  }

  static String getThemeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.transparent:
        return '原生透明';
      case AppThemeMode.darkGlass:
        return '暗夜磨砂';
      case AppThemeMode.aurora:
        return '极光渐变';
      case AppThemeMode.pureWhite:
        return '纯白哑光';
      case AppThemeMode.cyberBlue:
        return '赛博冷透';
    }
  }
}