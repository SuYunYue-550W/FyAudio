import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// 场景模式 - 决定缓冲/码率/帧长/严格同步等参数
enum SceneMode { music, video, game, room, weakNet, night }

/// 场景自动检测与切换管理器
///
/// 通过 [onSceneChanged] 回调将场景参数广播给 AudioService / NetworkService，
/// 避免反向依赖。所有可变字段私有化，仅通过 getter 暴露。
class SceneAutoManager extends ChangeNotifier {
  double _bufferMs = 40;
  int _bitRate = 128;
  int _frameMs = 20;
  bool _strictSync = false;
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

  /// 场景变更回调 - 由外部（如 HomeScreen）注册，转发给 AudioService / NetworkService
  void Function(SceneMode mode, int bufferMs, int bitRate, int frameMs, bool strictSync)?
      onSceneChanged;

  double get bufferMs => _bufferMs;
  int get bitRate => _bitRate;
  int get frameMs => _frameMs;
  bool get strictSync => _strictSync;
  bool get autoDetectEnabled => _autoDetectEnabled;
  double get currentLossRate => _currentLossRate;
  int get deviceCount => _deviceCount;

  /// 启动自动检测 - 先取消已有定时器避免泄漏
  void startAutoDetection() {
    _detectionTimer?.cancel();
    _networkMonitorTimer?.cancel();
    _autoDetectEnabled = true;
    _detectionTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _performAutoDetection());
    _networkMonitorTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _monitorNetworkQuality());
    debugPrint('[SceneManager] 自动场景检测已启动');
  }

  void stopAutoDetection() {
    _autoDetectEnabled = false;
    _detectionTimer?.cancel();
    _networkMonitorTimer?.cancel();
    _detectionTimer = null;
    _networkMonitorTimer = null;
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
      final highFreqEnergy =
          _currentFreq.sublist(16, 32).reduce((a, b) => a + b) / 16;
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
      final midFreqEnergy =
          _currentFreq.sublist(4, 12).reduce((a, b) => a + b) / 8;
      final lowFreqEnergy =
          _currentFreq.sublist(0, 4).reduce((a, b) => a + b) / 4;
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

  /// 网络质量监控 - 当前为模拟数据
  // TODO: 替换为基于 NetworkService 真实统计的丢包率与延迟采集
  void _monitorNetworkQuality() {
    _currentLossRate = 0.01 + _random.nextDouble() * 0.04;
    _isHighLatency = _random.nextDouble() > 0.85;
    _isLowBandwidth = _random.nextDouble() > 0.9;
  }

  /// 供外部更新音频频谱（用于场景判定的输入）
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

  /// 应用场景 - 通过回调通知 AudioService / NetworkService
  void applyScene(SceneMode mode) {
    currentScene = mode;
    switch (mode) {
      case SceneMode.music:
        _bufferMs = 40;
        _bitRate = 192;
        _frameMs = 20;
        _strictSync = false;
        break;
      case SceneMode.video:
        _bufferMs = 45;
        _bitRate = 128;
        _frameMs = 20;
        _strictSync = true;
        break;
      case SceneMode.game:
        _bufferMs = 20;
        _bitRate = 96;
        _frameMs = 10;
        _strictSync = false;
        break;
      case SceneMode.weakNet:
        _bufferMs = 60;
        _bitRate = 96;
        _frameMs = 20;
        _strictSync = false;
        break;
      case SceneMode.night:
        _bufferMs = 40;
        _bitRate = 128;
        _frameMs = 20;
        _strictSync = false;
        break;
      case SceneMode.room:
        _bufferMs = 50;
        _bitRate = 128;
        _frameMs = 20;
        _strictSync = true;
        break;
    }
    // 通过回调通知 AudioService / NetworkService 调整参数
    onSceneChanged?.call(mode, _bufferMs.toInt(), _bitRate, _frameMs, _strictSync);
    notifyListeners();
    debugPrint(
        '[SceneManager] 场景切换: ${getSceneName()} (缓冲=$_bufferMs ms, 码率=$_bitRate kbps, 帧长=$_frameMs ms)');
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
