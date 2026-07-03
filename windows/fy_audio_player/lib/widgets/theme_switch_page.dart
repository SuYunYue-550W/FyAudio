import 'package:flutter/material.dart';
import '../core/theme_manager.dart';
import 'liquid_glass.dart';

class ThemeSwitchPage extends StatelessWidget {
  const ThemeSwitchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      blurRadius: 16,
      padding: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '视觉主题切换',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ThemeColorManager.getTextColor(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _themeBtn('原生透明', AppThemeMode.transparent),
                _themeBtn('暗夜磨砂', AppThemeMode.darkGlass),
                _themeBtn('极光渐变', AppThemeMode.aurora),
                _themeBtn('纯白哑光', AppThemeMode.pureWhite),
                _themeBtn('赛博冷透', AppThemeMode.cyberBlue),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '当前主题: ${ThemeColorManager.getThemeName(ThemeColorManager.currentTheme)}',
                style: TextStyle(
                  color: ThemeColorManager.getSubTextColor(),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeBtn(String name, AppThemeMode mode) {
    bool isActive = ThemeColorManager.currentTheme == mode;
    return GestureDetector(
      onTap: () {
        ThemeColorManager.switchTheme(mode);
      },
      child: Container(
        width: 110,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: _getThemePreviewColors(mode)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? ThemeColorManager.getPrimaryColor()
                : Colors.white.withOpacity(0.1),
            width: isActive ? 2 : 0.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: ThemeColorManager.getPrimaryColor().withOpacity(0.2),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: _getThemeTextColor(mode),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  List<Color> _getThemePreviewColors(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.transparent:
        return [const Color(0xfff6f9ff), const Color(0xffeef2ff)];
      case AppThemeMode.darkGlass:
        return [const Color(0xff1a1a2e), const Color(0xff16213e)];
      case AppThemeMode.aurora:
        return [const Color(0xff6366f1), const Color(0xffec4899)];
      case AppThemeMode.pureWhite:
        return [const Color(0xffffffff), const Color(0xfff0f0f0)];
      case AppThemeMode.cyberBlue:
        return [const Color(0xff0f172a), const Color(0xff06b6d4)];
    }
  }

  Color _getThemeTextColor(AppThemeMode mode) {
    if (mode == AppThemeMode.darkGlass || mode == AppThemeMode.cyberBlue) {
      return Colors.white;
    }
    return const Color(0xff1d2129);
  }
}