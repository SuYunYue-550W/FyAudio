// Android 协议层 - 消息解析与序列化
package com.fyaudio.syncplayer.protocol

import android.util.Log
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

// ============================================================================
// 消息类型
// ============================================================================

object MsgType {
    const val MSG_DISCOVER = 0x01
    const val MSG_ONLINE = 0x02
    const val MSG_OFFLINE = 0x03
    const val MSG_SET_SOURCE = 0x10
    const val MSG_VOLUME_SYNC = 0x11
    const val MSG_SYNC_REQUEST = 0x20
    const val MSG_SYNC_RESPONSE = 0x21
    const val MSG_HEARTBEAT = 0x30
}

// ============================================================================
// 控制消息包
// ============================================================================

data class ControlPacket(
    val msgType: Int,
    val payloadJson: JSONObject
) {
    companion object {
        private const val TAG = "FyAudio-ControlPacket"
        private const val MAGIC = 0x46594155 // "FYAU"
        private val crc16Table = UShortArray(256)

        init {
            // 初始化 CRC16 表
            for (i in 0..255) {
                var c = i.toUShort()
                for (j in 0..7) {
                    c = if ((c.toInt() and 1) == 1) {
                        (0xA001.toUShort() xor (c.toInt() shr 1).toUShort())
                    } else {
                        (c.toInt() shr 1).toUShort()
                    }
                }
                crc16Table[i] = c
            }
        }

        fun parse(data: ByteArray): ControlPacket? {
            if (data.size < 5) return null

            val buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)

            val magic = buf.int
            if (magic != MAGIC) {
                Log.w(TAG, "魔数不匹配: ${Integer.toHexString(magic)}")
                return null
            }

            val msgType = buf.get().toInt() and 0xFF
            val payloadLen = data.size - 7
            if (payloadLen <= 0) return ControlPacket(msgType, JSONObject())

            val payloadBytes = ByteArray(payloadLen)
            buf.get(payloadBytes)
            val payloadJson = try {
                JSONObject(String(payloadBytes, Charsets.UTF_8))
            } catch (e: Exception) {
                Log.e(TAG, "JSON解析失败", e)
                JSONObject()
            }

            return ControlPacket(msgType, payloadJson)
        }
    }

    fun serialize(): ByteArray {
        val payloadBytes = payloadJson.toString().toByteArray(Charsets.UTF_8)
        val totalLen = 4 + 1 + payloadBytes.size + 2 // magic + type + payload + crc16

        val buf = ByteBuffer.allocate(totalLen).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(MAGIC)
        buf.put(msgType.toByte())
        buf.put(payloadBytes)

        // CRC16
        val crcBuf = ByteBuffer.allocate(5 + payloadBytes.size).order(ByteOrder.LITTLE_ENDIAN)
        crcBuf.putInt(MAGIC)
        crcBuf.put(msgType.toByte())
        crcBuf.put(payloadBytes)

        var crc = 0xFFFF.toUShort()
        for (i in 0 until crcBuf.capacity()) {
            crc = (crc.toInt() shr 8).toUShort() xor crc16Table[(crc.toInt() xor crcBuf.get(i).toInt()) and 0xFF]
        }
        buf.putShort(crc.toShort())

        return buf.array()
    }
}

// ============================================================================
// 音频帧包
// ============================================================================

data class AudioFramePacket(
    val timestamp: Long,   // UTC毫秒
    val payload: ByteArray
) {
    companion object {
        private const val TAG = "FyAudio-AudioFrame"
        private const val MAGIC = 0x46594155

        fun parse(data: ByteArray, length: Int): AudioFramePacket? {
            if (length < 16) return null

            val buf = ByteBuffer.wrap(data, 0, length).order(ByteOrder.LITTLE_ENDIAN)

            val magic = buf.int
            if (magic != MAGIC) return null

            val timestamp = buf.long
            val payloadLen = buf.int
            if (length < 16 + payloadLen) return null

            val payload = ByteArray(payloadLen)
            buf.get(payload)

            // TODO: CRC 校验

            return AudioFramePacket(timestamp, payload)
        }
    }

    fun serialize(): ByteArray {
        val buf = ByteBuffer.allocate(16 + payload.size).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(MAGIC)
        buf.putLong(timestamp)
        buf.putInt(payload.size)
        buf.put(payload)
        return buf.array()
    }

    val serializedSize: Int get() = 16 + payload.size
}

// ============================================================================
// 同步请求/响应
// ============================================================================

data class SyncRequest(
    val clientTime: Long
)

data class SyncResponse(
    val clientTime: Long,
    val serverTime: Long,
    val serverLatency: Long
)

// ============================================================================
// 辅助
// ============================================================================

fun getTimestamp(): Long = System.currentTimeMillis()
