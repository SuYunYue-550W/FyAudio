import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'core/models.dart';
import 'core/theme_manager.dart';
import 'core/scene_manager.dart';
import 'services/audio_service.dart';
import 'services/network_service.dart';
import 'services/bluetooth_service.dart';
import 'services/sync_service.dart';
import 'screens/home_screen.dart';

Process? _backendProcess;

Future<void> _startBackend() async {
  if (!kIsWeb) {
    String backendPath;
    if (Platform.isWindows) {
      backendPath = Platform.resolvedExecutable.replaceAll('fy_audio_player.exe', 'fy_audio_backend.exe');
    } else if (Platform.isLinux) {
      backendPath = Platform.resolvedExecutable.replaceAll('/fy_audio_player', '/fy_audio_backend');
    } else {
      debugPrint('[Backend] Backend only supported on Windows/Linux');
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
        debugPrint('[Backend] Started: $backendPath');
      } catch (e) {
        debugPrint('[Backend] Failed to start: $e');
      }
    } else {
      debugPrint('[Backend] Not found: $backendPath');
    }
  }
}

void _stopBackend() {
  if (_backendProcess != null) {
    try {
      _backendProcess!.kill();
      debugPrint('[Backend] Stopped');
    } catch (e) {
      debugPrint('[Backend] Failed to stop: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await _startBackend();
  }

  if ((!kIsWeb && Platform.isWindows) || Platform.isLinux) {
    try {
      await _initDesktopWindow();
    } catch (e) {
      debugPrint('[Window] Desktop init error: $e');
    }
  }

  runApp(const FyAudioApp());

  WidgetsBinding.instance.addObserver(
    _AppLifecycleObserver(),
  );
}

Future<void> _initDesktopWindow() async {
  try {
    if (Platform.isWindows || Platform.isLinux) {
      await _setupWindowManager();
    }
  } catch (e) {
    debugPrint('[Window] Desktop init failed: $e');
  }
}

Future<void> _setupWindowManager() async {
  try {
    dynamic windowManager;
    try {
      windowManager = await _loadWindowManager();
      if (windowManager != null) {
        await windowManager.ensureInitialized();
        
        final windowOptions = {
          'size': {'width': 960.0, 'height': 680.0},
          'minimumSize': {'width': 800.0, 'height': 600.0},
          'center': true,
          'backgroundColor': Colors.transparent.value,
          'skipTaskbar': false,
          'titleBarStyle': 0,
          'title': 'FyAudio - Multi-device Sync',
        };
        
        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }
    } catch (e) {
      debugPrint('[Window] WindowManager setup failed: $e');
    }
  } catch (e) {
    debugPrint('[Window] Window setup failed: $e');
  }
}

Future<dynamic> _loadWindowManager() async {
  return null;
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _stopBackend();
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
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => NetworkService()),
        ChangeNotifierProvider(create: (_) => BluetoothService()),
        ChangeNotifierProvider(create: (_) => SyncService()),
        ChangeNotifierProvider(create: (_) => SceneAutoManager()),
      ],
      child: MaterialApp(
        title: 'FyAudio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: ThemeColorManager.getPrimaryColor(),
            brightness: ThemeColorManager.getBrightness(),
          ),
          fontFamily: 'Microsoft YaHei',
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeColorManager.getPrimaryColor(),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  String _deviceId = '';
  String _deviceName = 'Windows主机';
  String _role = 'receiver';
  bool _isSource = false;
  bool _isPlaying = false;
  int _volume = 80;
  int _manualOffsetMs = 0;
  int _syncLatencyMs = 0;
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
  int get bufferFrames => _bufferFrames;
  ThemeMode get themeMode => _themeMode;
  List<DeviceInfo> get devices => List.unmodifiable(_devices);

  List<DeviceInfo> get sources => _devices.where((d) => d.isSource).toList();
  List<DeviceInfo> get receivers => _devices.where((d) => !d.isSource).toList();
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
    _themeMode = ThemeMode.values[prefs.getInt('theme_mode') ?? 0];
    notifyListeners();
  }

  String _getDefaultDeviceName() {
    if (Platform.isWindows) return 'Windows主机';
    if (Platform.isAndroid) return 'Android设备';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isLinux) return 'Linux设备';
    return '设备';
  }

  void setRole(String role) {
    _role = role;
    _isSource = role == 'source';
    notifyListeners();
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

  void updateSyncStats({int? latencyMs, int? frames, int? offsetMs}) {
    if (latencyMs != null) _syncLatencyMs = latencyMs;
    if (frames != null) _bufferFrames = frames;
    if (offsetMs != null) _syncLatencyMs = offsetMs;
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

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', _deviceName);
    await prefs.setInt('volume', _volume);
    await prefs.setInt('manual_offset', _manualOffsetMs);
    await prefs.setInt('theme_mode', _themeMode.index);
  }
}