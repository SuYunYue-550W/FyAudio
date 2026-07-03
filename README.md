# FyAudio - 多终端WiFi蓝牙同步音频播放系统

<div align="center">

**让任意设备成为音源，任意设备同步接收**

[架构文档](docs/ARCHITECTURE.md) · [API协议](docs/PROTOCOL.md) · [快速开始](#快速开始) · [FAQ](docs/FAQ.md)

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android%20%7C%20macOS%20%7C%20Raspberry%20Pi-green.svg)

</div>

---

## 🎯 项目概述

FyAudio 是一个跨平台的多设备音频同步播放系统，支持：

- **WiFi局域网广播**: 将任意设备设为音源，局域网内所有设备同步播放
- **蓝牙输出**: 通过蓝牙A2DP连接无线音响
- **精确时序同步**: 基于NTP时钟同步算法，实现多设备毫秒级同步
- **零延迟切换**: 音源设备热切换，无缝接管播放

### 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    WiFi 局域网                          │
│                                                         │
│  ┌─────────┐         ┌─────────┐        ┌─────────┐   │
│  │ Windows │         │ Android │        │ Raspberry│   │
│  │  (Go)   │◄───────►│ (Kotlin)│◄──────►│   Pi    │   │
│  │         │  UDP    │         │  UDP   │   (Go)  │   │
│  │ 🎙️音源  │  广播   │ 🎧接收  │  中继   │ 🌐网关   │   │
│  └────┬────┘         └────┬────┘        └────┬────┘   │
│       │  AAC音频帧         │                 │        │
│       └───────────────────┴─────────────────┘        │
│            UDP:5001 (音频) / 5002 (控制)              │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │     蓝牙 A2DP        │
              │   📶 无线音响输出     │
              └──────────────────────┘
```

### 工作模式

| 模式 | 角色 | 说明 |
|------|------|------|
| **Source** | 🎙️ 音源 | 采集系统音频，通过WiFi广播到所有设备 |
| **Receiver** | 🎧 接收 | 接收音频流，通过本地/蓝牙播放 |
| **Gateway** | 🌐 网关 | 树莓派专属，既是接收器也是WiFi中继，可连接蓝牙音响 |

---

## 📁 项目结构

```
FyAudio/
├── common/                    # 跨平台公共代码
│   ├── protocol/              # 协议定义 (packet.go)
│   ├── network/               # 网络通信 (discovery.go)
│   ├── audio/                 # 音频处理 (processor.go)
│   └── sync/                  # 同步算法 (ring_buffer.go)
│
├── windows/                   # Windows 端 (Flutter)
│   └── fy_audio_player/
│       ├── lib/               # Dart 源代码
│       │   ├── main.dart
│       │   ├── core/          # 模型定义
│       │   ├── services/      # 服务层
│       │   ├── screens/       # 界面
│       │   └── widgets/       # 组件
│       └── pubspec.yaml
│
├── android/                   # Android 端 (Kotlin)
│   └── app/src/main/kotlin/com/fyaudio/syncplayer/
│       ├── MainActivity.kt    # 主界面
│       ├── network/           # 网络通信
│       ├── audio/             # 音频采集/播放
│       ├── bluetooth/         # 蓝牙A2DP
│       ├── sync/              # 同步引擎
│       └── ui/                # Jetpack Compose UI
│
├── raspberrypi/               # 树莓派网关 (Go)
│   └── gateway/
│       ├── main.go            # 入口
│       ├── audio/             # ALSA + BlueALSA
│       ├── bluetooth/         # BlueALSA 控制
│       └── network/           # UDP 收发
│
├── docs/                      # 文档
│   ├── ARCHITECTURE.md        # 系统架构详解
│   ├── PROTOCOL.md            # 通信协议
│   └── FAQ.md                 # 常见问题
│
├── SPEC.md                    # 产品规格书
└── PROTOCOL.md                # 协议文档
```

---

## 🚀 快速开始

### Windows 端

```bash
cd windows/fy_audio_player

# 安装 Flutter SDK (>=3.0)
flutter pub get

# 安装 VB-Audio Virtual Cable (用于采集系统音频)
# 下载: https://vb-audio.com/Cable/

# 运行
flutter run -d windows
```

### Android 端

```bash
cd android

# Android Studio 打开项目
# 或命令行构建
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

**权限需求**:
- `RECORD_AUDIO` - 采集系统音频（需要MediaProjection）
- `BLUETOOTH` / `BLUETOOTH_CONNECT` - 蓝牙A2DP
- `INTERNET` - UDP网络通信
- `ACCESS_WIFI_STATE` / `ACCESS_NETWORK_STATE` - 网络状态

### 树莓派端

```bash
# 安装依赖
sudo apt update
sudo apt install -y bluealsa libasound2-dev golang-go

# 克隆项目
cd raspberrypi/gateway
go mod init fyaudio/gateway
go mod tidy

# 运行
sudo go run main.go -name "客厅音响"
```

---

## 🔧 技术实现细节

### 音频帧格式

```
┌──────────────────────────────────────────────┐
│ Magic(4B) │ Timestamp(8B) │ Len(4B) │ Payload│
│ 0x46594155│   UTC毫秒      │  AAC长度 │  AAC数据│
└──────────────────────────────────────────────┘
```

- **编码**: AAC-LC 128kbps (通过FFmpeg编码)
- **帧长**: 20ms (882 samples @ 44100Hz)
- **传输**: UDP单播/广播

### 同步算法

```
播放时刻 = 帧时间戳 + 缓冲窗口 + 手动补偿 + 时钟偏差
```

- **缓冲窗口**: 动态调整，RTT中位数×2
- **时钟同步**: 广播端发送UTC时间戳，接收端计算偏差
- **手动补偿**: 用户可调整±200ms补偿硬件延迟

---

## ❓ FAQ

**Q: 为什么选择WiFi而不是蓝牙多点连接?**
A: 蓝牙A2DP是点对点的，无法一对多传输。WiFi方案可支持数十个设备同时同步。

**Q: 同步延迟有多大?**
A: 在同一局域网内，通常延迟在30-80ms。可以通过手动补偿微调。

**Q: 能否用于在线会议?**
A: 暂不支持。FyAudio面向娱乐场景（音乐、视频、游戏）的同步播放。

**Q: iOS端呢?**
A: iOS沙盒限制系统音频采集，只能作为接收端（需要TFly或类似方案）。

**Q: 如何提高音质?**
A: 可将FFmpeg编码器从AAC-LC改为ALAC（Apple Lossless）或FLAC，码率提升到256kbps+。

---

## 📄 License

MIT License - 详见 [LICENSE](LICENSE)
