#!/usr/bin/env bash

# runit 服务参数提供者
# 负责按 runit 规则填充安装期服务变量

_init_provider_runit() {
    service_src="${SCRIPT_INIT_DIR}/runit.sh"
    service_target="/etc/sv/${KERNEL_NAME}/run"
    service_mode=0755
    service_del=(rm -rf "/etc/sv/${KERNEL_NAME:-mihomo}")

    service_reload=(sleep 2)
    service_enable=(ln -s "$(dirname "$service_target")" "/etc/runit/runsvdir/default/${KERNEL_NAME}")
    service_disable=(rm -f "/etc/runit/runsvdir/current/${KERNEL_NAME}")

    service_start=(sv up "$KERNEL_NAME")
    service_stop=(sv down "$KERNEL_NAME")
    service_restart=(sv restart "$KERNEL_NAME")
    service_status=(sv status "$KERNEL_NAME")
    service_is_active=(sv status "$KERNEL_NAME" \| grep -qs '^run')
}
