@echo off
chcp 65001 >nul
echo ================================================
echo   FyAudio 开发模式运行 (国内镜像版)
echo ================================================

set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo [1/2] 获取依赖包...
flutter pub get

if %errorlevel% neq 0 (
    echo 错误：依赖获取失败
    pause
    exit /b 1
)

echo.
echo [2/2] 启动开发模式...
flutter run -d windows

pause