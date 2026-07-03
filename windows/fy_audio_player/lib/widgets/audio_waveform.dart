// 音频波形显示
import 'dart:math';
import 'package:flutter/material.dart';

class AudioWaveform extends StatefulWidget {
  final bool isActive;
  final int frameCount;

  const AudioWaveform({
    super.key,
    this.isActive = false,
    this.frameCount = 0,
  });

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _samples = List.generate(50, (_) => 0.0);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_updateSamples);
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        for (var i = 0; i < _samples.length; i++) {
          _samples[i] = _samples[i] * 0.8; // 衰减
        }
      });
    }
  }

  void _updateSamples() {
    if (!widget.isActive) return;
    setState(() {
      for (var i = 0; i < _samples.length - 1; i++) {
        _samples[i] = _samples[i + 1];
      }
      // 模拟音频波形（实际应从 PCM 数据计算 RMS）
      _samples[_samples.length - 1] = 0.2 + _random.nextDouble() * 0.8;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: WaveformPainter(
          samples: _samples,
          active: widget.isActive,
          color: colorScheme.primary,
          secondaryColor: colorScheme.tertiary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> samples;
  final bool active;
  final Color color;
  final Color secondaryColor;

  WaveformPainter({
    required this.samples,
    required this.active,
    required this.color,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / samples.length - 2;
    final centerY = size.height / 2;
    final maxHeight = size.height / 2 - 4;

    for (var i = 0; i < samples.length; i++) {
      final x = i * (barWidth + 2) + 1;
      final barHeight = samples[i] * maxHeight;
      final alpha = (0.3 + samples[i] * 0.7).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = (i % 2 == 0 ? color : secondaryColor)
            .withAlpha((alpha * 255).round())
        ..style = PaintingStyle.fill
        ..strokeCap = StrokeCap.round;

      // 上下对称的波形
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, centerY),
            width: barWidth,
            height: barHeight * 2,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }

    // 中心线
    final linePaint = Paint()
      ..color = color.withAlpha(30)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) => true;
}
