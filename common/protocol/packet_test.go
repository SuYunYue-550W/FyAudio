package protocol

import (
	"encoding/json"
	"testing"
	"time"
)

func TestCRC16Checksum(t *testing.T) {
	testCases := []struct {
		name     string
		data     []byte
		expected uint16
	}{
		{"empty", []byte{}, 0xFFFF},
		{"single_byte", []byte{0x00}, 0xE1F0},
		{"magic_number", []byte{0x46, 0x59, 0x41, 0x55}, 0x3937},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := crc16Checksum(tc.data)
			if result != tc.expected {
				t.Errorf("crc16Checksum(%v) = 0x%04X, want 0x%04X", tc.data, result, tc.expected)
			}
		})
	}
}

func TestAudioFramePacket(t *testing.T) {
	payload := []byte("test_audio_data_12345")
	timestamp := uint64(time.Now().UnixNano() / 1_000_000)

	packet := NewAudioFrame(payload, timestamp)
	if packet.Magic != MagicNumber {
		t.Errorf("Magic = 0x%08X, want 0x%08X", packet.Magic, MagicNumber)
	}
	if packet.Timestamp != timestamp {
		t.Errorf("Timestamp = %d, want %d", packet.Timestamp, timestamp)
	}
	if packet.FrameLength != uint32(len(payload)) {
		t.Errorf("FrameLength = %d, want %d", packet.FrameLength, len(payload))
	}

	data, err := packet.Serialize()
	if err != nil {
		t.Fatalf("Serialize failed: %v", err)
	}

	parsed, err := ParseAudioFrame(data)
	if err != nil {
		t.Fatalf("ParseAudioFrame failed: %v", err)
	}

	if parsed.Magic != MagicNumber {
		t.Errorf("Parsed Magic = 0x%08X, want 0x%08X", parsed.Magic, MagicNumber)
	}
	if parsed.Timestamp != timestamp {
		t.Errorf("Parsed Timestamp = %d, want %d", parsed.Timestamp, timestamp)
	}
	if string(parsed.Payload) != string(payload) {
		t.Errorf("Parsed Payload = %q, want %q", string(parsed.Payload), string(payload))
	}
}

func TestAudioFrameCRCValidation(t *testing.T) {
	payload := []byte("test_crc_data")
	packet := NewAudioFrame(payload, 1234567890)
	data, _ := packet.Serialize()

	data[len(data)-1] ^= 0xFF

	_, err := ParseAudioFrame(data)
	if err == nil {
		t.Error("ParseAudioFrame should fail with corrupted CRC")
	}
}

func TestControlPacket(t *testing.T) {
	deviceInfo := &DeviceInfo{
		DeviceID:   "FY-TEST001",
		DeviceName: "TestDevice",
		Platform:   "windows",
		Role:       RoleSource,
		IP:         "192.168.1.100",
	}

	packet, err := NewControlPacket(MsgTypeOnline, deviceInfo)
	if err != nil {
		t.Fatalf("NewControlPacket failed: %v", err)
	}

	data, err := packet.Serialize()
	if err != nil {
		t.Fatalf("Serialize failed: %v", err)
	}

	parsed, err := ParseControlPacket(data)
	if err != nil {
		t.Fatalf("ParseControlPacket failed: %v", err)
	}

	if parsed.MsgType != MsgTypeOnline {
		t.Errorf("MsgType = %d, want %d", parsed.MsgType, MsgTypeOnline)
	}

	var parsedInfo DeviceInfo
	if err := parsed.ParsePayload(&parsedInfo); err != nil {
		t.Fatalf("ParsePayload failed: %v", err)
	}

	if parsedInfo.DeviceID != deviceInfo.DeviceID {
		t.Errorf("DeviceID = %q, want %q", parsedInfo.DeviceID, deviceInfo.DeviceID)
	}
	if parsedInfo.DeviceName != deviceInfo.DeviceName {
		t.Errorf("DeviceName = %q, want %q", parsedInfo.DeviceName, deviceInfo.DeviceName)
	}
}

func TestDeviceInfoJSON(t *testing.T) {
	info := &DeviceInfo{
		DeviceID:       "FY-JSON001",
		DeviceName:     "JSONTest",
		Platform:       "android",
		Role:           RoleReceiver,
		IP:             "10.0.0.1",
		SampleRate:     44100,
		Channels:       2,
		Capabilities:   []Capability{CapSpeaker, CapBluetooth},
		BluetoothConn:  true,
		IsSource:       false,
		Volume:         80,
		LatencyCompensate: 10,
		Version:        "1.0.0",
	}

	data, err := json.Marshal(info)
	if err != nil {
		t.Fatalf("Marshal failed: %v", err)
	}

	var decoded DeviceInfo
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal failed: %v", err)
	}

	if decoded.DeviceID != info.DeviceID {
		t.Errorf("DeviceID mismatch")
	}
	if decoded.IsSource != info.IsSource {
		t.Errorf("IsSource mismatch")
	}
	if len(decoded.Capabilities) != len(info.Capabilities) {
		t.Errorf("Capabilities length mismatch")
	}
}

func TestGetTimestamp(t *testing.T) {
	ts := GetTimestamp()
	now := uint64(time.Now().UnixNano() / 1_000_000)
	
	if ts > now+1000 {
		t.Errorf("Timestamp %d is too far in the future (now: %d)", ts, now)
	}
	if ts < now-1000 {
		t.Errorf("Timestamp %d is too far in the past (now: %d)", ts, now)
	}
}

func TestGenerateDeviceID(t *testing.T) {
	id := GenerateDeviceID()
	
	if len(id) != 15 {
		t.Errorf("DeviceID length = %d, want 15", len(id))
	}
	if len(id) >= 3 && id[:3] != "FY-" {
		t.Errorf("DeviceID should start with 'FY-'")
	}

	id2 := GenerateDeviceID()
	if id == id2 {
		t.Error("DeviceIDs should be unique")
	}
}

func TestValidateTimestamp(t *testing.T) {
	now := GetTimestamp()
	
	if !ValidateTimestamp(now, 1000) {
		t.Error("Current timestamp should be valid")
	}
	if ValidateTimestamp(now+2000, 1000) {
		t.Error("Future timestamp 2s ahead should be invalid")
	}
	if ValidateTimestamp(now-2000, 1000) {
		t.Error("Past timestamp 2s ago should be invalid")
	}
}

func TestBufferDuration(t *testing.T) {
	testCases := []struct {
		ms     int
		frames int
	}{
		{0, 0},
		{20, 1},
		{40, 2},
		{100, 5},
		{200, 10},
	}

	for _, tc := range testCases {
		t.Run(string(rune(tc.ms)), func(t *testing.T) {
			result := BufferDuration(tc.ms)
			if result != tc.frames {
				t.Errorf("BufferDuration(%d) = %d, want %d", tc.ms, result, tc.frames)
			}
		})
	}
}