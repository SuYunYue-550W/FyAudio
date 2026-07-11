package sync

import (
	"errors"
	"time"

	"fyaudio/common/sync"
)

var ErrBufferUnderrun = errors.New("buffer underrun")

type AudioFrame struct {
	Timestamp uint64
	Payload   []byte
}

type Engine struct {
	buffer    *sync.RingBuffer
	bufferMs  int
	lastTs    uint64
}

func NewEngine(bufferMs int) *Engine {
	return &Engine{
		buffer:   sync.NewRingBuffer(bufferMs / 20),
		bufferMs: bufferMs,
	}
}

func (e *Engine) ProcessFrame(payload []byte, timestamp uint64) (*AudioFrame, error) {
	e.lastTs = timestamp

	frame := &sync.AudioFrame{
		Timestamp: timestamp,
		Payload:   payload,
		RecvTime:  time.Now().UnixNano() / 1_000_000,
	}

	if !e.buffer.Push(frame) {
		return nil, ErrBufferUnderrun
	}

	playable := e.buffer.GetPlayableFrame(int64(e.bufferMs))
	if playable == nil {
		return nil, ErrBufferUnderrun
	}

	return &AudioFrame{
		Timestamp: playable.Timestamp,
		Payload:   playable.Payload,
	}, nil
}

func (e *Engine) GetStats() (int, int64) {
	size := e.buffer.Size()
	return size, int64(e.bufferMs)
}