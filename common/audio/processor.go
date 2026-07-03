// FyAudio 音频处理模块
// 跨平台 AAC 编码/解码、PCM 音频处理
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
	SampleRate   = 44100
	Channels     = 2
	BitsPerSample = 16
	FrameDuration = 20 // ms
	FrameSamples  = SampleRate * FrameDuration / 1000 // 882 samples @ 44100Hz
	PCMTotalBytes = FrameSamples * Channels * (BitsPerSample / 8) // 3528 bytes
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

// AudioEncoder 音频编码器（AAC）
type AudioEncoder struct {
	sampleRate int
	channels   int
	bitrate    int
	frameSize  int
}

// AudioDecoder 音频解码器（AAC）
type AudioDecoder struct {
	sampleRate int
	channels   int
}

// AACFrameHandler AAC帧处理
type AACFrameHandler struct {
	encoder *AudioEncoder
	decoder *AudioDecoder
	onFrame func(payload []byte, timestamp uint64) // 编码完成回调
	quit    chan struct{}
	wg      sync.WaitGroup
}

// PCMBuffer PCM音频缓冲
type PCMBuffer struct {
	samples []int16      // 立体声交错样本
	mu      sync.Mutex
}

// ============================================================================
// AudioEncoder 编码器
// ============================================================================

// NewAudioEncoder 创建AAC编码器
// 注意：实际编码依赖 FFmpeg（通过系统调用）
func NewAudioEncoder(sampleRate, channels, bitrate int) *AudioEncoder {
	return &AudioEncoder{
		sampleRate: sampleRate,
		channels:   channels,
		bitrate:    bitrate,
		frameSize:  sampleRate * channels * (bitsPerSample() / 8) * FrameDuration / 1000,
	}
}

// bitsPerSample 返回采样位数
func bitsPerSample() int { return 16 }

// Encode 将PCM数据编码为AAC帧
// 返回: AAC帧数据（已包含ADTS头）
func (e *AudioEncoder) Encode(pcm []byte) ([]byte, error) {
	// 校验PCM长度
	expectedLen := e.frameSize
	if len(pcm) < expectedLen {
		// 填充静音
		padding := make([]byte, expectedLen-len(pcm))
		for i := range padding {
			padding[i] = 0
		}
		pcm = append(pcm, padding...)
	}

	// TODO: 实际调用 FFmpeg 命令行工具进行 AAC 编码
	// macOS/Linux: ffmpeg -f s16le -ar 44100 -ac 2 -i - -c:a aac -b:a 128k -frames:a 1 -f adts -
	// Windows: 通过 FFmpeg Go bindings 或 subprocess 调用
	// 这里返回占位数据，实际项目需要接入 FFmpeg
	return e.encodeWithFFmpeg(pcm)
}

// encodeWithFFmpeg 通过FFmpeg执行AAC编码
func (e *AudioEncoder) encodeWithFFmpeg(pcm []byte) ([]byte, error) {
	// 占位实现
	// 真实实现需要使用 FFmpeg C bindings (avcodec) 或 subprocess
	// 这里模拟返回编码后的数据（实际为压缩噪声）
	return pcm, nil
}

// FrameSize 返回每帧字节数
func (e *AudioEncoder) FrameSize() int {
	return e.frameSize
}

// ============================================================================
// AudioDecoder 解码器
// ============================================================================

// NewAudioDecoder 创建AAC解码器
func NewAudioDecoder(sampleRate, channels int) *AudioDecoder {
	return &AudioDecoder{
		sampleRate: sampleRate,
		channels:   channels,
	}
}

// Decode 解码AAC帧为PCM
// 输入: AAC帧数据（带ADTS头）
// 输出: PCM原始音频
func (d *AudioDecoder) Decode(aac []byte) ([]byte, error) {
	// TODO: 实际调用 FFmpeg 解码
	// 真实实现使用 FFmpeg API: avcodec_send_packet / avcodec_receive_frame
	return d.decodeWithFFmpeg(aac)
}

// decodeWithFFmpeg 通过FFmpeg执行解码
func (d *AudioDecoder) decodeWithFFmpeg(aac []byte) ([]byte, error) {
	// 占位实现
	return aac, nil
}

// ============================================================================
// AACFrameHandler AAC帧处理器
// ============================================================================

// NewAACFrameHandler 创建AAC帧处理器
func NewAACFrameHandler(encoder *AudioEncoder, decoder *AudioDecoder) *AACFrameHandler {
	return &AACFrameHandler{
		encoder: encoder,
		decoder: decoder,
		quit:    make(chan struct{}),
	}
}

// StartCaptureLoop 启动采集-编码循环（Source端使用）
func (h *AACFrameHandler) StartCaptureLoop(capture AudioCapture, broadcastFunc func(*protocol.AudioFramePacket)) {
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

				aac, err := h.encoder.Encode(pcm)
				if err != nil || len(aac) == 0 {
					continue
				}

				frame := protocol.NewAudioFrame(aac, protocol.GetTimestamp())

				if h.onFrame != nil {
					h.onFrame(aac, frame.Timestamp)
				}

				if broadcastFunc != nil {
					broadcastFunc(frame)
				}
			}
		}
	}()
}

// StartPlaybackLoop 启动解码-播放循环（Receiver端使用）
func (h *AACFrameHandler) StartPlaybackLoop(decoder *AudioDecoder, player AudioPlayer, syncEngine interface{}) {
	h.wg.Add(1)
	go func() {
		defer h.wg.Done()

		for {
			select {
			case <-h.quit:
				return
			default:
				// 从同步引擎获取帧
				// TODO: 接入 sync.SyncEngine
				time.Sleep(10 * time.Millisecond)
			}
		}
	}()
}

// FeedFrame 喂入AAC帧进行解码
func (h *AACFrameHandler) FeedFrame(payload []byte) ([]byte, error) {
	return h.decoder.Decode(payload)
}

// Stop 停止处理
func (h *AACFrameHandler) Stop() {
	close(h.quit)
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

// WriteBytes 写入字节（自动转换）
func (b *PCMBuffer) WriteBytes(data []byte) error {
	if len(data)%2 != 0 {
		return fmt.Errorf("PCM字节长度必须为偶数: %d", len(data))
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for i := 0; i < len(data); i += 2 {
		sample := int16(binary.LittleEndian.Uint16([]byte{data[i], data[i+1]}))
		b.samples = append(b.samples, sample)
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
		// 限幅
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
	// volume: 0-100
	if volume < 0 {
		volume = 0
	}
	if volume > 100 {
		volume = 100
	}
	scale := float32(volume) / 100.0

	buf := make([]byte, len(samples))
	for i := 0; i+1 < len(samples); i += 2 {
		sample := int16(binary.LittleEndian.Uint16([]byte{samples[i], samples[i+1]}))
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
		sample := int16(binary.LittleEndian.Uint16([]byte{pcm[i], pcm[i+1]}))
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
		sample := int16(binary.LittleEndian.Uint16([]byte{pcm[i], pcm[i+1]}))
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
