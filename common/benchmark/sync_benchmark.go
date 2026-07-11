package main

import (
	"fmt"
	"math/rand"
	"sync"
	"time"

	"fyaudio/common/protocol"
	fysync "fyaudio/common/sync"
)

func main() {
	fmt.Println("=== FyAudio Sync Engine Benchmark ===")
	fmt.Println()

	benchmarkRingBuffer()
	fmt.Println()
	benchmarkSyncEngine()
	fmt.Println()
	benchmarkClockOffset()
}

func benchmarkRingBuffer() {
	fmt.Println("1. Ring Buffer Benchmark")
	fmt.Println("========================")

	buffer := fysync.NewRingBuffer(100)

	start := time.Now()
	for i := 0; i < 100000; i++ {
		buffer.Push(&fysync.AudioFrame{
			Timestamp: uint64(i * 20),
			Payload:   []byte("test"),
			RecvTime:  int64(i * 20),
		})
		if i > 100 {
			buffer.Pop()
		}
	}
	elapsed := time.Since(start)

	fmt.Printf("  Operations: 100,000 push/pop\n")
	fmt.Printf("  Time: %v\n", elapsed)
	fmt.Printf("  Rate: %.2f ops/ms\n", float64(100000)/elapsed.Seconds()/1000)

	dropped := buffer.Drain()
	fmt.Printf("  Drain dropped: %d frames\n", dropped)
}

func benchmarkSyncEngine() {
	fmt.Println("2. Sync Engine Benchmark")
	fmt.Println("========================")

	se := fysync.NewSyncEngine()

	start := time.Now()
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		for i := 0; i < 10000; i++ {
			packet := &protocol.AudioFramePacket{
				Timestamp: uint64(time.Now().UnixNano()/1_000_000) - uint64(i*20),
				Payload:   make([]byte, 384),
			}
			se.FeedFrame(packet)
			time.Sleep(time.Microsecond * 100)
		}
	}()

	go func() {
		defer wg.Done()
		for i := 0; i < 10000; i++ {
			se.GetStats()
			time.Sleep(time.Microsecond * 100)
		}
	}()

	wg.Wait()
	elapsed := time.Since(start)

	fmt.Printf("  Feed/GetStats: 10,000 each (concurrent)\n")
	fmt.Printf("  Time: %v\n", elapsed)
	fmt.Printf("  Rate: %.2f ops/ms\n", float64(20000)/elapsed.Seconds()/1000)

	se.Reset()
}

func benchmarkClockOffset() {
	fmt.Println("3. Clock Offset Benchmark")
	fmt.Println("=========================")

	se := fysync.NewSyncEngine()

	start := time.Now()
	rttValues := []int64{20, 30, 50, 80, 100}
	for i := 0; i < 1000; i++ {
		rtt := rttValues[rand.Intn(len(rttValues))]
		se.UpdateClockOffset(uint64(i*1000), uint64(i*1000)+uint64(50)+uint64(rtt/2), rtt)
	}
	elapsed := time.Since(start)

	fmt.Printf("  UpdateClockOffset: 1,000 iterations\n")
	fmt.Printf("  Time: %v\n", elapsed)
	fmt.Printf("  Rate: %.2f updates/ms\n", float64(1000)/elapsed.Seconds()/1000)

	_, _, _, offset := se.GetStats()
	fmt.Printf("  Final offset: %d ms\n", offset)
}