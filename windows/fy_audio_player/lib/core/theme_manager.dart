import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式枚举 - 五种内置主题
enum AppThemeMode {
  transparent,
  darkGlass,
  aurora,
  pureWhite,
  cyberBlue,
}

/// 单一主题的配色定义
class ThemeColors {
  final Color primaryColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color textColor;
  final Brightness brightness;

  const ThemeColors({
    required this.primaryColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.textColor,
    required this.brightness,
  });
}

/// 主题管理器 - ChangeNotifier，负责主题切换与持久化
///
/// 通过 [Provider] 注入 UI 树以驱动重建；同时通过单例 [instance]
/// 与 [ThemeColorManager] 静态门面保持兼容，便于尚未迁移的旧组件读取。
class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  static ThemeManager get instance => _instance;

  AppThemeMode _currentTheme = AppThemeMode.transparent;

  AppThemeMode get currentTheme => _currentTheme;
  ThemeColors get colors => _resolveColors(_currentTheme);

  ThemeManager._internal() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt('app_theme_mode') ?? 0;
      _currentTheme = (idx >= 0 && idx < AppThemeMode.values.length)
          ? AppThemeMode.values[idx]
          : AppThemeMode.transparent;
      _syncStatic();
      notifyListeners();
    } catch (_) {
      // 读取失败时保持默认主题
    }
  }

  /// 切换主题并持久化
  Future<void> setTheme(AppThemeMode mode) async {
    if (_currentTheme == mode) return;
    _currentTheme = mode;
    _syncStatic();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('app_theme_mode', mode.index);
    } catch (_) {
      // 持久化失败不影响内存中的主题
    }
  }

  void _syncStatic() {
    ThemeColorManager.currentTheme = _currentTheme;
  }

  ThemeColors _resolveColors(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.transparent:
        return const ThemeColors(
          primaryColor: Color(0xff4f46e5),
          backgroundColor: Color(0xfff6f9ff),
          cardColor: Color(0xffffffff),
          textColor: Color(0xff1d2129),
          brightness: Brightness.light,
        );
      case AppThemeMode.darkGlass:
        return const ThemeColors(
          primaryColor: Color(0xff60a5fa),
          backgroundColor: Color(0xff0a0a12),
          cardColor: Color(0xff121220),
          textColor: Color(0xffffffff),
          brightness: Brightness.dark,
        );
      case AppThemeMode.aurora:
        return const ThemeColors(
          primaryColor: Color(0xffa855f7),
          backgroundColor: Color(0xff6366f1),
          cardColor: Color(0xffa855f7),
          textColor: Color(0xffffffff),
          brightness: Brightness.light,
        );
      case AppThemeMode.pureWhite:
        return const ThemeColors(
          primaryColor: Color(0xff3b82f6),
          backgroundColor: Color(0xffffffff),
          cardColor: Color(0xfff8f9fa),
          textColor: Color(0xff1d2129),
          brightness: Brightness.light,
        );
      case AppThemeMode.cyberBlue:
        return const ThemeColors(
          primaryColor: Color(0xff22d3ee),
          backgroundColor: Color(0xff0f172a),
          cardColor: Color(0xff1e293b),
          textColor: Color(0xffffffff),
          brightness: Brightness.dark,
        );
    }
  }
}

/// 旧组件兼容门面 - 读取操作委托给 [ThemeManager.instance]
///
/// 旧组件直接调用静态方法获取颜色；当主题变化时，[ThemeManager] 通过
/// [Provider] 触发整树重建，旧组件在重建时即可读到最新的静态颜色。
class ThemeColorManager {
  /// 旧代码使用的当前主题镜像，由 [ThemeManager._syncStatic] 同步。
  static AppThemeMode currentTheme = AppThemeMode.transparent;

  static List<Color> getBgGradient() {
    switch (currentTheme) {
      case AppThemeMode.transparent:
        return [const Color(0xfff6f9ff), const Color(0xffeef2ff)];
      case AppThemeMode.darkGlass:
        return [const Color(0xff0a0a12), const Color(0xff121220)];
      case AppThemeMode.aurora:
        return [
          const Color(0xff6366f1),
          const Color(0xffa855f7),
          const Color(0xffec4899)
        ];
      case AppThemeMode.pureWhite:
        return [const Color(0xffffffff), const Color(0xfff8f9fa)];
      case AppThemeMode.cyberBlue:
        return [
          const Color(0xff0f172a),
          const Color(0xff1e293b),
          const Color(0xff06b6d4)
        ];
    }
  }

  static Color getTextColor() {
    if (currentTheme == AppThemeMode.darkGlass ||
        currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.95);
    }
    return const Color(0xff1d2129);
  }

  static Color getSubTextColor() {
    if (currentTheme == AppThemeMode.darkGlass ||
        currentTheme == AppThemeMode.cyberBlue) {
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
    if (currentTheme == AppThemeMode.darkGlass ||
        currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.05);
    }
    return Colors.white.withOpacity(0.6);
  }

  static Color getBorderColor() {
    if (currentTheme == AppThemeMode.darkGlass ||
        currentTheme == AppThemeMode.cyberBlue) {
      return Colors.white.withOpacity(0.1);
    }
    return Colors.black.withOpacity(0.05);
  }

  static Brightness getBrightness() {
    if (currentTheme == AppThemeMode.darkGlass ||
        currentTheme == AppThemeMode.cyberBlue) {
      return Brightness.dark;
    }
    return Brightness.light;
  }

  /// 切换主题 - 委托给 [ThemeManager] 并触发持久化与通知
  static void switchTheme(AppThemeMode mode) {
    currentTheme = mode;
    ThemeManager.instance.setTheme(mode);
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
