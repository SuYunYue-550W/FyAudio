import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

class BluetoothService extends ChangeNotifier {
  bool _isEnabled = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  final bool _useMockMode = true;
  final List<BluetoothDeviceInfo> _pairedDevices = [];
  final List<BluetoothDeviceInfo> _scannedDevices = [];
  BluetoothDeviceInfo? _connectedDevice;
  int _volume = 80;
  Timer? _reconnectTimer;
  Timer? _scanTimer;

  Function()? onConnected;
  Function()? onDisconnected;

  bool get isEnabled => _isEnabled;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get useMockMode => _useMockMode;
  List<BluetoothDeviceInfo> get pairedDevices => List.unmodifiable(_pairedDevices);
  List<BluetoothDeviceInfo> get scannedDevices => List.unmodifiable(_scannedDevices);
  BluetoothDeviceInfo? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;
  int get volume => _volume;

  BluetoothService() {
    _init();
  }

  Future<void> _init() async {
    debugPrint('[Bluetooth] 蓝牙服务初始化 - 模拟模式');
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
    notifyListeners();
  }

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

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
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

  BluetoothDeviceType _inferDeviceType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('headphone') || lower.contains('earbud') || lower.contains('pod')) {
      return BluetoothDeviceType.headphones;
    }
    if (lower.contains('speaker') || lower.contains('soundbar')) {
      return BluetoothDeviceType.speaker;
    }
    return BluetoothDeviceType.other;
  }

  void stopScan() {
    _isScanning = false;
    _scanTimer?.cancel();
    notifyListeners();
    debugPrint('[Bluetooth] 扫描停止');
  }

  Future<bool> connect(String address) async {
    if (_isConnecting) return false;
    _isConnecting = true;
    notifyListeners();

    debugPrint('[Bluetooth] 连接设备: $address');

    try {
      final device = _scannedDevices.firstWhere((d) => d.address == address);
      _connectedDevice = device.copyWith(connected: true);
      _pairedDevices.removeWhere((d) => d.address == address);
      _pairedDevices.insert(0, _connectedDevice!);
      _scheduleReconnect(address);
      onConnected?.call();
      notifyListeners();
      return true;
    } catch (e) {
      try {
        final device = _pairedDevices.firstWhere((d) => d.address == address);
        _connectedDevice = device.copyWith(connected: true);
        onConnected?.call();
        notifyListeners();
        return true;
      } catch (e2) {
        debugPrint('[Bluetooth] 连接失败: $e');
        _isConnecting = false;
        notifyListeners();
        return false;
      }
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    debugPrint('[Bluetooth] 断开设备: ${_connectedDevice!.address}');

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

  void setVolume(int vol) {
    _volume = vol.clamp(0, 100);
    notifyListeners();
    debugPrint('[Bluetooth] 音量设置为: $_volume');
  }

  void volumeUp() {
    setVolume(_volume + 5);
  }

  void volumeDown() {
    setVolume(_volume - 5);
  }

  void _scheduleReconnect(String address) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_connectedDevice == null && _isEnabled) {
        debugPrint('[Bluetooth] 尝试自动重连...');
        await connect(address);
      } else {
        timer.cancel();
      }
    });
  }

  Future<List<BluetoothDeviceInfo>> getPairedDevices() async {
    return _pairedDevices;
  }

  Future<int?> getDeviceBattery(String address) async {
    final device = _pairedDevices.firstWhere((d) => d.address == address);
    return device.batteryLevel;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _scanTimer?.cancel();
    stopScan();
    disconnect();
    super.dispose();
  }
}