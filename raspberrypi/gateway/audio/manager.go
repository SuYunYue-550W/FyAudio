package audio

import (
	"log"
	"sync"
)

type Config struct {
	BufferMs     int
	SampleRate   int
	Channels     int
	OnFrameReady func([]byte)
}

type Manager struct {
	cfg         *Config
	playbackBuf []byte
	bufMu       sync.Mutex
	isActive    bool
	volume      int
	done        chan struct{}
	wg          sync.WaitGroup
}

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

	return m
}

func (m *Manager) Start() error {
	m.isActive = true
	log.Printf("[Audio] 音频系统已启动（采样率=%dHz, 通道=%d）", m.cfg.SampleRate, m.cfg.Channels)
	return nil
}

func (m *Manager) Play(pcm []byte) {
	m.bufMu.Lock()
	defer m.bufMu.Unlock()

	if len(pcm) > len(m.playbackBuf) {
		pcm = pcm[:len(m.playbackBuf)]
	}

	if m.cfg.OnFrameReady != nil {
		m.cfg.OnFrameReady(pcm)
	}
}

func (m *Manager) SetVolume(vol int) {
	if vol < 0 {
		vol = 0
	}
	if vol > 100 {
		vol = 100
	}
	m.volume = vol
}

func (m *Manager) GetVolume() int {
	return m.volume
}

func (m *Manager) Stop() {
	m.isActive = false
	m.wg.Wait()
	log.Printf("[Audio] 音频系统已停止")
}