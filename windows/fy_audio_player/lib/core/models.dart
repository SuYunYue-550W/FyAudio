import 'dart:convert';
import 'dart:typed_data';

/// 协议常量 - 必须与 Go 端 protocol/packet.go 完全一致
class ProtocolConst {
  static const int magicNumber = 0x46594155; // "FYAU"

  static const int portAudio = 5001;
  static const int portControl = 5002;
  static const int portSync = 5003;

  static const int sampleRate = 44100;
  static const int channels = 2;
  static const int bitsPerSample = 16;
  static const int frameDuration = 20; // ms

  // 缓冲区参数
  static const int bufferMinMs = 20;
  static const int bufferDefaultMs = 40;
  static const int bufferMaxMs = 200;
  static const int maxBufferFrames = 200;

  // 消息类型
  static const int msgTypeDiscover = 0x01;
  static const int msgTypeOnline = 0x02;
  static const int msgTypeOffline = 0x03;
  static const int msgTypeSetSource = 0x10;
  static const int msgTypeVolumeSync = 0x11;
  static const int msgTypeSyncRequest = 0x20;
  static const int msgTypeSyncResponse = 0x21;
  static const int msgTypeHeartbeat = 0x30;

  // 设备角色
  static const String roleSource = 'source';
  static const String roleReceiver = 'receiver';
  static const String roleGateway = 'gateway';

  // 平台类型
  static const String platformWindows = 'windows';
  static const String platformMac = 'mac';
  static const String platformAndroid = 'android';
  static const String platformLinux = 'linux';
  static const String platformIos = 'ios';
  static const String platformHarmony = 'harmony';
  static const String platformRaspberryPi = 'raspberrypi';
}

/// 音频编解码器
enum AudioCodec { pcm, aac, opus, mp3 }

/// 音频场景模式
enum AudioScene { music, video, gaming, room, weakNetwork, night }

/// 音频设备类型
enum AudioDeviceType { system, virtual, bluetooth, hdmi, usb }

/// 蓝牙设备类型
enum BluetoothDeviceType { headphones, speaker, other }

/// 音频设备信息
class AudioDevice {
  final String id;
  final String name;
  final AudioDeviceType type;
  final bool isDefault;
  final bool isActive;

  AudioDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isDefault = false,
    this.isActive = false,
  });
}

/// 音频帧 - 时间戳统一使用毫秒
class AudioFrame {
  final AudioCodec codec;
  final int timestamp; // UTC 毫秒时间戳
  final int duration; // 帧时长 ms
  final int bitrate; // kbps
  final Uint8List payload;
  final int syncOffset;

  AudioFrame({
    required this.codec,
    required this.timestamp,
    required this.duration,
    required this.bitrate,
    required this.payload,
    this.syncOffset = 0,
  });

  AudioFrame copyWith({
    AudioCodec? codec,
    int? timestamp,
    int? duration,
    int? bitrate,
    Uint8List? payload,
    int? syncOffset,
  }) {
    return AudioFrame(
      codec: codec ?? this.codec,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      bitrate: bitrate ?? this.bitrate,
      payload: payload ?? this.payload,
      syncOffset: syncOffset ?? this.syncOffset,
    );
  }
}

/// 设备信息
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String role;
  final String ip;
  final int sampleRate;
  final int channels;
  final List<String> capabilities;
  final bool bluetoothConnected;
  final bool isSource;
  final int volume;
  final int latencyCompensate;
  final String version;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.role,
    required this.ip,
    this.sampleRate = ProtocolConst.sampleRate,
    this.channels = ProtocolConst.channels,
    this.capabilities = const [],
    this.bluetoothConnected = false,
    this.isSource = false,
    this.volume = 80,
    this.latencyCompensate = 0,
    this.version = '1.0.0',
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      role: json['role'] as String? ?? ProtocolConst.roleReceiver,
      ip: json['ip'] as String? ?? '',
      sampleRate: json['audio_sample_rate'] as int? ?? ProtocolConst.sampleRate,
      channels: json['audio_channels'] as int? ?? ProtocolConst.channels,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      bluetoothConnected: json['bluetooth_connected'] as bool? ?? false,
      isSource: json['is_source'] as bool? ?? false,
      volume: json['volume'] as int? ?? 80,
      latencyCompensate: json['latency_compensate'] as int? ?? 0,
      version: json['version'] as String? ?? '1.0.0',
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'role': role,
        'ip': ip,
        'audio_sample_rate': sampleRate,
        'audio_channels': channels,
        'capabilities': capabilities,
        'bluetooth_connected': bluetoothConnected,
        'is_source': isSource,
        'volume': volume,
        'latency_compensate': latencyCompensate,
        'version': version,
      };

  DeviceInfo copyWith({
    String? deviceId,
    String? deviceName,
    String? platform,
    String? role,
    String? ip,
    int? sampleRate,
    int? channels,
    List<String>? capabilities,
    bool? bluetoothConnected,
    bool? isSource,
    int? volume,
    int? latencyCompensate,
    String? version,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      role: role ?? this.role,
      ip: ip ?? this.ip,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      capabilities: capabilities ?? this.capabilities,
      bluetoothConnected: bluetoothConnected ?? this.bluetoothConnected,
      isSource: isSource ?? this.isSource,
      volume: volume ?? this.volume,
      latencyCompensate: latencyCompensate ?? this.latencyCompensate,
      version: version ?? this.version,
    );
  }

  String get platformIcon {
    switch (platform) {
      case ProtocolConst.platformWindows:
        return '🖥️';
      case ProtocolConst.platformMac:
        return '🍎';
      case ProtocolConst.platformAndroid:
        return '📱';
      case ProtocolConst.platformIos:
        return '📱';
      case ProtocolConst.platformLinux:
        return '🐧';
      case ProtocolConst.platformHarmony:
        return ' HarmonyOS';
      case ProtocolConst.platformRaspberryPi:
        return '🍓';
      default:
        return '📟';
    }
  }

  String get displayName => '$platformIcon $deviceName';

  bool get hasBluetooth => capabilities.contains('bluetooth');
  bool get hasSpeaker => capabilities.contains('speaker');
  bool get hasCapture => capabilities.contains('capture');
}

/// 控制消息 - CRC16-CCITT 与 Go 端完全一致
class ControlMessage {
  final int msgType;
  final Map<String, dynamic>? payload;

  ControlMessage({required this.msgType, this.payload});

  /// 序列化为二进制: Magic(4) + MsgType(1) + Payload(N) + CRC16(2)
  Uint8List serialize() {
    final jsonBytes = utf8.encode(jsonEncode(payload ?? {}));
    final totalLen = 5 + jsonBytes.length + 2;
    final buf = ByteData(totalLen);

    buf.setUint32(0, ProtocolConst.magicNumber, Endian.little);
    buf.setUint8(4, msgType);
    for (var i = 0; i < jsonBytes.length; i++) {
      buf.setUint8(5 + i, jsonBytes[i]);
    }

    // CRC16-CCITT (多项式 0x1021, 初始值 0xFFFF, 非反射)
    final crcData = buf.buffer.asUint8List().sublist(0, 5 + jsonBytes.length);
    final crc = _crc16CCITT(crcData);
    buf.setUint16(5 + jsonBytes.length, crc, Endian.little);

    return buf.buffer.asUint8List();
  }

  /// 从二进制反序列化: 含 CRC 校验
  static ControlMessage? parse(Uint8List data) {
    if (data.length < 7) return null;

    final magic = ByteData.sublistView(data).getUint32(0, Endian.little);
    if (magic != ProtocolConst.magicNumber) return null;

    final msgType = data[4];
    final payloadLen = data.length - 7;

    // CRC 校验
    final crcData = data.sublist(0, 5 + payloadLen);
    final expectedCRC = ByteData.sublistView(data)
        .getUint16(5 + payloadLen, Endian.little);
    final actualCRC = _crc16CCITT(crcData);
    if (expectedCRC != actualCRC) return null;

    Map<String, dynamic>? payload;
    if (payloadLen > 0) {
      final payloadBytes = data.sublist(5, 5 + payloadLen);
      try {
        payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>?;
      } catch (_) {
        payload = null;
      }
    }

    return ControlMessage(msgType: msgType, payload: payload);
  }

  /// CRC16-CCITT 校验 - 与 Go 端 crc16Checksum 完全一致
  static int _crc16CCITT(Uint8List data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc = ((crc ^ (b << 8)) & 0xFFFF);
      for (var i = 0; i < 8; i++) {
        if (crc & 0x8000 != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }
}

/// 同步统计信息
class SyncStats {
  final int bufferFrames;
  final int estimatedRTT;
  final int windowMs;
  final int offsetMs;
  final bool isPlaying;
  final int droppedFrames;
  final int totalFrames;

  SyncStats({
    this.bufferFrames = 0,
    this.estimatedRTT = 0,
    this.windowMs = ProtocolConst.bufferDefaultMs,
    this.offsetMs = 0,
    this.isPlaying = false,
    this.droppedFrames = 0,
    this.totalFrames = 0,
  });

  SyncStats copyWith({
    int? bufferFrames,
    int? estimatedRTT,
    int? windowMs,
    int? offsetMs,
    bool? isPlaying,
    int? droppedFrames,
    int? totalFrames,
  }) {
    return SyncStats(
      bufferFrames: bufferFrames ?? this.bufferFrames,
      estimatedRTT: estimatedRTT ?? this.estimatedRTT,
      windowMs: windowMs ?? this.windowMs,
      offsetMs: offsetMs ?? this.offsetMs,
      isPlaying: isPlaying ?? this.isPlaying,
      droppedFrames: droppedFrames ?? this.droppedFrames,
      totalFrames: totalFrames ?? this.totalFrames,
    );
  }

  double get dropRate => totalFrames > 0 ? droppedFrames / totalFrames : 0.0;
}

/// 蓝牙设备信息
class BluetoothDeviceInfo {
  final String name;
  final String address;
  final bool connected;
  final int? rssi;
  final int batteryLevel;
  final BluetoothDeviceType deviceType;

  BluetoothDeviceInfo({
    required this.name,
    required this.address,
    this.connected = false,
    this.rssi,
    this.batteryLevel = 0,
    this.deviceType = BluetoothDeviceType.other,
  });

  BluetoothDeviceInfo copyWith({
    String? name,
    String? address,
    bool? connected,
    int? rssi,
    int? batteryLevel,
    BluetoothDeviceType? deviceType,
  }) {
    return BluetoothDeviceInfo(
      name: name ?? this.name,
      address: address ?? this.address,
      connected: connected ?? this.connected,
      rssi: rssi ?? this.rssi,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      deviceType: deviceType ?? this.deviceType,
    );
  }

  factory BluetoothDeviceInfo.fromMap(Map<String, dynamic> map) {
    final typeIdx = map['device_type'] as int? ?? 2;
    return BluetoothDeviceInfo(
      name: map['name'] as String? ?? '未知设备',
      address: map['address'] as String? ?? '',
      connected: map['connected'] as bool? ?? false,
      rssi: map['rssi'] as int?,
      batteryLevel: map['battery_level'] as int? ?? 0,
      deviceType: typeIdx >= 0 && typeIdx < BluetoothDeviceType.values.length
          ? BluetoothDeviceType.values[typeIdx]
          : BluetoothDeviceType.other,
    );
  }
}

/// 音频帧数据包序列化/反序列化 - 与 Go 端 AudioFramePacket 一致
class AudioFramePacket {
  static Uint8List serialize({
    required int timestamp, // UTC 毫秒
    required Uint8List payload,
  }) {
    final totalLen = 18 + payload.length;
    final buf = ByteData(totalLen);

    buf.setUint32(0, ProtocolConst.magicNumber, Endian.little);
    buf.setUint64(4, timestamp, Endian.little);
    buf.setUint32(12, payload.length, Endian.little);
    for (var i = 0; i < payload.length; i++) {
      buf.setUint8(16 + i, payload[i]);
    }

    // CRC16-CCITT
    final crcData = buf.buffer.asUint8List().sublist(0, 16 + payload.length);
    final crc = ControlMessage._crc16CCITT(crcData);
    buf.setUint16(16 + payload.length, crc, Endian.little);

    return buf.buffer.asUint8List();
  }

  /// 从二进制解析音频帧: Magic(4) + Timestamp(8) + FrameLen(4) + Payload(N) + CRC16(2)
  static AudioFramePacketData? parse(Uint8List data) {
    if (data.length < 18) return null;

    final byteData = ByteData.sublistView(data);
    final magic = byteData.getUint32(0, Endian.little);
    if (magic != ProtocolConst.magicNumber) return null;

    final timestamp = byteData.getUint64(4, Endian.little);
    final frameLen = byteData.getUint32(12, Endian.little);

    if (data.length < 18 + frameLen) return null;

    // CRC 校验
    final crcData = data.sublist(0, 16 + frameLen);
    final expectedCRC = byteData.getUint16(16 + frameLen, Endian.little);
    final actualCRC = ControlMessage._crc16CCITT(crcData);
    if (expectedCRC != actualCRC) return null;

    final payload = data.sublist(16, 16 + frameLen);

    return AudioFramePacketData(
      timestamp: timestamp,
      payload: Uint8List.fromList(payload),
    );
  }
}

/// 音频帧解析结果
class AudioFramePacketData {
  final int timestamp; // UTC 毫秒
  final Uint8List payload;

  AudioFramePacketData({required this.timestamp, required this.payload});
}
