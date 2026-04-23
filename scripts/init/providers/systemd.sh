#!/usr/bin/env bash

# systemd 服务参数提供者
# 负责按 systemd 规则填充安装期服务变量

_init_provider_systemd() {
    service_src="${SCRIPT_INIT_DIR}/systemd.sh"
    service_mode=0644
    if _is_root || _is_regular_sudo; then
        service_target="/etc/systemd/system/${KERNEL_NAME}.service"
        service_reload=($_SUDO systemctl daemon-reload)

        service_enable=($_SUDO systemctl enable "$KERNEL_NAME")
        service_disable=($_SUDO systemctl disable "$KERNEL_NAME")

        service_start=($_SUDO systemctl start "$KERNEL_NAME")
        service_stop=($_SUDO systemctl stop "$KERNEL_NAME")
        service_restart=($_SUDO systemctl restart "$KERNEL_NAME")
        service_status=($_SUDO systemctl status "$KERNEL_NAME")
        service_is_active=($_SUDO systemctl is-active "$KERNEL_NAME")
        service_sudo_start=("${service_start[@]}")
        service_sudo_stop=($_SUDO systemctl stop "$KERNEL_NAME")
        service_sudo_status=("${service_status[@]}")
        service_sudo_is_active=("${service_is_active[@]}")
        service_sudo_log=("${service_log[@]}")
        SYSTEMD_WANTED_BY='multi-user.target'
        SYSTEMD_CAPABILITIES='CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE'
        return 0
    fi

    service_target="${HOME}/.config/systemd/user/${KERNEL_NAME}.service"
    service_reload=(systemctl --user daemon-reload)

    service_enable=(systemctl --user enable "$KERNEL_NAME")
    service_disable=(systemctl --user disable "$KERNEL_NAME")

    service_start=(systemctl --user start "$KERNEL_NAME")
    service_stop=(systemctl --user stop "$KERNEL_NAME")
    service_restart=(systemctl --user restart "$KERNEL_NAME")
    service_status=(systemctl --user status "$KERNEL_NAME")
    service_is_active=(systemctl --user is-active "$KERNEL_NAME")

    service_sudo_start=(sudo sh -c '"nohup' "$BIN_KERNEL" -d "$CLASH_RESOURCES_DIR" -f "$CLASH_CONFIG_RUNTIME" '<' '/dev/null' '>' "$FILE_LOG" '2>\&1' '\&"')
    service_sudo_stop=($(_build_root_process_cmd stop))
    service_sudo_status=($(_build_root_process_cmd status))
    service_sudo_is_active=($(_build_root_process_cmd is_active))
    service_sudo_log=(sudo tail -n 200 "$FILE_LOG")

    INIT_TYPE='systemd-user'
    SYSTEMD_WANTED_BY='default.target'
    SYSTEMD_CAPABILITIES=''
}
