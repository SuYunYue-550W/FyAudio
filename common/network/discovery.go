// FyAudio 网络发现与通信模块
// 处理设备发现、心跳保活、UDP广播/接收
package network

import (
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"fyaudio/common/protocol"
)

// ============================================================================
// 类型定义
// ============================================================================

// Device 局域网内的设备
type Device struct {
	Info       *protocol.DeviceInfo
	Addr       *net.UDPAddr
	LastHeartbeat time.Time
}

// DiscoveryService 设备发现服务
type DiscoveryService struct {
	deviceID   string
	deviceName string
	platform   string
	role       string
	localIP    string
	listener   *net.UDPConn       // 控制消息监听
	audioConn  *net.UDPConn       // 音频流连接
	devices    map[string]*Device // deviceID -> Device
	mu         sync.RWMutex
	quit       chan struct{}
	onDeviceOnline   func(*protocol.DeviceInfo)
	onDeviceOffline func(string)
}

// AudioStream 音频流发送/接收
type AudioStream struct {
	conn      *net.UDPConn
	isSource  bool
	remoteIP  string
	quit      chan struct{}
	onFrame   func(*protocol.AudioFramePacket) // 仅receiver使用
}

// ============================================================================
// DiscoveryService 设备发现
// ============================================================================

// NewDiscoveryService 创建设备发现服务
func NewDiscoveryService(deviceID, deviceName, platform, role string) (*DiscoveryService, error) {
	svc := &DiscoveryService{
		deviceID:   deviceID,
		deviceName: deviceName,
		platform:   platform,
		role:       role,
		devices:    make(map[string]*Device),
		quit:       make(chan struct{}),
	}

	// 获取本机IP
	if err := svc.resolveLocalIP(); err != nil {
		return nil, fmt.Errorf("获取本机IP失败: %w", err)
	}

	// 绑定控制消息端口
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf(":%d", protocol.PortControl))
	if err != nil {
		return nil, err
	}
	svc.listener, err = net.ListenUDP("udp4", addr)
	if err != nil {
		return nil, fmt.Errorf("监听控制端口失败: %w", err)
	}

	log.Printf("[Discovery] 监听控制端口 %d, 本机IP: %s", protocol.PortControl, svc.localIP)
	return svc, nil
}

// resolveLocalIP 解析本机局域网IP
func (s *DiscoveryService) resolveLocalIP() error {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		// 备用方案：遍历网络接口
		ifaces, err := net.Interfaces()
		if err != nil {
			return err
		}
		for _, iface := range ifaces {
			if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
				continue
			}
			addrs, _ := iface.Addrs()
			for _, addr := range addrs {
				if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
					s.localIP = ipnet.IP.String()
					return nil
				}
			}
		}
		return err
	}
	defer conn.Close()
	s.localIP = conn.LocalAddr().(*net.TCPAddr).IP.String()
	return nil
}

// Start 开始监听
func (s *DiscoveryService) Start() error {
	// 广播设备上线
	s.broadcastOnline()

	// 启动监听协程
	go s.recvLoop()
	// 启动心跳协程
	go s.heartbeatLoop()

	return nil
}

// recvLoop 接收控制消息循环
func (s *DiscoveryService) recvLoop() {
	buf := make([]byte, 4096)
	for {
		select {
		case <-s.quit:
			return
		default:
		}

		s.listener.SetReadDeadline(time.Now().Add(1 * time.Second))
		n, addr, err := s.listener.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			log.Printf("[Discovery] 接收错误: %v", err)
			continue
		}

		s.handlePacket(buf[:n], addr)
	}
}

// handlePacket 处理接收到的数据包
func (s *DiscoveryService) handlePacket(data []byte, addr *net.UDPAddr) {
	packet, err := protocol.ParseControlPacket(data)
	if err != nil {
		return // 忽略无效包
	}

	switch packet.MsgType {
	case protocol.MsgTypeDiscover:
		// 对方在发现设备，回复自己的在线状态
		s.replyOnline(addr)
		s.saveDevice(packet, addr)

	case protocol.MsgTypeOnline:
		var info protocol.DeviceInfo
		if err := packet.ParsePayload(&info); err != nil {
			return
		}
		s.saveDevice(packet, addr)
		info.LastSeen = time.Now()
		if s.onDeviceOnline != nil {
			s.onDeviceOnline(&info)
		}

	case protocol.MsgTypeOffline:
		var info protocol.DeviceInfo
		if err := packet.ParsePayload(&info); err != nil {
			return
		}
		s.removeDevice(info.DeviceID)

	case protocol.MsgTypeHeartbeat:
		var hb protocol.Heartbeat
		if err := packet.ParsePayload(&hb); err != nil {
			return
		}
		s.refreshHeartbeat(hb.DeviceID)

	case protocol.MsgTypeSetSource:
		// 音源切换指令，由业务层处理
		log.Printf("[Discovery] 收到音源切换指令")

	case protocol.MsgTypeVolumeSync:
		var vol protocol.VolumeSync
		if err := packet.ParsePayload(&vol); err != nil {
			return
		}
		log.Printf("[Discovery] 音量同步: device=%s, volume=%d", vol.DeviceID, vol.Volume)
	}
}

// saveDevice 保存/更新设备
func (s *DiscoveryService) saveDevice(packet *protocol.ControlPacket, addr *net.UDPAddr) {
	var info protocol.DeviceInfo
	if err := packet.ParsePayload(&info); err != nil {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	// 忽略自己
	if info.DeviceID == s.deviceID {
		return
	}

	info.LastSeen = time.Now()
	s.devices[info.DeviceID] = &Device{
		Info:          &info,
		Addr:          addr,
		LastHeartbeat: time.Now(),
	}
}

// removeDevice 移除设备
func (s *DiscoveryService) removeDevice(deviceID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.devices[deviceID]; ok {
		delete(s.devices, deviceID)
		log.Printf("[Discovery] 设备离线: %s", deviceID)
		if s.onDeviceOffline != nil {
			s.onDeviceOffline(deviceID)
		}
	}
}

// refreshHeartbeat 刷新心跳
func (s *DiscoveryService) refreshHeartbeat(deviceID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if dev, ok := s.devices[deviceID]; ok {
		dev.LastHeartbeat = time.Now()
	}
}

// broadcastOnline 广播上线消息
func (s *DiscoveryService) broadcastOnline() error {
	info := &protocol.DeviceInfo{
		DeviceID:       s.deviceID,
		DeviceName:     s.deviceName,
		Platform:       s.platform,
		Role:           s.role,
		IP:             s.localIP,
		SampleRate:     protocol.SampleRate,
		Channels:       protocol.Channels,
		Capabilities:   []protocol.Capability{protocol.CapSpeaker, protocol.CapBluetooth},
		BluetoothConn:  false,
		IsSource:       s.role == protocol.RoleSource,
		Version:        "1.0.0",
	}

	packet, err := protocol.NewControlPacket(protocol.MsgTypeOnline, info)
	if err != nil {
		return err
	}
	data, _ := packet.Serialize()

	return s.broadcast(data)
}

// replyOnline 回复在线消息
func (s *DiscoveryService) replyOnline(addr *net.UDPAddr) error {
	info := &protocol.DeviceInfo{
		DeviceID:       s.deviceID,
		DeviceName:     s.deviceName,
		Platform:       s.platform,
		Role:           s.role,
		IP:             s.localIP,
		SampleRate:     protocol.SampleRate,
		Channels:       protocol.Channels,
		BluetoothConn:  false,
		IsSource:       s.role == protocol.RoleSource,
		Version:        "1.0.0",
	}

	packet, err := protocol.NewControlPacket(protocol.MsgTypeOnline, info)
	if err != nil {
		return err
	}
	data, _ := packet.Serialize()

	conn, err := net.DialUDP("udp4", nil, addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(data)
	return err
}

// broadcast 广播消息
func (s *DiscoveryService) broadcast(data []byte) error {
	// 尝试获取广播地址
	broadcastAddr := fmt.Sprintf("%s:%d", GetBroadcastAddr(), protocol.PortControl)
	addr, err := net.ResolveUDPAddr("udp4", broadcastAddr)
	if err != nil {
		return err
	}

	conn, err := net.DialUDP("udp4", nil, addr)
	if err != nil {
		return err
	}
	defer conn.Close()

	_, err = conn.Write(data)
	return err
}

// heartbeatLoop 心跳循环
func (s *DiscoveryService) heartbeatLoop() {
	ticker := time.NewTicker(protocol.HeartbeatInterval)
	defer ticker.Stop()

	for {
		select {
		case <-s.quit:
			return
		case <-ticker.C:
			hb := protocol.Heartbeat{
				DeviceID: s.deviceID,
				IsSource: s.role == protocol.RoleSource,
				// AudioState 由业务层更新
			}
			packet, _ := protocol.NewControlPacket(protocol.MsgTypeHeartbeat, hb)
			data, _ := packet.Serialize()
			s.broadcast(data)

			// 检查超时设备
			s.checkTimeout()
		}
	}
}

// checkTimeout 检查超时设备
func (s *DiscoveryService) checkTimeout() {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	for id, dev := range s.devices {
		if now.Sub(dev.LastHeartbeat) > protocol.HeartbeatTimeout {
			delete(s.devices, id)
			log.Printf("[Discovery] 设备超时移除: %s", id)
			if s.onDeviceOffline != nil {
				s.onDeviceOffline(id)
			}
		}
	}
}

// GetDevices 获取所有设备列表
func (s *DiscoveryService) GetDevices() []*protocol.DeviceInfo {
	s.mu.RLock()
	defer s.mu.RUnlock()

	devs := make([]*protocol.DeviceInfo, 0, len(s.devices))
	for _, dev := range s.devices {
		devs = append(devs, dev.Info)
	}
	return devs
}

// SendSetSource 发送音源切换指令
func (s *DiscoveryService) SendSetSource(sourceID, sourceName string) error {
	cmd := protocol.SetSource{SourceID: sourceID, SourceName: sourceName}
	packet, err := protocol.NewControlPacket(protocol.MsgTypeSetSource, cmd)
	if err != nil {
		return err
	}
	data, _ := packet.Serialize()
	return s.broadcast(data)
}

// SendVolumeSync 发送音量同步
func (s *DiscoveryService) SendVolumeSync(volume int) error {
	cmd := protocol.VolumeSync{DeviceID: s.deviceID, Volume: volume}
	packet, err := protocol.NewControlPacket(protocol.MsgTypeVolumeSync, cmd)
	if err != nil {
		return err
	}
	data, _ := packet.Serialize()
	return s.broadcast(data)
}

// OnDeviceOnline 设置设备上线回调
func (s *DiscoveryService) OnDeviceOnline(fn func(*protocol.DeviceInfo)) {
	s.onDeviceOnline = fn
}

// OnDeviceOffline 设置设备下线回调
func (s *DiscoveryService) OnDeviceOffline(fn func(string)) {
	s.onDeviceOffline = fn
}

// Close 关闭服务
func (s *DiscoveryService) Close() error {
	close(s.quit)
	// 广播离线消息
	packet, _ := protocol.NewControlPacket(protocol.MsgTypeOffline, map[string]string{
		"device_id": s.deviceID,
	})
	if data, err := packet.Serialize(); err == nil {
		s.broadcast(data)
	}

	if s.listener != nil {
		s.listener.Close()
	}
	return nil
}

// ============================================================================
// AudioStream 音频流
// ============================================================================

// NewAudioStream 创建筑音频流（Receiver模式）
func NewAudioStream(onFrame func(*protocol.AudioFramePacket)) (*AudioStream, error) {
	as := &AudioStream{
		onFrame: onFrame,
		quit:    make(chan struct{}),
	}

	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf(":%d", protocol.PortAudio))
	if err != nil {
		return nil, err
	}

	as.conn, err = net.ListenUDP("udp4", addr)
	if err != nil {
		return nil, fmt.Errorf("监听音频端口失败: %w", err)
	}

	// 设置接收缓冲区
	if err := as.conn.SetReadBuffer(1024 * 1024); err != nil {
		log.Printf("[AudioStream] 设置缓冲区失败: %v", err)
	}

	log.Printf("[AudioStream] 监听音频端口 %d (Receiver模式)", protocol.PortAudio)
	return as, nil
}

// NewAudioStreamAsSource 创建筑音频流（Source模式）
func NewAudioStreamAsSource(broadcastIP string) (*AudioStream, error) {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", broadcastIP, protocol.PortAudio))
	if err != nil {
		return nil, err
	}

	conn, err := net.DialUDP("udp4", nil, addr)
	if err != nil {
		return nil, fmt.Errorf("创建音频广播连接失败: %w", err)
	}

	as := &AudioStream{
		conn:     conn,
		isSource: true,
		remoteIP: broadcastIP,
		quit:     make(chan struct{}),
	}

	log.Printf("[AudioStream] 音频广播目标: %s:%d (Source模式)", broadcastIP, protocol.PortAudio)
	return as, nil
}

// StartReceiving 开始接收音频流
func (as *AudioStream) StartReceiving() {
	go func() {
		buf := make([]byte, 64*1024) // 64KB缓冲，足够大
		for {
			select {
			case <-as.quit:
				return
			default:
			}

			as.conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
			n, _, err := as.conn.ReadFromUDP(buf)
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					continue
				}
				log.Printf("[AudioStream] 接收错误: %v", err)
				continue
			}

			packet, err := protocol.ParseAudioFrame(buf[:n])
			if err != nil {
				// 忽略无效帧
				continue
			}

			if as.onFrame != nil {
				as.onFrame(packet)
			}
		}
	}()
}

// SendFrame 发送音频帧（仅Source模式）
func (as *AudioStream) SendFrame(frame *protocol.AudioFramePacket) error {
	if !as.isSource || as.conn == nil {
		return fmt.Errorf("非音源模式，无法发送")
	}
	data, err := frame.Serialize()
	if err != nil {
		return err
	}
	_, err = as.conn.Write(data)
	return err
}

// Close 关闭音频流
func (as *AudioStream) Close() error {
	close(as.quit)
	if as.conn != nil {
		return as.conn.Close()
	}
	return nil
}

// ============================================================================
// 辅助函数
// ============================================================================

// getBroadcastAddr 获取本机网段的广播地址
func GetBroadcastAddr() string {
	// 遍历网络接口找广播地址
	ifaces, err := net.Interfaces()
	if err != nil {
		return "255.255.255.255"
	}

	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagBroadcast == 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
				// 计算广播地址
				broadcast := make(net.IP, 4)
				for i := 0; i < 4; i++ {
					broadcast[i] = ipnet.IP[i] | ^ipnet.Mask[i]
				}
				return broadcast.String()
			}
		}
	}
	return "255.255.255.255"
}

// GetLocalIPs 获取本机所有IPv4地址
func GetLocalIPs() []string {
	var ips []string
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
				ips = append(ips, ipnet.IP.String())
			}
		}
	}
	return ips
}
