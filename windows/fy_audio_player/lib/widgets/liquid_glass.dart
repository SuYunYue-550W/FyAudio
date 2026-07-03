import 'package:flutter/material.dart';
import 'dart:ui';

/// 液态玻璃卡片 - 根据当前 [Theme.brightness] 自适应深/浅色透明度。
///
/// 修复要点：
/// - 深色主题下提高透明度对比，避免文字与背景融为一体；
/// - boxShadow 与 ClipRRect 共用同一 [borderRadius]，避免圆角错位。
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double blurRadius;
  final Color glowColor;
  final double borderRadius;
  final double padding;
  final bool hasShadow;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.blurRadius = 14,
    this.glowColor = Colors.white10,
    this.borderRadius = 16,
    this.padding = 0,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardOpacity = isDark ? 0.08 : 0.12;
    final borderOpacity = isDark ? 0.10 : 0.18;

    return DecoratedBox(
      decoration: hasShadow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(4, 4),
                ),
                BoxShadow(
                  color: glowColor.withOpacity(0.03),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            )
          : const BoxDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurRadius,
            sigmaY: blurRadius,
          ),
          child: Container(
            padding: padding > 0 ? EdgeInsets.all(padding) : null,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(cardOpacity),
              border: Border.all(
                color: Colors.white.withOpacity(borderOpacity),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃按钮
///
/// 修复要点：
/// - [onPressed] 为 null 时显示禁用态（灰色 + 降低不透明度）；
/// - 使用 [InkWell] 替代 [GestureDetector] 以提供水波纹反馈；
/// - 阴影与裁切使用同一圆角，避免视觉错位。
class LiquidGlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color activeColor;

  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.isActive = false,
    this.activeColor = const Color(0xff1890ff),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDisabled = onPressed == null;

    final Color bg;
    final Color borderColor;
    if (isDisabled) {
      bg = Colors.grey.withOpacity(isDark ? 0.1 : 0.2);
      borderColor = Colors.grey.withOpacity(0.3);
    } else if (isActive) {
      bg = activeColor.withOpacity(0.15);
      borderColor = activeColor.withOpacity(0.4);
    } else {
      bg = Colors.white.withOpacity(isDark ? 0.06 : 0.08);
      borderColor = Colors.white.withOpacity(isDark ? 0.10 : 0.15);
    }

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: (isActive && !isDisabled)
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DefaultTextStyle(
                    style: DefaultTextStyle.of(context).style,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
