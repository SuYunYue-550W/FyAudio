// FyAudio 时序同步模块
// 环形音频缓冲池 + 时间戳对齐算法
package sync

import (
	"container/list"
	"fmt"
	"log"
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
	Payload   []byte // AAC压缩数据
	RecvTime  int64  // 本机收到时间（纳秒）
}

// RingBuffer 环形音频缓冲池
type RingBuffer struct {
	capacity    int           // 缓冲区容量（帧数）
	frames      *list.List    // 双向链表存储
	maxAgeMs    int64         // 帧最大存活时间（毫秒）
	mu          sync.Mutex
	notEmpty    *sync.Cond     // 条件变量，有帧可读时通知
}

// SyncEngine 同步引擎
type SyncEngine struct {
	buffer          *RingBuffer
	bufferWindowMs  int64         // 动态缓冲窗口（毫秒）
	clockOffset     int64         // 时钟偏差补偿（毫秒）
	manualOffsetMs  int64         // 用户手动补偿（毫秒）
	latencyHistory  []int64       // 延迟历史（滑动窗口）
	latencyIdx      int
	estimatedRTT    int64         // 估算的RTT（毫秒）
	isPlaying      bool
	droppedFrames   int64
	totalFrames     int64
	mu              sync.RWMutex
}

// ============================================================================
// RingBuffer 环形缓冲
// ============================================================================

// NewRingBuffer 创建环形缓冲池
func NewRingBuffer(capacity int) *RingBuffer {
	rb := &RingBuffer{
		capacity: capacity,
		frames:    list.New(),
		maxAgeMs:  500, // 超过500ms的帧直接丢弃
	}
	rb.notEmpty = sync.NewCond(&rb.mu)
	return rb
}

// Push 写入帧（带时间戳）
func (rb *RingBuffer) Push(frame *AudioFrame) bool {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	// 检查帧是否过期
	nowMs := time.Now().UnixNano() / 1_000_000
	if int64(frame.Timestamp) < nowMs-rb.maxAgeMs {
		// 帧已过期，丢弃
		return false
	}

	// 环形缓冲：超出容量则移除最老的帧
	if rb.frames.Len() >= rb.capacity {
		rb.frames.Remove(rb.frames.Front())
	}

	// 插入到正确位置（按时间戳排序，二分查找优化可用二叉搜索树）
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

	rb.notEmpty.Signal()
	return true
}

// Pop 弹出最早可播放的帧
// wait=true 时阻塞等待，wait=false 时立即返回
func (rb *RingBuffer) Pop(wait bool) (*AudioFrame, error) {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	for rb.frames.Len() == 0 {
		if !wait {
			return nil, fmt.Errorf("缓冲区为空")
		}
		rb.notEmpty.Wait()
	}

	front := rb.frames.Front()
	frame := front.Value.(*AudioFrame)
	rb.frames.Remove(front)
	return frame, nil
}

// PopByTimestamp 按时间戳弹出帧
// 返回 <= targetTimestamp 的最早帧
func (rb *RingBuffer) PopByTimestamp(targetTimestamp uint64) (*AudioFrame, error) {
	rb.mu.Lock()
	defer rb.mu.Unlock()

	if rb.frames.Len() == 0 {
		return nil, fmt.Errorf("缓冲区为空")
	}

	front := rb.frames.Front()
	frame := front.Value.(*AudioFrame)

	if frame.Timestamp > targetTimestamp {
		return nil, fmt.Errorf("下一帧未到播放时间")
	}

	rb.frames.Remove(front)
	return frame, nil
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
	se := &SyncEngine{
		buffer:         NewRingBuffer(protocol.MaxBufferFrames),
		bufferWindowMs: int64(protocol.BufferDefaultMS),
		latencyHistory: make([]int64, 20),
		latencyIdx:     0,
		estimatedRTT:   50, // 初始估算RTT 50ms
	}
	return se
}

// FeedFrame 喂入音频帧
// 帧来自网络接收线程
func (se *SyncEngine) FeedFrame(packet *protocol.AudioFramePacket) bool {
	frame := &AudioFrame{
		Timestamp: packet.Timestamp,
		Payload:   packet.Payload,
		RecvTime:  time.Now().UnixNano(),
	}

	se.mu.Lock()
	se.totalFrames++
	// 估算网络延迟
	nowMs := time.Now().UnixNano() / 1_000_000
	latency := int64(nowMs) - int64(frame.Timestamp)
	if latency < 0 {
		latency = 0
	}
	se.latencyHistory[se.latencyIdx%len(se.latencyHistory)] = latency
	se.latencyIdx++
	se.estimatedRTT = se.calcMedianLatency()
	se.mu.Unlock()

	return se.buffer.Push(frame)
}

// calcMedianLatency 计算中位延迟
func (se *SyncEngine) calcMedianLatency() int64 {
	count := se.latencyIdx
	if count == 0 {
		return 50
	}
	if count > len(se.latencyHistory) {
		count = len(se.latencyHistory)
	}

	// 取最近count个值的中位数
	vals := make([]int64, count)
	for i := 0; i < count; i++ {
		vals[i] = se.latencyHistory[i]
	}

	// 简单选择排序
	for i := 0; i < count-1; i++ {
		minIdx := i
		for j := i + 1; j < count; j++ {
			if vals[j] < vals[minIdx] {
				minIdx = j
			}
		}
		vals[i], vals[minIdx] = vals[minIdx], vals[i]
	}

	// 返回中位数
	median := vals[count/2]
	// 更新缓冲窗口 = 中位延迟 * 2，但不超过最大值
	window := median * 2
	if window < protocol.BufferMinMS {
		window = protocol.BufferMinMS
	}
	if window > protocol.BufferMaxMS {
		window = protocol.BufferMaxMS
	}
	se.bufferWindowMs = window

	return median
}

// GetPlayableFrame 获取可播放的帧
// 计算帧的实际播放时间
func (se *SyncEngine) GetPlayableFrame() (*AudioFrame, error) {
	se.mu.RLock()
	nowMs := time.Now().UnixNano() / 1_000_000
	// 计算目标播放时间
	targetPlayTime := nowMs + se.bufferWindowMs + se.clockOffset + se.manualOffsetMs
	se.mu.RUnlock()

	// 按目标时间查找帧
	frame, err := se.buffer.PopByTimestamp(uint64(targetPlayTime))
	if err != nil {
		// 缓冲区不足，等待
		frame, err = se.buffer.Pop(true) // 阻塞等待
		if err != nil {
			return nil, err
		}
	}

	return frame, nil
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

// Reset 重置同步状态
func (se *SyncEngine) Reset() {
	se.buffer.Clear()
	se.mu.Lock()
	se.clockOffset = 0
	se.estimatedRTT = 50
	se.isPlaying = false
	se.mu.Unlock()
	log.Printf("[SyncEngine] 同步状态已重置，丢弃 %d 帧", se.buffer.Drain())
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

// MakeSyncRequest 生成同步请求
func (sc *SyncCalibrator) MakeSyncRequest() *protocol.SyncRequest {
	sc.mu.Lock()
	defer sc.mu.Unlock()

	req := &protocol.SyncRequest{
		ClientTime: protocol.GetTimestamp(),
	}
	sc.requests[req.ClientTime] = time.Now()
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
