import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/models.dart';

class SyncService extends ChangeNotifier {
  final List<AudioFrame> _buffer = []; // 环形缓冲
  final int _bufferCapacity = 200;
  int _bufferWindowMs = 40;
  int _manualOffsetMs = 0;
  int _clockOffsetMs = 0;
  int _estimatedRTT = 0;
  bool _isPlaying = false;
  int _droppedFrames = 0;
  int _totalFrames = 0;

  Timer? _syncTimer;
  Function(AudioFrame)? onPlayableFrame;

  SyncStats get stats => SyncStats(
        bufferFrames: _buffer.length,
        estimatedRTT: _estimatedRTT,
        windowMs: _bufferWindowMs,
        offsetMs: _clockOffsetMs + _manualOffsetMs,
        isPlaying: _isPlaying,
        droppedFrames: _droppedFrames,
        totalFrames: _totalFrames,
      );

  int get bufferWindowMs => _bufferWindowMs;
  int get manualOffsetMs => _manualOffsetMs;
  bool get isPlaying => _isPlaying;
  int get bufferSize => _buffer.length;

  // =========================================================================
  // 接收音频帧
  // =========================================================================

  void feedFrame(AudioFrame frame) {
    _totalFrames++;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 过期帧丢弃（超过500ms）
    if (nowMs - frame.timestamp > 500) {
      _droppedFrames++;
      return;
    }

    // 插入排序（按时间戳）
    _insertFrame(frame);

    // 动态调整缓冲窗口
    _adjustBufferWindow(frame.timestamp, nowMs);

    // 触发播放检查
    _checkPlayable(nowMs);

    notifyListeners();
  }

  void _insertFrame(AudioFrame frame) {
    // 环形缓冲：超出容量丢弃最老的
    if (_buffer.length >= _bufferCapacity) {
      _buffer.removeAt(0);
    }

    // 按时间戳插入（O(n)，可优化为二叉搜索）
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
    // 估算延迟
    final latency = nowMs - frameTimestamp;
    _estimatedRTT = (_estimatedRTT + latency) ~/ 2;

    // 动态调整缓冲窗口
    final targetWindow = (_estimatedRTT * 2).clamp(20, 200);
    _bufferWindowMs = (_bufferWindowMs + targetWindow) ~/ 2;
  }

  void _checkPlayable(int nowMs) {
    if (_buffer.isEmpty || !_isPlaying) return;

    final front = _buffer.first;
    // 计算播放时间 = 帧时间戳 + 缓冲窗口 + 手动补偿 + 时钟补偿
    final playTime = front.timestamp + _bufferWindowMs + _manualOffsetMs + _clockOffsetMs;

    if (nowMs >= playTime) {
      // 可以播放
      final frame = _buffer.removeAt(0);
      onPlayableFrame?.call(frame);
    }
  }

  // =========================================================================
  // 播放控制
  // =========================================================================

  void startPlaying() {
    _isPlaying = true;
    notifyListeners();
  }

  void pausePlaying() {
    _isPlaying = false;
    notifyListeners();
  }

  void reset() {
    _buffer.clear();
    _bufferWindowMs = 40;
    _clockOffsetMs = 0;
    _isPlaying = false;
    _droppedFrames = 0;
    _totalFrames = 0;
    notifyListeners();
    debugPrint('[Sync] 同步状态已重置');
  }

  // =========================================================================
  // 手动延迟补偿
  // =========================================================================

  void setManualOffset(int offsetMs) {
    _manualOffsetMs = offsetMs.clamp(-200, 200);
    debugPrint('[Sync] 手动延迟补偿: ${_manualOffsetMs}ms');
    notifyListeners();
  }

  void adjustOffset(int deltaMs) {
    setManualOffset(_manualOffsetMs + deltaMs);
  }

  // =========================================================================
  // 同步校准
  // =========================================================================

  void updateClockOffset(int clientTime, int serverTime, int rttMs) {
    _clockOffsetMs = (serverTime - clientTime - rttMs ~/ 2);
    debugPrint('[Sync] 时钟偏差补偿: ${_clockOffsetMs}ms (RTT=$rttMs)');
    notifyListeners();
  }

  // =========================================================================
  // 统计
  // =========================================================================

  void clearStats() {
    _droppedFrames = 0;
    _totalFrames = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
