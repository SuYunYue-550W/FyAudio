import 'package:flutter/material.dart';
import 'dart:math';
import '../core/scene_manager.dart';

class AudioParticlePainter extends CustomPainter {
  final double volume;
  final List<double> spectrum;
  final SceneMode sceneMode;

  AudioParticlePainter({
    required this.volume,
    required this.spectrum,
    required this.sceneMode,
  }) : super(repaint: const AlwaysStoppedAnimation(0));

  final List<Offset> particles = [];
  final List<double> speeds = [];
  final List<double> sizes = [];
  final Random rd = Random();

  @override
  void paint(Canvas canvas, Size size) {
    double maxCount = 80;
    double speed = 1.0;
    double opacityMultiplier = 1.0;

    switch (sceneMode) {
      case SceneMode.game:
        maxCount = 20;
        speed = 0.2;
        opacityMultiplier = 0.5;
        break;
      case SceneMode.night:
        maxCount = 30;
        speed = 0.4;
        opacityMultiplier = 0.6;
        break;
      case SceneMode.weakNet:
        maxCount = 15;
        speed = 0.1;
        opacityMultiplier = 0.3;
        break;
      default:
        maxCount = 80;
        speed = 1.0;
        opacityMultiplier = 1.0;
    }

    int genCount = (maxCount * volume.clamp(0.1, 1.0)).toInt();

    while (particles.length < genCount) {
      particles.add(Offset(
        rd.nextDouble() * size.width,
        rd.nextDouble() * size.height,
      ));
      speeds.add(0.5 + rd.nextDouble() * 1.5);
      sizes.add(2 + rd.nextDouble() * 6);
    }

    while (particles.length > genCount) {
      particles.removeLast();
      speeds.removeLast();
      sizes.removeLast();
    }

    for (int i = 0; i < particles.length; i++) {
      double baseSpeed = speeds[i] * speed;
      double spectrumInfluence =
          spectrum.isNotEmpty ? spectrum[i % spectrum.length] : 0.5;

      particles[i] = Offset(
        particles[i].dx + (rd.nextDouble() - 0.5) * baseSpeed * 2,
        particles[i].dy + (rd.nextDouble() - 0.5) * baseSpeed * 2,
      );

      if (particles[i].dx < 0) {
        particles[i] = Offset(0, particles[i].dy);
      }
      if (particles[i].dx > size.width) {
        particles[i] = Offset(size.width, particles[i].dy);
      }
      if (particles[i].dy < 0) {
        particles[i] = Offset(particles[i].dx, 0);
      }
      if (particles[i].dy > size.height) {
        particles[i] = Offset(particles[i].dx, size.height);
      }

      double r = sizes[i] * (0.5 + spectrumInfluence * 0.5);
      double opacity = (0.15 + volume * 0.2) * opacityMultiplier;

      Paint paint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(particles[i], r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AudioParticlePainter oldDelegate) {
    return oldDelegate.volume != volume ||
        oldDelegate.sceneMode != sceneMode ||
        oldDelegate.spectrum.length != spectrum.length;
  }
}

class AudioParticleBackground extends StatefulWidget {
  final Widget child;
  final double volume;
  final List<double> spectrum;
  final SceneMode sceneMode;

  const AudioParticleBackground({
    super.key,
    required this.child,
    this.volume = 0.5,
    this.spectrum = const [],
    this.sceneMode = SceneMode.music,
  });

  @override
  State<AudioParticleBackground> createState() => _AudioParticleBackgroundState();
}

class _AudioParticleBackgroundState extends State<AudioParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            CustomPaint(
              painter: AudioParticlePainter(
                volume: widget.volume,
                spectrum: widget.spectrum,
                sceneMode: widget.sceneMode,
              ),
              size: MediaQuery.of(context).size,
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}