// 树莓派蓝牙管理（BlueALSA）
package bluetooth

import (
	"log"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// Config 蓝牙配置
type Config struct {
	OnConnected    func(*Device)
	OnDisconnected func(string)
}

// Device 蓝牙设备
type Device struct {
	Name    string
	Address string
}

// Manager 蓝牙管理器
type Manager struct {
	cfg         *Config
	connected   *Device
	available   map[string]*Device // 已配对设备
	monitorDone chan struct{}
	mu          sync.RWMutex
}

// NewManager 创建蓝牙管理器
func NewManager(cfg *Config) *Manager {
	return &Manager{
		cfg:       cfg,
		available: make(map[string]*Device),
		monitorDone: make(chan struct{}),
	}
}

// Start 启动蓝牙
func (m *Manager) Start() error {
	// 确保 bluealsa 服务运行
	if err := m.ensureBlueALSA(); err != nil {
		return err
	}

	// 扫描已配对设备
	if err := m.listPairedDevices(); err != nil {
		log.Printf("[Bluetooth] 扫描配对设备失败: %v", err)
	}

	// 启动连接监控
	go m.monitorLoop()

	log.Printf("[Bluetooth] 蓝牙系统已启动")
	return nil
}

// ensureBlueALSA 确保 BlueALSA 服务运行
func (m *Manager) ensureBlueALSA() error {
	// 检查服务是否运行
	// systemctl status bluealsa
	cmd := exec.Command("pgrep", "-x", "bluealsa")
	if err := cmd.Run(); err != nil {
		log.Printf("[Bluetooth] 启动 BlueALSA 服务...")
		// 启动 bluealsa
		startCmd := exec.Command("sudo", " systemctl", "start", "bluealsa")
		if err := startCmd.Run(); err != nil {
			// 尝试手动启动
			daemonCmd := exec.Command("bluealsa", "-p", "a2dp-sink")
			if err := daemonCmd.Start(); err != nil {
				log.Printf("[Bluetooth] BlueALSA 启动失败: %v", err)
			}
		}
	}
	return nil
}

// listPairedDevices 列出已配对设备
func (m *Manager) listPairedDevices() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	cmd := exec.Command("bluetoothctl", "paired-devices", "list")
	out, err := cmd.Output()
	if err != nil {
		return err
	}

	lines := strings.Split(string(out), "\n")
	for _, line := range lines {
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			addr := parts[1]
			name := parts[2] if len(parts) > 2 else "未知设备"
			m.available[addr] = &Device{Name: name, Address: addr}
		}
	}

	return nil
}

// Connect 连接到A2DP设备
func (m *Manager) Connect(address string) error {
	// 连接命令
	cmd := exec.Command("bluetoothctl", "connect", address)
	out, err := cmd.CombinedOutput()
	log.Printf("[Bluetooth] 连接 %s: %s", address, string(out))

	if err != nil {
		return err
	}

	// 建立 BlueALSA 连接
	bluealsaCmd := exec.Command("bluealsa-cli", "connect", address)
	if err := bluealsaCmd.Run(); err != nil {
		log.Printf("[Bluetooth] BlueALSA 连接失败: %v", err)
	}

	m.mu.Lock()
	name := address
	if d, ok := m.available[address]; ok {
		name = d.Name
	}
	m.connected = &Device{Name: name, Address: address}
	m.mu.Unlock()

	if m.cfg.OnConnected != nil {
		m.cfg.OnConnected(m.connected)
	}

	return nil
}

// Disconnect 断开连接
func (m *Manager) Disconnect() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.connected == nil {
		return nil
	}

	cmd := exec.Command("bluetoothctl", "disconnect", m.connected.Address)
	cmd.Run()

	addr := m.connected.Address
	m.connected = nil

	if m.cfg.OnDisconnected != nil {
		m.cfg.OnDisconnected(addr)
	}

	return nil
}

// GetConnected 获取已连接设备
func (m *Manager) GetConnected() *Device {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.connected
}

// GetAvailable 获取可用设备列表
func (m *Manager) GetAvailable() []*Device {
	m.mu.RLock()
	defer m.mu.RUnlock()

	devices := make([]*Device, 0, len(m.available))
	for _, d := range m.available {
		devices = append(devices, d)
	}
	return devices
}

// monitorLoop 连接监控循环
func (m *Manager) monitorLoop() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-m.monitorDone:
			return
		case <-ticker.C:
			m.checkConnection()
		}
	}
}

// checkConnection 检查连接状态
func (m *Manager) checkConnection() {
	m.mu.RLock()
	connected := m.connected
	m.mu.RUnlock()

	if connected == nil {
		return
	}

	// 检查设备是否仍然连接
	cmd := exec.Command("bluetoothctl", "info", connected.Address)
	out, _ := cmd.Output()

	if !strings.Contains(string(out), "Connected: yes") {
		log.Printf("[Bluetooth] 检测到设备断开: %s", connected.Address)
		m.mu.Lock()
		m.connected = nil
		m.mu.Unlock()

		if m.cfg.OnDisconnected != nil {
			m.cfg.OnDisconnected(connected.Address)
		}

		// 自动重连
		go func(addr string) {
			time.Sleep(5 * time.Second)
			m.Connect(addr)
		}(connected.Address)
	}
}

// Stop 停止蓝牙
func (m *Manager) Stop() {
	close(m.monitorDone)
	m.Disconnect()
	log.Printf("[Bluetooth] 蓝牙系统已停止")
}
