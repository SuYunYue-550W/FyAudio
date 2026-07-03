import 'package:flutter/material.dart';
import 'dart:ui';

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
    return Container(
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
          : null,
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
              color: Colors.white.withOpacity(0.12),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor.withOpacity(0.15)
                    : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: isActive
                      ? activeColor.withOpacity(0.4)
                      : Colors.white.withOpacity(0.15),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}