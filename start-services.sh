#!/bin/bash
# 启动 SOCKS 代理
cd /opt/aimilivpn
LOCAL_PROXY_HOST=0.0.0.0 LOCAL_PROXY_PORT=8500 /opt/python3.13-gnu/bin/python3.13 proxy_server.py > /tmp/proxy.log 2>&1 &
# 启动 OpenVPN
sleep 3
cd /opt/aimilivpn/vpngate_data/configs
sudo openvpn --config JP_219.100.37.109_443_tcp.ovpn --auth-user-pass ../vpngate_auth.txt --daemon --log /tmp/openvpn-jp.log
sleep 10
# 启动 3X-UI（前台运行，作为主进程）
cd /usr/local/x-ui
exec /usr/local/x-ui/x-ui
