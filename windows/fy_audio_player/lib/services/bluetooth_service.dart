import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

/// 蓝牙服务。
///
/// 平台策略：
/// - Android/iOS/鸿蒙：使用模拟模式
/// - Windows/Linux/macOS：计划使用 flutter_blue_plus（条件导入，待集成，暂回退模拟）
///
/// [\_useMockMode] 根据 [Platform] 判断，不再硬编码。
class BluetoothService extends ChangeNotifier {
  bool _isEnabled = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  final List<BluetoothDeviceInfo> _pairedDevices = [];
  final List<BluetoothDeviceInfo> _scannedDevices = [];
  BluetoothDeviceInfo? _connectedDevice;
  int _volume = 80;

  Timer? _reconnectTimer;
  Timer? _scanTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  String? _reconnectAddress;

  /// 模拟模式：根据 Platform 判断。
  /// 移动端使用模拟；桌面端待集成 flutter_blue_plus 后切换为真实模式。
  final bool _useMockMode = _detectMockMode();

  static bool _detectMockMode() {
    // Android/iOS/鸿蒙 使用模拟模式
    // Windows/Linux/macOS 计划使用 flutter_blue_plus（待集成，暂回退模拟）
    return Platform.isAndroid || Platform.isIOS;
  }

  Function()? onConnected;
  Function()? onDisconnected;

  bool get isEnabled => _isEnabled;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get useMockMode => _useMockMode;
  bool get isSupported => true;
  List<BluetoothDeviceInfo> get pairedDevices =>
      List.unmodifiable(_pairedDevices);
  List<BluetoothDeviceInfo> get scannedDevices =>
      List.unmodifiable(_scannedDevices);
  BluetoothDeviceInfo? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;
  int get volume => _volume;

  BluetoothService() {
    _init();
  }

  Future<void> _init() async {
    debugPrint(
        '[Bluetooth] 蓝牙服务初始化 (mock=$_useMockMode, platform=${Platform.operatingSystem})');
    _loadMockDevices();
    _isEnabled = true;
    notifyListeners();
  }

  void _loadMockDevices() {
    _pairedDevices.addAll([
      BluetoothDeviceInfo(
        name: 'Sony WH-1000XM5',
        address: 'AA:BB:CC:DD:EE:01',
        connected: false,
        rssi: -45,
        batteryLevel: 85,
        deviceType: BluetoothDeviceType.headphones,
      ),
      BluetoothDeviceInfo(
        name: 'JBL Flip 6',
        address: 'AA:BB:CC:DD:EE:02',
        connected: false,
        rssi: -55,
        batteryLevel: 60,
        deviceType: BluetoothDeviceType.speaker,
      ),
      BluetoothDeviceInfo(
        name: 'AirPods Pro 2',
        address: 'AA:BB:CC:DD:EE:03',
        connected: false,
        rssi: -35,
        batteryLevel: 95,
        deviceType: BluetoothDeviceType.headphones,
      ),
    ]);
  }

  // =========================================================================
  // 启用 / 禁用
  // =========================================================================

  Future<void> enable() async {
    _isEnabled = true;
    notifyListeners();
    debugPrint('[Bluetooth] 蓝牙已启用');
  }

  Future<void> disable() async {
    _isEnabled = false;
    if (_connectedDevice != null) {
      await disconnect();
    }
    notifyListeners();
    debugPrint('[Bluetooth] 蓝牙已禁用');
  }

  // =========================================================================
  // 扫描
  // =========================================================================

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isScanning) return;

    _isScanning = true;
    _scannedDevices.clear();
    notifyListeners();

    debugPrint('[Bluetooth] 开始扫描...');

    _simulateScanResults();
    _scanTimer = Timer(timeout, () {
      stopScan();
    });
  }

  void _simulateScanResults() {
    _scannedDevices.addAll([
      BluetoothDeviceInfo(
        name: 'Bose QuietComfort',
        address: 'AA:BB:CC:DD:FF:01',
        connected: false,
        rssi: -60,
        batteryLevel: 70,
        deviceType: BluetoothDeviceType.headphones,
      ),
      BluetoothDeviceInfo(
        name: 'Samsung Soundbar',
        address: 'AA:BB:CC:DD:FF:02',
        connected: false,
        rssi: -70,
        batteryLevel: 100,
        deviceType: BluetoothDeviceType.speaker,
      ),
      BluetoothDeviceInfo(
        name: 'Huawei FreeBuds',
        address: 'AA:BB:CC:DD:FF:03',
        connected: false,
        rssi: -40,
        batteryLevel: 80,
        deviceType: BluetoothDeviceType.headphones,
      ),
    ]);
    notifyListeners();
  }

  void stopScan() {
    _isScanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    notifyListeners();
    debugPrint('[Bluetooth] 扫描停止');
  }

  // =========================================================================
  // 连接 / 断开
  // =========================================================================

  /// 连接设备（有限次数重连，不再无限递归）。
  Future<bool> connect(String address) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    notifyListeners();

    try {
      BluetoothDeviceInfo? device;
      try {
        device = _scannedDevices.firstWhere((d) => d.address == address);
      } catch (_) {
        try {
          device = _pairedDevices.firstWhere((d) => d.address == address);
        } catch (_) {
          device = null;
        }
      }

      if (device == null) {
        debugPrint('[Bluetooth] 未找到设备: $address');
        _scheduleReconnect(address);
        return false;
      }

      _connectedDevice = device.copyWith(connected: true);
      _pairedDevices.removeWhere((d) => d.address == address);
      _pairedDevices.insert(0, _connectedDevice!);
      _reconnectAttempts = 0;
      _reconnectAddress = null;
      onConnected?.call();
      notifyListeners();
      return true;
    } finally {
      _isConnecting = false;
    }
  }

  /// 断开连接（取消重连定时器）。
  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    debugPrint('[Bluetooth] 断开设备: ${_connectedDevice!.address}');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _reconnectAddress = null;
    _connectedDevice = null;
    notifyListeners();
    onDisconnected?.call();
  }

  Future<void> toggleConnection(String address) async {
    if (_connectedDevice?.address == address) {
      await disconnect();
    } else {
      await connect(address);
    }
  }

  /// 有限次数重连（最多 [_maxReconnectAttempts] 次，非递归）。
  void _scheduleReconnect(String address) {
    _reconnectAddress = address;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Bluetooth] 重连次数已达上限($_maxReconnectAttempts)，停止重连');
      _reconnectAttempts = 0;
      _reconnectAddress = null;
      return;
    }

    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_connectedDevice == null && _isEnabled && _reconnectAddress != null) {
        debugPrint(
            '[Bluetooth] 尝试重连 ($_reconnectAttempts/$_maxReconnectAttempts)...');
        await connect(_reconnectAddress!);
      }
    });
  }

  // =========================================================================
  // 音量
  // =========================================================================

  void setVolume(int vol) {
    _volume = vol.clamp(0, 100);
    notifyListeners();
    debugPrint('[Bluetooth] 音量设置为: $_volume');
  }

  void volumeUp() => setVolume(_volume + 5);
  void volumeDown() => setVolume(_volume - 5);

  // =========================================================================
  // 设备信息
  // =========================================================================

  Future<List<BluetoothDeviceInfo>> getPairedDevices() async {
    return _pairedDevices;
  }

  /// 获取设备电量（使用 try-catch 避免 StateError）。
  Future<int?> getDeviceBattery(String address) async {
    try {
      final device = _pairedDevices.firstWhere((d) => d.address == address);
      return device.batteryLevel;
    } catch (_) {
      try {
        final device = _scannedDevices.firstWhere((d) => d.address == address);
        return device.batteryLevel;
      } catch (_) {
        return null;
      }
    }
  }

  // =========================================================================
  // 清理
  // =========================================================================

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _connectedDevice = null;
    _isScanning = false;
    // 不调用 notifyListeners（安全清理）
    super.dispose();
  }
}
