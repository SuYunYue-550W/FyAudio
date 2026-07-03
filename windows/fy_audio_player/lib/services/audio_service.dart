import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

/// 音频服务：负责音频采集（模拟 PCM 正弦波）与播放（桌面端计数器模拟）。
///
/// 采集的帧通过公开回调 [onAudioFrame] 发出，需由外部注册到
/// `NetworkService.sendAudioFrame` 进行网络传输。
class AudioService extends ChangeNotifier {
  bool _isCapturing = false;
  bool _isPlaying = false;
  int _volume = 80;
  int _capturedFrames = 0;
  int _playedFrames = 0;
  String _selectedInputDevice = '';
  String _selectedOutputDevice = '';
  AudioCodec _currentCodec = AudioCodec.pcm;
  AudioScene _currentScene = AudioScene.music;
  double _latencyMs = 0;
  int _jitterMs = 0;

  final int sampleRate = ProtocolConst.sampleRate;
  final int channels = ProtocolConst.channels;
  final int frameDuration = ProtocolConst.frameDuration;

  Timer? _captureTimer;
  Timer? _latencyTimer;
  final Random _random = Random();
  int _capturePhase = 0;

  /// 采集回调：发出 [AudioFrame]，外部注册到 network_service.sendAudioFrame。
  Function(AudioFrame frame)? onAudioFrame;

  /// PCM 回调：发出原始 PCM 数据 + 时间戳（毫秒）。
  Function(Uint8List pcm, int timestamp)? onPCMFrame;

  /// 同步状态回调：延迟(ms) 与抖动(ms)。
  Function(double latency, int jitter)? onSyncStatus;

  bool get isCapturing => _isCapturing;
  bool get isPlaying => _isPlaying;
  int get volume => _volume;
  int get capturedFrames => _capturedFrames;
  int get playedFrames => _playedFrames;
  String get selectedInputDevice => _selectedInputDevice;
  String get selectedOutputDevice => _selectedOutputDevice;
  AudioCodec get currentCodec => _currentCodec;
  AudioScene get currentScene => _currentScene;
  double get latencyMs => _latencyMs;
  int get jitterMs => _jitterMs;

  /// 启动音频采集：生成模拟 PCM 正弦波测试音。
  /// 时间戳统一使用毫秒 [DateTime.now().millisecondsSinceEpoch]。
  Future<bool> startCapture() async {
    if (_isCapturing) return true;

    debugPrint('[AudioService] 启动音频采集...');
    _isCapturing = true;
    _capturedFrames = 0;
    _capturePhase = 0;

    _captureTimer = Timer.periodic(
      Duration(milliseconds: frameDuration),
      (_) => _doCapture(),
    );

    _startLatencyMonitor();
    notifyListeners();
    return true;
  }

  void _doCapture() {
    final frameSize = (sampleRate * channels * 2 * frameDuration) ~/ 1000;
    final pcmData = Uint8List(frameSize);
    final samples = frameSize ~/ 4; // 立体声：每采样 4 字节

    // 生成 440Hz 正弦波测试音
    for (int i = 0; i < samples; i++) {
      final t = _capturePhase / sampleRate;
      final amp = sin(t * 2 * pi * 440) * 0.5;
      final val = (amp * 32767).toInt().clamp(-32768, 32767);
      // 左声道
      pcmData[i * 4] = val & 0xFF;
      pcmData[i * 4 + 1] = (val >> 8) & 0xFF;
      // 右声道
      pcmData[i * 4 + 2] = val & 0xFF;
      pcmData[i * 4 + 3] = (val >> 8) & 0xFF;
      _capturePhase++;
    }

    _capturedFrames++;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // 发出原始 PCM
    onPCMFrame?.call(pcmData, timestamp);

    // PCM 模式直接透传，不做编解码
    final frame = AudioFrame(
      codec: AudioCodec.pcm,
      timestamp: timestamp,
      duration: frameDuration,
      bitrate: _bitrateForScene(_currentScene),
      payload: pcmData,
      syncOffset: 0,
    );
    onAudioFrame?.call(frame);

    notifyListeners();
  }

  int _bitrateForScene(AudioScene scene) {
    switch (scene) {
      case AudioScene.gaming:
        return 128;
      case AudioScene.music:
        return 256;
      case AudioScene.video:
        return 192;
      case AudioScene.weakNetwork:
        return 64;
      default:
        return 128;
    }
  }

  void stopCapture() {
    _captureTimer?.cancel();
    _latencyTimer?.cancel();
    _isCapturing = false;
    _capturedFrames = 0;
    _capturePhase = 0;
    notifyListeners();
    debugPrint('[AudioService] 停止音频采集');
  }

  /// 播放接收到的音频帧（桌面端用计数器模拟）。
  /// PCM 模式直接使用 payload，无需解码。
  void playFrame(AudioFrame frame) {
    _playedFrames++;
    notifyListeners();
  }

  /// 启动播放（标记状态，供 UI 使用）。
  Future<bool> startPlayback() async {
    if (_isPlaying) return true;
    _isPlaying = true;
    _playedFrames = 0;
    notifyListeners();
    return true;
  }

  void stopPlayback() {
    _isPlaying = false;
    _playedFrames = 0;
    notifyListeners();
    debugPrint('[AudioService] 停止音频播放');
  }

  void setVolume(int vol) {
    _volume = vol.clamp(0, 100);
    notifyListeners();
  }

  void volumeUp() => setVolume(_volume + 5);
  void volumeDown() => setVolume(_volume - 5);

  void setCodec(AudioCodec codec) {
    _currentCodec = codec;
    debugPrint('[AudioService] 切换编码格式: $codec');
    notifyListeners();
  }

  void setScene(AudioScene scene) {
    _currentScene = scene;
    debugPrint('[AudioService] 切换场景: $scene');
    _adjustParametersForScene(scene);
    notifyListeners();
  }

  /// 场景切换：只切换 codec，不做真实编解码。
  void _adjustParametersForScene(AudioScene scene) {
    switch (scene) {
      case AudioScene.gaming:
        _currentCodec = AudioCodec.opus;
        break;
      case AudioScene.music:
        _currentCodec = AudioCodec.pcm;
        break;
      case AudioScene.video:
        _currentCodec = AudioCodec.aac;
        break;
      case AudioScene.weakNetwork:
        _currentCodec = AudioCodec.opus;
        break;
      default:
        _currentCodec = AudioCodec.pcm;
    }
  }

  void selectInputDevice(String deviceId) {
    _selectedInputDevice = deviceId;
    notifyListeners();
  }

  void selectOutputDevice(String deviceId) {
    _selectedOutputDevice = deviceId;
    notifyListeners();
  }

  void _startLatencyMonitor() {
    _latencyTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _latencyMs = 5 + _random.nextDouble() * 15;
      _jitterMs = _random.nextInt(5);
      onSyncStatus?.call(_latencyMs, _jitterMs);
    });
  }

  Future<List<AudioDevice>> getAudioDevices() async {
    return [
      AudioDevice(id: 'default', name: '默认设备', type: AudioDeviceType.system),
      AudioDevice(
          id: 'virtual',
          name: 'VB-Audio Virtual Cable',
          type: AudioDeviceType.virtual),
      AudioDevice(
          id: 'bluetooth',
          name: '蓝牙音箱 (A2DP)',
          type: AudioDeviceType.bluetooth),
      AudioDevice(id: 'hdmi', name: 'HDMI 输出', type: AudioDeviceType.hdmi),
      AudioDevice(id: 'usb', name: 'USB 耳机', type: AudioDeviceType.usb),
    ];
  }

  Future<List<AudioDevice>> getInputDevices() async {
    return [
      AudioDevice(
          id: 'mic_default', name: '麦克风', type: AudioDeviceType.system),
      AudioDevice(
          id: 'virtual_in',
          name: 'VB-Audio Virtual Cable (输入)',
          type: AudioDeviceType.virtual),
    ];
  }

  Future<List<AudioDevice>> getOutputDevices() async {
    return [
      AudioDevice(
          id: 'speaker_default', name: '扬声器', type: AudioDeviceType.system),
      AudioDevice(
          id: 'virtual_out',
          name: 'VB-Audio Virtual Cable (输出)',
          type: AudioDeviceType.virtual),
      AudioDevice(
          id: 'bluetooth_out', name: '蓝牙音箱', type: AudioDeviceType.bluetooth),
    ];
  }

  Future<String?> getVirtualCableDevice() async {
    final devices = await getAudioDevices();
    for (final d in devices) {
      if (d.name.contains('VB-Audio') || d.name.contains('Virtual')) {
        return d.id;
      }
    }
    return null;
  }

  bool get hasVirtualCable => true;

  @override
  void dispose() {
    stopCapture();
    _latencyTimer?.cancel();
    super.dispose();
  }
}
