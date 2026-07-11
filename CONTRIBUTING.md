# Contributing to FyAudio

欢迎贡献代码！请阅读以下指南，确保你的贡献符合项目规范。

---

## 📖 代码风格

### Go 代码风格

- 使用 `go fmt` 自动格式化代码
- 遵循 [Go 官方编码规范](https://golang.org/doc/effective_go.html)
- 使用 `go vet` 和 `golangci-lint` 检查代码

```bash
# 格式化
go fmt ./...

# 静态检查
go vet ./...

# 安装 golangci-lint
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
golangci-lint run
```

### Dart/Flutter 代码风格

- 使用 `dart format` 自动格式化
- 使用 `flutter analyze` 检查代码

```bash
# 格式化
dart format lib/

# 静态分析
flutter analyze
```

### Kotlin 代码风格

- 使用 Android Studio 默认格式化
- 遵循 [Kotlin 官方编码规范](https://kotlinlang.org/docs/coding-conventions.html)

---

## 🌿 分支策略

```
main          # 主分支，稳定版本
develop       # 开发分支，日常开发
feature/*     # 功能分支，从 develop 切出
fix/*         # Bug 修复分支，从 develop 切出
release/*     # 发布分支，从 develop 切出
```

### 创建分支

```bash
# 功能开发
git checkout -b feature/your-feature-name

# Bug 修复
git checkout -b fix/your-fix-name
```

---

## 📋 PR 模板

提交 PR 时，请使用以下模板：

```markdown
## 类型

- [ ] 新功能
- [ ] Bug 修复
- [ ] 代码重构
- [ ] 文档更新
- [ ] 测试

## 描述

简要说明本次修改的内容和目的。

## 测试

- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 手动测试验证

## 相关 Issue

Fixes #123
```

---

## 🏗️ 本地构建

### Windows 端

```bash
cd windows/fy_audio_player

# 配置国内镜像（可选）
flutter config --enable-windows-desktop
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 安装依赖
flutter pub get

# 运行
flutter run -d windows

# 构建发布版
flutter build windows --release
```

### Android 端

```bash
cd android

# Android Studio 打开项目
# 或命令行构建
./gradlew assembleDebug
./gradlew assembleRelease
```

### 树莓派端

```bash
cd raspberrypi/gateway

# 安装依赖
sudo apt update
sudo apt install -y bluealsa libasound2-dev golang-go

# 构建
go build -o fyaudio-gateway .

# 运行
sudo ./fyaudio-gateway -name "客厅音响"
```

---

## ✅ 代码审查流程

1. **提交 PR**：将分支推送到远程仓库，创建 PR
2. **自动检查**：GitHub Actions 自动运行测试和 lint
3. **代码审查**：至少需要一位维护者批准
4. **合并**：通过审查后合并到 develop 分支

---

## 📝 提交信息规范

使用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<类型>(<范围>): <描述>

[可选的详细描述]

[关联的 Issue]
```

**类型**:
- `feat`: 新功能
- `fix`: Bug 修复
- `refactor`: 代码重构
- `docs`: 文档更新
- `test`: 测试
- `chore`: 构建/工具变更
- `ci`: CI/CD 配置

**示例**:
```
feat(sync): 添加手动延迟补偿功能

用户可通过 UI 调整 ±200ms 的延迟补偿
修复不同设备硬件延迟不一致的问题

Fixes #45
```

---

## 🐛 报告 Bug

请在 Issue 中提供以下信息：

- 设备型号和系统版本
- 复现步骤
- 预期行为和实际行为
- 日志截图（如果有）

---

## 💡 功能建议

欢迎提出功能建议！请在 Issue 中描述：

- 功能的用途和场景
- 预期的行为
- 可能的实现方案（可选）