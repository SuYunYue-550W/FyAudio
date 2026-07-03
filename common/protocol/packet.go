// FyAudio 公共协议定义
// 统一数据包结构，跨平台复用
package protocol

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"time"
)

const CRC16_CCITT = 0x1021

func crc16Checksum(data []byte) uint16 {
	var crc uint16 = 0xFFFF
	for _, b := range data {
		crc ^= uint16(b) << 8
		for i := 0; i < 8; i++ {
			if crc&0x8000 != 0 {
				crc = (crc << 1) ^ CRC16_CCITT
			} else {
				crc <<= 1
			}
		}
	}
	return crc
}

// ============================================================================
// 常量定义
// ============================================================================

const (
	// 包头魔数 "FYAU"
	MagicNumber uint32 = 0x46594155

	// 端口配置
	PortAudio   = 5001 // 音频流端口
	PortControl = 5002 // 控制消息端口
	PortSync    = 5003 // 同步校准端口

	// 音频参数
	SampleRate    = 44100
	Channels      = 2
	BitsPerSample = 16
	FrameDuration = 20 // ms
	AACBitrate    = 128 // kbps

	// 缓冲区参数
	BufferMinMS     = 20  // 最小缓冲（1帧）
	BufferDefaultMS = 40  // 默认缓冲
	BufferMaxMS     = 200 // 最大缓冲
	MaxBufferFrames = 200 // 环形缓冲区最大帧数

	// 心跳参数
	HeartbeatInterval = 3 * time.Second  // 心跳间隔
	HeartbeatTimeout  = 10 * time.Second // 超时判定
)

// 消息类型
const (
	MsgTypeDiscover      = 0x01
	MsgTypeOnline        = 0x02
	MsgTypeOffline       = 0x03
	MsgTypeSetSource     = 0x10
	MsgTypeVolumeSync    = 0x11
	MsgTypeSyncRequest   = 0x20
	MsgTypeSyncResponse  = 0x21
	MsgTypeHeartbeat     = 0x30
)

// 设备角色
const (
	RoleSource   = "source"
	RoleReceiver = "receiver"
	RoleGateway  = "gateway"
)

// 平台类型
const (
	PlatformWindows     = "windows"
	PlatformMac         = "mac"
	PlatformAndroid     = "android"
	PlatformRaspberryPi = "raspberrypi"
)

// 设备能力
type Capability string

const (
	CapSpeaker   Capability = "speaker"
	CapBluetooth Capability = "bluetooth"
	CapCapture   Capability = "capture"
)

// ============================================================================
// 数据结构
// ============================================================================

// AudioFramePacket 音频帧数据包
// 格式: Magic(4) + Timestamp(8) + FrameLength(4) + Payload(N) + CRC16(2)
type AudioFramePacket struct {
	Magic       uint32  // 包头: 0x46594155
	Timestamp   uint64  // UTC毫秒时间戳
	FrameLength uint32  // AAC数据长度
	Payload     []byte  // AAC压缩音频数据
	CRC         uint16  // CRC16校验
}

// ControlPacket 控制消息包
type ControlPacket struct {
	Magic   uint32 // 包头: 0x46594155
	MsgType uint8  // 消息类型
	Payload []byte // JSON载荷
	CRC     uint16 // CRC16校验
}

// DeviceInfo 设备信息
type DeviceInfo struct {
	DeviceID          string       `json:"device_id"`
	DeviceName        string       `json:"device_name"`
	Platform          string       `json:"platform"`
	Role              string       `json:"role"` // source | receiver | gateway
	IP                string       `json:"ip"`
	SampleRate        int          `json:"audio_sample_rate"`
	Channels          int          `json:"audio_channels"`
	Capabilities      []Capability `json:"capabilities"`
	BluetoothConn     bool         `json:"bluetooth_connected"`
	IsSource          bool         `json:"is_source"`
	Volume            int          `json:"volume"` // 0-100
	LatencyCompensate int          `json:"latency_compensate"` // ms, 手动延迟补偿
	Version           string       `json:"version"`
	LastSeen          time.Time    `json:"-"`
}

// SyncRequest 同步校准请求
type SyncRequest struct {
	ClientTime uint64 `json:"client_time"` // 客户端UTC毫秒时间
}

// SyncResponse 同步校准响应
type SyncResponse struct {
	ClientTime uint64 `json:"client_time"` // 客户端原始时间
	ServerTime uint64 `json:"server_time"` // 服务端UTC毫秒时间
	DeviceID   string `json:"device_id"`   // 当前音源设备ID
}

// Heartbeat 心跳消息
type Heartbeat struct {
	DeviceID   string `json:"device_id"`
	IsSource   bool   `json:"is_source"`
	AudioState string `json:"audio_state"` // playing | paused | stopped
	SourceID   string `json:"source_id,omitempty"`
}

// SetSource 设置音源指令
type SetSource struct {
	SourceID   string `json:"source_id"`
	SourceName string `json:"source_name"`
}

// VolumeSync 音量同步
type VolumeSync struct {
	DeviceID string `json:"device_id"`
	Volume   int    `json:"volume"` // 0-100
}

// ============================================================================
// 序列化/反序列化
// ============================================================================

// NewAudioFrame 创建音频帧包
func NewAudioFrame(payload []byte, timestamp uint64) *AudioFramePacket {
	// 计算CRC（不含CRC字段本身）
	data := make([]byte, 16+len(payload))
	binary.LittleEndian.PutUint32(data[0:4], MagicNumber)
	binary.LittleEndian.PutUint64(data[4:12], timestamp)
	binary.LittleEndian.PutUint32(data[12:16], uint32(len(payload)))
	copy(data[16:], payload)

	crc := crc16Checksum(data)

	return &AudioFramePacket{
		Magic:       MagicNumber,
		Timestamp:   timestamp,
		FrameLength: uint32(len(payload)),
		Payload:     payload,
		CRC:         crc,
	}
}

// Serialize 序列化音频帧为二进制
func (p *AudioFramePacket) Serialize() ([]byte, error) {
	payloadLen := len(p.Payload)
	totalLen := 18 + payloadLen
	buf := make([]byte, totalLen)
	binary.LittleEndian.PutUint32(buf[0:4], p.Magic)
	binary.LittleEndian.PutUint64(buf[4:12], p.Timestamp)
	binary.LittleEndian.PutUint32(buf[12:16], uint32(payloadLen))
	copy(buf[16:16+payloadLen], p.Payload)
	binary.LittleEndian.PutUint16(buf[16+payloadLen:18+payloadLen], p.CRC)
	return buf, nil
}

// ParseAudioFrame 从二进制解析音频帧
func ParseAudioFrame(data []byte) (*AudioFramePacket, error) {
	if len(data) < 18 {
		return nil, fmt.Errorf("数据包长度不足: %d < 18", len(data))
	}

	magic := binary.LittleEndian.Uint32(data[0:4])
	if magic != MagicNumber {
		return nil, fmt.Errorf("无效魔数: 0x%08X", magic)
	}

	timestamp := binary.LittleEndian.Uint64(data[4:12])
	frameLen := binary.LittleEndian.Uint32(data[12:16])

	if len(data) < 18+int(frameLen) {
		return nil, fmt.Errorf("数据长度不足: %d < %d", len(data), 18+frameLen)
	}

	// 验证CRC
	payload := data[16 : 16+frameLen]
	crcData := data[0 : 16+frameLen]
	expectedCRC := binary.LittleEndian.Uint16(data[16+frameLen : 18+frameLen])
	actualCRC := crc16Checksum(crcData)

	if expectedCRC != actualCRC {
		return nil, fmt.Errorf("CRC校验失败: expected=0x%04X, actual=0x%04X", expectedCRC, actualCRC)
	}

	return &AudioFramePacket{
		Magic:       magic,
		Timestamp:   timestamp,
		FrameLength: frameLen,
		Payload:     append([]byte(nil), payload...),
		CRC:         expectedCRC,
	}, nil
}

// NewControlPacket 创建控制消息包
func NewControlPacket(msgType uint8, payload interface{}) (*ControlPacket, error) {
	var payloadBytes []byte
	var err error

	if payload != nil {
		payloadBytes, err = json.Marshal(payload)
		if err != nil {
			return nil, fmt.Errorf("JSON序列化失败: %w", err)
		}
	}

	// CRC计算
	data := make([]byte, 5+len(payloadBytes))
	binary.LittleEndian.PutUint32(data[0:4], MagicNumber)
	data[4] = msgType
	copy(data[5:], payloadBytes)
	crc := crc16Checksum(data)

	return &ControlPacket{
		Magic:   MagicNumber,
		MsgType: msgType,
		Payload: payloadBytes,
		CRC:     crc,
	}, nil
}

// Serialize 序列化控制消息
func (p *ControlPacket) Serialize() ([]byte, error) {
	totalLen := 7 + len(p.Payload)
	buf := make([]byte, totalLen)
	binary.LittleEndian.PutUint32(buf[0:4], p.Magic)
	buf[4] = p.MsgType
	copy(buf[5:5+len(p.Payload)], p.Payload)
	binary.LittleEndian.PutUint16(buf[5+len(p.Payload):], p.CRC)
	return buf, nil
}

// ParseControlPacket 从二进制解析控制消息
func ParseControlPacket(data []byte) (*ControlPacket, error) {
	if len(data) < 7 {
		return nil, fmt.Errorf("控制包长度不足: %d < 7", len(data))
	}

	magic := binary.LittleEndian.Uint32(data[0:4])
	if magic != MagicNumber {
		return nil, fmt.Errorf("无效魔数: 0x%08X", magic)
	}

	msgType := data[4]
	payloadLen := len(data) - 7
	var payload []byte
	if payloadLen > 0 {
		payload = data[5 : 5+payloadLen]
	}

	expectedCRC := binary.LittleEndian.Uint16(data[5+payloadLen:])
	actualCRC := crc16Checksum(data[0 : 5+payloadLen])
	if expectedCRC != actualCRC {
		return nil, fmt.Errorf("CRC校验失败")
	}

	return &ControlPacket{
		Magic:   magic,
		MsgType: msgType,
		Payload: payload,
		CRC:     expectedCRC,
	}, nil
}

// ParsePayload 解析载荷JSON
func (p *ControlPacket) ParsePayload(v interface{}) error {
	if len(p.Payload) == 0 {
		return nil
	}
	return json.Unmarshal(p.Payload, v)
}

// ============================================================================
// 工具函数
// ============================================================================

// GetTimestamp 获取当前UTC毫秒时间戳
func GetTimestamp() uint64 {
	return uint64(time.Now().UnixNano() / 1_000_000)
}

// GenerateDeviceID 生成设备唯一ID
func GenerateDeviceID() string {
	b := make([]byte, 6)
	rand.Read(b)
	return fmt.Sprintf("FY-%02X%02X%02X%02X%02X%02X",
		b[0], b[1], b[2], b[3], b[4], b[5])
}

// BytesToDeviceInfo 从JSON解析设备信息
func BytesToDeviceInfo(data []byte) (*DeviceInfo, error) {
	var info DeviceInfo
	if err := json.Unmarshal(data, &info); err != nil {
		return nil, err
	}
	return &info, nil
}

// DeviceInfoToBytes 设备信息序列化为JSON
func DeviceInfoToBytes(info *DeviceInfo) ([]byte, error) {
	return json.Marshal(info)
}

// BufferDuration 计算缓冲时长对应的帧数
func BufferDuration(durationMs int) int {
	return durationMs / FrameDuration
}

// ValidateTimestamp 检查时间戳是否有效（不超过maxAge毫秒）
func ValidateTimestamp(ts uint64, maxAgeMs int64) bool {
	now := GetTimestamp()
	if ts > now {
		// 允许少量时钟偏差
		return (ts - now) < uint64(maxAgeMs)
	}
	return (now - ts) < uint64(maxAgeMs)
}
