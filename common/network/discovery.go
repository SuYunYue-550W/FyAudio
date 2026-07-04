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
	Info          *protocol.DeviceInfo
	Addr          *net.UDPAddr
	LastHeartbeat time.Time
}

// DiscoveryService 设备发现服务
type DiscoveryService struct {
	deviceID   string
	deviceName string
	platform   string
	role       string
	localIP    string

	listener       *net.UDPConn   // 控制消息监听
	broadcastConns []*net.UDPConn // 复用的广播发送 socket（每个广播地址一个）

	devices map[string]*Device
	mu      sync.RWMutex

	quit     chan struct{}
	quitOnce sync.Once
	wg       sync.WaitGroup

	callbackMu      sync.RWMutex // 保护回调设置
	onDeviceOnline  func(*protocol.DeviceInfo)
	onDeviceOffline func(string)
}

// AudioStream 音频流发送/接收
type AudioStream struct {
	conn     *net.UDPConn
	isSource bool
	remoteIP string
	quit     chan struct{}
	quitOnce sync.Once
	wg       sync.WaitGroup
	onFrame  func(*protocol.AudioFramePacket) // 仅receiver使用
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

	// 预创建广播连接（复用 socket）
	for _, baddr := range GetBroadcastAddrs() {
		udpAddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", baddr, protocol.PortControl))
		if err != nil {
			continue
		}
		conn, err := net.DialUDP("udp4", nil, udpAddr)
		if err != nil {
			log.Printf("[Discovery] 创建广播连接失败 %s: %v", baddr, err)
			continue
		}
		svc.broadcastConns = append(svc.broadcastConns, conn)
	}

	log.Printf("[Discovery] 监听控制端口 %d, 本机IP: %s, 广播地址数: %d",
		protocol.PortControl, svc.localIP, len(svc.broadcastConns))
	return svc, nil
}

// resolveLocalIP 解析本机局域网IP
func (s *DiscoveryService) resolveLocalIP() error {
	// 尝试通过连接外部地址获取本机IP（不会真正发送数据）
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err == nil {
		defer conn.Close()
		if udpAddr, ok := conn.LocalAddr().(*net.UDPAddr); ok && udpAddr.IP != nil {
			s.localIP = udpAddr.IP.String()
			return nil
		}
	}

	// 备用方案：遍历网络接口
	ifaces, err := net.Interfaces()
	if err != nil {
		return fmt.Errorf("获取网络接口失败: %w", err)
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
	return fmt.Errorf("未找到可用的IPv4地址")
}

// Start 开始监听
func (s *DiscoveryService) Start() error {
	// 广播设备上线
	if err := s.broadcastOnline(); err != nil {
		log.Printf("[Discovery] 初始广播上线失败: %v", err)
	}

	// 启动监听协程
	s.wg.Add(2)
	go s.recvLoop()
	go s.heartbeatLoop()

	return nil
}

// recvLoop 接收控制消息循环
func (s *DiscoveryService) recvLoop() {
	defer s.wg.Done()
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
			// 检查是否正在关闭
			select {
			case <-s.quit:
				return
			default:
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
		// Discover 包 payload 为空，仅回复 Online 包，不保存设备（避免污染设备列表）
		s.replyOnline(addr)

	case protocol.MsgTypeOnline:
		var info protocol.DeviceInfo
		if err := packet.ParsePayload(&info); err != nil {
			return
		}
		info.IP = addr.IP.String()
		info.LastSeen = time.Now()
		isNew := s.saveDevice(&info, addr)
		if isNew {
			s.callOnline(&info)
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
		log.Printf("[Discovery] 收到音源切换指令")

	case protocol.MsgTypeVolumeSync:
		var vol protocol.VolumeSync
		if err := packet.ParsePayload(&vol); err != nil {
			return
		}
		log.Printf("[Discovery] 音量同步: device=%s, volume=%d", vol.DeviceID, vol.Volume)
	}
}

// saveDevice 保存/更新设备，返回是否为新设备
func (s *DiscoveryService) saveDevice(info *protocol.DeviceInfo, addr *net.UDPAddr) bool {
	// 忽略自己
	if info.DeviceID == s.deviceID {
		return false
	}

	s.mu.Lock()
	_, existed := s.devices[info.DeviceID]
	s.devices[info.DeviceID] = &Device{
		Info:          info,
		Addr:          addr,
		LastHeartbeat: time.Now(),
	}
	s.mu.Unlock()
	return !existed
}

// removeDevice 移除设备（解锁后回调，避免死锁）
func (s *DiscoveryService) removeDevice(deviceID string) {
	s.mu.Lock()
	_, existed := s.devices[deviceID]
	if existed {
		delete(s.devices, deviceID)
	}
	s.mu.Unlock()

	if existed {
		log.Printf("[Discovery] 设备离线: %s", deviceID)
		s.callOffline(deviceID)
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

// buildDeviceInfo 构建本机设备信息
func (s *DiscoveryService) buildDeviceInfo() *protocol.DeviceInfo {
	return &protocol.DeviceInfo{
		DeviceID:      s.deviceID,
		DeviceName:    s.deviceName,
		Platform:      s.platform,
		Role:          s.role,
		IP:            s.localIP,
		SampleRate:    protocol.SampleRate,
		Channels:      protocol.Channels,
		Capabilities:  []protocol.Capability{protocol.CapSpeaker, protocol.CapBluetooth},
		BluetoothConn: false,
		IsSource:      s.role == protocol.RoleSource,
		Version:       "1.0.0",
	}
}

// broadcastOnline 广播上线消息
func (s *DiscoveryService) broadcastOnline() error {
	packet, err := protocol.NewControlPacket(protocol.MsgTypeOnline, s.buildDeviceInfo())
	if err != nil {
		return err
	}
	data, err := packet.Serialize()
	if err != nil {
		return err
	}
	return s.broadcast(data)
}

// replyOnline 回复在线消息（复用 listener）
func (s *DiscoveryService) replyOnline(addr *net.UDPAddr) error {
	packet, err := protocol.NewControlPacket(protocol.MsgTypeOnline, s.buildDeviceInfo())
	if err != nil {
		return err
	}
	data, err := packet.Serialize()
	if err != nil {
		return err
	}
	_, err = s.listener.WriteToUDP(data, addr)
	return err
}

// broadcast 广播消息（复用预创建的 socket）
func (s *DiscoveryService) broadcast(data []byte) error {
	var lastErr error
	for _, conn := range s.broadcastConns {
		if _, err := conn.Write(data); err != nil {
			lastErr = err
			log.Printf("[Discovery] 广播失败: %v", err)
		}
	}
	return lastErr
}

// broadcastOffline 广播离线消息
func (s *DiscoveryService) broadcastOffline() {
	packet, err := protocol.NewControlPacket(protocol.MsgTypeOffline, &protocol.DeviceInfo{
		DeviceID: s.deviceID,
	})
	if err != nil {
		return
	}
	data, err := packet.Serialize()
	if err != nil {
		return
	}
	s.broadcast(data)
}

// heartbeatLoop 心跳循环
func (s *DiscoveryService) heartbeatLoop() {
	defer s.wg.Done()
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
			}
			packet, _ := protocol.NewControlPacket(protocol.MsgTypeHeartbeat, hb)
			data, _ := packet.Serialize()
			s.broadcast(data)

			// 检查超时设备
			s.checkTimeout()
		}
	}
}

// checkTimeout 检查超时设备（先收集超时设备，解锁后再回调，避免死锁）
func (s *DiscoveryService) checkTimeout() {
	s.mu.Lock()
	now := time.Now()
	var timedOut []string
	for id, dev := range s.devices {
		if now.Sub(dev.LastHeartbeat) > protocol.HeartbeatTimeout {
			delete(s.devices, id)
			timedOut = append(timedOut, id)
		}
	}
	s.mu.Unlock()

	// 解锁后回调，避免回调内调用 GetDevices(RLock) 导致死锁
	for _, id := range timedOut {
		log.Printf("[Discovery] 设备超时移除: %s", id)
		s.callOffline(id)
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

// OnDeviceOnline 设置设备上线回调（线程安全）
func (s *DiscoveryService) OnDeviceOnline(fn func(*protocol.DeviceInfo)) {
	s.callbackMu.Lock()
	defer s.callbackMu.Unlock()
	s.onDeviceOnline = fn
}

// OnDeviceOffline 设置设备下线回调（线程安全）
func (s *DiscoveryService) OnDeviceOffline(fn func(string)) {
	s.callbackMu.Lock()
	defer s.callbackMu.Unlock()
	s.onDeviceOffline = fn
}

// callOnline 调用设备上线回调
func (s *DiscoveryService) callOnline(info *protocol.DeviceInfo) {
	s.callbackMu.RLock()
	fn := s.onDeviceOnline
	s.callbackMu.RUnlock()
	if fn != nil {
		fn(info)
	}
}

// callOffline 调用设备离线回调
func (s *DiscoveryService) callOffline(deviceID string) {
	s.callbackMu.RLock()
	fn := s.onDeviceOffline
	s.callbackMu.RUnlock()
	if fn != nil {
		fn(deviceID)
	}
}

// Close 关闭服务（sync.Once 保护，等待 goroutine 退出）
func (s *DiscoveryService) Close() error {
	s.quitOnce.Do(func() {
		close(s.quit)
	})

	// 广播离线消息
	s.broadcastOffline()

	// 等待 goroutine 退出
	s.wg.Wait()

	// 关闭连接
	if s.listener != nil {
		s.listener.Close()
	}
	for _, c := range s.broadcastConns {
		c.Close()
	}
	return nil
}

// ============================================================================
// AudioStream 音频流
// ============================================================================

// NewAudioStream 创建音频流（Receiver模式）
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

// NewAudioStreamAsSource 创建音频流（Source模式）
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
	as.wg.Add(1)
	go func() {
		defer as.wg.Done()
		buf := make([]byte, 64*1024) // 64KB缓冲
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
				// 检查是否正在关闭
				select {
				case <-as.quit:
					return
				default:
				}
				log.Printf("[AudioStream] 接收错误: %v", err)
				continue
			}

			packet, err := protocol.ParseAudioFrame(buf[:n])
			if err != nil {
				continue // 忽略无效帧
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

// Close 关闭音频流（sync.Once 保护，等待 goroutine 退出）
func (as *AudioStream) Close() error {
	as.quitOnce.Do(func() {
		close(as.quit)
	})
	if as.conn != nil {
		as.conn.Close()
	}
	as.wg.Wait()
	return nil
}

// ============================================================================
// 辅助函数
// ============================================================================

// GetBroadcastAddrs 获取本机所有网段的广播地址
func GetBroadcastAddrs() []string {
	var result []string
	ifaces, err := net.Interfaces()
	if err != nil {
		return []string{"255.255.255.255"}
	}

	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 {
			continue
		}
		ifaceAddrs, _ := iface.Addrs()
		for _, addr := range ifaceAddrs {
			if ipnet, ok := addr.(*net.IPNet); ok {
				ip4 := ipnet.IP.To4()
				if ip4 == nil {
					continue
				}
				if len(ipnet.Mask) != 4 {
					continue
				}
				broadcast := make(net.IP, 4)
				for i := 0; i < 4; i++ {
					broadcast[i] = ip4[i] | ^ipnet.Mask[i]
				}
				result = append(result, broadcast.String())
			}
		}
	}

	if len(result) == 0 {
		result = append(result, "255.255.255.255")
	}
	return result
}

// GetBroadcastAddr 返回第一个广播地址（兼容单地址调用）
func GetBroadcastAddr() string {
	addrs := GetBroadcastAddrs()
	return addrs[0]
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
