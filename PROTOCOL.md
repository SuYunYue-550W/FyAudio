# FyAudio 网络协议规范

> 版本：V1.0

---

## 1. 数据包格式

### 1.1 音频帧数据包（AudioFramePacket）

```
偏移(字节)  字段           长度      类型      说明
0           magic          4        uint32    包头：0x46594155 ("FYAU")
4           timestamp      8        uint64    UTC毫秒时间戳
12          frame_length   4        uint32    AAC数据长度
16          payload        N        bytes     AAC压缩音频数据
16+N        crc16          2        uint16    CRC16校验
```

**总长度**：18 + N 字节（N = AAC帧大小）

### 1.2 控制消息包（ControlPacket）

```
偏移(字节)  字段           长度      类型      说明
0           magic          4        uint32    包头：0x46594155
4           msg_type        1        uint8     消息类型
5           payload         N        bytes     消息内容（JSON）
5+N         crc16          2        uint16    CRC16校验
```

### 1.3 消息类型（MsgType）

```go
const (
    MsgTypeDiscover      = 0x01  // 设备发现广播
    MsgTypeOnline       = 0x02  // 设备上线
    MsgTypeOffline      = 0x03  // 设备下线
    MsgTypeSetSource    = 0x10  // 设置音源
    MsgTypeVolumeSync   = 0x11  // 音量同步
    MsgTypeSyncRequest  = 0x20  // 同步校准请求
    MsgTypeSyncResponse = 0x21  // 同步校准响应
    MsgTypeHeartbeat    = 0x30  // 心跳保活
)
```

### 1.4 设备信息（DeviceInfo）

```json
{
    "device_id": "FY-XXXXXXXXXXXX",
    "device_name": "主机-张三",
    "platform": "windows|mac|android|raspberrypi",
    "role": "source|receiver|gateway",
    "ip": "192.168.1.100",
    "audio_sample_rate": 44100,
    "audio_channels": 2,
    "capabilities": ["speaker", "bluetooth"],
    "bluetooth_connected": true,
    "is_source": false,
    "version": "1.0.0"
}
```

---

## 2. 传输配置

### 2.1 端口配置

| 用途 | 端口 | 协议 | 说明 |
|------|------|------|------|
| 音频流 | 5001 | UDP | 广播所有接收端 |
| 控制消息 | 5002 | UDP | 设备发现、心跳、指令 |
| 同步校准 | 5003 | UDP | 时间戳校准专用 |

### 2.2 广播地址

- **IPv4 子网广播**：`255.255.255.255`（自动选择当前网络接口）
- **IPv6 组播**：备用方案

### 2.3 心跳机制

- 频率：每 3 秒发送一次心跳
- 超时判定：超过 10 秒无心跳 → 设备下线
- 心跳包含：设备ID、当前角色（source/receiver）、音频状态

---

## 3. 同步算法

### 3.1 时间戳同步流程

```
音源端:
  1. 采集 PCM 原始音频
  2. AAC 编码单帧（20ms）
  3. 写入当前 UTC 时间戳（毫秒）
  4. 组包广播

接收端:
  1. 接收 UDP 包，验证 magic 和 CRC
  2. 提取时间戳 T_source 和本地接收时间 T_recv
  3. 计算网络延迟 d = T_recv - T_source
  4. 估算播放时间 T_play = T_recv + buffer_window - d
  5. 按 T_play 将帧写入环形缓冲区
  6. 播放线程按顺序读取并解码播放
```

### 3.2 动态缓冲窗口

```
最小缓冲：20ms（帧时长）
默认缓冲：40ms
最大缓冲：200ms（弱网容错）

buffer_window = min(max(estimated_rtt * 2, 40), 200)
```

### 3.3 同步校准流程

```
1. 接收端发送 SYNC_REQUEST（含本地时间 T_client）
2. 音源端回复 SYNC_RESPONSE（含 T_client 和 T_server）
3. 接收端计算 RTT = T_response - T_request
4. 接收端估算时钟偏差 offset = (T_server - T_client) - RTT/2
5. 后续播放时间 += offset 补偿
```

---

## 4. 错误处理

### 4.1 网络错误

| 错误 | 处理策略 |
|------|----------|
| UDP 包丢失 | 丢弃，静默等待下一帧（最多容忍 3 帧）|
| 连续丢包 >3 | 播放静默，输出警告 |
| 包序号跳跃 | 刷新缓冲，重新同步 |

### 4.2 蓝牙错误

| 错误 | 处理策略 |
|------|----------|
| A2DP 断开 | 自动降级为扬声器，1秒后重连尝试 |
| 重连失败 | 保持扬声器输出，显示蓝牙状态 |
| 多设备切换 | 平滑过渡，渐变切换（100ms） |

---

## 5. 示例数据包（十六进制）

### 5.1 音频帧示例

```
46 59 41 55           // Magic: "FYAU"
A2 8F 01 5D 02 4F 5E 8B  // Timestamp: 1699999999999
80 01 00 00           // Frame length: 384 bytes
[384 bytes AAC data...]
XX XX                  // CRC16
```

### 5.2 设备发现示例

```json
{
    "device_id": "FY-AABBCCDDEEFF",
    "device_name": "PC-客厅",
    "platform": "windows",
    "role": "receiver",
    "ip": "192.168.1.10",
    "capabilities": ["speaker", "bluetooth"],
    "is_source": false
}
```
