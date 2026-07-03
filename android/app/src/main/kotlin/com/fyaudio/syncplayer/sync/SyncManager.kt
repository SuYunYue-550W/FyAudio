// Android 同步管理模块
package com.fyaudio.syncplayer.sync

import android.util.Log
import com.fyaudio.syncplayer.model.AudioFrame
import com.fyaudio.syncplayer.model.SyncStats
import kotlinx.coroutines.*
import java.util.*

class SyncManager(
    private val onPlayableFrame: (AudioFrame) -> Unit,
    private val onStatsUpdate: (SyncStats) -> Unit
) {
    companion object {
        private const val TAG = "FyAudio-Sync"
        private const val BUFFER_CAPACITY = 200
        private const val MAX_FRAME_AGE_MS = 500L
        private const val BUFFER_MIN_MS = 20
        private const val BUFFER_DEFAULT_MS = 40
        private const val BUFFER_MAX_MS = 200
    }

    // 环形缓冲（按时间戳排序的帧列表）
    private val buffer = LinkedList<AudioFrame>()
    private val bufferLock = Any()

    private var isPlaying = false
    private var manualOffsetMs = 0
    private var clockOffsetMs = 0
    private var bufferWindowMs = BUFFER_DEFAULT_MS
    private var estimatedRTT = 50

    private val latencyHistory = LongArray(20)
    private var latencyIdx = 0
    private var droppedFrames = 0L
    private var totalFrames = 0L

    private var checkJob: Job? = null

    // =========================================================================
    // 接收帧
    // =========================================================================

    fun feedFrame(frame: AudioFrame) {
        totalFrames++
        val nowMs = System.currentTimeMillis()

        // 过期帧丢弃
        if (nowMs - frame.timestamp > MAX_FRAME_AGE_MS) {
            droppedFrames++
            return
        }

        // 估算网络延迟
        val latency = nowMs - frame.timestamp
        latencyHistory[latencyIdx % latencyHistory.size] = latency
        latencyIdx++
        updateBufferWindow(latency)

        // 插入到排序位置
        synchronized(bufferLock) {
            if (buffer.size >= BUFFER_CAPACITY) {
                buffer.removeFirst()
            }

            // 二分插入（O(n)，可优化为二叉树）
            var inserted = false
            val it = buffer.listIterator(buffer.size)
            while (it.hasPrevious()) {
                val prev = it.previous()
                if (frame.timestamp >= prev.timestamp) {
                    it.next()
                    it.add(frame)
                    inserted = true
                    break
                }
            }
            if (!inserted) {
                buffer.addFirst(frame)
            }
        }

        // 触发播放检查
        if (isPlaying) {
            checkPlayable(nowMs)
        }

        // 更新统计
        updateStats()
    }

    private fun updateBufferWindow(latency: Long) {
        // 中位延迟
        val sorted = latencyHistory.copyOf().sorted()
        val median = sorted[sorted.size / 2]

        estimatedRTT = median.toInt()
        val targetWindow = (median * 2).toInt()
            .coerceAtLeast(BUFFER_MIN_MS)
            .coerceAtMost(BUFFER_MAX_MS)

        bufferWindowMs = (bufferWindowMs + targetWindow) / 2
    }

    // =========================================================================
    // 播放控制
    // =========================================================================

    fun startPlaying() {
        isPlaying = true
        checkJob = CoroutineScope(Dispatchers.Default).launch {
            while (isActive) {
                checkPlayable(System.currentTimeMillis())
                delay(5) // 5ms 检查间隔
            }
        }
        Log.i(TAG, "同步播放已启动")
    }

    fun pausePlaying() {
        isPlaying = false
        checkJob?.cancel()
        Log.i(TAG, "同步播放已暂停")
    }

    private fun checkPlayable(nowMs: Long) {
        val targetTime = nowMs + bufferWindowMs + manualOffsetMs + clockOffsetMs

        while (true) {
            val frame = synchronized(bufferLock) {
                buffer.peekFirst()
            } ?: break

            if (frame.timestamp <= targetTime) {
                val removed = synchronized(bufferLock) { buffer.removeFirst() }
                if (removed != null) {
                    onPlayableFrame(removed)
                }
            } else {
                break
            }
        }
    }

    // =========================================================================
    // 延迟补偿
    // =========================================================================

    fun setManualOffset(offsetMs: Int) {
        manualOffsetMs = offsetMs.coerceIn(-200, 200)
        Log.i(TAG, "手动延迟补偿: ${manualOffsetMs}ms")
    }

    fun adjustOffset(deltaMs: Int) {
        setManualOffset(manualOffsetMs + deltaMs)
    }

    // 时钟偏差校准
    fun updateClockOffset(clientTime: Long, serverTime: Long, rttMs: Long) {
        clockOffsetMs = ((serverTime - clientTime - rttMs / 2)).toInt()
        Log.i(TAG, "时钟偏差补偿: ${clockOffsetMs}ms (RTT=$rttMs)")
    }

    // =========================================================================
    // 重置
    // =========================================================================

    fun reset() {
        synchronized(bufferLock) { buffer.clear() }
        bufferWindowMs = BUFFER_DEFAULT_MS
        clockOffsetMs = 0
        manualOffsetMs = 0
        droppedFrames = 0
        totalFrames = 0
        Log.i(TAG, "同步状态已重置")
    }

    // =========================================================================
    // 统计
    // =========================================================================

    private fun updateStats() {
        val stats = SyncStats(
            bufferFrames = synchronized(bufferLock) { buffer.size },
            estimatedRTT = estimatedRTT,
            windowMs = bufferWindowMs,
            offsetMs = clockOffsetMs + manualOffsetMs,
            isPlaying = isPlaying,
            droppedFrames = droppedFrames,
            totalFrames = totalFrames
        )
        onStatsUpdate(stats)
    }

    fun getBufferSize(): Int = synchronized(bufferLock) { buffer.size }
}
