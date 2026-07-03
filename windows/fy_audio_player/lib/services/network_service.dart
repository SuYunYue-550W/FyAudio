import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

/// 网络服务：基于 UDP 广播实现设备发现、控制消息收发与音频帧传输。
///
/// 协议与 Go 端 [protocol/packet.go] 完全一致：
/// - 控制端口 [ProtocolConst.portControl] 收发 [ControlMessage]
/// - 音频端口 [ProtocolConst.portAudio] 收发 [AudioFramePacket]
/// - CRC16-CCITT（多项式 0x1021）统一校验
class NetworkService extends ChangeNotifier {
  RawDatagramSocket? _controlSocket;
  RawDatagramSocket? _audioSocket;

  String _deviceId = '';
  String _deviceName = '';
  String _platform = '';
  String _role = ProtocolConst.roleReceiver;

  final List<DeviceInfo> _devices = [];
  final Map<String, DateTime> _heartbeats = {};

  StreamSubscription? _controlSub;
  StreamSubscription? _audioSub;

  Timer? _heartbeatTimer;
  Timer? _discoverTimer;
  Timer? _cleanupTimer;

  // =========================================================================
  // 公开回调
  // =========================================================================

  /// 设备上线回调
  Function(DeviceInfo)? onDeviceOnline;

  /// 设备下线回调
  Function(String)? onDeviceOffline;

  /// 发现设备回调（收到 Discover 请求时触发）
  Function(DeviceInfo)? onDeviceDiscovered;

  /// 收到音频帧回调（公开，供 home_screen 注册到 sync_service.feedFrame）
  Function(AudioFrame)? onAudioFrame;

  /// 音量同步回调
  Function(int volume)? onVolumeSync;

  /// 设置音源回调
  Function(String sourceId)? onSetSource;

  /// 同步请求回调（client_time 为请求方毫秒时间戳）
  Function(int clientTime)? onSyncRequest;

  /// 同步响应回调（client_time 为请求方时间戳，server_time 为服务端时间戳）
  Function(int clientTime, int serverTime)? onSyncResponse;

  bool _isRunning = false;
  String _localIP = '';

  List<DeviceInfo> get devices => List.unmodifiable(_devices);
  bool get isRunning => _isRunning;
  String get localIP => _localIP;
  String get role => _role;
  String get platform => _platform;

  // =========================================================================
  // 初始化（旧版兼容，home_screen 使用）
  // =========================================================================

  /// 初始化设备信息（home_screen 调用）。
  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    required String role,
  }) async {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _role = role;
    _platform = _detectPlatform();
    await _resolveLocalIP();
  }

  /// 根据 Platform 推断平台标识（修复 _platform 硬编码）。
  String _detectPlatform() {
    if (Platform.isWindows) return ProtocolConst.platformWindows;
    if (Platform.isMacOS) return ProtocolConst.platformMac;
    if (Platform.isLinux) return ProtocolConst.platformLinux;
    if (Platform.isAndroid) return ProtocolConst.platformAndroid;
    if (Platform.isIOS) return ProtocolConst.platformIos;
    return ProtocolConst.platformWindows;
  }

  /// 解析本机 IP（修复离线环境回退逻辑）。
  /// 不再依赖外网连接探测，直接枚举网络接口。
  Future<void> _resolveLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254.')) {
            _localIP = addr.address;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[Network] 获取网络接口失败: $e');
    }
    _localIP = '127.0.0.1';
  }

  // =========================================================================
  // 启动 / 停止
  // =========================================================================

  /// 启动网络服务。
  ///
  /// 参数可选以兼容 home_screen 的 `initialize + start()` 调用方式；
  /// 也支持直接 `start(deviceId, deviceName, platform, role)`。
  Future<void> start([
    String? deviceId,
    String? deviceName,
    String? platform,
    String? role,
  ]) async {
    if (deviceId != null) _deviceId = deviceId;
    if (deviceName != null) _deviceName = deviceName;
    if (platform != null) {
      _platform = platform;
    } else if (_platform.isEmpty) {
      _platform = _detectPlatform();
    }
    if (role != null) _role = role;

    if (_deviceId.isEmpty) {
      debugPrint('[Network] 无法启动：deviceId 为空');
      return;
    }

    if (_localIP.isEmpty) {
      await _resolveLocalIP();
    }

    if (_isRunning) return;

    // 修复 reusePort：Windows 不支持 reusePort
    final reusePort = !Platform.isWindows;

    try {
      _controlSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ProtocolConst.portControl,
        reuseAddress: true,
        reusePort: reusePort,
      );
      _controlSocket!.broadcastEnabled = true;
      _controlSub = _controlSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _controlSocket!.receive();
          if (datagram != null) {
            _onControlPacket(datagram);
          }
        }
      });
    } catch (e) {
      debugPrint('[Network] 控制端口绑定失败: $e');
    }

    // 音频端口：接收端绑定以接收音频帧
    if (_role != ProtocolConst.roleSource) {
      try {
        _audioSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          ProtocolConst.portAudio,
          reuseAddress: true,
          reusePort: reusePort,
        );
        _audioSub = _audioSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = _audioSocket!.receive();
            if (datagram != null) {
              _onAudioPacket(datagram);
            }
          }
        });
      } catch (e) {
        debugPrint('[Network] 音频端口绑定失败: $e');
      }
    }

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => sendHeartbeat(),
    );
    _discoverTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => sendDiscover(),
    );
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cleanupStaleDevices(),
    );

    _isRunning = true;
    notifyListeners();

    await sendOnline(_buildDeviceInfo());
    sendDiscover();
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    await sendOffline();

    _heartbeatTimer?.cancel();
    _discoverTimer?.cancel();
    _cleanupTimer?.cancel();
    _controlSub?.cancel();
    _audioSub?.cancel();
    _controlSocket?.close();
    _audioSocket?.close();
    _controlSocket = null;
    _audioSocket = null;
    _isRunning = false;
    _devices.clear();
    _heartbeats.clear();
    notifyListeners();
  }

  // =========================================================================
  // 数据包接收
  // =========================================================================

  /// 处理控制包：使用 [ControlMessage.parse] 解析（含 CRC 校验）。
  void _onControlPacket(Datagram datagram) {
    final msg = ControlMessage.parse(datagram.data);
    if (msg == null) return; // CRC 校验失败或 magic 不匹配

    final payload = msg.payload ?? {};

    switch (msg.msgType) {
      case ProtocolConst.msgTypeOnline:
        final device = DeviceInfo.fromJson(payload);
        if (device.deviceId.isNotEmpty && device.deviceId != _deviceId) {
          _addOrUpdateDevice(device, datagram.address.address);
        }
        break;

      case ProtocolConst.msgTypeDiscover:
        final device = DeviceInfo.fromJson(payload);
        if (device.deviceId.isNotEmpty && device.deviceId != _deviceId) {
          _addOrUpdateDevice(device, datagram.address.address);
          onDeviceDiscovered?.call(device);
        }
        // 回应上线消息给请求方
        _sendOnlineTo(datagram.address.address);
        break;

      case ProtocolConst.msgTypeOffline:
        final deviceId = payload['device_id'] as String?;
        if (deviceId != null && deviceId.isNotEmpty) {
          _removeDevice(deviceId);
        }
        break;

      case ProtocolConst.msgTypeHeartbeat:
        final deviceId = payload['device_id'] as String?;
        if (deviceId != null && deviceId.isNotEmpty) {
          _heartbeats[deviceId] = DateTime.now();
        }
        break;

      case ProtocolConst.msgTypeSetSource:
        final sourceId = payload['source_id'] as String?;
        if (sourceId != null) {
          onSetSource?.call(sourceId);
        }
        break;

      case ProtocolConst.msgTypeVolumeSync:
        final volume = payload['volume'] as int?;
        if (volume != null) {
          onVolumeSync?.call(volume);
        }
        break;

      case ProtocolConst.msgTypeSyncRequest:
        final clientTime = payload['client_time'] as int?;
        if (clientTime != null) {
          onSyncRequest?.call(clientTime);
        }
        break;

      case ProtocolConst.msgTypeSyncResponse:
        final clientTime = payload['client_time'] as int?;
        final serverTime = payload['server_time'] as int?;
        if (clientTime != null && serverTime != null) {
          onSyncResponse?.call(clientTime, serverTime);
        }
        break;
    }
  }

  /// 处理音频包：使用 [AudioFramePacket.parse] 解析（含 CRC 校验）。
  void _onAudioPacket(Datagram datagram) {
    final parsed = AudioFramePacket.parse(datagram.data);
    if (parsed == null) return; // CRC 校验失败或格式错误

    onAudioFrame?.call(AudioFrame(
      codec: AudioCodec.pcm,
      timestamp: parsed.timestamp,
      duration: ProtocolConst.frameDuration,
      bitrate: 128,
      payload: parsed.payload,
    ));
  }

  // =========================================================================
  // 设备列表管理
  // =========================================================================

  void _addOrUpdateDevice(DeviceInfo device, String? addr) {
    final ip = (addr != null && addr.isNotEmpty) ? addr : device.ip;
    final newDevice = device.copyWith(ip: ip);

    final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (idx >= 0) {
      _devices[idx] = newDevice;
    } else {
      _devices.add(newDevice);
    }
    _heartbeats[device.deviceId] = DateTime.now();
    onDeviceOnline?.call(newDevice);
    notifyListeners();
  }

  void _removeDevice(String deviceId) {
    final idx = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx >= 0) {
      _devices.removeAt(idx);
      _heartbeats.remove(deviceId);
      onDeviceOffline?.call(deviceId);
      notifyListeners();
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final stale = <String>[];
    for (final entry in _heartbeats.entries) {
      if (now.difference(entry.value).inSeconds > 12) {
        stale.add(entry.key);
      }
    }
    for (final id in stale) {
      _removeDevice(id);
    }
  }

  /// 返回当前设备列表。
  List<DeviceInfo> getDevices() => List.unmodifiable(_devices);

  // =========================================================================
  // 发送方法
  // =========================================================================

  /// 发送音频帧（通过控制 socket 广播到 portAudio）。
  Future<void> sendAudioFrame(Uint8List payload, int timestamp) async {
    if (_controlSocket == null) return;
    final data =
        AudioFramePacket.serialize(timestamp: timestamp, payload: payload);
    try {
      _controlSocket!.send(
        data,
        InternetAddress('255.255.255.255'),
        ProtocolConst.portAudio,
      );
    } catch (e) {
      debugPrint('[Network] 发送音频帧失败: $e');
    }
  }

  /// 发送控制消息。
  Future<void> sendControl(ControlMessage msg) async {
    await _broadcast(msg.serialize());
  }

  /// 发送发现请求。
  void sendDiscover() {
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeDiscover, payload: {});
    _broadcast(msg.serialize());
  }

  /// 广播上线。
  Future<void> sendOnline(DeviceInfo info) async {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeOnline,
      payload: info.toJson(),
    );
    await _broadcast(msg.serialize());
  }

  Future<void> _sendOnlineTo(String ip) async {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeOnline,
      payload: _buildDeviceInfo().toJson(),
    );
    await _sendTo(msg.serialize(), ip, ProtocolConst.portControl);
  }

  /// 广播下线。
  Future<void> sendOffline() async {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeOffline,
      payload: {'device_id': _deviceId},
    );
    await _broadcast(msg.serialize());
  }

  /// 发送设置音源。
  /// 第二参数兼容 home_screen 的双参调用方式。
  Future<void> sendSetSource(String sourceId, [String? sourceName]) async {
    final payload = <String, dynamic>{'source_id': sourceId};
    if (sourceName != null) payload['source_name'] = sourceName;
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeSetSource,
      payload: payload,
    );
    await _broadcast(msg.serialize());
  }

  /// 发送心跳。
  void sendHeartbeat() {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeHeartbeat,
      payload: {
        'device_id': _deviceId,
        'is_source': _role == ProtocolConst.roleSource,
        'audio_state': 'playing',
      },
    );
    _broadcast(msg.serialize());
  }

  /// 发送同步请求（client_time 为本机毫秒时间戳）。
  Future<void> sendSyncRequest(int clientTime) async {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeSyncRequest,
      payload: {'device_id': _deviceId, 'client_time': clientTime},
    );
    await _broadcast(msg.serialize());
  }

  /// 发送同步响应。
  Future<void> sendSyncResponse(int clientTime, int serverTime) async {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeSyncResponse,
      payload: {'client_time': clientTime, 'server_time': serverTime},
    );
    await _broadcast(msg.serialize());
  }

  Future<void> sendVolumeSync(int volume) async {
    final msg = ControlMessage(
      msgType: ProtocolConst.msgTypeVolumeSync,
      payload: {'device_id': _deviceId, 'volume': volume},
    );
    await _broadcast(msg.serialize());
  }

  Future<void> _broadcast(Uint8List data) async {
    try {
      _controlSocket?.send(
        data,
        InternetAddress('255.255.255.255'),
        ProtocolConst.portControl,
      );
    } catch (e) {
      debugPrint('[Network] 广播失败: $e');
    }
  }

  Future<void> _sendTo(Uint8List data, String ip, int port) async {
    try {
      _controlSocket?.send(data, InternetAddress(ip), port);
    } catch (e) {
      debugPrint('[Network] 单播失败: $e');
    }
  }

  DeviceInfo _buildDeviceInfo() {
    return DeviceInfo(
      deviceId: _deviceId,
      deviceName: _deviceName,
      platform: _platform,
      role: _role,
      ip: _localIP,
      sampleRate: ProtocolConst.sampleRate,
      channels: ProtocolConst.channels,
      capabilities: const ['speaker', 'bluetooth'],
      bluetoothConnected: false,
      isSource: _role == ProtocolConst.roleSource,
      version: '1.0.0',
    );
  }

  /// 更新角色并重新广播上线。
  void updateRole(String role) {
    _role = role;
    if (_isRunning) {
      sendOnline(_buildDeviceInfo());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
