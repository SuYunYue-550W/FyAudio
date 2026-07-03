import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';


enum SceneMode { music, video, game, room, weakNet, night }

class SceneAutoManager extends ChangeNotifier {
  double bufferMs = 40;
  int bitRate = 128;
  int frameMs = 20;
  bool strictSync = false;
  SceneMode currentScene = SceneMode.music;
  bool _autoDetectEnabled = true;

  Timer? _detectionTimer;
  Timer? _networkMonitorTimer;
  final Random _random = Random();

  double _currentLossRate = 0.0;
  List<double> _currentFreq = List.generate(32, (_) => 0.0);
  int _deviceCount = 1;
  bool _isHighLatency = false;
  bool _isLowBandwidth = false;

  bool get autoDetectEnabled => _autoDetectEnabled;
  double get currentLossRate => _currentLossRate;
  int get deviceCount => _deviceCount;

  void startAutoDetection() {
    _autoDetectEnabled = true;
    _detectionTimer = Timer.periodic(const Duration(seconds: 3), (_) => _performAutoDetection());
    _networkMonitorTimer = Timer.periodic(const Duration(seconds: 2), (_) => _monitorNetworkQuality());
    debugPrint('[SceneManager] 自动场景检测已启动');
  }

  void stopAutoDetection() {
    _autoDetectEnabled = false;
    _detectionTimer?.cancel();
    _networkMonitorTimer?.cancel();
    debugPrint('[SceneManager] 自动场景检测已停止');
  }

  void _performAutoDetection() {
    if (!_autoDetectEnabled) return;

    final now = DateTime.now();
    final hour = now.hour;

    if (_checkNightMode(hour)) {
      applyScene(SceneMode.night);
      return;
    }

    if (_checkWeakNetwork()) {
      applyScene(SceneMode.weakNet);
      return;
    }

    if (_checkGameMode()) {
      applyScene(SceneMode.game);
      return;
    }

    if (_checkRoomMode()) {
      applyScene(SceneMode.room);
      return;
    }

    if (_checkVideoMode()) {
      applyScene(SceneMode.video);
      return;
    }

    applyScene(SceneMode.music);
  }

  bool _checkNightMode(int hour) {
    return hour >= 22 || hour <= 7;
  }

  bool _checkWeakNetwork() {
    return _currentLossRate > 0.05 || _isHighLatency || _isLowBandwidth;
  }

  bool _checkGameMode() {
    if (_currentFreq.length >= 32) {
      final highFreqEnergy = _currentFreq.sublist(16, 32).reduce((a, b) => a + b) / 16;
      final rapidChanges = _countRapidChanges(_currentFreq);
      return highFreqEnergy > 0.6 && rapidChanges > 8;
    }
    return false;
  }

  bool _checkRoomMode() {
    return _deviceCount >= 3;
  }

  bool _checkVideoMode() {
    if (_currentFreq.length >= 16) {
      final midFreqEnergy = _currentFreq.sublist(4, 12).reduce((a, b) => a + b) / 8;
      final lowFreqEnergy = _currentFreq.sublist(0, 4).reduce((a, b) => a + b) / 4;
      return midFreqEnergy > 0.4 && lowFreqEnergy > 0.3;
    }
    return false;
  }

  int _countRapidChanges(List<double> freq) {
    int count = 0;
    for (int i = 1; i < freq.length; i++) {
      if ((freq[i] - freq[i - 1]).abs() > 0.3) {
        count++;
      }
    }
    return count;
  }

  void _monitorNetworkQuality() {
    _currentLossRate = 0.01 + _random.nextDouble() * 0.04;
    _isHighLatency = _random.nextDouble() > 0.85;
    _isLowBandwidth = _random.nextDouble() > 0.9;
  }

  void updateAudioSpectrum(List<double> spectrum) {
    _currentFreq = spectrum;
  }

  void updateDeviceCount(int count) {
    _deviceCount = count;
    debugPrint('[SceneManager] 设备数量更新: $count');
  }

  void updateNetworkQuality(double lossRate, double latencyMs) {
    _currentLossRate = lossRate;
    _isHighLatency = latencyMs > 100;
    debugPrint('[SceneManager] 网络质量更新: 丢包率=$lossRate, 延迟=$latencyMs');
  }

  SceneMode detectScene({
    required double lossRate,
    required List<double> freq,
    required int hour,
    int deviceCount = 1,
  }) {
    if (hour >= 22 || hour <= 7) {
      return SceneMode.night;
    }
    if (lossRate > 0.05) {
      return SceneMode.weakNet;
    }
    if (deviceCount >= 3) {
      return SceneMode.room;
    }
    if (freq.length > 20) {
      bool isGame = freq.sublist(20).every((e) => e > 0.6);
      if (isGame) return SceneMode.game;
    }
    if (freq.length > 16) {
      bool isVideo = freq.sublist(8, 16).every((e) => e > 0.4);
      if (isVideo) return SceneMode.video;
    }
    return SceneMode.music;
  }

  void applyScene(SceneMode mode) {
    currentScene = mode;
    switch (mode) {
      case SceneMode.music:
        bufferMs = 40;
        bitRate = 192;
        frameMs = 20;
        strictSync = false;
        break;
      case SceneMode.video:
        bufferMs = 45;
        bitRate = 128;
        frameMs = 20;
        strictSync = true;
        break;
      case SceneMode.game:
        bufferMs = 20;
        bitRate = 96;
        frameMs = 10;
        strictSync = false;
        break;
      case SceneMode.weakNet:
        bufferMs = 60;
        bitRate = 96;
        frameMs = 20;
        strictSync = false;
        break;
      case SceneMode.night:
        bufferMs = 40;
        bitRate = 128;
        frameMs = 20;
        strictSync = false;
        break;
      case SceneMode.room:
        bufferMs = 50;
        bitRate = 128;
        frameMs = 20;
        strictSync = true;
        break;
    }
    notifyListeners();
    debugPrint('[SceneManager] 场景切换: ${getSceneName()} (缓冲=$bufferMs ms, 码率=$bitRate kbps, 帧长=$frameMs ms)');
  }

  void setAutoDetect(bool enabled) {
    _autoDetectEnabled = enabled;
    if (enabled) {
      startAutoDetection();
    } else {
      stopAutoDetection();
    }
    notifyListeners();
  }

  String getSceneName() {
    switch (currentScene) {
      case SceneMode.music:
        return '音乐模式';
      case SceneMode.video:
        return '观影模式';
      case SceneMode.game:
        return '游戏低延迟';
      case SceneMode.room:
        return '全屋播放';
      case SceneMode.weakNet:
        return '弱网容错';
      case SceneMode.night:
        return '夜间静谧';
    }
  }

  String getSceneDescription() {
    switch (currentScene) {
      case SceneMode.music:
        return '高音质 AAC 192kbps';
      case SceneMode.video:
        return '音画同步 45ms缓冲';
      case SceneMode.game:
        return '超低延迟 OPUS 10ms';
      case SceneMode.room:
        return '多设备同步 统一时钟';
      case SceneMode.weakNet:
        return '自适应降级 96kbps';
      case SceneMode.night:
        return '平滑渐变 低功耗';
    }
  }

  @override
  void dispose() {
    stopAutoDetection();
    super.dispose();
  }
}