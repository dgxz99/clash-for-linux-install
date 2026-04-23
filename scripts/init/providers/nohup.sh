#!/usr/bin/env bash

# nohup 服务参数提供者
# 负责无服务管理器时的兜底运行方式

_init_provider_nohup() {
    service_enable=(false)
    service_disable=(false)

    # 使用子 shell 启动，确保进程脱离终端
    service_start=('(' nohup "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" '>' "$FILE_LOG" '2>\&1' '\&' ')')
    # sudo 启动：nohup 完全脱离终端，关闭所有标准流
    service_sudo_start=(sudo sh -c '"nohup' "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" '<' '/dev/null' '>' "$FILE_LOG" '2>\&1' '\&"')
    service_sudo_stop=($(_build_root_process_cmd stop))
    service_status=(pgrep -fa "$BIN_KERNEL")
    service_is_active=(pgrep -fa "$BIN_KERNEL")
    service_sudo_status=($(_build_root_process_cmd status))
    service_sudo_is_active=($(_build_root_process_cmd is_active))
    service_sudo_log=(sudo tail -n 200 "$FILE_LOG")
    service_stop=(pkill -9 -f "$BIN_KERNEL")
}
