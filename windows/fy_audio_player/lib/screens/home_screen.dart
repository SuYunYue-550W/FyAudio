import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/audio_service.dart';
import '../services/network_service.dart';
import '../services/bluetooth_service.dart';
import '../services/sync_service.dart';
import '../core/theme_manager.dart';
import '../core/scene_manager.dart';
import '../core/models.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/audio_particles.dart';

/// 主界面 - 单页布局
///
/// 布局：
/// - 顶部：应用标题 + 设备角色切换（音源/接收端）+ 右上角设置按钮
/// - 中部：已发现设备列表（名称、平台、IP、延迟）
/// - 底部：播放控制（播放/暂停、音量滑块、同步状态指示器）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _initialized = false;
  final double _particleVolume = 0.3;

  @override
  void initState() {
    super.initState();
    // 在 initState 中完成服务初始化与音频数据流接线
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final appState = context.read<AppState>();
    final network = context.read<NetworkService>();
    final audio = context.read<AudioService>();
    final sync = context.read<SyncService>();
    final sceneManager = context.read<SceneAutoManager>();

    await network.initialize(
      deviceId: appState.deviceId,
      deviceName: appState.deviceName,
      role: appState.role,
    );

    // ============ 修复音频数据流断裂 ============
    // 1. 网络帧送入同步引擎
    network.onAudioFrame = (frame) => sync.feedFrame(frame);
    // 2. 采集帧发送到网络（AudioFrame 已带 payload 与毫秒时间戳）
    audio.onAudioFrame =
        (frame) => network.sendAudioFrame(frame.payload, frame.timestamp);
    // 3. 可播放帧送入音频服务
    sync.onPlayableFrame = (frame) => audio.playFrame(frame);
    // 4. 同步统计更新 - 转发给 AppState
    sync.onStatsUpdate = (stats) {
      appState.updateSyncStats(
        latencyMs: stats.estimatedRTT,
        bufferFrames: stats.bufferFrames,
        clockOffsetMs: stats.offsetMs,
      );
    };

    // ============ 设备发现回调 ============
    network.onDeviceOnline = (device) => appState.addDevice(device);
    network.onDeviceOffline = (id) => appState.removeDevice(id);

    // ============ 音量同步 ============
    network.onVolumeSync = (vol) {
      appState.setVolume(vol);
      audio.setVolume(vol);
    };

    // ============ 场景变更回调 - 通知 AudioService / NetworkService ============
    sceneManager.onSceneChanged = (mode, bufferMs, bitRate, frameMs, strictSync) {
      // 将场景映射到 AudioService 的 AudioScene
      audio.setScene(_toAudioScene(mode));
    };

    await network.start();

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  AudioScene _toAudioScene(SceneMode mode) {
    switch (mode) {
      case SceneMode.music:
        return AudioScene.music;
      case SceneMode.video:
        return AudioScene.video;
      case SceneMode.game:
        return AudioScene.gaming;
      case SceneMode.room:
        return AudioScene.room;
      case SceneMode.weakNet:
        return AudioScene.weakNetwork;
      case SceneMode.night:
        return AudioScene.night;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sceneManager = context.watch<SceneAutoManager>();
    final isPlaying = context.select<AppState, bool>((s) => s.isPlaying);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AudioParticleBackground(
        volume: _particleVolume,
        sceneMode: sceneManager.currentScene,
        isPlaying: isPlaying,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: ThemeColorManager.getBgGradient()
                  .map((c) => c.withOpacity(0.78))
                  .toList(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(child: _buildBody(context)),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== 顶部栏 =====================

  Widget _buildAppBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LiquidGlassCard(
        blurRadius: 20,
        padding: 0,
        hasShadow: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildLogo(),
              const SizedBox(width: 12),
              Expanded(child: _buildTitle(context)),
              _buildRoleSwitcher(context),
              const SizedBox(width: 8),
              _buildSettingsButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            ThemeColorManager.getPrimaryColor(),
            ThemeColorManager.getPrimaryColor().withOpacity(0.6),
          ],
        ),
      ),
      child: const Icon(Icons.speaker_group, color: Colors.white, size: 22),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final sceneManager = context.watch<SceneAutoManager>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FyAudio',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: ThemeColorManager.getTextColor(),
          ),
        ),
        Text(
          '${sceneManager.getSceneName()} · ${sceneManager.bitRate}kbps',
          style: TextStyle(
            fontSize: 11,
            color: ThemeColorManager.getSubTextColor(),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSwitcher(BuildContext context) {
    final appState = context.watch<AppState>();
    return LiquidGlassButton(
      isActive: appState.isSource,
      activeColor: ThemeColorManager.getPrimaryColor(),
      onPressed: () {
        final newRole = appState.isSource ? 'receiver' : 'source';
        appState.setRole(newRole);
        context.read<NetworkService>().updateRole(newRole);
      },
      child: Text(
        appState.isSource ? '🎙️ 音源' : '🎧 接收',
        style: TextStyle(
          fontSize: 13,
          color: ThemeColorManager.getTextColor(),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return LiquidGlassButton(
      onPressed: () => _showSettingsDialog(context),
      child: Icon(
        Icons.settings_outlined,
        color: ThemeColorManager.getTextColor(),
        size: 20,
      ),
    );
  }

  // ===================== 主体内容 =====================

  Widget _buildBody(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLocalDeviceCard(context),
          const SizedBox(height: 12),
          _buildBluetoothCard(context),
          const SizedBox(height: 12),
          _buildDeviceListHeader(context),
          const SizedBox(height: 8),
          _buildDeviceList(context),
          const SizedBox(height: 16),
          _buildSceneCard(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// 本机设备卡片 - 修复 isCurrentSource 逻辑：使用 appState.isSource
  Widget _buildLocalDeviceCard(BuildContext context) {
    final appState = context.watch<AppState>();
    final network = context.watch<NetworkService>();

    return LiquidGlassCard(
      blurRadius: 16,
      padding: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    ThemeColorManager.getPrimaryColor(),
                    ThemeColorManager.getPrimaryColor().withOpacity(0.5),
                  ],
                ),
              ),
              child: Icon(
                // 修复：判断 appState.isSource 而非 currentSource?.deviceId == ...
                appState.isSource ? Icons.podcasts : Icons.headphones,
                color: Colors.white,
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
                        appState.deviceName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ThemeColorManager.getTextColor(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 修复：本机是否为音源由 appState.isSource 决定
                      if (appState.isSource)
                        _buildBadge('音源', ThemeColorManager.getPrimaryColor()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '本机IP: ${network.localIP}',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeColorManager.getSubTextColor(),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ThemeColorManager.getPrimaryColor().withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${appState.devices.length} 台在线',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ThemeColorManager.getPrimaryColor(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 蓝牙卡片 - 支持扫描、连接、断开
  Widget _buildBluetoothCard(BuildContext context) {
    final bluetooth = context.watch<BluetoothService>();
    final connected = bluetooth.connectedDevice;

    return LiquidGlassCard(
      blurRadius: 14,
      padding: 0,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: connected != null
              ? ThemeColorManager.getPrimaryColor().withOpacity(0.08)
              : ThemeColorManager.getSurfaceColor(),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: connected != null
                        ? ThemeColorManager.getPrimaryColor()
                        : ThemeColorManager.getSurfaceColor(),
                  ),
                  child: Icon(
                    connected != null
                        ? Icons.bluetooth_audio
                        : Icons.bluetooth_searching,
                    color: connected != null ? Colors.white : ThemeColorManager.getPrimaryColor(),
                    size: 20,
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
                            connected != null ? connected.name : '蓝牙设备',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ThemeColorManager.getTextColor(),
                            ),
                          ),
                          if (connected != null)
                            _buildBadge('已连接', const Color(0xff22c55e)),
                          if (bluetooth.isScanning)
                            _buildBadge('扫描中', ThemeColorManager.getPrimaryColor()),
                        ],
                      ),
                      if (connected != null)
                        Text(
                          '电量 ${connected.batteryLevel}% · ${connected.address}',
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColorManager.getSubTextColor(),
                          ),
                        ),
                      if (connected == null && !bluetooth.isScanning)
                        Text(
                          '点击扫描查找蓝牙设备',
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColorManager.getSubTextColor(),
                          ),
                        ),
                    ],
                  ),
                ),
                LiquidGlassButton(
                  onPressed: connected != null
                      ? () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await bluetooth.disconnect();
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('已断开蓝牙连接'),
                                backgroundColor: Colors.grey,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      : () {
                          bluetooth.startScan();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('正在扫描蓝牙设备...'),
                              backgroundColor: ThemeColorManager.getPrimaryColor(),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  child: Icon(
                    connected != null ? Icons.bluetooth_disabled : Icons.refresh,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (bluetooth.scannedDevices.isNotEmpty)
              _buildBluetoothDeviceList(context, bluetooth),
            if (bluetooth.pairedDevices.isNotEmpty && connected == null)
              _buildPairedDevicesList(context, bluetooth),
          ],
        ),
      ),
    );
  }

  /// 蓝牙扫描设备列表
  Widget _buildBluetoothDeviceList(BuildContext context, BluetoothService bluetooth) {
    return Column(
      children: [
        const SizedBox(height: 8),
        ...bluetooth.scannedDevices.map((device) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: ThemeColorManager.getSurfaceColor(),
                    ),
                    child: Center(
                      child: Text(
                        device.deviceType == BluetoothDeviceType.headphones
                            ? '🎧'
                            : device.deviceType == BluetoothDeviceType.speaker
                                ? '🔊'
                                : '📱',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: ThemeColorManager.getTextColor(),
                          ),
                        ),
                        Text(
                          '${device.address} · ${device.rssi != null ? '信号 ${device.rssi}dBm' : ''}${device.batteryLevel > 0 ? ' · 电量 ${device.batteryLevel}%' : ''}',
                          style: TextStyle(
                            fontSize: 10,
                            color: ThemeColorManager.getSubTextColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LiquidGlassButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await bluetooth.connect(device.address);
                      if (success && mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('已连接设备'),
                            backgroundColor: Color(0xff22c55e),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: Text(
                      '连接',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  /// 已配对蓝牙设备列表
  Widget _buildPairedDevicesList(BuildContext context, BluetoothService bluetooth) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '已配对设备',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ThemeColorManager.getSubTextColor(),
          ),
        ),
        const SizedBox(height: 4),
        ...bluetooth.pairedDevices.map((device) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: ThemeColorManager.getSurfaceColor(),
                    ),
                    child: Center(
                      child: Text(
                        device.deviceType == BluetoothDeviceType.headphones
                            ? '🎧'
                            : device.deviceType == BluetoothDeviceType.speaker
                                ? '🔊'
                                : '📱',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: ThemeColorManager.getTextColor(),
                          ),
                        ),
                        Text(
                          '${device.address} · 电量 ${device.batteryLevel}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: ThemeColorManager.getSubTextColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LiquidGlassButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await bluetooth.connect(device.address);
                      if (success && mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('已连接设备'),
                            backgroundColor: Color(0xff22c55e),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: Text(
                      '连接',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildDeviceListHeader(BuildContext context) {
    final network = context.read<NetworkService>();
    return Row(
      children: [
        Icon(Icons.devices, size: 18, color: ThemeColorManager.getSubTextColor()),
        const SizedBox(width: 6),
        Text(
          '已发现设备',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ThemeColorManager.getTextColor(),
          ),
        ),
        const Spacer(),
        LiquidGlassButton(
          onPressed: () {
            network.sendDiscover();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('正在搜索局域网设备...'),
                  backgroundColor: ThemeColorManager.getPrimaryColor(),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          child: const Icon(Icons.refresh, size: 18),
        ),
      ],
    );
  }

  Widget _buildDeviceList(BuildContext context) {
    final appState = context.watch<AppState>();
    final syncLatency = appState.syncLatencyMs;

    if (appState.devices.isEmpty) {
      return LiquidGlassCard(
        blurRadius: 12,
        padding: 0,
        child: Container(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(
                Icons.radar,
                size: 56,
                color: ThemeColorManager.getSubTextColor(),
              ),
              const SizedBox(height: 12),
              Text(
                '正在搜索局域网设备...',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: ThemeColorManager.getTextColor(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '请确保所有设备连接到同一 WiFi 网络',
                style: TextStyle(
                  fontSize: 12,
                  color: ThemeColorManager.getSubTextColor(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: appState.devices.map((device) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildDeviceCard(context, device, syncLatency),
        );
      }).toList(),
    );
  }

  /// 设备卡片 - 显示名称、平台、IP、延迟，支持连接控制
  Widget _buildDeviceCard(
      BuildContext context, DeviceInfo device, int syncLatency) {
    final appState = context.read<AppState>();
    final network = context.read<NetworkService>();
    final isCurrentSource = appState.isSource;

    return LiquidGlassCard(
      blurRadius: 12,
      padding: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: ThemeColorManager.getSurfaceColor(),
              ),
              child: Center(
                child: Text(
                  device.platformIcon,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.deviceName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: ThemeColorManager.getTextColor(),
                          ),
                        ),
                      ),
                      if (device.isSource) ...[
                        const SizedBox(width: 6),
                        _buildBadge('音源', ThemeColorManager.getPrimaryColor()),
                      ],
                      if (device.bluetoothConnected) ...[
                        const SizedBox(width: 6),
                        _buildBadge('蓝牙', const Color(0xff22c55e)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${device.platform} · ${device.ip}',
                        style: TextStyle(
                          fontSize: 11,
                          color: ThemeColorManager.getSubTextColor(),
                        ),
                      ),
                      if (device.capabilities.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        const Text('·'),
                        const SizedBox(width: 4),
                        Text(
                          device.capabilities.join(', '),
                          style: TextStyle(
                            fontSize: 11,
                            color: ThemeColorManager.getSubTextColor(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _getLatencyColor(syncLatency),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$syncLatency ms',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _getLatencyColor(syncLatency),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (!isCurrentSource && !device.isSource)
                  LiquidGlassButton(
                    onPressed: () {
                      network.sendSetSource(device.deviceId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已设置 ${device.deviceName} 为音源'),
                          backgroundColor: ThemeColorManager.getPrimaryColor(),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Text(
                      '设为音源',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColorManager.getTextColor(),
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

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }

  /// 场景卡片 - 显示当前场景并允许切换
  Widget _buildSceneCard(BuildContext context) {
    final sceneManager = context.watch<SceneAutoManager>();
    return LiquidGlassCard(
      blurRadius: 12,
      padding: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showSceneSwitchDialog(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.theaters,
                color: ThemeColorManager.getPrimaryColor(),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sceneManager.getSceneName(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                    Text(
                      '${sceneManager.getSceneDescription()} · 缓冲 ${sceneManager.bufferMs.toInt()}ms · 帧 ${sceneManager.frameMs}ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeColorManager.getSubTextColor(),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: ThemeColorManager.getSubTextColor(),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== 底部播放控制栏 =====================

  Widget _buildBottomBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: LiquidGlassCard(
        blurRadius: 20,
        padding: 0,
        hasShadow: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSyncIndicator(context),
              const SizedBox(height: 10),
              _buildPlaybackRow(context),
              const SizedBox(height: 8),
              _buildVolumeSlider(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 同步状态指示器 - 支持点击查看详情和手动同步
  Widget _buildSyncIndicator(BuildContext context) {
    final latency = context.select<AppState, int>((s) => s.syncLatencyMs);
    final bufferFrames =
        context.select<AppState, int>((s) => s.bufferFrames);
    final color = _getLatencyColor(latency);
    final network = context.read<NetworkService>();
    final sync = context.read<SyncService>();

    return InkWell(
      onTap: () => _showSyncDetailsDialog(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '同步中 · 延迟 ${latency}ms · 缓冲 $bufferFrames 帧',
            style: TextStyle(
              fontSize: 12,
              color: ThemeColorManager.getSubTextColor(),
            ),
          ),
          const SizedBox(width: 8),
          LiquidGlassButton(
            onPressed: () {
              network.sendSyncRequest(DateTime.now().millisecondsSinceEpoch);
              sync.reset();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('正在重新同步...'),
                    backgroundColor: ThemeColorManager.getPrimaryColor(),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Icon(Icons.sync, size: 16),
          ),
        ],
      ),
    );
  }

  /// 同步详情对话框
  void _showSyncDetailsDialog(BuildContext context) {
    final appState = context.read<AppState>();
    final stats = context.read<SyncService>().getStats();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: LiquidGlassCard(
          blurRadius: 20,
          padding: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync, color: ThemeColorManager.getPrimaryColor()),
                    const SizedBox(width: 8),
                    Text(
                      '同步状态详情',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStatRow('网络延迟', '${appState.syncLatencyMs} ms', _getLatencyColor(appState.syncLatencyMs)),
                _buildStatRow('缓冲帧数', '${appState.bufferFrames} 帧', ThemeColorManager.getPrimaryColor()),
                _buildStatRow('时钟偏移', '${appState.clockOffsetMs} ms', Colors.grey),
                _buildStatRow('播放状态', stats.isPlaying ? '播放中' : '已暂停', stats.isPlaying ? const Color(0xff22c55e) : Colors.grey),
                _buildStatRow('丢帧率', '${(stats.dropRate * 100).toStringAsFixed(1)}%', stats.dropRate > 0.1 ? const Color(0xfff97316) : const Color(0xff22c55e)),
                _buildStatRow('窗口大小', '${stats.windowMs} ms', ThemeColorManager.getPrimaryColor()),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    LiquidGlassButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('关闭', style: TextStyle(color: ThemeColorManager.getTextColor())),
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

  /// 统计行组件
  Widget _buildStatRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: ThemeColorManager.getSubTextColor()),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
      ),
    );
  }

  /// 播放/暂停按钮 - 音源端控制采集，接收端控制同步播放
  Widget _buildPlaybackRow(BuildContext context) {
    final appState = context.watch<AppState>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LiquidGlassButton(
          isActive: appState.isPlaying,
          activeColor: appState.isPlaying
              ? const Color(0xfffa5252)
              : ThemeColorManager.getPrimaryColor(),
          onPressed: () {
            final newPlaying = !appState.isPlaying;
            appState.setPlaying(newPlaying);
            if (appState.isSource) {
              final audio = context.read<AudioService>();
              if (newPlaying) {
                audio.startCapture();
              } else {
                audio.stopCapture();
              }
            } else {
              final sync = context.read<SyncService>();
              if (newPlaying) {
                sync.startPlaying();
              } else {
                sync.pausePlaying();
              }
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                appState.isPlaying ? Icons.stop : Icons.play_arrow,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                appState.isPlaying ? '停止' : '播放',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeSlider(BuildContext context) {
    final volume = context.select<AppState, int>((s) => s.volume);
    return Row(
      children: [
        Icon(
          Icons.volume_mute,
          size: 18,
          color: ThemeColorManager.getSubTextColor(),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: ThemeColorManager.getPrimaryColor(),
              inactiveTrackColor: Colors.white.withOpacity(0.15),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              min: 0,
              max: 100,
              value: volume.toDouble().clamp(0, 100),
              onChanged: (v) {
                final appState = context.read<AppState>();
                final audio = context.read<AudioService>();
                final network = context.read<NetworkService>();
                final rounded = v.round();
                appState.setVolume(rounded);
                audio.setVolume(rounded);
                network.sendVolumeSync(rounded);
              },
            ),
          ),
        ),
        Icon(
          Icons.volume_up,
          size: 18,
          color: ThemeColorManager.getSubTextColor(),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '$volume%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ThemeColorManager.getTextColor(),
            ),
          ),
        ),
      ],
    );
  }

  // ===================== 对话框 =====================

  /// 设置对话框 - 修复：设备名称 onChanged 调用 setDeviceName 而非 setRole
  void _showSettingsDialog(BuildContext context) {
    final appState = context.read<AppState>();
    final textController = TextEditingController(text: appState.deviceName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: LiquidGlassCard(
          blurRadius: 20,
          padding: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings,
                        color: ThemeColorManager.getPrimaryColor()),
                    const SizedBox(width: 8),
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: textController,
                  decoration: InputDecoration(
                    labelText: '设备名称',
                    hintText: '例如: PC-客厅',
                    labelStyle:
                        TextStyle(color: ThemeColorManager.getSubTextColor()),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: ThemeColorManager.getBorderColor()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: ThemeColorManager.getPrimaryColor()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  // 修复：调用 setDeviceName 而非 setRole
                  onChanged: (v) => appState.setDeviceName(v),
                  style: TextStyle(color: ThemeColorManager.getTextColor()),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '深色模式',
                      style:
                          TextStyle(color: ThemeColorManager.getTextColor()),
                    ),
                    const Spacer(),
                    Switch(
                      value: appState.themeMode == ThemeMode.dark,
                      onChanged: (v) {
                        appState.setThemeMode(
                            v ? ThemeMode.dark : ThemeMode.light);
                      },
                      activeColor: ThemeColorManager.getPrimaryColor(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    LiquidGlassButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('取消',
                          style: TextStyle(
                              color: ThemeColorManager.getTextColor())),
                    ),
                    const SizedBox(width: 8),
                    LiquidGlassButton(
                      isActive: true,
                      activeColor: ThemeColorManager.getPrimaryColor(),
                      onPressed: () {
                        appState.saveSettings();
                        Navigator.pop(ctx);
                      },
                      child: const Text('保存',
                          style: TextStyle(color: Colors.white)),
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

  /// 场景切换对话框
  void _showSceneSwitchDialog(BuildContext context) {
    final sceneManager = context.read<SceneAutoManager>();
    final scenes = [
      {'mode': SceneMode.music, 'name': '音乐模式', 'desc': '高音质 AAC 192kbps'},
      {'mode': SceneMode.video, 'name': '观影模式', 'desc': '音画同步 45ms缓冲'},
      {'mode': SceneMode.game, 'name': '游戏模式', 'desc': '超低延迟 OPUS 10ms'},
      {'mode': SceneMode.room, 'name': '全屋播放', 'desc': '多设备同步'},
      {'mode': SceneMode.weakNet, 'name': '弱网模式', 'desc': '自适应降级'},
      {'mode': SceneMode.night, 'name': '夜间模式', 'desc': '平滑渐变'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: LiquidGlassCard(
          blurRadius: 20,
          padding: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.theaters,
                        color: ThemeColorManager.getPrimaryColor()),
                    const SizedBox(width: 8),
                    Text(
                      '场景切换',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: scenes.map((scene) {
                    final mode = scene['mode'] as SceneMode;
                    final isActive = sceneManager.currentScene == mode;
                    return LiquidGlassButton(
                      isActive: isActive,
                      activeColor: ThemeColorManager.getPrimaryColor(),
                      onPressed: () {
                        sceneManager.applyScene(mode);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        children: [
                          Text(
                            scene['name'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(
                            scene['desc'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: LiquidGlassButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('取消',
                        style: TextStyle(
                            color: ThemeColorManager.getTextColor())),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===================== 工具方法 =====================

  Color _getLatencyColor(int latency) {
    if (latency < 30) return const Color(0xff52c41a);
    if (latency < 80) return const Color(0xfffa8c16);
    return const Color(0xfffa5252);
  }
}
