// FyAudio 树莓派网关主程序
// 功能: 接收WiFi音源 + 转发蓝牙 + 充当多房间同步中枢
package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"fyaudio/gateway/audio"
	"fyaudio/gateway/bluetooth"
	"fyaudio/gateway/network"
	"fyaudio/gateway/sync"
)

const (
	Version          = "1.0.0"
	GatewayIDPrefix  = "FYGW-"
	GatewayName      = "FyAudio-Gateway"

	// 端口配置
	PortAudio   = 5001
	PortControl = 5002
	PortSync     = 5003
)

// Config 网关配置
type Config struct {
	GatewayID     string
	GatewayName   string
	ListenIP      string
	WiFiInterface string
	BufferMs      int
	LatencyMs     int
}

// Gateway 网关主体
type Gateway struct {
	cfg      *Config
	network  *network.Manager
	audio    *audio.Manager
	bluetooth *bluetooth.Manager
	sync     *sync.Engine

	done chan struct{}
}

// NewGateway 创建网关实例
func NewGateway(cfg *Config) *Gateway {
	gw := &Gateway{
		cfg:  cfg,
		done: make(chan struct{}),
	}
	gw.init()
	return gw
}

func (gw *Gateway) init() {
	// 网络管理
	gw.network = network.NewManager(&network.Config{
		GatewayID:   gw.cfg.GatewayID,
		GatewayName: gw.cfg.GatewayName,
		ListenIP:    gw.cfg.WiFiInterface,
		OnAudioFrame: gw.handleAudioFrame,
		OnDeviceOnline: gw.handleDeviceOnline,
		OnDeviceOffline: gw.handleDeviceOffline,
	})

	// 同步引擎
	gw.sync = sync.NewEngine(gw.cfg.BufferMs)

	// 音频管理（ALSA + 蓝牙）
	gw.audio = audio.NewManager(&audio.Config{
		BufferMs: gw.cfg.BufferMs,
		OnFrameReady: gw.handlePlayableFrame,
	})

	// 蓝牙管理（BlueALSA）
	gw.bluetooth = bluetooth.NewManager(&bluetooth.Config{
		OnConnected:    gw.handleBluetoothConnected,
		OnDisconnected: gw.handleBluetoothDisconnected,
	})
}

// Run 启动网关
func (gw *Gateway) Run() error {
	log.Printf("🎵 FyAudio 网关 v%s 启动中...", Version)
	log.Printf("   网关ID: %s", gw.cfg.GatewayID)
	log.Printf("   设备名: %s", gw.cfg.GatewayName)
	log.Printf("   网络接口: %s", gw.cfg.WiFiInterface)
	log.Printf("   缓冲延迟: %d ms", gw.cfg.BufferMs)

	// 启动蓝牙
	if err := gw.bluetooth.Start(); err != nil {
		log.Printf("⚠️  蓝牙启动失败: %v（继续运行）", err)
	}

	// 启动音频
	if err := gw.audio.Start(); err != nil {
		log.Printf("⚠️  音频启动失败: %v（继续运行）", err)
	}

	// 启动网络
	if err := gw.network.Start(); err != nil {
		return fmt.Errorf("网络启动失败: %w", err)
	}

	// 发送上线广播
	gw.network.BroadcastOnline()

	// 设备发现
	gw.network.Discover()

	// 定期心跳和发现
	go gw.heartbeatLoop()

	// 信号处理
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-sigCh:
		log.Printf("\n📤 收到信号 %v，正在关闭...", sig)
		gw.Stop()
	}

	return nil
}

// Stop 关闭网关
func (gw *Gateway) Stop() {
	close(gw.done)

	gw.network.BroadcastOffline()
	gw.network.Stop()
	gw.audio.Stop()
	gw.bluetooth.Stop()

	log.Println("✅ 网关已关闭")
}

// ============================================================================
// 事件处理
// ============================================================================

// handleAudioFrame 处理接收到的音频帧
func (gw *Gateway) handleAudioFrame(frame []byte, timestamp uint64) {
	// 喂入同步引擎
	playable, err := gw.sync.ProcessFrame(frame, timestamp)
	if err != nil {
		if err != sync.ErrBufferUnderrun {
			log.Printf("[Sync] 处理帧错误: %v", err)
		}
		return
	}

	// 播放
	gw.audio.Play(playable.Payload)
}

// handlePlayableFrame 处理可播放帧（同步引擎回调）
func (gw *Gateway) handlePlayableFrame(payload []byte) {
	gw.audio.Play(payload)
}

// handleDeviceOnline 设备上线
func (gw *Gateway) handleDeviceOnline(device *network.Device) {
	log.Printf("[Device] 设备上线: %s (%s) @ %s", device.Name, device.ID, device.IP)

	// 记录设备信息
	gw.network.RecordDevice(device)
}

// handleDeviceOffline 设备离线
func (gw *Gateway) handleDeviceOffline(deviceID string) {
	log.Printf("[Device] 设备离线: %s", deviceID)

	// 清除设备信息
	gw.network.RemoveDevice(deviceID)
}

// handleBluetoothConnected 蓝牙连接
func (gw *Gateway) handleBluetoothConnected(device *bluetooth.Device) {
	log.Printf("[Bluetooth] 设备连接: %s (%s)", device.Name, device.Address)
}

// handleBluetoothDisconnected 蓝牙断开
func (gw *Gateway) handleBluetoothDisconnected(address string) {
	log.Printf("[Bluetooth] 设备断开: %s", address)
}

// heartbeatLoop 心跳和设备发现循环
func (gw *Gateway) heartbeatLoop() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	discoverTicker := time.NewTicker(5 * time.Second)
	defer discoverTicker.Stop()

	for {
		select {
		case <-gw.done:
			return
		case <-ticker.C:
			gw.network.SendHeartbeat()
		case <-discoverTicker.C:
			gw.network.Discover()
		}
	}
}

// ============================================================================
// 主函数
// ============================================================================

func main() {
	var (
		gatewayID   = flag.String("id", "", "网关ID（留空自动生成）")
		gatewayName = flag.String("name", GatewayName, "网关名称")
		listenIP    = flag.String("ip", "", "监听IP（留空自动选择）")
		bufferMs    = flag.Int("buffer", 40, "缓冲延迟(ms)")
		latencyMs   = flag.Int("latency", 50, "预估网络延迟(ms)")
	)
	flag.Parse()

	// 生成网关ID
	if *gatewayID == "" {
		hostname, _ := os.Hostname()
		*gatewayID = fmt.Sprintf("%s%s", GatewayIDPrefix, hostname)
	}

	// 自动选择网络接口
	if *listenIP == "" {
		ip, err := getDefaultIP()
		if err != nil {
			log.Fatalf("无法获取默认IP: %v", err)
		}
		*listenIP = ip
	}

	cfg := &Config{
		GatewayID:     *gatewayID,
		GatewayName:   *gatewayName,
		WiFiInterface: *listenIP,
		BufferMs:      *bufferMs,
		LatencyMs:     *latencyMs,
	}

	gw := NewGateway(cfg)
	if err := gw.Run(); err != nil {
		log.Fatalf("网关运行失败: %v", err)
	}
}

// getDefaultIP 获取默认网络IP
func getDefaultIP() (string, error) {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "", err
	}
	defer conn.Close()

	addr := conn.LocalAddr().(*net.UDPAddr)
	return addr.IP.String(), nil
}
