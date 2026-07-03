import 'dart:convert';
import 'dart:typed_data';

class ProtocolConst {
  static const int magicNumber = 0x46594155;

  static const int portAudio = 5001;
  static const int portControl = 5002;
  static const int portSync = 5003;

  static const int sampleRate = 44100;
  static const int channels = 2;
  static const int frameDuration = 20;

  static const int msgTypeDiscover = 0x01;
  static const int msgTypeOnline = 0x02;
  static const int msgTypeOffline = 0x03;
  static const int msgTypeSetSource = 0x10;
  static const int msgTypeVolumeSync = 0x11;
  static const int msgTypeSyncRequest = 0x20;
  static const int msgTypeSyncResponse = 0x21;
  static const int msgTypeHeartbeat = 0x30;
}

enum AudioCodec { pcm, aac, opus, mp3 }

enum AudioScene { music, video, gaming, room, weakNetwork, night }

enum AudioDeviceType { system, virtual, bluetooth, hdmi, usb }

enum BluetoothDeviceType { headphones, speaker, other }

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

class AudioFrame {
  final AudioCodec codec;
  final int timestamp;
  final int duration;
  final int bitrate;
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
}

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
    this.sampleRate = 44100,
    this.channels = 2,
    this.capabilities = const [],
    this.bluetoothConnected = false,
    this.isSource = false,
    this.volume = 80,
    this.latencyCompensate = 0,
    this.version = '1.0.0',
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] ?? '',
      deviceName: json['device_name'] ?? '',
      platform: json['platform'] ?? '',
      role: json['role'] ?? 'receiver',
      ip: json['ip'] ?? '',
      sampleRate: json['audio_sample_rate'] ?? 44100,
      channels: json['audio_channels'] ?? 2,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      bluetoothConnected: json['bluetooth_connected'] ?? false,
      isSource: json['is_source'] ?? false,
      volume: json['volume'] ?? 80,
      latencyCompensate: json['latency_compensate'] ?? 0,
      version: json['version'] ?? '1.0.0',
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

  String get platformIcon {
    switch (platform) {
      case 'windows':
        return '🖥️';
      case 'mac':
        return '🍎';
      case 'android':
        return '📱';
      case 'raspberrypi':
        return '🖥️';
      default:
        return '📟';
    }
  }

  String get displayName => '$platformIcon $deviceName';

  bool get hasBluetooth => capabilities.contains('bluetooth');
  bool get hasSpeaker => capabilities.contains('speaker');
}

class ControlMessage {
  final int msgType;
  final Map<String, dynamic>? payload;

  ControlMessage({required this.msgType, this.payload});

  Uint8List serialize() {
    final jsonBytes = utf8.encode(jsonEncode(payload ?? {}));
    final totalLen = 5 + 2 + jsonBytes.length;
    final buf = ByteData(totalLen);

    buf.setUint32(0, ProtocolConst.magicNumber, Endian.little);
    buf.setUint8(4, msgType);

    for (var i = 0; i < jsonBytes.length && i < totalLen - 7; i++) {
      buf.setUint8(5 + i, jsonBytes[i]);
    }

    var crc = 0xFFFF;
    for (var i = 0; i < 5 + jsonBytes.length; i++) {
      crc = (crc >> 8) ^ _crc16Table[(crc ^ buf.getUint8(i)) & 0xFF];
    }
    buf.setUint16(5 + jsonBytes.length, crc, Endian.little);

    return buf.buffer.asUint8List();
  }

  static final _crc16Table = List.generate(256, (i) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      c = (c & 1) == 1 ? (0xA001 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });
}

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
    this.windowMs = 40,
    this.offsetMs = 0,
    this.isPlaying = false,
    this.droppedFrames = 0,
    this.totalFrames = 0,
  });

  double get dropRate =>
      totalFrames > 0 ? droppedFrames / totalFrames : 0.0;
}

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
    return BluetoothDeviceInfo(
      name: map['name'] ?? '未知设备',
      address: map['address'] ?? '',
      connected: map['connected'] ?? false,
      rssi: map['rssi'],
      batteryLevel: map['battery_level'] ?? 0,
      deviceType: BluetoothDeviceType.values[map['device_type'] ?? 2],
    );
  }
}