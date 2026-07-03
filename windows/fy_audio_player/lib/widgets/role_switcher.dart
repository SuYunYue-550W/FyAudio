// 角色切换器
import 'package:flutter/material.dart';

class RoleSwitcher extends StatelessWidget {
  final String role; // source | receiver | gateway
  final ValueChanged<String> onChanged;

  const RoleSwitcher({
    super.key,
    required this.role,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'source',
          label: Text('🎙️ 音源'),
          icon: Icon(Icons.podcasts, size: 16),
        ),
        ButtonSegment(
          value: 'receiver',
          label: Text('🎧 接收'),
          icon: Icon(Icons.headphones, size: 16),
        ),
      ],
      selected: {role},
      onSelectionChanged: (selected) {
        onChanged(selected.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
