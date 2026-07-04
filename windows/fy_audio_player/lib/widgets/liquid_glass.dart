import 'package:flutter/material.dart';
import 'dart:ui';

/// 液态玻璃卡片 - iOS 26 风格四层渲染
///
/// 四层结构：
/// 1. 高斯模糊（BackdropFilter）— 磨砂玻璃基底
/// 2. 半透明背景色 — 玻璃材质
/// 3. 径向渐变高光 — 液态光泽
/// 4. 高亮描边 — 边缘折射
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double blurRadius;
  final Color glowColor;
  final double borderRadius;
  final double padding;
  final bool hasShadow;
  final double surfaceOpacity;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.blurRadius = 18,
    this.glowColor = Colors.white10,
    this.borderRadius = 16,
    this.padding = 0,
    this.hasShadow = true,
    this.surfaceOpacity = 0.10,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardOpacity = isDark ? surfaceOpacity * 0.7 : surfaceOpacity;
    final borderOpacity = isDark ? 0.12 : 0.22;

    return DecoratedBox(
      decoration: hasShadow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(0.10),
                  blurRadius: 20,
                  offset: const Offset(4, 6),
                ),
                BoxShadow(
                  color: glowColor.withOpacity(0.04),
                  blurRadius: 32,
                  offset: const Offset(0, 10),
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
          child: Stack(
            children: [
              // 第2层：半透明背景色
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(cardOpacity),
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                ),
              ),
              // 第3层：径向渐变高光（左上角光源）
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    gradient: RadialGradient(
                      center: const Alignment(-0.6, -0.8),
                      radius: 1.2,
                      colors: [
                        Colors.white.withOpacity(isDark ? 0.08 : 0.14),
                        Colors.white.withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.6],
                    ),
                  ),
                ),
              ),
              // 第4层：高亮描边
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: Colors.white.withOpacity(borderOpacity),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
              // 内容
              Container(
                padding:
                    padding > 0 ? EdgeInsets.all(padding) : null,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃按钮
class LiquidGlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color activeColor;
  final double blurRadius;

  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.isActive = false,
    this.activeColor = const Color(0xff1890ff),
    this.blurRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDisabled = onPressed == null;

    final Color bg;
    final Color borderColor;
    if (isDisabled) {
      bg = Colors.grey.withOpacity(isDark ? 0.08 : 0.15);
      borderColor = Colors.grey.withOpacity(0.25);
    } else if (isActive) {
      bg = activeColor.withOpacity(0.12);
      borderColor = activeColor.withOpacity(0.45);
    } else {
      bg = Colors.white.withOpacity(isDark ? 0.05 : 0.07);
      borderColor = Colors.white.withOpacity(isDark ? 0.10 : 0.16);
    }

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: (isActive && !isDisabled)
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurRadius, sigmaY: blurRadius),
            child: Stack(
              children: [
                // 背景
                Positioned.fill(
                  child: Material(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                // 径向高光
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: RadialGradient(
                        center: const Alignment(-0.5, -0.8),
                        radius: 1.0,
                        colors: [
                          Colors.white
                              .withOpacity(isDark ? 0.06 : 0.10),
                          Colors.white.withOpacity(0.0),
                        ],
                        stops: const [0.0, 0.5],
                      ),
                    ),
                  ),
                ),
                // 描边 + 点击
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: borderColor, width: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DefaultTextStyle(
                        style: DefaultTextStyle.of(context).style,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
