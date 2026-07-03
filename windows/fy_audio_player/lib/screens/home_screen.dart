import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/audio_service.dart';
import '../services/network_service.dart';
import '../services/bluetooth_service.dart';
import '../services/sync_service.dart';
import '../core/theme_manager.dart';
import '../core/scene_manager.dart';
import '../core/codec_manager.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/glass_hover_animate.dart';
import '../widgets/audio_particles.dart';
import '../widgets/device_item_card.dart';
import '../widgets/audio_control_panel.dart';
import '../widgets/theme_switch_page.dart';
import '../widgets/audio_waveform.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _initialized = false;
  final FrontCodecManager _codecManager = FrontCodecManager();
  double _audioVolume = 0.3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final appState = context.read<AppState>();
    final network = context.read<NetworkService>();
    final audio = context.read<AudioService>();
    final bluetooth = context.read<BluetoothService>();
    final sync = context.read<SyncService>();
    final sceneManager = context.read<SceneAutoManager>();

    await network.initialize(
      deviceId: appState.deviceId,
      deviceName: appState.deviceName,
      role: appState.role,
    );

    network.onDeviceOnline = (device) {
      appState.addDevice(device);
    };
    network.onDeviceOffline = (id) {
      appState.removeDevice(id);
    };

    sync.onPlayableFrame = (frame) {
      audio.playFrame(frame);
    };

    network.onVolumeSync = (vol) {
      appState.setVolume(vol);
      audio.setVolume(vol);
    };

    await network.start();

    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sceneManager = context.watch<SceneAutoManager>();
    _codecManager.matchSceneCodec(sceneManager.currentScene);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AudioParticleBackground(
        volume: _audioVolume,
        sceneMode: sceneManager.currentScene,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: ThemeColorManager.getBgGradient(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              _buildCustomAppBar(context),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDevicesTab(context),
                    _buildPlaybackTab(context),
                    _buildBluetoothTab(context),
                    _buildSyncTab(context),
                    _buildThemeTab(context),
                  ],
                ),
              ),
              _buildCustomTabBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar(BuildContext context) {
    final appState = context.watch<AppState>();
    final sceneManager = context.watch<SceneAutoManager>();

    return LiquidGlassCard(
      blurRadius: 20,
      padding: 0,
      hasShadow: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        ThemeColorManager.getPrimaryColor(),
                        ThemeColorManager.getPrimaryColor().withOpacity(0.6),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.speaker_group,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FyAudio',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                    Text(
                      sceneManager.getSceneName(),
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeColorManager.getSubTextColor(),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _buildRoleSwitcher(appState),
                const SizedBox(width: 16),
                _buildSettingsButton(),
              ],
            ),
            const SizedBox(height: 8),
            _buildSceneIndicator(sceneManager),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSwitcher(AppState appState) {
    return LiquidGlassButton(
      isActive: appState.isSource,
      onPressed: () {
        appState.setRole(appState.isSource ? 'receiver' : 'source');
        context.read<NetworkService>().updateRole(appState.role);
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

  Widget _buildSettingsButton() {
    return LiquidGlassButton(
      onPressed: () => _showSettingsDialog(context),
      child: const Icon(
        Icons.settings_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildSceneIndicator(SceneAutoManager sceneManager) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ThemeColorManager.getPrimaryColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: ThemeColorManager.getPrimaryColor(),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${sceneManager.getSceneName()} · ${sceneManager.bitRate}kbps · ${sceneManager.bufferMs}ms缓冲',
            style: TextStyle(
              fontSize: 11,
              color: ThemeColorManager.getSubTextColor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTabBar() {
    final tabs = [
      {'icon': Icons.devices, 'label': '设备'},
      {'icon': Icons.music_note, 'label': '播放'},
      {'icon': Icons.bluetooth, 'label': '蓝牙'},
      {'icon': Icons.tune, 'label': '同步'},
      {'icon': Icons.palette, 'label': '主题'},
    ];

    return LiquidGlassCard(
      blurRadius: 20,
      padding: 0,
      hasShadow: true,
      child: TabBar(
        controller: _tabController,
        tabs: tabs.map((tab) {
          return Tab(
            icon: Icon(
              tab['icon'] as IconData,
              size: 20,
            ),
            text: tab['label'] as String,
          );
        }).toList(),
        labelColor: ThemeColorManager.getPrimaryColor(),
        unselectedLabelColor: ThemeColorManager.getSubTextColor(),
        indicator: BoxDecoration(
          color: ThemeColorManager.getPrimaryColor().withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _buildDevicesTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final network = context.watch<NetworkService>();

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassHoverAnimate(
            child: LiquidGlassCard(
              blurRadius: 16,
              padding: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            ThemeColorManager.getPrimaryColor(),
                            ThemeColorManager.getPrimaryColor().withOpacity(0.5),
                          ],
                        ),
                      ),
                      child: Icon(
                        appState.isSource
                            ? Icons.podcasts
                            : Icons.headphones,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appState.isSource
                                ? '🎙️ 正在播放音源'
                                : '🎧 正在接收音频',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: ThemeColorManager.getTextColor(),
                            ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: ThemeColorManager.getPrimaryColor().withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${appState.devices.length} 台设备',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: ThemeColorManager.getPrimaryColor(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (appState.devices.isEmpty)
            LiquidGlassCard(
              blurRadius: 12,
              padding: 0,
              child: Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.radar,
                      size: 64,
                      color: ThemeColorManager.getSubTextColor(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '正在搜索局域网设备...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: ThemeColorManager.getTextColor(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '确保所有设备在同一WiFi网络',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeColorManager.getSubTextColor(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final device in appState.devices)
            Column(
              children: [
                DeviceItemCard(
                  device: device,
                  status: DeviceStatus.online,
                  isMaster: appState.currentSource?.deviceId == device.deviceId,
                  onTap: appState.isSource && appState.currentSource?.deviceId != device.deviceId
                      ? () {
                          context.read<NetworkService>().sendSetSource(
                                device.deviceId,
                                device.deviceName,
                              );
                        }
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildPlaybackTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final audio = context.watch<AudioService>();
    final sceneManager = context.watch<SceneAutoManager>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassHoverAnimate(
            child: LiquidGlassCard(
              blurRadius: 16,
              padding: 0,
              child: Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                child: AudioWaveform(
                  isActive: audio.isPlaying || audio.isCapturing,
                  frameCount: audio.capturedFrames + audio.playedFrames,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AudioControlPanel(
            volume: appState.volume.toDouble(),
            currentScene: sceneManager.currentScene,
            codecName: _codecManager.getCodecName(),
            onVolumeChange: (v) {
              appState.setVolume(v.round());
              audio.setVolume(v.round());
            },
            onSceneTap: () => _showSceneSwitchDialog(context),
          ),
          const SizedBox(height: 16),
          LiquidGlassCard(
            blurRadius: 14,
            padding: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '实时统计',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ThemeColorManager.getTextColor(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatCard(
                        label: '采集帧',
                        value: '${audio.capturedFrames}',
                        icon: Icons.mic,
                        color: ThemeColorManager.getPrimaryColor(),
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '播放帧',
                        value: '${audio.playedFrames}',
                        icon: Icons.play_arrow,
                        color: const Color(0xff52c41a),
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '缓冲帧',
                        value: '${context.watch<SyncService>().bufferSize}',
                        icon: Icons.memory,
                        color: const Color(0xfffa8c16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (appState.isSource)
            GlassHoverAnimate(
              child: LiquidGlassButton(
                isActive: appState.isPlaying,
                activeColor: appState.isPlaying
                    ? const Color(0xfffa5252)
                    : ThemeColorManager.getPrimaryColor(),
                onPressed: () {
                  appState.setPlaying(!appState.isPlaying);
                  final audioService = context.read<AudioService>();
                  if (appState.isPlaying) {
                    audioService.startCapture();
                  } else {
                    audioService.stopCapture();
                  }
                },
                child: Text(
                  appState.isPlaying ? '⏹️ 停止播放' : '▶️ 开始播放',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildBluetoothTab(BuildContext context) {
    final bluetooth = context.watch<BluetoothService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LiquidGlassCard(
            blurRadius: 14,
            padding: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.bluetooth,
                    color: bluetooth.isEnabled
                        ? ThemeColorManager.getPrimaryColor()
                        : ThemeColorManager.getSubTextColor(),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '蓝牙开关',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: ThemeColorManager.getTextColor(),
                          ),
                        ),
                        Text(
                          bluetooth.isEnabled ? '蓝牙已启用' : '蓝牙已禁用',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeColorManager.getSubTextColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: bluetooth.isEnabled,
                    onChanged: (v) {
                      if (v) {
                        bluetooth.enable();
                      } else {
                        bluetooth.disable();
                      }
                    },
                    activeColor: ThemeColorManager.getPrimaryColor(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (bluetooth.connectedDevice != null)
            GlassHoverAnimate(
              child: LiquidGlassCard(
                blurRadius: 14,
                padding: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ThemeColorManager.getPrimaryColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: ThemeColorManager.getPrimaryColor(),
                        ),
                        child: const Icon(Icons.speaker, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bluetooth.connectedDevice!.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: ThemeColorManager.getTextColor(),
                              ),
                            ),
                            Text(
                              '已连接',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xff52c41a),
                              ),
                            ),
                          ],
                        ),
                      ),
                      LiquidGlassButton(
                        onPressed: bluetooth.disconnect,
                        child: const Icon(
                          Icons.bluetooth_disabled,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          LiquidGlassButton(
            isActive: bluetooth.isScanning,
            onPressed: bluetooth.isScanning
                ? bluetooth.stopScan
                : () => bluetooth.startScan(),
            child: Text(
              bluetooth.isScanning ? '🔍 扫描中...' : '🔍 扫描蓝牙设备',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (bluetooth.pairedDevices.isNotEmpty)
            ...bluetooth.pairedDevices.map((device) => LiquidGlassCard(
                  blurRadius: 12,
                  padding: 0,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bluetooth_audio,
                          color: ThemeColorManager.getSubTextColor(),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: ThemeColorManager.getTextColor(),
                                ),
                              ),
                              Text(
                                device.address,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ThemeColorManager.getSubTextColor(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        device.connected
                            ? const Icon(Icons.check_circle, color: Color(0xff52c41a))
                            : LiquidGlassButton(
                                onPressed: () =>
                                    bluetooth.connect(device.address),
                                child: const Text(
                                  '连接',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: 16),
          LiquidGlassCard(
            blurRadius: 12,
            padding: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '蓝牙说明',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ThemeColorManager.getTextColor(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 蓝牙用于本地音频输出，不做跨设备传输',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeColorManager.getSubTextColor(),
                    ),
                  ),
                  Text(
                    '• 建议使用支持 A2DP 的蓝牙音响',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeColorManager.getSubTextColor(),
                    ),
                  ),
                  Text(
                    '• 多个音响建议使用树莓派网关方案',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeColorManager.getSubTextColor(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSyncTab(BuildContext context) {
    final appState = context.watch<AppState>();
    final sync = context.watch<SyncService>();
    final stats = sync.stats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassHoverAnimate(
            child: LiquidGlassCard(
              blurRadius: 16,
              padding: 0,
              child: Container(
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
                            color: _getStatusColor(stats.estimatedRTT),
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    _getStatusColor(stats.estimatedRTT).withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          stats.isPlaying ? '同步播放中' : '等待音频流',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: ThemeColorManager.getTextColor(),
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
                          value: '${stats.estimatedRTT}ms',
                          color: _getStatusColor(stats.estimatedRTT),
                        ),
                        _MetricChip(
                          label: '时钟补偿',
                          value: '${stats.offsetMs}ms',
                          color: stats.offsetMs.abs() < 50
                              ? const Color(0xff52c41a)
                              : const Color(0xfffa8c16),
                        ),
                        _MetricChip(
                          label: '缓冲',
                          value: '${stats.bufferFrames} 帧',
                          color: ThemeColorManager.getPrimaryColor(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: stats.bufferFrames / 200,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(
                            ThemeColorManager.getPrimaryColor()),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '缓冲占用: ${(stats.bufferFrames / 200 * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeColorManager.getSubTextColor(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LiquidGlassCard(
            blurRadius: 14,
            padding: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune,
                        color: ThemeColorManager.getPrimaryColor(),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '手动延迟补偿',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: ThemeColorManager.getTextColor(),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              ThemeColorManager.getPrimaryColor().withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${appState.manualOffsetMs}ms',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: ThemeColorManager.getPrimaryColor(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '调整以补偿不同蓝牙音响的硬件延迟',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeColorManager.getSubTextColor(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        '-200ms',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 6,
                            activeTrackColor:
                                ThemeColorManager.getPrimaryColor(),
                            inactiveTrackColor: Colors.white.withOpacity(0.15),
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: appState.manualOffsetMs.toDouble(),
                            min: -200,
                            max: 200,
                            onChanged: (v) {
                              appState.setManualOffset(v.round());
                              sync.setManualOffset(v.round());
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '+200ms',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      LiquidGlassButton(
                        onPressed: () => appState.setManualOffset(
                            appState.manualOffsetMs - 10),
                        child: const Text('-10ms',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      LiquidGlassButton(
                        onPressed: () => appState.setManualOffset(0),
                        child: const Text('归零',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      LiquidGlassButton(
                        onPressed: () => appState.setManualOffset(
                            appState.manualOffsetMs + 10),
                        child: const Text('+10ms',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LiquidGlassCard(
            blurRadius: 14,
            padding: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '缓冲状态',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ThemeColorManager.getTextColor(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatCard(
                        label: '缓冲帧',
                        value: '${stats.bufferFrames}',
                        icon: Icons.memory,
                        color: ThemeColorManager.getPrimaryColor(),
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: 'RTT估算',
                        value: '${stats.estimatedRTT}ms',
                        icon: Icons.speed,
                        color: const Color(0xff1890ff),
                      ),
                      const SizedBox(width: 8),
                      _StatCard(
                        label: '缓冲窗口',
                        value: '${stats.windowMs}ms',
                        icon: Icons.timer,
                        color: const Color(0xfffa8c16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LiquidGlassButton(
            onPressed: () {
              sync.reset();
              appState.setManualOffset(0);
            },
            child: const Text(
              '🔄 重置同步状态',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildThemeTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ThemeSwitchPage(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Color _getStatusColor(int latency) {
    if (latency < 30) return const Color(0xff52c41a);
    if (latency < 80) return const Color(0xfffa8c16);
    return const Color(0xfffa5252);
  }

  void _showSettingsDialog(BuildContext context) {
    final appState = context.read<AppState>();

    showDialog(
      context: context,
      builder: (ctx) => LiquidGlassCard(
        blurRadius: 20,
        padding: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.settings, color: ThemeColorManager.getPrimaryColor()),
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
                decoration: InputDecoration(
                  labelText: '设备名称',
                  hintText: '例如: PC-客厅',
                  labelStyle: TextStyle(color: ThemeColorManager.getSubTextColor()),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: ThemeColorManager.getBorderColor()),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: ThemeColorManager.getPrimaryColor()),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                controller: TextEditingController(text: appState.deviceName),
                onChanged: (v) => appState.setRole(v),
                style: TextStyle(color: ThemeColorManager.getTextColor()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '深色模式',
                    style: TextStyle(color: ThemeColorManager.getTextColor()),
                  ),
                  const Spacer(),
                  Switch(
                    value: appState.themeMode == ThemeMode.dark,
                    onChanged: (v) {
                      appState.setThemeMode(v ? ThemeMode.dark : ThemeMode.light);
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
                    child: const Text('取消', style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  LiquidGlassButton(
                    isActive: true,
                    onPressed: () {
                      appState.saveSettings();
                      Navigator.pop(ctx);
                    },
                    child: const Text('保存', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      builder: (ctx) => LiquidGlassCard(
        blurRadius: 20,
        padding: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.theaters,
                    color: ThemeColorManager.getPrimaryColor(),
                  ),
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
                            color: isActive ? Colors.white : Colors.white,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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
              LiquidGlassButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2), width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10, color: ThemeColorManager.getSubTextColor()),
            ),
          ],
        ),
      ),
    );
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
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: ThemeColorManager.getSubTextColor(),
          ),
        ),
      ],
    );
  }
}