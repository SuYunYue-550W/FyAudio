import 'dart:math';
import 'package:flutter/material.dart';
import '../core/scene_manager.dart';

/// 单个粒子的可变状态 - 由外层 StatefulWidget 持有，CustomPainter 只读
class Particle {
  Offset position;
  final double speed;
  final double size;
  Particle(this.position, this.speed, this.size);
}

/// 音频粒子画笔 - 无可变状态，仅负责绘制
///
/// 通过 `super(repaint: animation)` 让外层 AnimationController 驱动重绘，
/// 不在内部维护可变列表，避免 CustomPainter 被复用时状态错乱。
class AudioParticlePainter extends CustomPainter {
  final double volume;
  final List<double> spectrum;
  final SceneMode sceneMode;
  final List<Particle> particles;

  AudioParticlePainter({
    required this.volume,
    required this.spectrum,
    required this.sceneMode,
    required this.particles,
    required Listenable animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    double opacityMultiplier;
    switch (sceneMode) {
      case SceneMode.game:
        opacityMultiplier = 0.5;
        break;
      case SceneMode.night:
        opacityMultiplier = 0.6;
        break;
      case SceneMode.weakNet:
        opacityMultiplier = 0.3;
        break;
      default:
        opacityMultiplier = 1.0;
    }

    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];
      final spectrumInfluence =
          spectrum.isNotEmpty ? spectrum[i % spectrum.length] : 0.5;
      final r = p.size * (0.5 + spectrumInfluence * 0.5);
      final opacity = (0.15 + volume * 0.2) * opacityMultiplier;

      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p.position, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioParticlePainter oldDelegate) {
    return oldDelegate.volume != volume ||
        oldDelegate.sceneMode != sceneMode ||
        oldDelegate.spectrum.length != spectrum.length ||
        !identical(oldDelegate.particles, particles);
  }
}

/// 音频粒子背景 - 外层持有粒子状态，由 AnimationController 驱动重绘
class AudioParticleBackground extends StatefulWidget {
  final Widget child;
  final double volume;
  final List<double> spectrum;
  final SceneMode sceneMode;
  final bool isPlaying;

  const AudioParticleBackground({
    super.key,
    required this.child,
    this.volume = 0.5,
    this.spectrum = const [],
    this.sceneMode = SceneMode.music,
    this.isPlaying = false,
  });

  @override
  State<AudioParticleBackground> createState() =>
      _AudioParticleBackgroundState();
}

class _AudioParticleBackgroundState extends State<AudioParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _rd = Random();
  final List<Particle> _particles = [];
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 33),
    )..addListener(_tick);
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AudioParticleBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      // 不播放时停止动画以节省 CPU
      _controller.stop();
    }
  }

  void _tick() {
    if (_canvasSize == Size.zero) return;

    final maxCount = _maxCountForScene(widget.sceneMode);
    final speed = _speedForScene(widget.sceneMode);
    final genCount = (maxCount * widget.volume.clamp(0.1, 1.0)).toInt();

    // 调整粒子数量
    while (_particles.length < genCount) {
      _particles.add(Particle(
        Offset(
          _rd.nextDouble() * _canvasSize.width,
          _rd.nextDouble() * _canvasSize.height,
        ),
        0.5 + _rd.nextDouble() * 1.5,
        2 + _rd.nextDouble() * 6,
      ));
    }
    while (_particles.length > genCount) {
      _particles.removeLast();
    }

    // 更新粒子位置（含边界检测）
    for (final p in _particles) {
      final dx = (_rd.nextDouble() - 0.5) * p.speed * speed * 2;
      final dy = (_rd.nextDouble() - 0.5) * p.speed * speed * 2;
      double nx = p.position.dx + dx;
      double ny = p.position.dy + dy;
      if (nx < 0) nx = 0;
      if (nx > _canvasSize.width) nx = _canvasSize.width;
      if (ny < 0) ny = 0;
      if (ny > _canvasSize.height) ny = _canvasSize.height;
      p.position = Offset(nx, ny);
    }

    setState(() {});
  }

  int _maxCountForScene(SceneMode mode) {
    switch (mode) {
      case SceneMode.game:
        return 20;
      case SceneMode.night:
        return 30;
      case SceneMode.weakNet:
        return 15;
      default:
        return 80;
    }
  }

  double _speedForScene(SceneMode mode) {
    switch (mode) {
      case SceneMode.game:
        return 0.2;
      case SceneMode.night:
        return 0.4;
      case SceneMode.weakNet:
        return 0.1;
      default:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            CustomPaint(
              painter: AudioParticlePainter(
                volume: widget.volume,
                spectrum: widget.spectrum,
                sceneMode: widget.sceneMode,
                particles: _particles,
                animation: _controller,
              ),
              size: _canvasSize,
            ),
            widget.child,
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
