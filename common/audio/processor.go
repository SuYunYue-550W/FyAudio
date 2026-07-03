// FyAudio 音频处理模块
// PCM 音频处理（AAC 等编解码器暂不支持，默认使用 PCM 透传）
package audio

import (
	"encoding/binary"
	"fmt"
	"math"
	"sync"
	"time"

	"fyaudio/common/protocol"
)

// ============================================================================
// 常量
// ============================================================================

const (
	SampleRate    = 44100
	Channels      = 2
	BitsPerSample = 16
	FrameDuration = 20                                                  // ms
	FrameSamples  = SampleRate * FrameDuration / 1000                   // 882 samples @ 44100Hz
	PCMTotalBytes = FrameSamples * Channels * (BitsPerSample / 8)       // 3528 bytes
)

// ============================================================================
// 类型定义
// ============================================================================

// AudioCapture 音频采集接口
type AudioCapture interface {
	Start() error
	Stop()
	ReadPCM() ([]byte, error) // 返回原始PCM数据
	IsActive() bool
}

// AudioPlayer 音频播放接口
type AudioPlayer interface {
	Start() error
	Stop()
	PlayPCM([]byte) error // 写入PCM数据播放
	IsActive() bool
	SetVolume(volume int) // 0-100
}

// AudioEncoder 音频编码器（PCM 透传模式）
type AudioEncoder struct {
	sampleRate int
	channels   int
	bitrate    int
	frameSize  int
}

// AudioDecoder 音频解码器（PCM 透传模式）
type AudioDecoder struct {
	sampleRate int
	channels   int
}

// FrameHandler 音频帧处理器
type FrameHandler struct {
	encoder    *AudioEncoder
	decoder    *AudioDecoder
	playbackCh chan *protocol.AudioFramePacket // 接收端播放队列
	quit       chan struct{}
	stopOnce   sync.Once
	wg         sync.WaitGroup
}

// PCMBuffer PCM音频缓冲
type PCMBuffer struct {
	samples []int16 // 立体声交错样本
	mu      sync.Mutex
}

// ============================================================================
// AudioEncoder 编码器
// ============================================================================

// NewAudioEncoder 创建编码器
// PCM 模式直接透传，AAC 等编解码器暂不支持
func NewAudioEncoder(sampleRate, channels, bitrate int) *AudioEncoder {
	return &AudioEncoder{
		sampleRate: sampleRate,
		channels:   channels,
		bitrate:    bitrate,
		frameSize:  sampleRate * channels * (BitsPerSample / 8) * FrameDuration / 1000,
	}
}

// Encode 将PCM数据编码
// PCM 模式直接透传（补齐/截断到帧大小）
func (e *AudioEncoder) Encode(pcm []byte) ([]byte, error) {
	expected := e.frameSize
	if len(pcm) < expected {
		padding := make([]byte, expected-len(pcm))
		pcm = append(pcm, padding...)
	} else if len(pcm) > expected {
		pcm = pcm[:expected]
	}
	return pcm, nil
}

// FrameSize 返回每帧字节数
func (e *AudioEncoder) FrameSize() int {
	return e.frameSize
}

// ============================================================================
// AudioDecoder 解码器
// ============================================================================

// NewAudioDecoder 创建解码器
func NewAudioDecoder(sampleRate, channels int) *AudioDecoder {
	return &AudioDecoder{
		sampleRate: sampleRate,
		channels:   channels,
	}
}

// Decode 解码为PCM
// PCM 模式直接透传
func (d *AudioDecoder) Decode(data []byte) ([]byte, error) {
	return data, nil
}

// ============================================================================
// FrameHandler 帧处理器
// ============================================================================

// NewFrameHandler 创建帧处理器
func NewFrameHandler(encoder *AudioEncoder, decoder *AudioDecoder) *FrameHandler {
	return &FrameHandler{
		encoder:    encoder,
		decoder:    decoder,
		playbackCh: make(chan *protocol.AudioFramePacket, 50),
		quit:       make(chan struct{}),
	}
}

// StartCaptureLoop 启动采集-编码循环（Source端使用）
func (h *FrameHandler) StartCaptureLoop(capture AudioCapture, broadcastFunc func(*protocol.AudioFramePacket)) {
	h.wg.Add(1)
	go func() {
		defer h.wg.Done()
		ticker := time.NewTicker(time.Duration(protocol.FrameDuration) * time.Millisecond)
		defer ticker.Stop()

		for {
			select {
			case <-h.quit:
				return
			case <-ticker.C:
				pcm, err := capture.ReadPCM()
				if err != nil || len(pcm) == 0 {
					continue
				}

				encoded, err := h.encoder.Encode(pcm)
				if err != nil || len(encoded) == 0 {
					continue
				}

				frame := protocol.NewAudioFrame(encoded, protocol.GetTimestamp())

				if broadcastFunc != nil {
					broadcastFunc(frame)
				}
			}
		}
	}()
}

// StartPlaybackLoop 启动解码-播放循环（Receiver端使用）
// 通过 onPCM 回调将解码后的 PCM 数据送出
func (h *FrameHandler) StartPlaybackLoop(onPCM func(pcm []byte, timestamp uint64)) {
	h.wg.Add(1)
	go func() {
		defer h.wg.Done()
		for {
			select {
			case <-h.quit:
				return
			case frame := <-h.playbackCh:
				pcm, err := h.decoder.Decode(frame.Payload)
				if err != nil || len(pcm) == 0 {
					continue
				}
				if onPCM != nil {
					onPCM(pcm, frame.Timestamp)
				}
			}
		}
	}()
}

// FeedFrameForPlayback 喂入接收到的音频帧用于播放
func (h *FrameHandler) FeedFrameForPlayback(frame *protocol.AudioFramePacket) {
	select {
	case h.playbackCh <- frame:
	default:
		// 队列满，丢弃帧
	}
}

// FeedFrame 同步解码一帧（工具方法）
func (h *FrameHandler) FeedFrame(payload []byte) ([]byte, error) {
	return h.decoder.Decode(payload)
}

// Stop 停止处理（sync.Once 保护，等待所有 goroutine 退出）
func (h *FrameHandler) Stop() {
	h.stopOnce.Do(func() {
		close(h.quit)
	})
	h.wg.Wait()
}

// ============================================================================
// PCMBuffer PCM缓冲
// ============================================================================

// NewPCMBuffer 创建PCM缓冲
func NewPCMBuffer(maxSamples int) *PCMBuffer {
	return &PCMBuffer{
		samples: make([]int16, 0, maxSamples),
	}
}

// WriteInt16 写入Int16样本
func (b *PCMBuffer) WriteInt16(samples []int16) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.samples = append(b.samples, samples...)
}

// WriteBytes 写入字节（自动转换为Int16，优化切片操作）
func (b *PCMBuffer) WriteBytes(data []byte) error {
	if len(data)%2 != 0 {
		return fmt.Errorf("PCM字节长度必须为偶数: %d", len(data))
	}
	n := len(data) / 2
	b.mu.Lock()
	defer b.mu.Unlock()
	// 一次性扩容，避免逐个 append 导致多次扩容
	start := len(b.samples)
	b.samples = append(b.samples, make([]int16, n)...)
	for i := 0; i < n; i++ {
		b.samples[start+i] = int16(binary.LittleEndian.Uint16(data[i*2 : i*2+2]))
	}
	return nil
}

// Read 读取并清空缓冲区
func (b *PCMBuffer) Read() []int16 {
	b.mu.Lock()
	defer b.mu.Unlock()
	samples := make([]int16, len(b.samples))
	copy(samples, b.samples)
	b.samples = b.samples[:0]
	return samples
}

// Size 返回当前缓冲样本数
func (b *PCMBuffer) Size() int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.samples)
}

// Silence 检测是否为静音
func (b *PCMBuffer) Silence(threshold int16) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, s := range b.samples {
		if s < -threshold || s > threshold {
			return false
		}
	}
	return true
}

// ============================================================================
// 工具函数
// ============================================================================

// Mix 混音（多路PCM叠加）
func Mix(pcm1, pcm2 []int16, gain1, gain2 float32) []int16 {
	maxLen := len(pcm1)
	if len(pcm2) > maxLen {
		maxLen = len(pcm2)
	}
	result := make([]int16, maxLen)

	for i := 0; i < maxLen; i++ {
		var v1, v2 int32
		if i < len(pcm1) {
			v1 = int32(float32(pcm1[i]) * gain1)
		}
		if i < len(pcm2) {
			v2 = int32(float32(pcm2[i]) * gain2)
		}
		sum := v1 + v2
		if sum > 32767 {
			sum = 32767
		}
		if sum < -32768 {
			sum = -32768
		}
		result[i] = int16(sum)
	}
	return result
}

// ToBytes 将Int16样本转为字节
func ToBytes(samples []int16) []byte {
	buf := make([]byte, len(samples)*2)
	for i, s := range samples {
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(s))
	}
	return buf
}

// VolumeScale 按音量缩放PCM
func VolumeScale(samples []byte, volume int) []byte {
	if volume < 0 {
		volume = 0
	}
	if volume > 100 {
		volume = 100
	}
	scale := float32(volume) / 100.0

	buf := make([]byte, len(samples))
	for i := 0; i+1 < len(samples); i += 2 {
		sample := int16(binary.LittleEndian.Uint16(samples[i : i+2]))
		scaled := float32(sample) * scale
		if scaled > 32767 {
			scaled = 32767
		}
		if scaled < -32768 {
			scaled = -32768
		}
		binary.LittleEndian.PutUint16(buf[i:i+2], uint16(int16(scaled)))
	}
	return buf
}

// ============================================================================
// 静音检测
// ============================================================================

// IsSilent 检测PCM数据是否为静音
func IsSilent(pcm []byte, threshold int16) bool {
	if len(pcm) < 2 {
		return true
	}
	for i := 0; i+1 < len(pcm); i += 2 {
		sample := int16(binary.LittleEndian.Uint16(pcm[i : i+2]))
		if sample < -threshold || sample > threshold {
			return false
		}
	}
	return true
}

// RMS 计算RMS电平
func RMS(pcm []byte) float64 {
	if len(pcm) < 2 {
		return 0
	}
	var sum float64
	count := 0
	for i := 0; i+1 < len(pcm); i += 2 {
		sample := int16(binary.LittleEndian.Uint16(pcm[i : i+2]))
		sum += float64(sample) * float64(sample)
		count++
	}
	if count == 0 {
		return 0
	}
	return math.Sqrt(sum / float64(count))
}

// dBFS 将RMS转换为dBFS
func dBFS(rms float64) float64 {
	if rms <= 0 {
		return -96.0
	}
	return 20 * math.Log10(rms/32768.0)
}
