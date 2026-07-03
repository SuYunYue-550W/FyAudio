@echo off
chcp 65001 >nul
echo ================================================
echo   FyAudio Windows 构建脚本 (国内镜像版)
echo ================================================

set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

echo [1/3] 获取Flutter版本信息...
flutter --version

echo.
echo [2/3] 获取依赖包...
flutter pub get

if %errorlevel% neq 0 (
    echo 错误：依赖获取失败，请检查网络连接或镜像配置
    pause
    exit /b 1
)

echo.
echo [3/3] 构建Release版本...
flutter build windows --release

if %errorlevel% neq 0 (
    echo 错误：构建失败
    pause
    exit /b 1
)

echo.
echo 构建成功！产物位于: build\windows\x64\runner\Release\
echo ================================================
pause