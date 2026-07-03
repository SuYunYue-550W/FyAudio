// FyAudio 后端服务主程序
// 多终端WiFi/蓝牙同步音频播放系统
package main

import (
	"encoding/binary"
	"flag"
	"log"
	"math"
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

	// 初始化编解码器（PCM 透传模式）
	encoder := audio.NewAudioEncoder(protocol.SampleRate, protocol.Channels, protocol.AACBitrate)
	decoder := audio.NewAudioDecoder(protocol.SampleRate, protocol.Channels)
	log.Printf("音频编解码器已初始化: %dHz, %d声道, PCM透传模式", protocol.SampleRate, protocol.Channels)

	frameHandler := audio.NewFrameHandler(encoder, decoder)

	var audioStream *network.AudioStream

	if *role == protocol.RoleSource {
		// Source 模式：采集音频并广播
		broadcastIP := network.GetBroadcastAddr()
		audioStream, err = network.NewAudioStreamAsSource(broadcastIP)
		if err != nil {
			log.Fatalf("创建音频广播失败: %v", err)
		}
		log.Printf("音频广播目标: %s:%d", broadcastIP, protocol.PortAudio)

		capture := &mockAudioCapture{}
		if err := capture.Start(); err != nil {
			log.Fatalf("启动音频采集失败: %v", err)
		}

		frameHandler.StartCaptureLoop(capture, func(packet *protocol.AudioFramePacket) {
			if audioStream != nil {
				if err := audioStream.SendFrame(packet); err != nil {
					log.Printf("发送音频帧失败: %v", err)
				}
			}
		})
		log.Printf("Source模式: 音频采集-编码-广播循环已启动")
	} else {
		// Receiver 模式：接收音频并播放
		audioStream, err = network.NewAudioStream(func(frame *protocol.AudioFramePacket) {
			frameHandler.FeedFrameForPlayback(frame)
		})
		if err != nil {
			log.Fatalf("创建音频接收失败: %v", err)
		}

		// 播放循环：将解码后的 PCM 通过标准输出送出
		// 可通过管道连接播放器，例如: fy_audio_backend | ffplay -f s16le -ar 44100 -ac 2 -
		frameHandler.StartPlaybackLoop(func(pcm []byte, timestamp uint64) {
			os.Stdout.Write(pcm)
		})

		audioStream.StartReceiving()
		log.Printf("Receiver模式: 音频接收-解码-播放循环已启动，监听端口 %d", protocol.PortAudio)
		log.Printf("PCM输出格式: s16le, %dHz, %d声道", protocol.SampleRate, protocol.Channels)
	}

	// 使用 SIGINT 和 SIGTERM（兼容 Windows）
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	log.Printf("服务运行中，按 Ctrl+C 退出...")
	<-sigChan

	log.Printf("收到退出信号，正在停止服务...")

	// 停止帧处理器（等待 goroutine 退出）
	frameHandler.Stop()

	// 关闭音频流
	if audioStream != nil {
		if err := audioStream.Close(); err != nil {
			log.Printf("关闭音频流失败: %v", err)
		}
	}

	// 关闭设备发现服务
	if err := discovery.Close(); err != nil {
		log.Printf("关闭发现服务失败: %v", err)
	}

	log.Printf("服务已停止")
}

// mockAudioCapture 模拟音频采集（生成 440Hz 正弦波测试音频）
type mockAudioCapture struct {
	phase float64
}

func (m *mockAudioCapture) Start() error {
	log.Printf("模拟音频采集已启动（正弦波 440Hz）")
	return nil
}

func (m *mockAudioCapture) Stop() {
	log.Printf("模拟音频采集已停止")
}

func (m *mockAudioCapture) ReadPCM() ([]byte, error) {
	pcm := make([]byte, audio.PCMTotalBytes)
	freq := 440.0
	// PCMTotalBytes / 4 = 每帧样本数（2声道 × 16bit = 4字节/样本）
	samples := audio.PCMTotalBytes / 4
	for i := 0; i < samples; i++ {
		// 半幅值（16384），避免削波
		s := int16(math.Sin(m.phase) * 16384)
		// 左声道
		binary.LittleEndian.PutUint16(pcm[i*4:], uint16(s))
		// 右声道
		binary.LittleEndian.PutUint16(pcm[i*4+2:], uint16(s))
		// 推进相位
		m.phase += 2 * math.Pi * freq / float64(audio.SampleRate)
		if m.phase > 2*math.Pi {
			m.phase -= 2 * math.Pi
		}
	}
	return pcm, nil
}

func (m *mockAudioCapture) IsActive() bool {
	return true
}
