#!/bin/bash

set -e

APP_DIR="/opt/fyaudio"
BIN_DIR="/usr/local/bin"

echo "==============================================="
echo "    FyAudio - 多终端WiFi蓝牙同步音频播放系统"
echo "            (树莓派 ARM64 版本)"
echo "==============================================="
echo ""

echo "[1/4] 更新系统..."
sudo apt-get update
sudo apt-get upgrade -y

echo "[2/4] 安装依赖..."
sudo apt-get install -y libasound2-dev libbluetooth-dev bluez

echo "[3/4] 创建安装目录并复制文件..."
sudo mkdir -p "$APP_DIR"
sudo cp "fy_audio_backend" "$APP_DIR/fy_audio_backend"
sudo chmod +x "$APP_DIR/fy_audio_backend"

echo "[4/4] 创建服务..."
cat > /tmp/fyaudio.service << 'EOF'
[Unit]
Description=FyAudio Backend Service
After=network.target bluetooth.target

[Service]
Type=simple
ExecStart=/opt/fyaudio/fy_audio_backend
Restart=always
User=pi
Environment=LD_LIBRARY_PATH=/opt/fyaudio/lib

[Install]
WantedBy=multi-user.target
EOF
sudo mv /tmp/fyaudio.service "/etc/systemd/system/fyaudio.service"
sudo systemctl daemon-reload
sudo systemctl enable fyaudio

echo ""
echo "安装完成！"
echo ""
echo "启动服务：sudo systemctl start fyaudio"
echo "停止服务：sudo systemctl stop fyaudio"
echo "查看状态：sudo systemctl status fyaudio"
echo "查看日志：journalctl -u fyaudio -f"