package audio

import (
	"testing"
)

func TestAudioEncoder(t *testing.T) {
	encoder := NewAudioEncoder(SampleRate, Channels, 128000)

	testCases := []struct {
		name     string
		inputLen int
		wantLen  int
	}{
		{"exact size", PCMTotalBytes, PCMTotalBytes},
		{"small input", PCMTotalBytes / 2, PCMTotalBytes},
		{"large input", PCMTotalBytes * 2, PCMTotalBytes},
		{"empty input", 0, PCMTotalBytes},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			input := make([]byte, tc.inputLen)
			result, err := encoder.Encode(input)
			if err != nil {
				t.Fatalf("Encode failed: %v", err)
			}
			if len(result) != tc.wantLen {
				t.Errorf("Encode() = %d bytes, want %d", len(result), tc.wantLen)
			}
		})
	}

	if encoder.FrameSize() != PCMTotalBytes {
		t.Errorf("FrameSize() = %d, want %d", encoder.FrameSize(), PCMTotalBytes)
	}
}

func TestAudioDecoder(t *testing.T) {
	decoder := NewAudioDecoder(SampleRate, Channels)

	input := []byte{0x01, 0x00, 0x02, 0x00}
	result, err := decoder.Decode(input)
	if err != nil {
		t.Fatalf("Decode failed: %v", err)
	}
	if len(result) != len(input) {
		t.Errorf("Decode() = %d bytes, want %d", len(result), len(input))
	}
}

func TestPCMBuffer(t *testing.T) {
	buf := NewPCMBuffer(1000)

	if buf.Size() != 0 {
		t.Errorf("Initial Size() = %d, want 0", buf.Size())
	}

	data := []byte{0x01, 0x00, 0x02, 0x00}
	if err := buf.WriteBytes(data); err != nil {
		t.Fatalf("WriteBytes failed: %v", err)
	}

	if buf.Size() != 2 {
		t.Errorf("Size() after write = %d, want 2", buf.Size())
	}

	samples := buf.Read()
	if len(samples) != 2 {
		t.Errorf("Read() = %d samples, want 2", len(samples))
	}
	if samples[0] != 1 || samples[1] != 2 {
		t.Errorf("Read() values = %v, want [1, 2]", samples)
	}

	if buf.Size() != 0 {
		t.Errorf("Size() after read = %d, want 0", buf.Size())
	}

	if err := buf.WriteBytes([]byte{0x01}); err == nil {
		t.Error("WriteBytes should fail for odd-length input")
	}
}

func TestPCMBufferSilence(t *testing.T) {
	buf := NewPCMBuffer(100)

	buf.WriteInt16([]int16{0, 0, 0})
	if !buf.Silence(10) {
		t.Error("Silence() should return true for zero samples")
	}

	buf.WriteInt16([]int16{100, 0, 0})
	if buf.Silence(10) {
		t.Error("Silence() should return false for non-zero samples")
	}
}

func TestMix(t *testing.T) {
	pcm1 := []int16{100, 200}
	pcm2 := []int16{50, 50}

	result := Mix(pcm1, pcm2, 1.0, 1.0)
	if len(result) != 2 {
		t.Fatalf("Mix() = %d samples, want 2", len(result))
	}
	if result[0] != 150 || result[1] != 250 {
		t.Errorf("Mix() = %v, want [150, 250]", result)
	}

	result = Mix(pcm1, pcm2, 0.5, 0.5)
	if result[0] != 75 || result[1] != 125 {
		t.Errorf("Mix() with gain = %v, want [75, 125]", result)
	}
}

func TestVolumeScale(t *testing.T) {
	input := []byte{0xFF, 0x7F, 0x00, 0x80}

	result := VolumeScale(input, 50)
	if len(result) != len(input) {
		t.Errorf("VolumeScale() = %d bytes, want %d", len(result), len(input))
	}

	result = VolumeScale(input, 0)
	if result[0] != 0 || result[1] != 0 {
		t.Errorf("VolumeScale(0) should return zeros")
	}

	result = VolumeScale(input, 200)
	if len(result) != len(input) {
		t.Errorf("VolumeScale(200) should clamp to 100")
	}
}

func TestIsSilent(t *testing.T) {
	if !IsSilent([]byte{}, 10) {
		t.Error("IsSilent should return true for empty input")
	}

	if !IsSilent([]byte{0x00, 0x00}, 10) {
		t.Error("IsSilent should return true for zero samples")
	}

	if IsSilent([]byte{0x64, 0x00}, 10) {
		t.Error("IsSilent should return false for non-zero sample")
	}
}

func TestRMS(t *testing.T) {
	input := []byte{0xFF, 0x7F, 0xFF, 0x7F}
	rms := RMS(input)
	if rms <= 0 {
		t.Errorf("RMS() = %f, want > 0", rms)
	}

	if RMS([]byte{}) != 0 {
		t.Error("RMS should return 0 for empty input")
	}
}

func TestDBFS(t *testing.T) {
	if dBFS(0) != -96.0 {
		t.Errorf("dBFS(0) = %f, want -96.0", dBFS(0))
	}

	db := dBFS(32768.0)
	if db != 0.0 {
		t.Errorf("dBFS(32768) = %f, want 0.0", db)
	}
}