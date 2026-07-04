import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import 'core/models.dart';
import 'core/theme_manager.dart';
import 'core/scene_manager.dart';
import 'services/audio_service.dart';
import 'services/network_service.dart';
import 'services/bluetooth_service.dart';
import 'services/sync_service.dart';
import 'screens/home_screen.dart';

Process? _backendProcess;
_AppLifecycleObserver? _lifecycleObserver;

/// 启动 Go 后端 - 仅 Windows/Linux 桌面端
Future<void> _startBackend() async {
  if (kIsWeb) return;

  String backendPath;
  if (Platform.isWindows) {
    backendPath = Platform.resolvedExecutable
        .replaceAll('fy_audio_player.exe', 'fy_audio_backend.exe');
  } else if (Platform.isLinux) {
    backendPath = Platform.resolvedExecutable
        .replaceAll('/fy_audio_player', '/fy_audio_backend');
  } else {
    debugPrint('[Backend] 仅支持 Windows/Linux 平台，跳过后端启动');
    return;
  }

  if (await File(backendPath).exists()) {
    try {
      _backendProcess = await Process.start(
        backendPath,
        [],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      debugPrint('[Backend] 已启动: $backendPath (pid=${_backendProcess!.pid})');
    } catch (e) {
      debugPrint('[Backend] 启动失败: $e');
    }
  } else {
    debugPrint('[Backend] 未找到后端可执行文件: $backendPath');
  }
}

/// 停止 Go 后端
void _stopBackend() {
  if (_backendProcess != null) {
    try {
      _backendProcess!.kill();
      debugPrint('[Backend] 已停止');
    } catch (e) {
      debugPrint('[Backend] 停止失败: $e');
    }
    _backendProcess = null;
  }
}

/// 初始化桌面窗口 - 使用 window_manager 创建 WindowOptions
Future<void> _initDesktopWindow() async {
  // 修复 Platform.isLinux 在 Web 抛异常 - 改为 !kIsWeb && (...)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    try {
      await windowManager.ensureInitialized();

      // 使用 WindowOptions 对象（不是 Map）
      const windowOptions = WindowOptions(
        size: Size(960, 680),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        title: 'FyAudio - Multi-device Sync',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('[Window] 桌面窗口初始化失败: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await _startBackend();
  }

  // 修复：原代码 Platform.isLinux 在 Web 抛异常，且条件判断有括号错误
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    await _initDesktopWindow();
  }

  // 添加生命周期观察者，并保留引用以便后续 removeObserver
  _lifecycleObserver = _AppLifecycleObserver();
  WidgetsBinding.instance.addObserver(_lifecycleObserver!);

  runApp(const FyAudioApp());
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _stopBackend();
      // 修复：添加 removeObserver 避免泄漏
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}

class FyAudioApp extends StatelessWidget {
  const FyAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider.value(value: ThemeManager.instance),
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProvider(create: (_) => BluetoothService()),
        ChangeNotifierProvider(create: (_) => SyncService()),
        ChangeNotifierProvider(create: (_) => SceneAutoManager()),
      ],
      // 使用 Consumer<ThemeManager> 让主题变化时整树重建
      child: Consumer<ThemeManager>(
        builder: (context, themeManager, _) {
          final colors = themeManager.colors;
          return MaterialApp(
            title: 'FyAudio',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: colors.primaryColor,
                brightness: colors.brightness,
              ),
              fontFamily: 'Microsoft YaHei',
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

/// 全局应用状态
///
/// 修复要点：
/// - [setDeviceName] 单独设置设备名称；
/// - [setRole] 切换角色后调用 [saveSettings] 持久化；
/// - [updateSyncStats] 区分 latencyMs / bufferFrames / clockOffsetMs，不再互相覆盖；
/// - [ThemeMode] 索引读取时做越界校验；
/// - 设备名称根据平台动态获取。
class AppState extends ChangeNotifier {
  String _deviceId = '';
  String _deviceName = '';
  String _role = 'receiver';
  bool _isSource = false;
  bool _isPlaying = false;
  int _volume = 80;
  int _manualOffsetMs = 0;
  int _syncLatencyMs = 0;
  int _clockOffsetMs = 0;  // 时钟偏移，由 SyncService 更新
  int _bufferFrames = 0;
  ThemeMode _themeMode = ThemeMode.system;
  final List<DeviceInfo> _devices = [];

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get role => _role;
  bool get isSource => _isSource;
  bool get isPlaying => _isPlaying;
  int get volume => _volume;
  int get manualOffsetMs => _manualOffsetMs;
  int get syncLatencyMs => _syncLatencyMs;
  int get clockOffsetMs => _clockOffsetMs;
  int get bufferFrames => _bufferFrames;
  ThemeMode get themeMode => _themeMode;
  List<DeviceInfo> get devices => List.unmodifiable(_devices);

  List<DeviceInfo> get sources => _devices.where((d) => d.isSource).toList();
  List<DeviceInfo> get receivers =>
      _devices.where((d) => !d.isSource).toList();
  DeviceInfo? get currentSource {
    try {
      return _devices.firstWhere((d) => d.isSource);
    } catch (_) {
      return null;
    }
  }

  AppState() {
    _init();
  }

  Future<void> _init() async {
    const uuid = Uuid();
    _deviceId = 'FY-${uuid.v4().substring(0, 12).toUpperCase()}';

    final prefs = await SharedPreferences.getInstance();
    _deviceName = prefs.getString('device_name') ?? _getDefaultDeviceName();
    _volume = prefs.getInt('volume') ?? 80;
    _manualOffsetMs = prefs.getInt('manual_offset') ?? 0;
    // 修复 ThemeMode 索引越界校验
    final themeIdx = prefs.getInt('theme_mode') ?? 0;
    _themeMode = (themeIdx >= 0 && themeIdx < ThemeMode.values.length)
        ? ThemeMode.values[themeIdx]
        : ThemeMode.system;
    notifyListeners();
  }

  /// 设备名称根据平台动态获取
  String _getDefaultDeviceName() {
    if (kIsWeb) return 'Web 设备';
    if (Platform.isWindows) return 'Windows 主机';
    if (Platform.isAndroid) return 'Android 设备';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isLinux) return 'Linux 设备';
    if (Platform.isMacOS) return 'Mac 设备';
    return 'FyAudio 设备';
  }

  /// 设置设备名称
  void setDeviceName(String name) {
    _deviceName = name;
    notifyListeners();
  }

  /// 设置角色 - 切换后持久化
  void setRole(String role) {
    _role = role;
    _isSource = role == 'source';
    notifyListeners();
    saveSettings();
  }

  void setPlaying(bool playing) {
    _isPlaying = playing;
    notifyListeners();
  }

  void setVolume(int vol) {
    _volume = vol.clamp(0, 100);
    notifyListeners();
  }

  void setManualOffset(int offsetMs) {
    _manualOffsetMs = offsetMs.clamp(-200, 200);
    notifyListeners();
  }

  /// 更新同步统计 - 修复参数语义冲突
  ///
  /// 原实现中 latencyMs 与 offsetMs 都写入 _syncLatencyMs 导致互相覆盖；
  /// 现拆分为：
  /// - [latencyMs] → _syncLatencyMs（网络延迟估算）
  /// - [bufferFrames] → _bufferFrames（缓冲帧数）
  /// - [clockOffsetMs] → _clockOffsetMs（时钟偏移，由 SyncService 内部使用）
  void updateSyncStats({
    int? latencyMs,
    int? bufferFrames,
    int? clockOffsetMs,
  }) {
    if (latencyMs != null) _syncLatencyMs = latencyMs;
    if (bufferFrames != null) _bufferFrames = bufferFrames;
    if (clockOffsetMs != null) _clockOffsetMs = clockOffsetMs;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void addDevice(DeviceInfo device) {
    final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (idx >= 0) {
      _devices[idx] = device;
    } else {
      _devices.add(device);
    }
    notifyListeners();
  }

  void removeDevice(String deviceId) {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    notifyListeners();
  }

  void clearDevices() {
    _devices.clear();
    notifyListeners();
  }

  /// 持久化设置
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', _deviceName);
    await prefs.setInt('volume', _volume);
    await prefs.setInt('manual_offset', _manualOffsetMs);
    await prefs.setInt('theme_mode', _themeMode.index);
  }
}
