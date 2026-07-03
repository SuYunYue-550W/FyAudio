// 设备列表项
import 'package:flutter/material.dart';
import '../core/models.dart';

class DeviceListTile extends StatelessWidget {
  final DeviceInfo device;
  final bool isCurrentSource;
  final VoidCallback? onSetSource;

  const DeviceListTile({
    super.key,
    required this.device,
    this.isCurrentSource = false,
    this.onSetSource,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isCurrentSource ? colorScheme.primaryContainer.withAlpha(80) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrentSource
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          child: Text(
            device.platformIcon,
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Row(
          children: [
            Text(
              device.deviceName,
              style: TextStyle(
                fontWeight: isCurrentSource ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isCurrentSource) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '音源',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              device.ip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            Text(
              device.platform,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            if (device.hasBluetooth) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.bluetooth,
                size: 14,
                color: device.bluetoothConnected
                    ? Colors.blue
                    : colorScheme.outline,
              ),
            ],
          ],
        ),
        trailing: onSetSource != null && !isCurrentSource
            ? FilledButton.tonal(
                onPressed: onSetSource,
                child: const Text('设为音源'),
              )
            : device.isSource
                ? Icon(Icons.podcasts, color: colorScheme.primary)
                : Icon(Icons.headphones, color: colorScheme.outline),
      ),
    );
  }
}
