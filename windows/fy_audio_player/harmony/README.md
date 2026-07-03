# FyAudio 华为鸿蒙平台构建指南

多终端同步音频播放系统 - 鸿蒙平台适配说明

## 环境要求

| 工具 | 版本要求 |
|------|----------|
| DevEco Studio | 4.0+ |
| HarmonyOS SDK | API 12+ |
| JDK | 11+ |
| Flutter | 3.22+ |

## 构建步骤

### 1. 安装 DevEco Studio

从华为官方网站下载安装：
https://developer.huawei.com/consumer/cn/deveco-studio/

### 2. 配置 HarmonyOS SDK

打开 DevEco Studio，进入 Settings -> Appearance & Behavior -> System Settings -> HarmonyOS SDK
- 选择 SDK Platforms 标签
- 勾选 HarmonyOS API 12 及以上版本
- 点击 Apply 安装

### 3. 导入项目

- 打开 DevEco Studio
- File -> Open -> 选择项目根目录 `d:\Fy audio\windows\fy_audio_player`
- 等待项目同步完成

### 4. 配置签名信息

由于华为应用市场要求应用必须签名，需要配置签名信息：

1. 打开 Build -> Generate Signed Bundle / APK
2. 选择 APK 格式
3. 点击 Create new... 创建签名文件（.keystore）
4. 填写签名信息：
   - Key store path: 选择保存位置
   - Key store password: 设置密码
   - Key alias: 设置别名
   - Key password: 设置密码
5. 点击 OK 保存

### 5. 构建 HAP/APP 包

- Build -> Build Bundle(s) / APK(s) -> Build HAP(s)/APP(s)
- 构建完成后，产物位于：`build\outputs\default\`

## 权限配置

鸿蒙平台权限配置在 `module.json5` 文件中，已配置以下权限：

| 权限 | 用途 |
|------|------|
| `ohos.permission.INTERNET` | 网络音频传输与设备同步通信 |
| `ohos.permission.ACCESS_NETWORK_STATE` | 检测网络连接状态 |
| `ohos.permission.BLUETOOTH` | 蓝牙设备连接与音频传输 |
| `ohos.permission.BLUETOOTH_ADMIN` | 蓝牙设备管理与扫描 |
| `ohos.permission.LOCATION` | 蓝牙设备扫描所需的位置权限 |

权限配置文件示例（详见 `module.json5`）：

```json5
{
  "module": {
    "name": "entry",
    "type": "entry",
    "mainElement": "EntryAbility",
    "deviceTypes": ["phone", "tablet"],
    "requestPermissions": [
      { "name": "ohos.permission.INTERNET" },
      { "name": "ohos.permission.ACCESS_NETWORK_STATE" },
      { "name": "ohos.permission.BLUETOOTH" },
      { "name": "ohos.permission.BLUETOOTH_ADMIN" },
      { "name": "ohos.permission.LOCATION" }
    ]
  }
}
```

## flutter_blue_plus 兼容性说明

本项目使用 `flutter_blue_plus: ^1.31.4` 进行蓝牙通信，需注意以下鸿蒙平台兼容性问题：

### 平台支持现状

- `flutter_blue_plus` 官方**未提供鸿蒙平台原生实现**，其底层依赖 Android 的 `android.bluetooth` API 与 iOS 的 `CoreBluetooth` 框架。
- 在鸿蒙平台上运行时，蓝牙相关 API 调用将无法正常工作，可能导致功能降级或异常。

### 适配方案

为兼容鸿蒙平台，本项目采用以下策略：

1. **模拟模式**：在鸿蒙平台上检测到蓝牙不可用时，自动降级为模拟模式，保证应用主流程可用。
2. **条件编译**：通过 `dart:io` 的 `Platform` 判断当前平台，在鸿蒙平台跳过蓝牙初始化逻辑。
3. **原生集成（可选）**：如需完整蓝牙功能，可参考华为鸿蒙官方文档集成 `ohos.bluetooth` 模块：
   - 文档地址：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-bluetooth
   - 需自行编写鸿蒙平台插件桥接代码

### 鸿蒙蓝牙 API 参考

鸿蒙平台蓝牙相关权限与 API：
- `@ohos.bluetoothManager`：蓝牙管理与设备扫描
- `@ohos.bluetoothSocket`：蓝牙 Socket 通信
- 权限要求：`ohos.permission.BLUETOOTH`、`ohos.permission.BLUETOOTH_ADMIN`、`ohos.permission.LOCATION`

## 网络同步

鸿蒙平台支持 UDP 广播和组播，网络同步功能（多终端音频同步）可以正常使用：

- **音频数据传输**：端口 5001（UDP）
- **控制信令**：端口 5002（UDP）
- **时钟同步**：端口 5003（UDP）

## 已知问题

- `flutter_blue_plus` 在鸿蒙平台无原生支持，蓝牙功能使用模拟模式
- 部分 Flutter 插件可能需要额外适配鸿蒙平台
- 建议在真机上进行测试，确保网络同步功能正常工作
- 鸿蒙平台首次运行需在系统设置中手动授予定位权限（蓝牙扫描依赖）
