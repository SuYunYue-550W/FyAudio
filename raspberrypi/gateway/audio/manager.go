// 树莓派 ALSA 音频管理
package audio

import (
	"log"
	"sync"
	"time"

	"github.com/raspberrypi/alsa/gbox"
)

// Config 音频配置
type Config struct {
	BufferMs   int // 缓冲延迟(ms)
	SampleRate int
	Channels   int
}

// Manager 音频管理器
type Manager struct {
	cfg         *Config
	alsaaudio   *ALSAHandler
	bluetooth   *BluetoothA2DPHandler
	mixer       *MixerHandler

	// 双缓冲播放
	playbackBuf []byte
	bufMu       sync.Mutex

	// 状态
	isActive bool
	volume   int // 0-100

	onFrameReady func([]byte) error
	done         chan struct{}
	wg           sync.WaitGroup
}

// ALSAHandler ALSA 处理
type ALSAHandler struct {
	device   *gbox.PCM
	channels int
}

// BluetoothA2DPHandler 蓝牙 A2DP 处理
type BluetoothA2DPHandler struct {
	// 使用 BlueALSA DBus 接口
	// dbus-send --system --dest=org.bluealsa --print-reply / org.bluealsa.MediaEndpoint1.Acquire
}

// MixerHandler 混音器
type MixerHandler struct {
	mixer   *gbox.Mixer
	volume  int
}

// NewManager 创建音频管理器
func NewManager(cfg *Config) *Manager {
	if cfg.SampleRate == 0 {
		cfg.SampleRate = 44100
	}
	if cfg.Channels == 0 {
		cfg.Channels = 2
	}

	m := &Manager{
		cfg:         cfg,
		volume:      80,
		playbackBuf: make([]byte, 8192),
		done:        make(chan struct{}),
	}

	// 初始化 ALSA
	if err := m.initALSA(); err != nil {
		log.Printf("[Audio] ALSA 初始化失败: %v", err)
	}

	// 初始化蓝牙
	if err := m.initBluetooth(); err != nil {
		log.Printf("[Audio] 蓝牙初始化失败: %v", err)
	}

	return m
}

// Start 启动音频
func (m *Manager) Start() error {
	m.isActive = true
	log.Printf("[Audio] 音频系统已启动（采样率=%dHz, 通道=%d）", m.cfg.SampleRate, m.cfg.Channels)
	return nil
}

// Play 播放PCM数据
// 写入ALSA环形缓冲，同时通过蓝牙播放
func (m *Manager) Play(pcm []byte) {
	m.bufMu.Lock()
	defer m.bufMu.Unlock()

	// TODO: 写入 ALSA 环形缓冲
	// alsa_write(m.alsaaudio.device, pcm)

	// TODO: 同时通过 BlueALSA 播放
	// bluealsa_write(m.bluetooth, pcm)

	// 丢弃过大的数据
	if len(pcm) > len(m.playbackBuf) {
		pcm = pcm[:len(m.playbackBuf)]
	}
}

// SetVolume 设置音量
func (m *Manager) SetVolume(vol int) {
	if vol < 0 {
		vol = 0
	}
	if vol > 100 {
		vol = 100
	}
	m.volume = vol

	// 应用到 ALSA
	if m.mixer != nil {
		m.mixer.SetVolume(vol)
	}
}

// GetVolume 获取音量
func (m *Manager) GetVolume() int {
	return m.volume
}

// Stop 停止音频
func (m *Manager) Stop() {
	m.isActive = false
	m.wg.Wait()
	log.Printf("[Audio] 音频系统已停止")
}

// ============================================================================
// ALSA 初始化（伪代码，需安装 libasound2-dev）
// ============================================================================

/*
# apt install libasound2-dev

import "github.com/raspberrypi/alsa" // 或直接用CGO调用

// 实际 ALSA 初始化代码：
func (m *Manager) initALSA() error {
    // 打开默认 PCM 设备（hw:0 或 default）
    pcm, err := alsa.NewPCMPublic("default", alsa.PCMStreamPlayback,
        alsa.PCMModeNonBlock, alsa.PCMFormatS16LE,
        m.cfg.SampleRate, uint(m.cfg.Channels))

    if err != nil {
        return err
    }

    m.alsaaudio = &ALSAHandler{
        device: pcm,
        channels: m.cfg.Channels,
    }

    // 打开混音器
    mixer, err := alsa.NewMixerPublic("default")
    if err != nil {
        log.Printf("[Audio] 混音器打开失败（非致命）: %v", err)
    } else {
        m.mixer = &MixerHandler{mixer: mixer}
    }

    return nil
}

// Write 写入ALSA
func (h *ALSAHandler) Write(data []byte) (int, error) {
    if h.device == nil {
        return 0, fmt.Errorf("ALSA设备未初始化")
    }
    return h.device.Write(data)
}
*/

// initALSA 初始化ALSA（占位）
func (m *Manager) initALSA() error {
	log.Printf("[Audio] ALSA 虚拟初始化成功")
	return nil
}

// initBluetooth 初始化蓝牙A2DP（占位）
func (m *Manager) initBluetooth() error {
	// 树莓派使用 BlueALSA
	// 通过 DBus 接口连接
	//
	// 步骤：
	// 1. 启动 bluealsa 服务：bluetoothd --experimental &
	// 2. 配对蓝牙设备：bluetoothctl
	// 3. 通过 DBus 连接 BlueALSA PCM
	//
	// 库推荐：
	// - go-dbus: https://github.com/godbus/dbus
	// - 直接使用 bluealsa-aplay 命令播放 PCM
	//
	// 示例：执行 bluealsa-aplay 00:11:22:33:44:55

	log.Printf("[Audio] BlueALSA 蓝牙初始化")
	return nil
}

// StartBluetoothA2DP 开始蓝牙A2DP播放
func (m *Manager) StartBluetoothA2DP(address string) error {
	// 使用 bluealsa-cli 或 dbus 控制蓝牙设备
	// bluealsa 连接命令
	log.Printf("[Audio] 连接到蓝牙A2DP: %s", address)
	return nil
}
