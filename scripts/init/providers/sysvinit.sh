#!/usr/bin/env bash

# SysVinit 服务参数提供者
# 负责按 SysVinit 规则填充安装期服务变量

_init_provider_sysvinit() {
    service_src="${SCRIPT_INIT_DIR}/SysVinit.sh"
    service_target="/etc/init.d/$KERNEL_NAME"
    service_mode=0755

    command -v chkconfig >&/dev/null && {
        service_add=(chkconfig --add "$KERNEL_NAME")
        service_del=(chkconfig --del "$KERNEL_NAME")

        service_enable=(chkconfig "$KERNEL_NAME" on)
        service_disable=(chkconfig "$KERNEL_NAME" off)
    }
    command -v update-rc.d >&/dev/null && {
        service_add=(update-rc.d "$KERNEL_NAME" defaults)
        service_del=(update-rc.d "$KERNEL_NAME" remove)

        service_enable=(update-rc.d "$KERNEL_NAME" enable)
        service_disable=(update-rc.d "$KERNEL_NAME" disable)
    }

    service_start=(service "$KERNEL_NAME" start)
    service_stop=(service "$KERNEL_NAME" stop)
    service_restart=(service "$KERNEL_NAME" restart)
    service_status=(service "$KERNEL_NAME" status)
    service_is_active=(service "$KERNEL_NAME" status)
}
