import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/theme_manager.dart';
import 'liquid_glass.dart';
import 'glass_hover_animate.dart';

enum DeviceStatus { online, offline, syncing, error }

class DeviceItemCard extends StatelessWidget {
  final DeviceInfo device;
  final DeviceStatus status;
  final bool isMaster;
  final VoidCallback? onTap;

  const DeviceItemCard({
    super.key,
    required this.device,
    required this.status,
    this.isMaster = false,
    this.onTap,
  });

  Color _getStatusColor() {
    switch (status) {
      case DeviceStatus.online:
        return const Color(0xff52c41a);
      case DeviceStatus.syncing:
        return const Color(0xff1890ff);
      case DeviceStatus.error:
        return const Color(0xfffa5252);
      default:
        return const Color(0xff86909c);
    }
  }

  String _getStatusText() {
    switch (status) {
      case DeviceStatus.online:
        return '在线同步中';
      case DeviceStatus.syncing:
        return '时序校准中';
      case DeviceStatus.error:
        return '连接异常';
      default:
        return '离线';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassHoverAnimate(
      child: LiquidGlassCard(
        blurRadius: 16,
        padding: 0,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: ThemeColorManager.getSurfaceColor(),
                  ),
                  child: Icon(
                    Icons.speaker_group_rounded,
                    color: ThemeColorManager.getTextColor(),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            device.deviceName,
                            style: TextStyle(
                              color: ThemeColorManager.getTextColor(),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isMaster)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xff1890ff).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '主机',
                                style: TextStyle(
                                    color: Color(0xff1890ff), fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.ip,
                        style: TextStyle(
                          color: ThemeColorManager.getSubTextColor(),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getStatusColor(),
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: status == DeviceStatus.online
                            ? [
                                BoxShadow(
                                  color: _getStatusColor().withOpacity(0.5),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStatusText(),
                      style: TextStyle(
                          color: _getStatusColor(), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}