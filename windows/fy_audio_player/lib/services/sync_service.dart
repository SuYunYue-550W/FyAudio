import 'package:flutter/foundation.dart';
import '../core/models.dart';

/// 同步服务：接收音频帧并缓冲，按时间戳调度播放。
///
/// 时间戳统一使用毫秒（[DateTime.now().millisecondsSinceEpoch]）。
/// 缓冲区使用 [List<AudioFrame>] 按时间戳升序插入，帧去重，过期帧丢弃。
class SyncService extends ChangeNotifier {
  final List<AudioFrame> _buffer = [];
  static const int _bufferCapacity = ProtocolConst.maxBufferFrames;
  static const int _maxAgeMs = 500; // 过期帧阈值
  static const int _playThreshold = 3; // 缓冲达到此帧数自动播放

  int _bufferWindowMs = ProtocolConst.bufferDefaultMs;
  int _manualOffsetMs = 0;
  int _clockOffsetMs = 0;
  int _estimatedRTT = 0;
  bool _isPlaying = false;
  int _droppedFrames = 0;
  int _totalFrames = 0;

  /// 帧到达播放时间时回调（由 home_screen 注册到 audio_service.playFrame）。
  Function(AudioFrame)? onPlayableFrame;

  /// 同步统计更新回调（供 home_screen 注册转发到 AppState）。
  Function(SyncStats)? onStatsUpdate;

  SyncStats get stats => getStats();

  int get bufferWindowMs => _bufferWindowMs;
  int get manualOffsetMs => _manualOffsetMs;
  bool get isPlaying => _isPlaying;
  int get bufferSize => _buffer.length;

  /// 通知状态变化并触发统计回调。
  ///
  /// 所有状态变更应通过此方法而非直接调用 [notifyListeners]，
  /// 以确保 [onStatsUpdate] 回调能收到最新统计。
  void _notify() {
    notifyListeners();
    onStatsUpdate?.call(getStats());
  }

  // =========================================================================
  // 接收音频帧
  // =========================================================================

  /// 接收音频帧并缓冲。
  void feedFrame(AudioFrame frame) {
    _totalFrames++;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 丢弃过期帧：timestamp < nowMs - maxAgeMs
    if (frame.timestamp < nowMs - _maxAgeMs) {
      _droppedFrames++;
      _notify();
      return;
    }

    // 帧去重：相同时间戳的帧只保留一个
    final exists = _buffer.any((f) => f.timestamp == frame.timestamp);
    if (exists) {
      _droppedFrames++;
      _notify();
      return;
    }

    // 按时间戳升序插入
    _insertFrame(frame);

    // 动态调整缓冲窗口
    _adjustBufferWindow(frame.timestamp, nowMs);

    // 缓冲达到阈值自动开始播放
    if (!_isPlaying && _buffer.length >= _playThreshold) {
      startPlaying();
    }

    // 播放所有已到时间的帧
    _checkPlayable(nowMs);

    _notify();
  }

  void _insertFrame(AudioFrame frame) {
    // 超出容量丢弃最老的
    if (_buffer.length >= _bufferCapacity) {
      _buffer.removeAt(0);
    }

    // 按时间戳升序插入
    var inserted = false;
    for (var i = _buffer.length - 1; i >= 0; i--) {
      if (frame.timestamp >= _buffer[i].timestamp) {
        _buffer.insert(i + 1, frame);
        inserted = true;
        break;
      }
    }
    if (!inserted) {
      _buffer.insert(0, frame);
    }
  }

  void _adjustBufferWindow(int frameTimestamp, int nowMs) {
    final latency = nowMs - frameTimestamp;
    if (latency < 0) return; // 未来帧，忽略
    _estimatedRTT = (_estimatedRTT + latency) ~/ 2;
    final targetWindow = (_estimatedRTT * 2).clamp(
      ProtocolConst.bufferMinMs,
      ProtocolConst.bufferMaxMs,
    );
    _bufferWindowMs = (_bufferWindowMs + targetWindow) ~/ 2;
  }

  /// 用 while 循环播放所有已到时间的帧。
  void _checkPlayable(int nowMs) {
    if (!_isPlaying) return;

    while (_buffer.isNotEmpty) {
      final front = _buffer.first;
      // 播放时间 = 帧时间戳 + 缓冲窗口 + 手动补偿 + 时钟补偿
      final playTime = front.timestamp +
          _bufferWindowMs +
          _manualOffsetMs +
          _clockOffsetMs;
      if (nowMs < playTime) break;

      final frame = _buffer.removeAt(0);
      onPlayableFrame?.call(frame);
    }
  }

  // =========================================================================
  // 播放控制
  // =========================================================================

  void startPlaying() {
    _isPlaying = true;
    _notify();
  }

  void stopPlaying() {
    _isPlaying = false;
    _notify();
  }

  /// pausePlaying 作为 stopPlaying 的别名（兼容 home_screen 调用）。
  void pausePlaying() => stopPlaying();

  // =========================================================================
  // 时钟校准与手动补偿
  // =========================================================================

  /// 更新时钟偏移。
  /// [serverTime] 为服务端毫秒时间戳，[rttMs] 为往返延迟。
  /// 隐含使用本机当前时间作为 clientTime。
  void updateClockOffset(int serverTime, int rttMs) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _clockOffsetMs = serverTime - nowMs - rttMs ~/ 2;
    debugPrint('[Sync] 时钟偏差补偿: ${_clockOffsetMs}ms (RTT=$rttMs)');
    _notify();
  }

  void setManualOffset(int offsetMs) {
    _manualOffsetMs = offsetMs.clamp(-200, 200);
    debugPrint('[Sync] 手动延迟补偿: ${_manualOffsetMs}ms');
    _notify();
  }

  void adjustOffset(int deltaMs) {
    setManualOffset(_manualOffsetMs + deltaMs);
  }

  // =========================================================================
  // 统计
  // =========================================================================

  SyncStats getStats() {
    return SyncStats(
      bufferFrames: _buffer.length,
      estimatedRTT: _estimatedRTT,
      windowMs: _bufferWindowMs,
      offsetMs: _clockOffsetMs + _manualOffsetMs,
      isPlaying: _isPlaying,
      droppedFrames: _droppedFrames,
      totalFrames: _totalFrames,
    );
  }

  void clearStats() {
    _droppedFrames = 0;
    _totalFrames = 0;
    _notify();
  }

  /// 完整重置（包括 _estimatedRTT 和 _manualOffsetMs）。
  void reset() {
    _buffer.clear();
    _bufferWindowMs = ProtocolConst.bufferDefaultMs;
    _clockOffsetMs = 0;
    _manualOffsetMs = 0;
    _estimatedRTT = 0;
    _isPlaying = false;
    _droppedFrames = 0;
    _totalFrames = 0;
    _notify();
    debugPrint('[Sync] 同步状态已重置');
  }

  @override
  void dispose() {
    _buffer.clear();
    super.dispose();
  }
}
