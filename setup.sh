#!/bin/bash
# Zerops aigroupchat 重部署安装脚本
# 在容器启动时执行，安装 AimiliVPN + 3X-UI，配置日本节点隧道
set -e

echo "=== Step 1: 安装系统包 ==="
sudo apk add --no-cache bash curl wget git openvpn iptables gcompat python3 py3-pip sudo
sudo apk add --no-cache gcc musl-dev linux-headers make zlib-dev openssl-dev libffi-dev bzip2-dev

echo "=== Step 2: 编译安装 Python 3.13.9 ==="
if [ ! -f "/opt/python3.13-gnu/bin/python3.13" ]; then
    cd /tmp
    wget -q https://www.python.org/ftp/python/3.13.9/Python-3.13.9.tgz
    tar xzf Python-3.13.9.tgz
    cd Python-3.13.9
    ./configure --prefix=/opt/python3.13-gnu --enable-optimizations --with-lto > /tmp/python-config.log 2>&1
    make -j$(nproc) > /tmp/python-make.log 2>&1
    make install > /tmp/python-install.log 2>&1
    cd /tmp && rm -rf Python-3.13.9 Python-3.13.9.tgz
    echo "Python 3.13.9 安装完成"
else
    echo "Python 3.13.9 已存在，跳过"
fi

echo "=== Step 3: 克隆 AimiliVPN ==="
if [ ! -d "/opt/aimilivpn" ]; then
    cd /opt && git clone https://github.com/hankinsus/AimiliVPN.git aimilivpn
    cd /opt/aimilivpn && git checkout 21446ac
fi

echo "=== Step 4: 安装 AimiliVPN 核心 ==="
cd /opt/aimilivpn
if [ -f "scripts/select_core.sh" ]; then
    bash scripts/select_core.sh || echo "select_core 失败，继续"
fi

echo "=== Step 5: 安装 3X-UI ==="
if [ ! -f "/usr/local/x-ui/x-ui" ]; then
    curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o /tmp/3x-ui-install.sh
    bash /tmp/3x-ui-install.sh || echo "3X-UI 安装失败"
fi

echo "=== Step 6: 配置 3X-UI ==="
# 3X-UI 安装后需要配置 VLESS 入站，这里先启动面板，稍后通过 API 配置
# 面板默认端口 2053，改为 50904
if [ -f "/usr/local/x-ui/x-ui" ]; then
    # 使用 x-ui 命令设置端口（如果支持）
    /usr/local/x-ui/x-ui setting -port 50904 2>/dev/null || echo "端口设置需手动"
fi

echo "=== Step 7: 启动 SOCKS 代理 ==="
export LOCAL_PROXY_HOST="0.0.0.0"
export LOCAL_PROXY_PORT="8500"
cd /opt/aimilivpn
nohup /opt/python3.13-gnu/bin/python3 proxy_server.py > /tmp/proxy.log 2>&1 &
echo "SOCKS 代理已启动"

echo "=== Step 8: 等待节点发现 ==="
sleep 60

echo "=== Step 9: 启动 OpenVPN 日本节点 ==="
JP_CONFIG=$(ls /opt/aimilivpn/vpngate_data/configs/JP_*_443_tcp.ovpn 2>/dev/null | head -1)
if [ -n "$JP_CONFIG" ]; then
    echo "使用日本节点: $JP_CONFIG"
    openvpn --config "$JP_CONFIG" --dev tun0 --dev-type tun --route-delay 2 --connect-retry-max 1 --connect-timeout 15 --auth-user-pass /opt/aimilivpn/vpngate_data/vpngate_auth.txt --auth-nocache --data-ciphers AES-128-CBC:AES-256-GCM:AES-128-GCM --daemon --log /tmp/openvpn-jp.log
    echo "OpenVPN 已启动"
else
    echo "警告：未找到日本节点配置，列出可用配置："
    ls /opt/aimilivpn/vpngate_data/configs/ 2>/dev/null | head -10 || echo "配置目录不存在"
fi

echo "=== Step 10: 启动 3X-UI 面板 ==="
if [ -f "/usr/local/x-ui/x-ui" ]; then
    nohup /usr/local/x-ui/x-ui > /tmp/x-ui.log 2>&1 &
    echo "3X-UI 已启动"
fi

echo "=== 安装完成 ==="
sleep 10
echo "监听端口："
ss -tlnp 2>/dev/null | grep -E "10001|50904|8500|8501|8443" || netstat -tlnp 2>/dev/null | grep -E "10001|50904|8500|8501|8443" || echo "端口检查工具不可用"

# 保持容器运行
tail -f /dev/null
