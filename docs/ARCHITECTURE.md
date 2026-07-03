# FyAudio 系统架构文档

## 1. 系统分层

```
┌──────────────────────────────────────────────────────────────┐
│                     应用层 (Application)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐ │
│  │  Windows  │  │ Android  │  │  macOS   │  │  Raspberry   │ │
│  │ Flutter  │  │ Compose  │  │ Flutter  │  │   Pi CLI     │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘ │
└───────┼─────────────┼─────────────┼────────────────┼────────┘
        │             │             │                │
┌───────┼─────────────┼─────────────┼────────────────┼────────┐
│       │         Service Layer     │                │        │
│  ┌────▼────┐  ┌────▼────┐  ┌────▼────┐  ┌────────▼────────┐ │
│  │Network  │  │Network  │  │Network  │  │    Network      │ │
│  │Manager  │  │Manager  │  │Manager  │  │    Manager      │ │
│  ├─────────┤  ├─────────┤  ├─────────┤  ├─────────────────┤ │
│  │ Audio   │  │ Audio   │  │ Audio   │  │     Audio       │ │
│  │Service  │  │Service  │  │Service  │  │    Manager      │ │
│  ├─────────┤  ├─────────┤  ├─────────┤  ├─────────────────┤ │
│  │Bluetooth│  │Bluetooth│  │Bluetooth│  │    Bluetooth    │ │
│  │Service  │  │Service  │  │Service  │  │    Manager      │ │
│  ├─────────┤  ├─────────┤  ├─────────┤  ├─────────────────┤ │
│  │  Sync   │  │  Sync   │  │  Sync   │  │     Sync        │ │
│  │ Engine  │  │ Engine  │  │ Engine  │  │    Engine       │ │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────────┬────────┘ │
└───────┼─────────────┼─────────────┼───────────────┼────────┘
        │             │             │               │
┌───────┼─────────────┼─────────────┼───────────────┼────────┐
│       │      Platform Abstraction     │               │        │
│  ┌────▼────┐  ┌────▼────┐  ┌────▼────┐  ┌────────▼────────┐ │
│  │ WASAPI   │  │MediaPro-│  │  Core   │  │   ALSA + Blue   │ │
│  │ + Cable  │  │jection  │  │ Audio   │  │     ALSA        │ │
│  │ VB-Audio │  │ + Media │  │         │  │                 │ │
│  │          │  │  Codec  │  │         │  │                 │ │
│  └──────────┘  └─────────┘  └─────────┘  └─────────────────┘ │
│                                                              │
│              Platform/Driver Layer                           │
└──────────────────────────────────────────────────────────────┘
```

## 2. 核心模块

### 2.1 协议层 (common/protocol)

**职责**: 定义网络消息格式、编解码、校验

```
消息结构: [Magic:4][Type:1][Payload:N][CRC16:2]
Magic: 0x46594155 ("FYAU")

消息类型:
├── Online (0x02)       # 设备上线
├── Offline (0x03)      # 设备离线
├── Discover (0x01)      # 设备发现（触发回复Online）
├── SetSource (0x10)     # 设置音源
├── VolumeSync (0x11)    # 音量同步
├── Heartbeat (0x30)     # 心跳保活
└── AudioFrame           # 音频帧（独立包）
    ├── [Magic:4]
    ├── [Timestamp:8]    # UTC毫秒时间戳
    ├── [Length:4]       # 负载长度
    └── [Payload:N]      # AAC数据
```

### 2.2 网络层 (common/network)

**职责**: UDP广播/单播、设备发现、心跳

- **控制消息**: 端口 5002 (UDP)
- **音频流**: 端口 5001 (UDP)
- **广播地址**: 255.255.255.255

**发现流程**:
1. 设备启动 → 发送 Online 广播
2. 定期发送 Discover → 触发新设备回复 Online
3. 心跳每3秒 → 超过12秒无心跳判定离线

### 2.3 音频层 (common/audio)

**职责**: PCM处理、AAC编解码

- **采样率**: 44100 Hz
- **通道**: 2 (立体声)
- **位深**: 16 bit
- **帧时长**: 20ms (882 samples)

**Source端**:
```
系统音频(PulseAudio/WASAPI) → PCM → FFmpeg AAC编码 → UDP广播
```

**Receiver端**:
```
UDP接收 → FFmpeg AAC解码 → PCM → ALSA/蓝牙播放
```

### 2.4 同步层 (common/sync)

**职责**: 时序对齐、环形缓冲、延迟补偿

```
┌─────────────────────────────────────────────────────────┐
│                     环形缓冲池                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │ [Frame(t=100)] [Frame(t=120)] [Frame(t=140)] ...│   │
│  └─────────────────────────────────────────────────┘   │
│       ↑ Head (最早播放)              Tail (最新) ↑       │
└─────────────────────────────────────────────────────────┘
```

**播放算法**:
```
current_time = now()
target_play_time = frame.timestamp + buffer_window + manual_offset + clock_offset

if current_time >= target_play_time:
    play(frame)
else:
    wait(...)
```

**动态缓冲调整**:
```
median_latency = median(recent_20_packets_latency)
buffer_window = median_latency * 2  # 动态窗口
```

## 3. 平台实现

### 3.1 Windows (Flutter)

```
┌────────────────────────────────────────┐
│           Flutter UI Layer            │
├────────────────────────────────────────┤
│         Provider (State Management)   │
├──────────┬──────────┬─────────┬───────┤
│NetworkSvc│AudioSvc   │BtSvc    │SyncSvc│
├──────────┼──────────┼─────────┼───────┤
│ dart:io  │ VB-Audio │system_  │ Sync  │
│ UDP      │ + WASAPI │tray     │Engine │
└──────────┴──────────┴─────────┴───────┘
```

**关键依赖**:
- `system_tray`: 系统托盘
- `window_manager`: 窗口管理
- `shared_preferences`: 配置存储
- `provider`: 状态管理

### 3.2 Android (Kotlin)

```
┌────────────────────────────────────────┐
│      Jetpack Compose UI Layer         │
├────────────────────────────────────────┤
│         ViewModel (StateFlow)         │
├──────────┬──────────┬─────────┬───────┤
│Network   │ AudioCap │Bluetooth│Sync   │
│Manager   │ Manager  │Manager  │Manager │
├──────────┼──────────┼─────────┼───────┤
│ Kotlin   │MediaPro- │ Android │ Sync  │
│ Coroutine│jection   │ Bluetooth│Engine │
│ + UDP    │ +Codec   │ API     │       │
└──────────┴──────────┴─────────┴───────┘
```

**关键实现**:
- `MediaProjection`: 系统音频采集（需用户授权）
- `MediaCodec`: AAC编解码
- `BluetoothA2dp`: 蓝牙音频播放
- `Kotlin Coroutine`: 异步网络处理

### 3.3 树莓派 (Go)

```
┌────────────────────────────────────────┐
│            CLI / TUI Layer            │
├────────────────────────────────────────┤
│           Flag / Config               │
├──────────┬──────────┬─────────┬───────┤
│Network   │ Audio    │Bluetooth│ Sync  │
│Manager   │ Manager  │Manager  │Engine │
├──────────┼──────────┼─────────┼───────┤
│ Go net   │ ALSA     │ Blue    │ Ring  │
│ UDP      │ libasound│ ALSA    │Buffer │
│          │          │ DBus    │       │
└──────────┴──────────┴─────────┴───────┘
```

**关键依赖**:
- `net`: Go标准库UDP
- `raspberrypi/alsa`: ALSA接口
- `bluealsa-utils`: 蓝牙A2DP
- `godbus/dbus`: DBus通信

## 4. 数据流

### 4.1 Source → Receiver 流

```
Source端                          Receiver端
  │                                  │
  │  [系统音频]                        │
  ▼                                  │
[PCM Buffer]                          │
  │                                  │
  ▼                                  │
[FFmpeg AAC] ─── UDP(5001) ───► [Buffer]
  │                                  │
  │  [时间戳=now()]                   │
  │                                  │
  ▼                                  ▼
  │                           [Sync Engine]
  │                                  │
  │  [Control(5002)]                  │
  │  - Online                        │
  │  - Heartbeat                     │
  │  - VolumeSync                    │
  │                                  ▼
  │                           [AudioTrack]
  │                                  │
  │                                  ▼
  │                           [播放输出]
  │
  ▼
[网络广播]
```

### 4.2 多设备同步时序

```
时间 ─────────────────────────────────────────────────────►

Source:  ████[T=100ms]████[T=120ms]████[T=140ms]████...
        发送音频帧（带时间戳）

Rcvr-A:  ░░░░░[T=100ms+40ms]████[T=120ms+40ms]████...
        缓冲窗口40ms后播放

Rcvr-B:  ░░░░░░░░░░[T=100ms+80ms]████[T=120ms+80ms]...
        蓝牙延迟更大，缓冲窗口自动调大
```

## 5. 错误处理

| 场景 | 检测 | 处理 |
|------|------|------|
| 网络断开 | 12秒无心跳 | 清除设备，提示用户 |
| 缓冲区下溢 | 缓冲帧<5 | 插入静音帧 |
| 缓冲区溢出 | 缓冲帧>200 | 丢弃最老帧 |
| 帧过期 | timestamp < now-500ms | 直接丢弃 |
| 音频设备异常 | WASAPI/ALSA错误 | 重试3次后降级 |
| 蓝牙断开 | BT状态回调 | 自动重连 |

## 6. 性能指标

| 指标 | 目标值 | 测量方法 |
|------|--------|----------|
| 同步精度 | <50ms | 测量同一帧在各设备播放时间差 |
| CPU占用(Source) | <15% | 单核CPU占用 |
| CPU占用(Receiver) | <8% | 单核CPU占用 |
| 内存占用 | <100MB | RSS |
| 网络带宽 | <256kbps | AAC 128k + 控制开销 |
| 端到端延迟 | 30-100ms | 音源播放到接收播放 |
