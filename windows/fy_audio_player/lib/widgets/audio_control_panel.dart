import 'package:flutter/material.dart';
import '../core/theme_manager.dart';
import '../core/scene_manager.dart';
import '../core/codec_manager.dart';
import 'liquid_glass.dart';

class AudioControlPanel extends StatelessWidget {
  final double volume;
  final SceneMode currentScene;
  final String codecName;
  final Function(double) onVolumeChange;
  final VoidCallback onSceneTap;

  const AudioControlPanel({
    super.key,
    required this.volume,
    required this.currentScene,
    required this.codecName,
    required this.onVolumeChange,
    required this.onSceneTap,
  });

  String _sceneName() {
    switch (currentScene) {
      case SceneMode.music:
        return '音乐模式';
      case SceneMode.video:
        return '观影模式';
      case SceneMode.game:
        return '游戏低延迟';
      case SceneMode.room:
        return '全屋播放';
      case SceneMode.weakNet:
        return '弱网容错';
      case SceneMode.night:
        return '夜间静谧';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      blurRadius: 16,
      padding: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '音频控制面板',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ThemeColorManager.getTextColor(),
                  ),
                ),
                Row(
                  children: [
                    _tagItem(_sceneName(), true),
                    const SizedBox(width: 8),
                    _tagItem(codecName, false),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '全局音量',
              style: TextStyle(
                color: ThemeColorManager.getSubTextColor(),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.volume_mute,
                  color: ThemeColorManager.getSubTextColor(),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 6,
                      activeTrackColor: ThemeColorManager.getPrimaryColor(),
                      inactiveTrackColor: Colors.white.withOpacity(0.15),
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: volume.clamp(0, 100),
                      onChanged: onVolumeChange,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.volume_up,
                  color: ThemeColorManager.getSubTextColor(),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${volume.round()}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ThemeColorManager.getTextColor(),
                  ),
                ),
                TextButton(
                  onPressed: onSceneTap,
                  child: Text(
                    '切换场景',
                    style: TextStyle(
                      color: ThemeColorManager.getPrimaryColor(),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagItem(String text, bool isScene) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isScene
            ? ThemeColorManager.getPrimaryColor().withOpacity(0.15)
            : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isScene
              ? ThemeColorManager.getPrimaryColor().withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isScene
              ? ThemeColorManager.getPrimaryColor()
              : ThemeColorManager.getTextColor(),
          fontWeight: isScene ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }
}