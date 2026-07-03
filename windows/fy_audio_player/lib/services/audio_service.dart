import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

class AudioService extends ChangeNotifier {
  bool _isCapturing = false;
  bool _isPlaying = false;
  int _volume = 80;
  int _capturedFrames = 0;
  int _playedFrames = 0;
  String _selectedInputDevice = '';
  String _selectedOutputDevice = '';
  AudioCodec _currentCodec = AudioCodec.aac;
  AudioScene _currentScene = AudioScene.music;
  double _latencyMs = 0;
  int _jitterMs = 0;

  final int sampleRate = ProtocolConst.sampleRate;
  final int channels = ProtocolConst.channels;
  final int frameDuration = ProtocolConst.frameDuration;

  Timer? _captureTimer;
  Timer? _playbackTimer;
  Timer? _latencyTimer;
  final Random _random = Random();

  Function(Uint8List pcm, int timestamp)? onPCMFrame;
  Function(AudioFrame frame)? onAudioFrame;
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

  Future<bool> startCapture() async {
    if (_isCapturing) return true;

    debugPrint('[AudioService] 启动音频采集...');

    _isCapturing = true;
    _capturedFrames = 0;

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

    for (int i = 0; i < frameSize; i += 4) {
      final t = _capturedFrames / (1000 / frameDuration);
      final amp = sin(t * 2 * pi * 440) * 0.5 + sin(t * 2 * pi * 880) * 0.3;
      final val = (amp * 32767).toInt().clamp(-32768, 32767);
      pcmData[i] = val & 0xFF;
      pcmData[i + 1] = (val >> 8) & 0xFF;
      pcmData[i + 2] = val & 0xFF;
      pcmData[i + 3] = (val >> 8) & 0xFF;
    }

    _capturedFrames++;
    onPCMFrame?.call(pcmData, DateTime.now().microsecondsSinceEpoch);

    final encoded = _encodeFrame(pcmData);
    onAudioFrame?.call(encoded);
    notifyListeners();
  }

  AudioFrame _encodeFrame(Uint8List pcmData) {
    int bitrate;
    switch (_currentScene) {
      case AudioScene.gaming:
        bitrate = 128;
        break;
      case AudioScene.music:
        bitrate = 256;
        break;
      case AudioScene.video:
        bitrate = 192;
        break;
      case AudioScene.weakNetwork:
        bitrate = 64;
        break;
      default:
        bitrate = 128;
    }

    return AudioFrame(
      codec: _currentCodec,
      timestamp: DateTime.now().microsecondsSinceEpoch,
      duration: frameDuration,
      bitrate: bitrate,
      payload: pcmData,
      syncOffset: 0,
    );
  }

  void stopCapture() {
    _captureTimer?.cancel();
    _latencyTimer?.cancel();
    _isCapturing = false;
    _capturedFrames = 0;
    notifyListeners();
    debugPrint('[AudioService] 停止音频采集');
  }

  Future<bool> startPlayback() async {
    if (_isPlaying) return true;

    debugPrint('[AudioService] 启动音频播放...');

    _isPlaying = true;
    _playedFrames = 0;

    _playbackTimer = Timer.periodic(
      Duration(milliseconds: frameDuration),
      (_) => _doPlayback(),
    );

    notifyListeners();
    return true;
  }

  void _doPlayback() {
    _playedFrames++;
    notifyListeners();
  }

  void playPCM(Uint8List pcm) {
    if (!_isPlaying) return;
    _playedFrames++;
    notifyListeners();
  }

  void playFrame(AudioFrame frame) {
    final pcm = _decodeFrame(frame);
    playPCM(pcm);
  }

  Uint8List _decodeFrame(AudioFrame frame) {
    return frame.payload;
  }

  void stopPlayback() {
    _playbackTimer?.cancel();
    _isPlaying = false;
    _playedFrames = 0;
    notifyListeners();
    debugPrint('[AudioService] 停止音频播放');
  }

  void setVolume(int vol) {
    _volume = vol.clamp(0, 100);
    notifyListeners();
  }

  void volumeUp() {
    setVolume(_volume + 5);
  }

  void volumeDown() {
    setVolume(_volume - 5);
  }

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

  void _adjustParametersForScene(AudioScene scene) {
    switch (scene) {
      case AudioScene.gaming:
        _currentCodec = AudioCodec.opus;
        break;
      case AudioScene.music:
        _currentCodec = AudioCodec.aac;
        break;
      case AudioScene.video:
        _currentCodec = AudioCodec.aac;
        break;
      case AudioScene.weakNetwork:
        _currentCodec = AudioCodec.opus;
        break;
      default:
        _currentCodec = AudioCodec.aac;
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
      AudioDevice(id: 'virtual', name: 'VB-Audio Virtual Cable', type: AudioDeviceType.virtual),
      AudioDevice(id: 'bluetooth', name: '蓝牙音箱 (A2DP)', type: AudioDeviceType.bluetooth),
      AudioDevice(id: 'hdmi', name: 'HDMI 输出', type: AudioDeviceType.hdmi),
      AudioDevice(id: 'usb', name: 'USB 耳机', type: AudioDeviceType.usb),
    ];
  }

  Future<List<AudioDevice>> getInputDevices() async {
    return [
      AudioDevice(id: 'mic_default', name: '麦克风', type: AudioDeviceType.system),
      AudioDevice(id: 'virtual_in', name: 'VB-Audio Virtual Cable (输入)', type: AudioDeviceType.virtual),
    ];
  }

  Future<List<AudioDevice>> getOutputDevices() async {
    return [
      AudioDevice(id: 'speaker_default', name: '扬声器', type: AudioDeviceType.system),
      AudioDevice(id: 'virtual_out', name: 'VB-Audio Virtual Cable (输出)', type: AudioDeviceType.virtual),
      AudioDevice(id: 'bluetooth_out', name: '蓝牙音箱', type: AudioDeviceType.bluetooth),
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
    stopPlayback();
    _latencyTimer?.cancel();
    super.dispose();
  }
}