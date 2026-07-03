// Android 音频采集与播放模块
package com.fyaudio.syncplayer.audio

import android.annotation.SuppressLint
import android.content.Context
import android.media.*
import android.media.projection.MediaProjection
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import java.nio.ByteBuffer

class AudioCaptureManager(private val context: Context) {
    companion object {
        private const val TAG = "FyAudio-Capture"
        const val SAMPLE_RATE = 44100
        const val CHANNELS = 2
        const val FRAME_DURATION_MS = 20
        const val FRAME_SIZE = SAMPLE_RATE * CHANNELS * FRAME_DURATION_MS / 1000 * 2 // bytes
    }

    private var mediaRecorder: AudioRecord? = null
    private var isCapturing = false
    private var projection: MediaProjection? = null
    private var captureJob: Job? = null
    private var audioFormat: AudioFormat? = null

    var onFrameCaptured: ((ByteArray) -> Unit)? = null

    // =========================================================================
    // MediaProjection 系统音频采集（Android 10+）
    // =========================================================================

    @SuppressLint("MissingPermission")
    fun startCapture(projectionData: MediaProjection) {
        if (isCapturing) return

        this.projection = projectionData

        // 配置 AudioFormat
        audioFormat = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()

        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_STEREO,
            AudioFormat.ENCODING_PCM_16BIT
        ) * 2

        try {
            mediaRecorder = AudioRecord(
                AudioSource.MEDIA_RECORD_APPLICATION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_STEREO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize.coerceAtLeast(FRAME_SIZE * 4)
            )

            if (mediaRecorder?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord 初始化失败")
                return
            }

            isCapturing = true
            mediaRecorder?.startRecording()

            // 采集循环
            captureJob = CoroutineScope(Dispatchers.IO).launch {
                val buffer = ByteArray(FRAME_SIZE)
                val byteBuffer = ByteBuffer.allocateDirect(FRAME_SIZE)

                while (isActive && isCapturing) {
                    try {
                        val read = mediaRecorder?.read(byteBuffer, FRAME_SIZE) ?: 0
                        if (read > 0) {
                            byteBuffer.get(buffer, 0, read)
                            byteBuffer.clear()
                            onFrameCaptured?.invoke(buffer.copyOf(read))
                        }
                        // 按帧时长休眠（精确控制）
                        delay(FRAME_DURATION_MS.toLong())
                    } catch (e: Exception) {
                        Log.e(TAG, "采集异常", e)
                        break
                    }
                }
            }

            Log.i(TAG, "系统音频采集已启动 (MediaProjection)")
        } catch (e: Exception) {
            Log.e(TAG, "启动采集失败", e)
        }
    }

    fun stopCapture() {
        isCapturing = false
        captureJob?.cancel()
        try {
            mediaRecorder?.stop()
            mediaRecorder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "停止采集异常", e)
        }
        mediaRecorder = null
        projection?.stop()
        projection = null
        Log.i(TAG, "系统音频采集已停止")
    }
}

// =============================================================================
// 音频播放
// =============================================================================

class AudioPlayerManager(private val context: Context) {
    companion object {
        private const val TAG = "FyAudio-Player"
        const val SAMPLE_RATE = 44100
        const val CHANNELS = 2
        const val FRAME_DURATION_MS = 20
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false
    private var currentVolume = 1.0f

    fun start() {
        if (isPlaying) return

        val bufferSize = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_STEREO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        audioTrack?.play()
        isPlaying = true
        Log.i(TAG, "音频播放已启动")
    }

    fun playFrame(payload: ByteArray) {
        if (!isPlaying || audioTrack?.playState != AudioTrack.PLAYSTATE_PLAYING) {
            return
        }

        try {
            // TODO: 通过 FFmpeg 或 MediaCodec 解码 AAC -> PCM
            // 目前接收端接收的是 AAC 数据，需要解码后再播放
            // 这里暂时直接写入（实际使用需要解码）

            // 示例：将 AAC 数据解码为 PCM 后播放
            // val pcm = decodeAAC(payload)
            // audioTrack?.write(pcm, 0, pcm.size)

            // 写入静音帧作为占位（实际替换为解码后的PCM）
            val silentFrame = ByteArray(payload.size.coerceAtLeast(3528))
            audioTrack?.write(silentFrame, 0, silentFrame.size)
        } catch (e: Exception) {
            Log.e(TAG, "播放帧异常", e)
        }
    }

    fun stop() {
        isPlaying = false
        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {
            Log.e(TAG, "停止播放异常", e)
        }
        audioTrack = null
        Log.i(TAG, "音频播放已停止")
    }

    fun setVolume(volume: Int) {
        currentVolume = volume / 100f
        audioTrack?.apply {
            val vol = AudioManager.ADJUST_RAISE
            // Android 8.0+ 使用 setVolumeShaping
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setVolume(currentVolume)
            }
        }
    }

    // AAC解码（使用 MediaCodec）
    // 实际实现需要使用 MediaCodec 解码 AAC -> PCM
    @SuppressLint("UnsafeInput")
    private fun decodeAAC(aacData: ByteArray): ByteArray {
        // 简单占位：实际实现需要 MediaCodec AAC 解码器
        // 1. 配置 MediaCodec 为 AAC 解码
        // 2. 输入 AAC 数据（含 ADTS 头）
        // 3. 输出 PCM 16bit 数据
        return aacData
    }
}

// =============================================================================
// 音频编解码（FFmpeg集成建议）
// =============================================================================

/*
 * 建议的 FFmpeg 集成方案：
 *
 * 1. 添加 FFmpeg 依赖（推荐使用 mobile-ffmpeg 或 ffmpeg-kit）：
 *    implementation 'com.arthenica:ffmpeg-kit-full:6.0-2'
 *
 * 2. AAC 编码（PCM -> AAC）：
 *    val command = "-f s16le -ar 44100 -ac 2 -i - -c:a aac -b:a 128k -frames:a 1 -f adts -"
 *    FFmpeg.execute(command, pcmInputStream, aacOutputStream)
 *
 * 3. AAC 解码（AAC -> PCM）：
 *    val command = "-f adts -i - -f s16le -ar 44100 -ac 2 -"
 *    FFmpeg.execute(command, aacInputStream, pcmOutputStream)
 *
 * 4. 也可使用 Android 原生 MediaCodec：
 *    - 编码：MediaCodec.createEncoderByType("audio/mp4a-latm")
 *    - 解码：MediaCodec.createDecoderByType("audio/mp4a-latm")
 *
 * 5. 实时音频优化：
 *    - 使用环形缓冲区减少 GC 压力
 *    - 使用 AudioRecord/AudioTrack 低延迟模式
 *    - 设置 AudioTrack.PERFORMANCE_MODE_LATENCY
 */
