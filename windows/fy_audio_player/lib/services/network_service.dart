import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

class NetworkService extends ChangeNotifier {
  RawDatagramSocket? _controlSocket;
  RawDatagramSocket? _audioSocket;

  String _deviceId = '';
  String _deviceName = '';
  final String _platform = 'windows';
  String _role = 'receiver';

  final List<DeviceInfo> _devices = [];
  final Map<String, DateTime> _heartbeats = {};

  StreamSubscription? _controlSub;
  StreamSubscription? _audioSub;

  Timer? _heartbeatTimer;
  Timer? _discoverTimer;
  Timer? _cleanupTimer;

  Function(DeviceInfo)? onDeviceOnline;
  Function(String)? onDeviceOffline;
  Function(AudioFrame)? onAudioFrame;
  Function(int volume)? onVolumeSync;

  bool _isRunning = false;
  String _localIP = '';

  List<DeviceInfo> get devices => List.unmodifiable(_devices);
  bool get isRunning => _isRunning;
  String get localIP => _localIP;

  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    required String role,
  }) async {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _role = role;
    await _resolveLocalIP();
  }

  Future<void> _resolveLocalIP() async {
    try {
      final sock = await RawSocket.connect('8.8.8.8', 80);
      _localIP = (sock.address as InternetAddress).address;
      sock.close();
    } catch (e) {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIP = addr.address;
            return;
          }
        }
      }
      _localIP = '127.0.0.1';
    }
  }

  Future<void> start() async {
    if (_isRunning) return;

    try {
      _controlSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ProtocolConst.portControl,
        reuseAddress: true,
        reusePort: true,
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

    if (_role != 'source') {
      try {
        _audioSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          ProtocolConst.portAudio,
          reuseAddress: true,
          reusePort: true,
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

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sendHeartbeat());
    _discoverTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendDiscover());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) => _cleanupStaleDevices());

    _isRunning = true;
    notifyListeners();

    await _sendOnlineBroadcast();
    _sendDiscover();
  }

  void _onControlPacket(Datagram datagram) {
    try {
      final data = datagram.data;
      if (data.length < 5) return;

      final magic = ByteData.sublistView(data, 0, 4).getUint32(0, Endian.little);
      if (magic != ProtocolConst.magicNumber) return;

      final msgType = data[4];
      final payloadLen = data.length - 7;
      String? payloadJson;
      if (payloadLen > 0) {
        payloadJson = utf8.decode(data.sublist(5, 5 + payloadLen));
      }

      switch (msgType) {
        case ProtocolConst.msgTypeOnline:
        case ProtocolConst.msgTypeDiscover:
          if (payloadJson != null) {
            final json = jsonDecode(payloadJson) as Map<String, dynamic>;
            final device = DeviceInfo.fromJson(json);
            if (device.deviceId != _deviceId) {
              _addOrUpdateDevice(device, datagram.address.address);
            }
          }
          if (msgType == ProtocolConst.msgTypeDiscover) {
            _sendOnlineTo(datagram.address.address);
          }
          break;

        case ProtocolConst.msgTypeOffline:
          if (payloadJson != null) {
            final json = jsonDecode(payloadJson) as Map<String, dynamic>;
            final deviceId = json['device_id'] as String?;
            if (deviceId != null) {
              _removeDevice(deviceId);
            }
          }
          break;

        case ProtocolConst.msgTypeHeartbeat:
          if (payloadJson != null) {
            final json = jsonDecode(payloadJson) as Map<String, dynamic>;
            final deviceId = json['device_id'] as String?;
            if (deviceId != null) {
              _heartbeats[deviceId] = DateTime.now();
            }
          }
          break;

        case ProtocolConst.msgTypeSetSource:
          break;

        case ProtocolConst.msgTypeVolumeSync:
          if (payloadJson != null) {
            final json = jsonDecode(payloadJson) as Map<String, dynamic>;
            final volume = json['volume'] as int?;
            if (volume != null) {
              onVolumeSync?.call(volume);
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('[Network] 控制消息解析错误: $e');
    }
  }

  void _onAudioPacket(Datagram datagram) {
    try {
      final data = datagram.data;
      if (data.length < 18) return;

      final magic = ByteData.sublistView(data, 0, 4).getUint32(0, Endian.little);
      if (magic != ProtocolConst.magicNumber) return;

      final timestamp = ByteData.sublistView(data, 4, 12).getUint64(0, Endian.little);
      final frameLen = ByteData.sublistView(data, 12, 16).getUint32(0, Endian.little);

      if (data.length < 18 + frameLen) return;

      final payload = data.sublist(16, 16 + frameLen);
      onAudioFrame?.call(AudioFrame(
        codec: AudioCodec.aac,
        timestamp: timestamp.toInt(),
        duration: ProtocolConst.frameDuration,
        bitrate: 128,
        payload: payload,
      ));
    } catch (e) {
      debugPrint('[Network] 音频包解析错误: $e');
    }
  }

  void _addOrUpdateDevice(DeviceInfo device, String? addr) {
    final ip = addr ?? device.ip;
    final newDevice = DeviceInfo(
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      platform: device.platform,
      role: device.role,
      ip: ip.isEmpty ? device.ip : ip,
      sampleRate: device.sampleRate,
      channels: device.channels,
      capabilities: device.capabilities,
      bluetoothConnected: device.bluetoothConnected,
      isSource: device.isSource,
      volume: device.volume,
      latencyCompensate: device.latencyCompensate,
      version: device.version,
    );

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

  Future<void> _sendOnlineBroadcast() async {
    final device = _buildDeviceInfo();
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeOnline, payload: device.toJson());
    await _broadcast(msg.serialize());
  }

  Future<void> _sendOnlineTo(String ip) async {
    final device = _buildDeviceInfo();
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeOnline, payload: device.toJson());
    await _sendTo(msg.serialize(), ip, ProtocolConst.portControl);
  }

  void _sendDiscover() {
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeDiscover, payload: {});
    _broadcast(msg.serialize());
  }

  void _sendHeartbeat() {
    final payload = {'device_id': _deviceId, 'is_source': _role == 'source', 'audio_state': 'playing'};
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeHeartbeat, payload: payload);
    _broadcast(msg.serialize());
  }

  Future<void> sendSetSource(String sourceId, String sourceName) async {
    final payload = {'source_id': sourceId, 'source_name': sourceName};
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeSetSource, payload: payload);
    await _broadcast(msg.serialize());
  }

  Future<void> sendVolumeSync(int volume) async {
    final payload = {'device_id': _deviceId, 'volume': volume};
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeVolumeSync, payload: payload);
    await _broadcast(msg.serialize());
  }

  Future<void> _broadcast(Uint8List data) async {
    try {
      _controlSocket?.send(data, InternetAddress('255.255.255.255'), ProtocolConst.portControl);
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
      capabilities: ['speaker', 'bluetooth'],
      bluetoothConnected: false,
      isSource: _role == 'source',
      version: '1.0.0',
    );
  }

  void updateRole(String role) {
    _role = role;
  }

  Future<void> stop() async {
    final payload = {'device_id': _deviceId};
    final msg = ControlMessage(msgType: ProtocolConst.msgTypeOffline, payload: payload);
    await _broadcast(msg.serialize());

    _heartbeatTimer?.cancel();
    _discoverTimer?.cancel();
    _cleanupTimer?.cancel();
    _controlSub?.cancel();
    _audioSub?.cancel();
    _controlSocket?.close();
    _audioSocket?.close();
    _isRunning = false;
    _devices.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}