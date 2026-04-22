[Unit]
# systemd 服务模板
# 安装时会由 preflight.sh 替换 placeholder 为实际值
Description=placeholder_kernel_desc
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=placeholder_systemd_capabilities
AmbientCapabilities=placeholder_systemd_capabilities
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=placeholder_cmd_full
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=placeholder_wanted_by
