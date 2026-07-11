#!/bin/bash
set -e

echo "=== FyAudio Gateway 安装脚本 ==="

echo "1. 安装依赖..."
sudo apt update
sudo apt install -y bluealsa libasound2-dev golang-go

echo "2. 创建目录..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /var/lib/fyaudio
sudo mkdir -p /etc/fyaudio

echo "3. 复制二进制文件..."
sudo cp fyaudio_gateway_arm /usr/local/bin/fyaudio-gateway
sudo chmod +x /usr/local/bin/fyaudio-gateway

echo "4. 安装 systemd 服务..."
sudo cp fyaudio-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable fyaudio-gateway

echo "5. 配置 BlueALSA..."
echo "pcm.bluealsa {
    type plug
    slave {
        pcm {
            type bluealsa
            device \"\"
            profile \"a2dp_sink\"
        }
    }
    hint {
        show on
        description \"BlueALSA Bluetooth Audio\"
    }
}" | sudo tee /etc/asound.conf

echo "6. 启动服务..."
sudo systemctl start fyaudio-gateway

echo ""
echo "=== 安装完成 ==="
echo ""
echo "查看服务状态: sudo systemctl status fyaudio-gateway"
echo "查看日志: sudo journalctl -u fyaudio-gateway -f"
echo "停止服务: sudo systemctl stop fyaudio-gateway"