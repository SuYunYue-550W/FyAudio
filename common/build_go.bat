@echo off
chcp 65001 >nul
echo ================================================
echo   FyAudio Go后端构建脚本 (国内镜像版)
echo ================================================

set GOPROXY=https://goproxy.cn,direct
set GO111MODULE=on

echo [1/3] 检查Go环境...
go version

echo.
echo [2/3] 获取依赖...
go mod tidy

if %errorlevel% neq 0 (
    echo 错误：依赖获取失败
    pause
    exit /b 1
)

echo.
echo [3/3] 构建Windows版本...
go build -o fy_audio_backend.exe main.go

if %errorlevel% neq 0 (
    echo 错误：构建失败
    pause
    exit /b 1
)

echo.
echo 构建成功！产物: fy_audio_backend.exe
echo ================================================
pause