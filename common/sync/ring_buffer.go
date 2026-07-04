// FyAudio 时序同步模块
// 环形音频缓冲池 + 时间戳对齐算法
package sync

import (
	"container/list"
	"log"
	"sort"
	"sync"
	"time"

	"fyaudio/common/protocol"
)

// ============================================================================
// 类型定义
// ============================================================================

// AudioFrame 音频帧（含时间戳）
type AudioFrame struct {
	Timestamp uint64 // 音源端UTC毫秒时间戳
	Payload   []byte // PCM/AAC数据
	RecvTime  int64  // 本机收到时间（毫秒）
}

// RingBuffer 环形音频缓冲池
type RingBuffer struct {
	capacity int        // 缓冲区容量（帧数）
	frames   *list.List // 双向链表存储
	maxAgeMs int64      // 帧最大存活时间（毫秒）
	mu       sync.Mutex
}

// SyncEngine 同步引擎
type SyncEngine struct {
	buffer         *RingBuffer
	bufferWindowMs int64   // 动态缓冲窗口（毫秒）
	clockOffset    int64   // 时钟偏差补偿（毫秒）
	manualOffsetMs int64   // 用户手动补偿（毫秒）
	latencyHistory []int64 // 延迟历史（滑动窗口）
	latencyIdx     int     // 已写入的延迟样本数
	estimatedRTT   int64   // 估算的RTT（毫秒）
	isPlaying      bool
	droppedFrames  int64
	totalFrames    int64
	mu             sync.RWMutex
}

// ============================================================================
// RingBuffer 环形缓冲
// ============================================================================

// NewRingBuffer 创建环形缓冲池
func NewRingBuffer(capacity int) *RingBuffer {
	return &RingBuffer{
		capacity: capacity,
		frames:   list.New(),
		maxAgeMs: 500, // 超过500ms的帧直接丢弃
	}
}

// Push 写入帧（带时间戳去重和过期检查）
func (rb *RingBuffer) Push(frame *AudioFrame) bool {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	// 检查帧是否过期
	nowMs := time.Now().UnixNano() / 1_000_000
	if int64(frame.Timestamp) < nowMs-rb.maxAgeMs {
		return false
	}

	// 去重：已有相同时间戳的帧则丢弃
	for e := rb.frames.Front(); e != nil; e = e.Next() {
		f := e.Value.(*AudioFrame)
		if f.Timestamp == frame.Timestamp {
			return false
		}
	}

	// 环形缓冲：超出容量则移除最老的帧
	if rb.frames.Len() >= rb.capacity {
		rb.frames.Remove(rb.frames.Front())
	}

	// 按时间戳有序插入
	inserted := false
	for e := rb.frames.Back(); e != nil; e = e.Prev() {
		f := e.Value.(*AudioFrame)
		if frame.Timestamp >= f.Timestamp {
			rb.frames.InsertAfter(frame, e)
			inserted = true
			break
		}
	}
	if !inserted {
		rb.frames.PushFront(frame)
	}

	return true
}

// Pop 弹出最早的帧（非阻塞，缓冲区为空时返回 nil）
func (rb *RingBuffer) Pop() *AudioFrame {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	if rb.frames.Len() == 0 {
		return nil
	}

	front := rb.frames.Front()
	frame := front.Value.(*AudioFrame)
	rb.frames.Remove(front)
	return frame
}

// GetPlayableFrame 获取已到播放时间的帧
// 帧满足: frame.Timestamp + bufferWindowMs <= nowMs
func (rb *RingBuffer) GetPlayableFrame(bufferWindowMs int64) *AudioFrame {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	if rb.frames.Len() == 0 {
		return nil
	}

	nowMs := time.Now().UnixNano() / 1_000_000
	front := rb.frames.Front()
	frame := front.Value.(*AudioFrame)

	if int64(frame.Timestamp)+bufferWindowMs <= nowMs {
		rb.frames.Remove(front)
		return frame
	}
	return nil
}

// Size 获取当前缓冲帧数
func (rb *RingBuffer) Size() int {
	rb.mu.Lock()
	defer rb.mu.Unlock()
	return rb.frames.Len()
}

// Clear 清空缓冲区
func (rb *RingBuffer) Clear() {
	rb.mu.Lock()
	defer rb.mu.Unlock()
	rb.frames.Init()
}

// Drain 丢弃所有帧并返回数量
func (rb *RingBuffer) Drain() int {
	rb.mu.Lock()
	defer rb.mu.Unlock()
	count := rb.frames.Len()
	rb.frames.Init()
	return count
}

// ============================================================================
// SyncEngine 同步引擎
// ============================================================================

// NewSyncEngine 创建同步引擎
func NewSyncEngine() *SyncEngine {
	return &SyncEngine{
		buffer:         NewRingBuffer(protocol.MaxBufferFrames),
		bufferWindowMs: int64(protocol.BufferDefaultMS),
		latencyHistory: make([]int64, 20),
		estimatedRTT:   50, // 初始估算RTT 50ms
	}
}

// FeedFrame 喂入音频帧
// 帧来自网络接收线程
func (se *SyncEngine) FeedFrame(packet *protocol.AudioFramePacket) bool {
	frame := &AudioFrame{
		Timestamp: packet.Timestamp,
		Payload:   packet.Payload,
		RecvTime:  time.Now().UnixNano() / 1_000_000,
	}

	se.mu.Lock()
	se.totalFrames++
	// 估算网络延迟
	nowMs := time.Now().UnixNano() / 1_000_000
	latency := nowMs - int64(frame.Timestamp)
	if latency < 0 {
		latency = 0
	}
	se.latencyHistory[se.latencyIdx%len(se.latencyHistory)] = latency
	se.latencyIdx++
	se.estimatedRTT = se.calcMedianLatency()
	se.updateBufferWindow()
	se.mu.Unlock()

	return se.buffer.Push(frame)
}

// calcMedianLatency 计算中位延迟（使用 sort.Ints，无副作用）
func (se *SyncEngine) calcMedianLatency() int64 {
	count := se.latencyIdx
	if count == 0 {
		return 50
	}
	if count > len(se.latencyHistory) {
		count = len(se.latencyHistory)
	}

	// 取最近 count 个值
	vals := make([]int64, count)
	copy(vals, se.latencyHistory[:count])
	sort.Slice(vals, func(i, j int) bool {
		return vals[i] < vals[j]
	})

	return vals[count/2]
}

// updateBufferWindow 根据中位延迟更新缓冲窗口
func (se *SyncEngine) updateBufferWindow() {
	median := se.calcMedianLatency()
	window := median * 2
	if window < int64(protocol.BufferMinMS) {
		window = int64(protocol.BufferMinMS)
	}
	if window > int64(protocol.BufferMaxMS) {
		window = int64(protocol.BufferMaxMS)
	}
	se.bufferWindowMs = window
}

// GetPlayableFrame 获取可播放的帧
// 帧播放条件: frame.Timestamp + windowMs <= now
// windowMs = bufferWindow + clockOffset + manualOffset
func (se *SyncEngine) GetPlayableFrame() *AudioFrame {
	se.mu.RLock()
	windowMs := se.bufferWindowMs + se.clockOffset + se.manualOffsetMs
	se.mu.RUnlock()
	return se.buffer.GetPlayableFrame(windowMs)
}

// SetManualOffset 设置手动延迟补偿
// offsetMs: 补偿毫秒数，正数延迟播放，负数提前播放
func (se *SyncEngine) SetManualOffset(offsetMs int64) {
	se.mu.Lock()
	defer se.mu.Unlock()

	// 限制范围：-200ms ~ +200ms
	if offsetMs < -200 {
		offsetMs = -200
	}
	if offsetMs > 200 {
		offsetMs = 200
	}
	se.manualOffsetMs = offsetMs
	log.Printf("[SyncEngine] 手动延迟补偿: %d ms", offsetMs)
}

// GetManualOffset 获取当前手动补偿
func (se *SyncEngine) GetManualOffset() int64 {
	se.mu.RLock()
	defer se.mu.RUnlock()
	return se.manualOffsetMs
}

// UpdateClockOffset 更新时钟偏差
func (se *SyncEngine) UpdateClockOffset(clientTime, serverTime uint64, rttMs int64) {
	se.mu.Lock()
	defer se.mu.Unlock()

	// 时钟偏差 = (服务器时间 - 客户端时间) - RTT/2
	se.clockOffset = int64(serverTime) - int64(clientTime) - (rttMs / 2)
	log.Printf("[SyncEngine] 时钟偏差补偿: %d ms (RTT=%d ms)", se.clockOffset, rttMs)
}

// Reset 重置同步状态（统一在锁内操作，再清空缓冲）
func (se *SyncEngine) Reset() {
	se.mu.Lock()
	se.clockOffset = 0
	se.manualOffsetMs = 0
	se.estimatedRTT = 50
	se.isPlaying = false
	se.latencyIdx = 0
	for i := range se.latencyHistory {
		se.latencyHistory[i] = 0
	}
	se.mu.Unlock()

	dropped := se.buffer.Drain()
	log.Printf("[SyncEngine] 同步状态已重置，丢弃 %d 帧", dropped)
}

// GetStats 获取同步统计信息
func (se *SyncEngine) GetStats() (bufferFrames int, estimatedRTT, windowMs, offsetMs int64) {
	se.mu.RLock()
	defer se.mu.RUnlock()
	return se.buffer.Size(), se.estimatedRTT, se.bufferWindowMs, se.clockOffset + se.manualOffsetMs
}

// SetPlaying 设置播放状态
func (se *SyncEngine) SetPlaying(playing bool) {
	se.mu.Lock()
	defer se.mu.Unlock()
	se.isPlaying = playing
}

// IsPlaying 是否正在播放
func (se *SyncEngine) IsPlaying() bool {
	se.mu.RLock()
	defer se.mu.RUnlock()
	return se.isPlaying
}

// ============================================================================
// 同步校准
// ============================================================================

// SyncCalibrator 同步校准器
type SyncCalibrator struct {
	requests   map[uint64]time.Time // 请求ID -> 发送时间
	mu         sync.Mutex
	lastOffset int64
}

// NewSyncCalibrator 创建校准器
func NewSyncCalibrator() *SyncCalibrator {
	return &SyncCalibrator{
		requests: make(map[uint64]time.Time),
	}
}

// MakeSyncRequest 生成同步请求（同时清理过期请求，防止内存泄漏）
func (sc *SyncCalibrator) MakeSyncRequest() *protocol.SyncRequest {
	sc.mu.Lock()
	defer sc.mu.Unlock()

	// 清理过期请求（超过10秒未响应的）
	now := time.Now()
	for id, t := range sc.requests {
		if now.Sub(t) > 10*time.Second {
			delete(sc.requests, id)
		}
	}

	req := &protocol.SyncRequest{
		ClientTime: protocol.GetTimestamp(),
	}
	sc.requests[req.ClientTime] = now
	return req
}

// HandleSyncResponse 处理同步响应
func (sc *SyncCalibrator) HandleSyncResponse(resp *protocol.SyncResponse) int64 {
	sc.mu.Lock()
	defer sc.mu.Unlock()

	sendTime, ok := sc.requests[resp.ClientTime]
	if !ok {
		return 0
	}
	delete(sc.requests, resp.ClientTime)

	// 计算RTT
	rttMs := time.Since(sendTime).Milliseconds()

	// 计算时钟偏差
	offset := int64(resp.ServerTime) - int64(resp.ClientTime) - rttMs/2
	sc.lastOffset = offset

	log.Printf("[SyncCalibrator] RTT=%d ms, 时钟偏差=%d ms", rttMs, offset)
	return offset
}

// GetLastOffset 获取最近校准的时钟偏差
func (sc *SyncCalibrator) GetLastOffset() int64 {
	sc.mu.Lock()
	defer sc.mu.Unlock()
	return sc.lastOffset
}
