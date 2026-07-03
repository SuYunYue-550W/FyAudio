// 同步状态指示器
import 'package:flutter/material.dart';

class SyncIndicator extends StatelessWidget {
  final int latencyMs;
  final int offsetMs;
  final int bufferFrames;
  final bool isPlaying;

  const SyncIndicator({
    super.key,
    required this.latencyMs,
    required this.offsetMs,
    required this.bufferFrames,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(latencyMs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withAlpha(100),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isPlaying ? '同步播放中' : '等待音频流',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MetricChip(
                  label: '网络延迟',
                  value: '${latencyMs}ms',
                  color: statusColor,
                ),
                _MetricChip(
                  label: '时钟补偿',
                  value: '${offsetMs}ms',
                  color: offsetMs.abs() < 50 ? Colors.green : Colors.orange,
                ),
                _MetricChip(
                  label: '缓冲',
                  value: '$bufferFrames 帧',
                  color: colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 质量条
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _getQualityScore() / 100,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(statusColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '同步质量: ${_getQualityLabel()} (${_getQualityScore()}%)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(int latency) {
    if (latency < 30) return Colors.green;
    if (latency < 80) return Colors.orange;
    return Colors.red;
  }

  int _getQualityScore() {
    if (latencyMs < 20) return 100;
    if (latencyMs < 50) return 80;
    if (latencyMs < 100) return 60;
    if (latencyMs < 200) return 40;
    return 20;
  }

  String _getQualityLabel() {
    final score = _getQualityScore();
    if (score >= 80) return '优秀';
    if (score >= 60) return '良好';
    if (score >= 40) return '一般';
    return '较差';
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
}
