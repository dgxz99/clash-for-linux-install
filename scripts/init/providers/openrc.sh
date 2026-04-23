#!/usr/bin/env bash

# OpenRC 服务参数提供者
# 负责按 OpenRC 规则填充安装期服务变量

_init_provider_openrc() {
    service_src="${SCRIPT_INIT_DIR}/OpenRC.sh"
    service_target="/etc/init.d/$KERNEL_NAME"
    service_mode=0755

    service_enable=(rc-update add "$KERNEL_NAME" default)
    service_disable=(rc-update del "$KERNEL_NAME" default)

    service_start=(rc-service "$KERNEL_NAME" start)
    service_stop=(rc-service "$KERNEL_NAME" stop)
    service_restart=(rc-service "$KERNEL_NAME" restart)
    service_status=(rc-service "$KERNEL_NAME" status)
    service_is_active=(rc-service "$KERNEL_NAME" status)
}
