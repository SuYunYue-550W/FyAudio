import 'package:flutter/material.dart';

class GlassHoverAnimate extends StatefulWidget {
  final Widget child;
  final double animateRange;

  const GlassHoverAnimate({
    super.key,
    required this.child,
    this.animateRange = 4,
  });

  @override
  State<GlassHoverAnimate> createState() => _GlassHoverAnimateState();
}

class _GlassHoverAnimateState extends State<GlassHoverAnimate>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animX;
  late Animation<double> _animY;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _animX = Tween<double>(begin: -1, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
    _animY = Tween<double>(begin: -0.6, end: 0.6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, child) {
        return Transform.translate(
          offset: Offset(
            _animX.value * widget.animateRange,
            _animY.value * widget.animateRange,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

class GlowShadowContainer extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final double glowRadius;

  const GlowShadowContainer({
    super.key,
    required this.child,
    this.glowColor = const Color(0xff1890ff),
    this.glowRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.15),
            blurRadius: glowRadius,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: glowColor.withOpacity(0.05),
            blurRadius: glowRadius * 2,
            spreadRadius: 8,
          ),
        ],
      ),
      child: child,
    );
  }
}