// 树莓派网络管理
package network

import (
	"encoding/json"
	"log"
	"net"
	"sync"
	"time"

	"fyaudio/common/protocol"
)

// Config 网络配置
type Config struct {
	GatewayID       string
	GatewayName     string
	ListenIP        string
	OnAudioFrame    func([]byte, uint64)
	OnDeviceOnline  func(*Device)
	OnDeviceOffline func(string)
}

// Device 设备信息
type Device struct {
	ID          string
	Name        string
	Platform    string
	IP          string
	IsSource    bool
	LastSeen    time.Time
	SampleRate  int
	Channels    int
	Capabilities []string
}

// Manager 网络管理器
type Manager struct {
	cfg         *Config
	controlConn *net.UDPConn
	audioConn   *net.UDPConn

	devices     map[string]*Device
	devicesMu   sync.RWMutex

	onAudioFrame   func([]byte, uint64)
	onDeviceOnline  func(*Device)
	onDeviceOffline func(string)

	stopCh chan struct{}
	wg     sync.WaitGroup
}

// NewManager 创建网络管理器
func NewManager(cfg *Config) *Manager {
	return &Manager{
		cfg:            cfg,
		devices:        make(map[string]*Device),
		onAudioFrame:   cfg.OnAudioFrame,
		onDeviceOnline:  cfg.OnDeviceOnline,
		onDeviceOffline: cfg.OnDeviceOffline,
		stopCh:         make(chan struct{}),
	}
}

// Start 启动网络
func (m *Manager) Start() error {
	// 绑定控制端口
	addr, err := net.ResolveUDPAddr("udp4", ":5002")
	if err != nil {
		return err
	}
	m.controlConn, err = net.ListenUDP("udp4", addr)
	if err != nil {
		return err
	}
	m.controlConn.SetReadBuffer(64 * 1024)

	// 绑定音频端口
	addr2, err := net.ResolveUDPAddr("udp4", ":5001")
	if err != nil {
		return err
	}
	m.audioConn, err = net.ListenUDP("udp4", addr2)
	if err != nil {
		return err
	}
	m.audioConn.SetReadBuffer(1024 * 1024)

	// 启动接收
	m.wg.Add(2)
	go m.recvControlLoop()
	go m.recvAudioLoop()

	log.Printf("[Network] 网络已启动 (控制:5002, 音频:5001)")
	return nil
}

// Stop 停止网络
func (m *Manager) Stop() {
	close(m.stopCh)
	m.wg.Wait()
	m.controlConn?.Close()
	m.audioConn?.Close()
	log.Printf("[Network] 网络已停止")
}

// ============================================================================
// 控制消息接收
// ============================================================================

func (m *Manager) recvControlLoop() {
	defer m.wg.Done()
	buf := make([]byte, 4096)

	for {
		select {
		case <-m.stopCh:
			return
		default:
		}

		m.controlConn.SetReadDeadline(time.Now().Add(1 * time.Second))
		n, addr, err := m.controlConn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			return
		}

		m.handleControlPacket(buf[:n], addr.IP.String())
	}
}

func (m *Manager) handleControlPacket(data []byte, fromIP string) {
	if len(data) < 5 {
		return
	}

	msgType := data[4]
	payloadLen := len(data) - 7
	if payloadLen <= 0 {
		return
	}

	payload := data[5 : 5+payloadLen]
	var jsonData map[string]interface{}
	if err := json.Unmarshal(payload, &jsonData); err != nil {
		return
	}

	switch msgType {
	case protocol.MsgTypeDiscover:
		// 回复在线
		m.sendOnlineTo(fromIP)

	case protocol.MsgTypeOnline:
		device := &Device{
			ID:          getString(jsonData, "device_id"),
			Name:        getString(jsonData, "device_name"),
			Platform:    getString(jsonData, "platform"),
			IP:          getString(jsonData, "ip"),
			IsSource:    getBool(jsonData, "is_source"),
			SampleRate:  getInt(jsonData, "audio_sample_rate"),
			Channels:    getInt(jsonData, "audio_channels"),
			LastSeen:    time.Now(),
		}
		device.Capabilities = getStringSlice(jsonData, "capabilities")

		m.devicesMu.Lock()
		_, exists := m.devices[device.ID]
		m.devices[device.ID] = device
		m.devicesMu.Unlock()

		if !exists {
			log.Printf("[Network] 设备上线: %s (%s) @ %s", device.Name, device.ID, device.IP)
			if m.onDeviceOnline != nil {
				m.onDeviceOnline(device)
			}
		}

	case protocol.MsgTypeOffline:
		deviceID := getString(jsonData, "device_id")
		m.devicesMu.Lock()
		delete(m.devices, deviceID)
		m.devicesMu.Unlock()

		log.Printf("[Network] 设备离线: %s", deviceID)
		if m.onDeviceOffline != nil {
			m.onDeviceOffline(deviceID)
		}

	case protocol.MsgTypeHeartbeat:
		deviceID := getString(jsonData, "device_id")
		m.devicesMu.Lock()
		if dev, ok := m.devices[deviceID]; ok {
			dev.LastSeen = time.Now()
		}
		m.devicesMu.Unlock()
	}
}

// ============================================================================
// 音频接收
// ============================================================================

func (m *Manager) recvAudioLoop() {
	defer m.wg.Done()
	buf := make([]byte, 65536)

	for {
		select {
		case <-m.stopCh:
			return
		default:
		}

		m.audioConn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
		n, _, err := m.audioConn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			return
		}

		m.handleAudioPacket(buf[:n])
	}
}

func (m *Manager) handleAudioPacket(data []byte) {
	// 使用 common/protocol 的解析
	frame, err := protocol.ParseAudioFrame(data)
	if err != nil || frame == nil {
		return
	}

	if m.onAudioFrame != nil {
		m.onAudioFrame(frame.Payload, frame.Timestamp)
	}
}

// ============================================================================
// 发送
// ============================================================================

func (m *Manager) BroadcastOnline() {
	device := map[string]interface{}{
		"device_id":         m.cfg.GatewayID,
		"device_name":       m.cfg.GatewayName,
		"platform":          "raspberrypi",
		"role":              "gateway",
		"audio_sample_rate": 44100,
		"audio_channels":    2,
		"capabilities":      []string{"speaker", "bluetooth", "gateway"},
		"is_source":         false,
	}

	packet := protocol.NewControlPacket(protocol.MsgTypeOnline, device)
	m.broadcast(packet)
}

func (m *Manager) BroadcastOffline() {
	packet := protocol.NewControlPacket(protocol.MsgTypeOffline, map[string]interface{}{
		"device_id": m.cfg.GatewayID,
	})
	m.broadcast(packet)
}

func (m *Manager) Discover() {
	packet := protocol.NewControlPacket(protocol.MsgTypeDiscover, nil)
	m.broadcast(packet)
}

func (m *Manager) SendHeartbeat() {
	packet := protocol.NewControlPacket(protocol.MsgTypeHeartbeat, map[string]interface{}{
		"device_id":   m.cfg.GatewayID,
		"audio_state":  "playing",
	})
	m.broadcast(packet)
}

func (m *Manager) sendOnlineTo(ip string) {
	device := map[string]interface{}{
		"device_id":         m.cfg.GatewayID,
		"device_name":       m.cfg.GatewayName,
		"platform":          "raspberrypi",
		"role":              "gateway",
		"audio_sample_rate": 44100,
		"audio_channels":    2,
		"capabilities":      []string{"speaker", "bluetooth", "gateway"},
	}

	packet := protocol.NewControlPacket(protocol.MsgTypeOnline, device)
	m.sendTo(packet, ip, 5002)
}

func (m *Manager) broadcast(data []byte) {
	addr := &net.UDPAddr{IP: net.IPv4bcast, Port: 5002}
	m.controlConn.WriteToUDP(data, addr)
}

func (m *Manager) sendTo(data []byte, ip string, port int) {
	addr, err := net.ResolveUDPAddr("udp4", ip)
	if err != nil {
		return
	}
	addr.Port = port
	m.controlConn.WriteToUDP(data, addr)
}

// RecordDevice 记录设备
func (m *Manager) RecordDevice(device *Device) {
	m.devicesMu.Lock()
	defer m.devicesMu.Unlock()
	m.devices[device.ID] = device
}

// RemoveDevice 移除设备
func (m *Manager) RemoveDevice(deviceID string) {
	m.devicesMu.Lock()
	delete(m.devices, deviceID)
	m.devicesMu.Unlock()
}

// GetDevices 获取设备列表
func (m *Manager) GetDevices() []*Device {
	m.devicesMu.RLock()
	defer m.devicesMu.RUnlock()

	devs := make([]*Device, 0, len(m.devices))
	for _, d := range m.devices {
		devs = append(devs, d)
	}
	return devs
}

// ============================================================================
// 辅助
// ============================================================================

func getString(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func getInt(m map[string]interface{}, key string) int {
	if v, ok := m[key].(float64); ok {
		return int(v)
	}
	return 0
}

func getBool(m map[string]interface{}, key string) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return false
}

func getStringSlice(m map[string]interface{}, key string) []string {
	if arr, ok := m[key].([]interface{}); ok {
		result := make([]string, len(arr))
		for i, v := range arr {
			if s, ok := v.(string); ok {
				result[i] = s
			}
		}
		return result
	}
	return nil
}
