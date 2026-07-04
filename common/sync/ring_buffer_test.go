package sync

import (
	"testing"
	"time"

	"fyaudio/common/protocol"
)

func TestRingBuffer(t *testing.T) {
	rb := NewRingBuffer(3)

	if rb.Size() != 0 {
		t.Errorf("Initial Size() = %d, want 0", rb.Size())
	}

	baseTs := uint64(time.Now().UnixNano() / 1_000_000)
	frame1 := &AudioFrame{Timestamp: baseTs + 1000, Payload: []byte("frame1")}
	frame2 := &AudioFrame{Timestamp: baseTs + 2000, Payload: []byte("frame2")}
	frame3 := &AudioFrame{Timestamp: baseTs + 3000, Payload: []byte("frame3")}

	if !rb.Push(frame1) {
		t.Error("Push() should succeed for first frame")
	}
	if !rb.Push(frame2) {
		t.Error("Push() should succeed for second frame")
	}
	if !rb.Push(frame3) {
		t.Error("Push() should succeed for third frame")
	}

	if rb.Size() != 3 {
		t.Errorf("Size() after 3 pushes = %d, want 3", rb.Size())
	}

	frame4 := &AudioFrame{Timestamp: baseTs + 4000, Payload: []byte("frame4")}
	if !rb.Push(frame4) {
		t.Error("Push() should succeed for fourth frame")
	}

	if rb.Size() != 3 {
		t.Errorf("Size() after overflow = %d, want 3", rb.Size())
	}

	frame4Dup := &AudioFrame{Timestamp: baseTs + 4000, Payload: []byte("frame4_dup")}
	if rb.Push(frame4Dup) {
		t.Error("Push() should fail for duplicate timestamp")
	}

	if rb.Size() != 3 {
		t.Errorf("Size() should remain 3 after duplicate")
	}

	popped := rb.Pop()
	if popped == nil {
		t.Fatal("Pop() should return a frame")
	}
	if popped.Timestamp != baseTs+2000 {
		t.Errorf("Pop() = %d, want %d (oldest after overflow)", popped.Timestamp, baseTs+2000)
	}

	if rb.Size() != 2 {
		t.Errorf("Size() after pop = %d, want 2", rb.Size())
	}

	rb.Clear()
	if rb.Size() != 0 {
		t.Errorf("Size() after Clear() = %d, want 0", rb.Size())
	}
}

func TestRingBufferDedup(t *testing.T) {
	rb := NewRingBuffer(5)

	baseTs := uint64(time.Now().UnixNano() / 1_000_000)
	frame1 := &AudioFrame{Timestamp: baseTs + 1000, Payload: []byte("frame1")}
	frame1Dup := &AudioFrame{Timestamp: baseTs + 1000, Payload: []byte("frame1_dup")}

	rb.Push(frame1)
	if rb.Push(frame1Dup) {
		t.Error("Push() should fail for duplicate timestamp")
	}

	if rb.Size() != 1 {
		t.Errorf("Size() should remain 1 after duplicate push")
	}
}

func TestRingBufferOrder(t *testing.T) {
	rb := NewRingBuffer(5)

	baseTs := uint64(time.Now().UnixNano() / 1_000_000)
	rb.Push(&AudioFrame{Timestamp: baseTs + 3000})
	rb.Push(&AudioFrame{Timestamp: baseTs + 1000})
	rb.Push(&AudioFrame{Timestamp: baseTs + 2000})

	f1 := rb.Pop()
	if f1 == nil {
		t.Fatal("Pop() should return a frame")
	}
	if f1.Timestamp != baseTs+1000 {
		t.Errorf("First Pop() = %d, want %d", f1.Timestamp, baseTs+1000)
	}

	f2 := rb.Pop()
	if f2 == nil {
		t.Fatal("Pop() should return a frame")
	}
	if f2.Timestamp != baseTs+2000 {
		t.Errorf("Second Pop() = %d, want %d", f2.Timestamp, baseTs+2000)
	}

	f3 := rb.Pop()
	if f3 == nil {
		t.Fatal("Pop() should return a frame")
	}
	if f3.Timestamp != baseTs+3000 {
		t.Errorf("Third Pop() = %d, want %d", f3.Timestamp, baseTs+3000)
	}
}

func TestRingBufferExpired(t *testing.T) {
	rb := NewRingBuffer(5)
	rb.maxAgeMs = 100

	baseTs := uint64(time.Now().UnixNano() / 1_000_000)
	oldFrame := &AudioFrame{Timestamp: baseTs - 200}
	if rb.Push(oldFrame) {
		t.Error("Push() should fail for expired frame")
	}

	recentFrame := &AudioFrame{Timestamp: baseTs + 100}
	if !rb.Push(recentFrame) {
		t.Error("Push() should succeed for recent frame")
	}
}

func TestRingBufferGetPlayableFrame(t *testing.T) {
	rb := NewRingBuffer(5)

	now := time.Now().UnixNano() / 1_000_000
	frame1 := &AudioFrame{Timestamp: uint64(now - 100)}
	frame2 := &AudioFrame{Timestamp: uint64(now + 100)}

	rb.Push(frame1)
	rb.Push(frame2)

	playable := rb.GetPlayableFrame(50)
	if playable == nil {
		t.Error("GetPlayableFrame() should return a playable frame")
	}
	if playable.Timestamp != uint64(now-100) {
		t.Errorf("GetPlayableFrame() = %d, want %d", playable.Timestamp, now-100)
	}

	playable = rb.GetPlayableFrame(50)
	if playable != nil {
		t.Error("GetPlayableFrame() should return nil for future frame")
	}
}

func TestSyncEngine(t *testing.T) {
	se := NewSyncEngine()

	if !se.IsPlaying() {
		se.SetPlaying(true)
	}
	if !se.IsPlaying() {
		t.Error("IsPlaying() should return true after SetPlaying(true)")
	}

	se.SetManualOffset(50)
	if se.GetManualOffset() != 50 {
		t.Errorf("GetManualOffset() = %d, want 50", se.GetManualOffset())
	}

	se.SetManualOffset(300)
	if se.GetManualOffset() != 200 {
		t.Errorf("GetManualOffset() should clamp to 200, got %d", se.GetManualOffset())
	}

	se.SetManualOffset(-300)
	if se.GetManualOffset() != -200 {
		t.Errorf("GetManualOffset() should clamp to -200, got %d", se.GetManualOffset())
	}

	se.Reset()
	if se.GetManualOffset() != 0 {
		t.Errorf("GetManualOffset() should be 0 after Reset(), got %d", se.GetManualOffset())
	}
}

func TestSyncEngineFeedFrame(t *testing.T) {
	se := NewSyncEngine()

	baseTs := uint64(time.Now().UnixNano() / 1_000_000)
	for i := 0; i < 5; i++ {
		packet := &protocol.AudioFramePacket{
			Timestamp: baseTs - uint64(50-i*10),
			Payload:   []byte("test payload"),
		}
		if !se.FeedFrame(packet) {
			t.Error("FeedFrame() should succeed")
		}
		time.Sleep(time.Millisecond)
	}

	_, _, window, _ := se.GetStats()
	if window <= 0 {
		t.Errorf("bufferWindowMs = %d, want > 0", window)
	}
}

func TestSyncEngineUpdateClockOffset(t *testing.T) {
	se := NewSyncEngine()

	se.UpdateClockOffset(1000, 1050, 20)

	_, _, _, offset := se.GetStats()
	if offset != 40 {
		t.Errorf("clockOffset = %d, want 40 (50 - 10)", offset)
	}
}

func TestSyncCalibrator(t *testing.T) {
	sc := NewSyncCalibrator()

	req := sc.MakeSyncRequest()
	if req.ClientTime == 0 {
		t.Error("MakeSyncRequest() should return non-zero ClientTime")
	}

	resp := &protocol.SyncResponse{
		ClientTime: req.ClientTime,
		ServerTime: req.ClientTime + 100,
	}

	offset := sc.HandleSyncResponse(resp)
	if offset <= 0 {
		t.Errorf("HandleSyncResponse() = %d, want > 0", offset)
	}

	if sc.GetLastOffset() != offset {
		t.Errorf("GetLastOffset() = %d, want %d", sc.GetLastOffset(), offset)
	}

	invalidResp := &protocol.SyncResponse{ClientTime: 0}
	if sc.HandleSyncResponse(invalidResp) != 0 {
		t.Error("HandleSyncResponse() should return 0 for invalid request")
	}
}