package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"fyaudio/common/audio"
	"fyaudio/common/network"
	"fyaudio/common/protocol"
)

var (
	role       = flag.String("role", "receiver", "设备角色: source/receiver/gateway")
	deviceName = flag.String("name", "FyAudio-Device", "设备名称")
	platform   = flag.String("platform", "windows", "平台: windows/mac/android/raspberrypi")
)

func main() {
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lshortfile)
	log.Printf("============================================")
	log.Printf("FyAudio 后端服务启动")
	log.Printf("角色: %s, 名称: %s, 平台: %s", *role, *deviceName, *platform)
	log.Printf("============================================")

	deviceID := protocol.GenerateDeviceID()
	log.Printf("设备ID: %s", deviceID)

	discovery, err := network.NewDiscoveryService(deviceID, *deviceName, *platform, *role)
	if err != nil {
		log.Fatalf("创建设备发现服务失败: %v", err)
	}

	discovery.OnDeviceOnline(func(info *protocol.DeviceInfo) {
		log.Printf("设备上线: %s (%s) - %s", info.DeviceName, info.DeviceID, info.IP)
	})

	discovery.OnDeviceOffline(func(deviceID string) {
		log.Printf("设备离线: %s", deviceID)
	})

	if err := discovery.Start(); err != nil {
		log.Fatalf("启动设备发现服务失败: %v", err)
	}
	log.Printf("设备发现服务已启动，监听端口 %d", protocol.PortControl)

	var audioStream *network.AudioStream
	if *role == protocol.RoleSource {
		broadcastIP := network.GetBroadcastAddr()
		audioStream, err = network.NewAudioStreamAsSource(broadcastIP)
		if err != nil {
			log.Fatalf("创建音频广播失败: %v", err)
		}
		log.Printf("音频广播目标: %s:%d", broadcastIP, protocol.PortAudio)
	} else {
		audioStream, err = network.NewAudioStream(func(frame *protocol.AudioFramePacket) {
			log.Printf("收到音频帧: ts=%d, len=%d", frame.Timestamp, len(frame.Payload))
		})
		if err != nil {
			log.Fatalf("创建音频接收失败: %v", err)
		}
		audioStream.StartReceiving()
		log.Printf("音频接收服务已启动，监听端口 %d", protocol.PortAudio)
	}

	encoder := audio.NewAudioEncoder(protocol.SampleRate, protocol.Channels, protocol.AACBitrate)
	decoder := audio.NewAudioDecoder(protocol.SampleRate, protocol.Channels)
	log.Printf("音频编解码器已初始化: %dHz, %d声道, %dkbps", protocol.SampleRate, protocol.Channels, protocol.AACBitrate)

	if *role == protocol.RoleSource {
		frameHandler := audio.NewAACFrameHandler(encoder, decoder)
		frameHandler.StartCaptureLoop(
			&mockAudioCapture{},
			func(packet *protocol.AudioFramePacket) {
				if audioStream != nil {
					audioStream.SendFrame(packet)
				}
			},
		)
		log.Printf("Source模式: 音频采集-编码-广播循环已启动")
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM, syscall.SIGQUIT)

	log.Printf("服务运行中，按 Ctrl+C 退出...")
	<-sigChan

	log.Printf("收到退出信号，正在停止服务...")

	if audioStream != nil {
		audioStream.Close()
	}
	discovery.Close()

	log.Printf("服务已停止")
}

type mockAudioCapture struct{}

func (m *mockAudioCapture) Start() error {
	log.Printf("模拟音频采集已启动")
	return nil
}

func (m *mockAudioCapture) Stop() {
	log.Printf("模拟音频采集已停止")
}

func (m *mockAudioCapture) ReadPCM() ([]byte, error) {
	pcm := make([]byte, audio.PCMTotalBytes)
	for i := range pcm {
		pcm[i] = byte(i % 256)
	}
	return pcm, nil
}

func (m *mockAudioCapture) IsActive() bool {
	return true
}